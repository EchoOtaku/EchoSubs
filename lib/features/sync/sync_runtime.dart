import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:bonsoir/bonsoir.dart';
import '../../core/crypto/ledger_keys.dart';
import '../../core/crypto/ledger_metadata.dart';
import '../../core/model/errors.dart';
import '../../core/model/ids.dart';
import '../../storage/ledger_store.dart';
import '../ledger/ledger_repository.dart';
import 'sync_coordinator.dart';
import 'sync_engine.dart';
import 'sync_state_store.dart';
import 'sync_status.dart';
import 'transports/lan_discovery.dart';
import 'transports/lan_identity.dart';
import 'transports/lan_pairing.dart';
import 'transports/lan_server.dart';
import 'transports/lan_transport.dart';
import 'transports/webdav_transport.dart';

/// Owns foreground-only listeners and creates terminal transports afresh.
class SyncRuntime {
  SyncRuntime(
    this.repository, {
    required this.attach,
    required this.detach,
    required this.select,
  }) : peers = LanPeerStore(repository.vault);
  final LedgerRepository repository;
  final LanPeerStore peers;
  final void Function(SyncCoordinator) attach;
  final Future<void> Function() detach;
  final Future<void> Function(LedgerId) select;
  Future<bool> Function(LanCertificate)? confirm;
  PairingService? pairing;
  LanServer? server;
  LanDiscovery? discovery;
  StreamSubscription<BonsoirService>? _hints;
  final _addresses = <String, BonsoirService>{};
  bool _foreground = true, _closed = false;
  int _generation = 0;
  Future<void> _queue = Future.value();
  String? discoveryError;
  String? runtimeError;
  Future<List<ChannelConfig>> configs() =>
      SyncStateStore(repository.database, repository.store.ledgerId).configs();
  static String credentialKey(String endpoint) => 'sync.dav.$endpoint';
  void _selected(String id) {
    if (_closed || id != repository.currentLedgerId)
      throw const EchoFailure('cancelled', '账本已切换，操作已取消');
  }

  Future<void> configureDav(
    Uri root,
    DavCredentials credentials, {
    required bool enabled,
    LedgerId? expectedLedgerId,
  }) async {
    if (expectedLedgerId != null) _selected(expectedLedgerId);
    if (root.scheme != 'https' ||
        root.host.isEmpty ||
        root.userInfo.isNotEmpty ||
        root.hasQuery ||
        root.hasFragment ||
        !root.path.endsWith('/') ||
        root.path == '/')
      invalidModel();
    final id = repository.store.ledgerId;
    final endpoint = newId();
    await repository.vault.put(
      credentialKey(endpoint),
      Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'username': credentials.username,
            'secret': credentials.secret,
          }),
        ),
      ),
    );
    _selected(id);
    await SyncStateStore(repository.database, id).save(
      ChannelConfig(SyncChannelKind.webdav, endpoint, enabled, {
        'root': root.toString(),
      }),
    );
    await rebind();
  }

  Future<void> configureLan(
    String address,
    int port, {
    required bool enabled,
    LedgerId? expectedLedgerId,
  }) async {
    if (expectedLedgerId != null) _selected(expectedLedgerId);
    validateLanEndpoint(address, port);
    final id = repository.store.ledgerId;
    await SyncStateStore(repository.database, id).save(
      ChannelConfig(SyncChannelKind.lan, newId(), enabled, {
        'address': address,
        'port': port,
      }),
    );
    _selected(id);
    await rebind();
  }

  Future<void> setEnabled(ChannelConfig config, bool enabled) async {
    final current = await configs();
    if (!current.any(
      (c) => c.kind == config.kind && c.endpointId == config.endpointId,
    )) {
      throw const EchoFailure('conflict', '通道配置已变化，请重新打开设置');
    }
    await SyncStateStore(repository.database, repository.store.ledgerId).save(
      ChannelConfig(config.kind, config.endpointId, enabled, config.settings),
    );
    await rebind();
  }

  Future<DavCredentials> _credentials(ChannelConfig config) async {
    final raw = await repository.vault.get(credentialKey(config.endpointId));
    if (raw == null) throw const EchoFailure('locked', '网盘凭据不可用，请重新配置');
    return parseModel(() {
      final values = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
      return DavCredentials(
        values['username'] as String,
        values['secret'] as String,
      );
    });
  }

  Future<void> rebind() {
    final generation = ++_generation;
    final op = _queue.then((_) => _bind(generation));
    _queue = op.then<void>((_) {}, onError: (Object _) {});
    return op;
  }

  Future<void> _stop() async {
    await detach();
    await _hints?.cancel();
    _hints = null;
    await discovery?.stop();
    discovery = null;
    await server?.close();
    server = null;
    await pairing?.close();
    pairing = null;
    _addresses.clear();
  }

  Future<void> _bind(int generation) async {
    await _stop();
    if (_closed || !_foreground || generation != _generation) return;
    final store = repository.store;
    final id = store.ledgerId;
    final settings = await SyncStateStore(repository.database, id).configs();
    final channels = <SyncChannel>[];
    late final SyncCoordinator coordinator;
    runtimeError = null;
    discoveryError = null;
    for (final config in settings.where((c) => c.enabled)) {
      if (config.kind == SyncChannelKind.webdav) {
        channels.add(
          SyncChannel(
            config.kind,
            config.endpointId,
            () async => WebDavTransport(
              root: Uri.parse(config.settings['root']! as String),
              ledgerId: id,
              credentials: await _credentials(config),
              onRetry: (attempt) => coordinator.retry(config.kind, attempt),
            ),
          ),
        );
      } else {
        try {
          final identity = await LanIdentity.loadOrCreate(
            repository.vault,
            repository.deviceId,
          );
          if (_closed || !_foreground || generation != _generation) return;
          final service = PairingService(
            identity: identity,
            peers: peers,
            confirm: (certificate) async =>
                await confirm?.call(certificate) ?? false,
            authorizeLedger: (ledger) async {
              if (ledger != id ||
                  repository.currentLedgerId != id ||
                  generation != _generation) {
                throw const EchoFailure('authentication', '账本授权已失效');
              }
              return AuthorizedLedger(
                await store.metadata(),
                await repository.authenticatedKeys(id),
              );
            },
          );
          pairing = service;
          final listener = LanServer(
            identity: identity,
            peers: peers,
            pairing: service,
            access: LanLedgerAccess(store, (object) async {
              final engine = SyncEngine(
                store,
                await repository.authenticatedKeys(id),
              );
              await engine.ingest(object);
            }),
          );
          server = listener;
          await listener.start(
            enabled: true,
            foreground: true,
            port: config.settings['port']! as int,
          );
          final discoveryService = LanDiscovery();
          discovery = discoveryService;
          _hints = discoveryService.candidates.listen(
            (hint) {
              final device = hint.attributes['device'];
              if (device != null) _addresses[device] = hint;
            },
            onError: (Object _) {
              discoveryError = '自动发现不可用，可使用已配对地址';
            },
          );
          try {
            await discoveryService.start(
              enabled: true,
              foreground: true,
              deviceId: identity.deviceId,
              port: listener.port,
            );
          } on Object {
            discoveryError = '自动发现不可用，可使用已配对地址';
          }
        } on Object {
          runtimeError = '局域网服务未启动，请检查地址、端口与设备身份';
          await server?.close();
          server = null;
          await pairing?.close();
          pairing = null;
          channels.add(
            SyncChannel(config.kind, config.endpointId, () async {
              throw const EchoFailure('unavailable', '局域网服务不可用');
            }),
          );
        }
      }
    }
    if (_closed ||
        !_foreground ||
        generation != _generation ||
        repository.currentLedgerId != id) {
      await _stop();
      return;
    }
    coordinator = SyncCoordinator(
      store: store,
      authenticate: () => repository.authenticatedKeys(id),
      channels: channels,
      loadChannels: () async {
        final current = [...channels];
        final lan = settings
            .where((c) => c.enabled && c.kind == SyncChannelKind.lan)
            .firstOrNull;
        if (lan != null && server != null) {
          try {
            for (final peer in await peers.list(id)) {
              current.add(
                SyncChannel(
                  SyncChannelKind.lan,
                  '${lan.endpointId}.${peer.pairingId}',
                  () async {
                    final hint = _addresses[peer.certificate.deviceId];
                    if (hint != null) {
                      try {
                        return await LanDiscovery.connect(hint, peer, peers);
                      } on Object {
                        /* A hint cannot replace the saved pin. */
                      }
                    }
                    return LanTransport(
                      peer: peer,
                      localDeviceId: repository.deviceId,
                      peers: peers,
                    );
                  },
                ),
              );
            }
          } on Object {
            current.add(
              SyncChannel(SyncChannelKind.lan, lan.endpointId, () async {
                throw const EchoFailure('authentication', '局域网设备授权不可用，请重新配对');
              }),
            );
          }
        }
        return current;
      },
    );
    attach(coordinator);
  }

  Future<void> foreground(bool value) async {
    _foreground = value;
    await rebind();
  }

  Future<PairingOffer> offer() async {
    final config = (await configs())
        .where((c) => c.kind == SyncChannelKind.lan && c.enabled)
        .firstOrNull;
    if (config == null || pairing == null || server == null)
      throw const EchoFailure('unavailable', '请先启用局域网通道');
    return pairing!.offer(
      ledgerId: repository.store.ledgerId,
      address: config.settings['address']! as String,
      port: server!.port,
    );
  }

  Future<void> joinPairing(PairingOffer offer, CancellationToken token) async {
    final original = repository.store.ledgerId;
    final config = (await configs())
        .where((c) => c.kind == SyncChannelKind.lan && c.enabled)
        .firstOrNull;
    final service = pairing;
    if (config == null || service == null || server == null)
      throw const EchoFailure('unavailable', '请先启用局域网通道');
    final peer = await service.join(
      offer,
      cancellation: token,
      localAddress: config.settings['address']! as String,
      localPort: server!.port,
    );
    final grant = peer.authorizedLedger;
    if (grant == null) throw const EchoFailure('authentication', '配对没有提供账本授权');
    final transport = LanTransport(
      peer: peer,
      localDeviceId: repository.deviceId,
      peers: peers,
    );
    try {
      final metadata = await transport.readMetadata();
      if (canonicalModelJson(metadata.toJson()) !=
          canonicalModelJson(grant.metadata.toJson())) {
        throw const EchoFailure('integrity', '配对账本元数据不匹配');
      }
      final objects = await _download(transport, token);
      _selected(original);
      if (token.isCancelled) throw const EchoFailure('cancelled', '加入已取消');
      await repository.importLedger(grant.metadata, grant.keys, objects);
      await SyncStateStore(repository.database, grant.metadata.id).save(config);
      await select(grant.metadata.id);
    } finally {
      await transport.close();
    }
  }

  Future<void> joinDav(
    Uri ledgerRoot,
    DavCredentials credentials,
    RecoveryCode recovery,
    CancellationToken token,
  ) async {
    final original = repository.store.ledgerId;
    final metadata = await WebDavTransport.probeMetadata(
      ledgerRoot,
      credentials,
    );
    final keys = await unwrapKeys(metadata, recovery);
    final root = ledgerRoot.resolve('../');
    final transport = WebDavTransport(
      root: root,
      ledgerId: metadata.id,
      credentials: credentials,
    );
    try {
      final objects = await _download(transport, token);
      _selected(original);
      if (token.isCancelled) throw const EchoFailure('cancelled', '加入已取消');
      await repository.importLedger(
        metadata,
        keys,
        objects,
        recovery: recovery,
      );
      await select(metadata.id);
      // The explicit join form includes the same upload/encryption disclosure.
      await configureDav(root, credentials, enabled: true);
    } finally {
      await transport.close();
    }
  }

  Future<List<StoredObject>> _download(
    SyncTransport transport,
    CancellationToken token,
  ) async {
    final values = <StoredObject>[];
    final timer = Timer.periodic(const Duration(milliseconds: 20), (_) {
      if (token.isCancelled || _closed) unawaited(transport.close());
    });
    try {
      await for (final ref in transport.listObjects(token)) {
        if (token.isCancelled) throw const EchoFailure('cancelled', '加入已取消');
        final object = await transport.read(ref);
        if (object.batchId != ref.batchId || object.sha256 != ref.sha256)
          throw const EchoFailure('integrity', '账本对象与目录不匹配');
        values.add(object);
      }
      return values;
    } finally {
      timer.cancel();
    }
  }

  Future<void> close() async {
    _closed = true;
    ++_generation;
    await _queue;
    await _stop();
  }
}

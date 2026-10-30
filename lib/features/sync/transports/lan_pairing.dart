import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import '../../../core/crypto/key_vault.dart';
import '../../../core/crypto/ledger_keys.dart';
import '../../../core/crypto/ledger_metadata.dart';
import '../../../core/model/errors.dart';
import '../../../core/model/ids.dart';
import 'lan_identity.dart';
import 'lan_transport.dart';

/// Only handed to Task8 in memory; registering an existing ledger is its job.
class AuthorizedLedger {
  AuthorizedLedger(this.metadata, this.keys) {
    if (metadata.id != keys.ledgerId) throw lanAuthentication;
  }
  final LedgerMetadata metadata;
  final LedgerKeys keys;
}

class PairingOffer {
  PairingOffer({
    required this.ledgerId,
    required this.certificate,
    required this.address,
    required this.port,
    required Uint8List secret,
    required this.issuedAt,
    required this.expiresAt,
  }) : _secret = Uint8List.fromList(secret) {
    validateId(ledgerId);
    validateLanEndpoint(address, port);
    if (secret.length != 32 ||
        !issuedAt.isUtc ||
        !expiresAt.isUtc ||
        expiresAt.difference(issuedAt) <= Duration.zero ||
        expiresAt.difference(issuedAt) > const Duration(seconds: 120))
      invalidModel();
  }
  final LedgerId ledgerId;
  final LanCertificate certificate;
  final String address;
  final int port;
  final DateTime issuedAt, expiresAt;
  final Uint8List _secret;
  Map<String, Object?> toJson() => {
    ...certificate.toJson(),
    'version': 1,
    'ledgerId': ledgerId,
    'address': address,
    'port': port,
    'secret': base64Encode(_secret),
    'issuedAt': issuedAt.toIso8601String(),
    'expiresAt': expiresAt.toIso8601String(),
  };
  String encode() => jsonEncode(toJson());
  factory PairingOffer.decode(String text) => parseModel(() {
    if (text.length > 8192) invalidModel();
    return PairingOffer.fromJson(jsonDecode(text) as Map<String, dynamic>);
  });
  factory PairingOffer.fromJson(Map<String, dynamic> map) => parseModel(() {
    if (map['version'] != 1)
      throw const EchoFailure('incompatible', '不支持的局域网配对版本');
    return PairingOffer(
      ledgerId: map['ledgerId'] as String,
      certificate: LanCertificate.fromJson(map),
      address: map['address'] as String,
      port: map['port'] as int,
      secret: base64Decode(map['secret'] as String),
      issuedAt: DateTime.parse(map['issuedAt'] as String),
      expiresAt: DateTime.parse(map['expiresAt'] as String),
    );
  });
  @override
  String toString() => 'PairingOffer([redacted])';
}

class PairedPeer {
  PairedPeer({
    required this.pairingId,
    required this.ledgerId,
    required this.localDeviceId,
    required this.localFingerprint,
    required this.certificate,
    required this.address,
    required this.port,
    required this.credentialRef,
    this.authorizedLedger,
  }) {
    validateId(pairingId);
    validateId(ledgerId);
    validateId(localDeviceId);
    validateLanEndpoint(address, port);
  }

  /// Public, random generation binding the record, credentials and active marker.
  final String pairingId;
  final LedgerId ledgerId;
  final DeviceId localDeviceId;
  final String localFingerprint;
  final LanCertificate certificate;
  final String address;
  final int port;
  final String credentialRef;
  final AuthorizedLedger? authorizedLedger;
  Map<String, Object?> toJson() => {
    'pairingId': pairingId,
    ...certificate.toJson(),
    'ledgerId': ledgerId,
    'localDeviceId': localDeviceId,
    'localFingerprint': localFingerprint,
    'address': address,
    'port': port,
    'credentialRef': credentialRef,
  };
  factory PairedPeer.fromJson(Map<String, dynamic> m) => parseModel(
    () => PairedPeer(
      pairingId: m['pairingId'] as String,
      ledgerId: m['ledgerId'] as String,
      localDeviceId: m['localDeviceId'] as String,
      localFingerprint: m['localFingerprint'] as String,
      certificate: LanCertificate.fromJson(m),
      address: m['address'] as String,
      port: m['port'] as int,
      credentialRef: m['credentialRef'] as String,
    ),
  );
}

/// One app instance owns this store. Shared-vault operations serialize in-process.
/// A record only becomes usable after secrets, record, index and active marker
/// all exist. An incomplete write or a tombstone never authorizes requests.
class LanPeerStore {
  LanPeerStore(this.vault);
  final KeyVault vault;
  static final _queues = Expando<Future<void>>();
  static final _denials = Expando<Set<String>>();
  static final _revocations = Expando<Map<String, int>>();
  Set<String> get _denied => _denials[vault] ??= <String>{};
  Map<String, int> get _revisions => _revocations[vault] ??= <String, int>{};
  String _base(LedgerId ledger, DeviceId remote) {
    validateId(ledger);
    validateId(remote);
    return 'lan.peer.$ledger.$remote';
  }

  Future<T> _serial<T>(Future<T> Function() fn) {
    final previous = _queues[vault] ?? Future<void>.value();
    final operation = previous.then((_) => fn());
    _queues[vault] = operation.then<void>((_) {}, onError: (Object _) {});
    return operation;
  }

  Future<List<String>> _index(LedgerId ledger) async {
    validateId(ledger);
    final raw = await vault.get('lan.index.$ledger');
    if (raw == null) return [];
    return parseModel(() {
      final values = (jsonDecode(utf8.decode(raw)) as List).cast<String>();
      if (values.length > 64 || values.toSet().length != values.length)
        invalidModel();
      for (final id in values) {
        validateId(id);
      }
      return values;
    });
  }

  Future<void> save(
    PairedPeer peer, {
    required Uint8List inboundToken,
    required Uint8List outboundToken,
    required bool Function() stillValid,
  }) {
    final base = _base(peer.ledgerId, peer.certificate.deviceId);
    // Capture before queueing: a save requested before revoke must not acquire
    // that later revocation's permission to clear the immediate deny.
    final revision = _revisions[base] ?? 0;
    bool valid() => stillValid() && (_revisions[base] ?? 0) == revision;
    return _serial(() async {
      if (inboundToken.length != 32 || outboundToken.length != 32 || !valid())
        throw lanAuthentication;
      if (peer.credentialRef != '$base.secret') invalidModel();
      final index = await _index(peer.ledgerId);
      if (!index.contains(peer.certificate.deviceId) && index.length >= 64)
        throw const EchoFailure('unavailable', '局域网配对设备已达上限');
      _denied.add(base);
      await vault.put('$base.state', Uint8List.fromList([0]));
      await vault.put(
        '$base.secret',
        Uint8List.fromList([
          ...utf8.encode(peer.pairingId),
          ...inboundToken,
          ...outboundToken,
        ]),
      );
      await vault.put(
        '$base.record',
        Uint8List.fromList(utf8.encode(jsonEncode(peer.toJson()))),
      );
      if (!index.contains(peer.certificate.deviceId))
        index.add(peer.certificate.deviceId);
      await vault.put(
        'lan.index.${peer.ledgerId}',
        Uint8List.fromList(utf8.encode(jsonEncode(index))),
      );
      if (!valid()) throw lanAuthentication;
      await vault.put(
        '$base.state',
        Uint8List.fromList([1, ...utf8.encode(peer.pairingId)]),
      );
      if (!valid()) {
        await vault.put('$base.state', Uint8List.fromList([0]));
        throw lanAuthentication;
      }
      _denied.remove(base);
    });
  }

  Future<PairedPeer?> get(LedgerId ledger, DeviceId remote) async {
    final base = _base(ledger, remote);
    if (_denied.contains(base) || !(await _index(ledger)).contains(remote))
      return null;
    final state = await vault.get('$base.state');
    // Legacy generation-free markers and partial writes are never active.
    if (state == null || state.length != 33 || state.first != 1) return null;
    final raw = await vault.get('$base.record');
    final secrets = await vault.get('$base.secret');
    if (raw == null || secrets == null || secrets.length != 96)
      throw lanAuthentication;
    final peer = parseModel(
      () => PairedPeer.fromJson(
        jsonDecode(utf8.decode(raw)) as Map<String, dynamic>,
      ),
    );
    if (peer.ledgerId != ledger ||
        peer.certificate.deviceId != remote ||
        peer.credentialRef != '$base.secret' ||
        !lanEqual(state.sublist(1), utf8.encode(peer.pairingId)) ||
        !lanEqual(secrets.sublist(0, 32), utf8.encode(peer.pairingId)))
      throw lanAuthentication;
    final finalState = await vault.get('$base.state');
    if (_denied.contains(base) ||
        finalState == null ||
        !lanEqual(finalState, state))
      return null;
    return peer;
  }

  Future<Uint8List> token(PairedPeer expected, {required bool inbound}) async {
    final peer = await get(expected.ledgerId, expected.certificate.deviceId);
    if (peer == null ||
        canonicalModelJson(peer.toJson()) !=
            canonicalModelJson(expected.toJson()))
      throw lanAuthentication;
    final raw = await vault.get(peer.credentialRef);
    if (raw == null ||
        raw.length != 96 ||
        !lanEqual(raw.sublist(0, 32), utf8.encode(peer.pairingId)))
      throw lanAuthentication;
    final current = await get(peer.ledgerId, peer.certificate.deviceId);
    if (current == null ||
        canonicalModelJson(current.toJson()) !=
            canonicalModelJson(expected.toJson()))
      throw lanAuthentication;
    return Uint8List.fromList(inbound ? raw.sublist(32, 64) : raw.sublist(64));
  }

  Future<int> approvedPeerCount(LedgerId ledger) async {
    var count = 0;
    for (final id in await _index(ledger)) {
      if (await get(ledger, id) != null) count++;
    }
    return count;
  }

  Future<void> revoke(LedgerId ledger, DeviceId remote) {
    final base = _base(ledger, remote);
    _revisions[base] = (_revisions[base] ?? 0) + 1;
    _denied.add(
      base,
    ); // Immediate denial even if the secure-storage write fails.
    return _serial(() => vault.put('$base.state', Uint8List.fromList([0])));
  }
}

class _OfferState {
  _OfferState(this.offer);
  final PairingOffer offer;
  final Stopwatch elapsed = Stopwatch()..start();
  bool consumed = false, cancelled = false, completed = false;
  String? session;
  LanCertificate? guest;
  String? address;
  int? port;
  Uint8List? reverseToken;
}

class PairingService {
  PairingService({
    required this.identity,
    required this.peers,
    required this.confirm,
    this.authorizeLedger,
    DateTime Function()? now,
  }) : now = now ?? (() => DateTime.now().toUtc());
  final LanIdentity identity;
  final LanPeerStore peers;
  final Future<bool> Function(LanCertificate peer) confirm;
  final Future<AuthorizedLedger> Function(LedgerId ledger)? authorizeLedger;
  final DateTime Function() now;
  final Map<String, _OfferState> _offers = {};
  final Set<LanHttp> _clients = {};
  bool _closed = false;
  Future<PairingOffer> offer({
    required LedgerId ledgerId,
    required String address,
    required int port,
  }) async {
    if (_closed || authorizeLedger == null) throw lanUnavailable;
    await identity.certificate.validate();
    // Only one displayed offer per host service; replacing it cancels the old one.
    for (final value in _offers.values) {
      value.cancelled = true;
    }
    _offers.clear();
    final issuedAt = now();
    final offer = PairingOffer(
      ledgerId: ledgerId,
      certificate: identity.certificate,
      address: address,
      port: port,
      secret: secureBytes(32),
      issuedAt: issuedAt,
      expiresAt: issuedAt.add(const Duration(seconds: 120)),
    );
    _offers[base64Encode(offer._secret)] = _OfferState(offer);
    return offer;
  }

  void cancelOffer(PairingOffer offer) {
    _offers[base64Encode(offer._secret)]?.cancelled = true;
  }

  bool _valid(_OfferState state) =>
      !_closed &&
      !state.cancelled &&
      state.elapsed.elapsed < const Duration(seconds: 120) &&
      now().isBefore(state.offer.expiresAt);
  Duration _remaining(_OfferState state) {
    final wall = state.offer.expiresAt.difference(now());
    final monotonic = const Duration(seconds: 120) - state.elapsed.elapsed;
    return wall < monotonic ? wall : monotonic;
  }

  Uint8List _claim(
    PairingOffer offer,
    LanCertificate guest,
    String address,
    int port,
    String reverseToken,
  ) => Uint8List.fromList(
    utf8.encode(
      canonicalModelJson({
        'domain': 'echosubs.lan.pair.v1',
        'purpose': 'guest-confirmation',
        'offer': offer.toJson(),
        'guest': guest.toJson(),
        'guestAddress': address,
        'guestPort': port,
        'reverseToken': reverseToken,
      }),
    ),
  );

  /// Called only by the secure server. No root/long-term credential is returned
  /// by prepare; finalize rechecks approval expiry and cancellation after awaits.
  Future<Map<String, Object?>> handle(
    String action,
    Map<String, dynamic> body,
  ) async {
    final secret = body['secret'];
    final state = secret is String ? _offers[secret] : null;
    if (state == null ||
        !_valid(state) ||
        body['ledgerId'] != state.offer.ledgerId)
      throw lanAuthentication;
    if (action == 'cancel') {
      if (state.reverseToken == null ||
          body['reverseToken'] != base64Encode(state.reverseToken!))
        throw lanAuthentication;
      state.cancelled = true;
      if (state.completed)
        await peers.revoke(state.offer.ledgerId, state.guest!.deviceId);
      return {};
    }
    if (action == 'prepare') {
      if (state.consumed) throw lanAuthentication;
      state.consumed = true; // Reserve synchronously before any await.
      try {
        final guest = LanCertificate.fromJson(jsonMap(body['guest']));
        final address = body['address'] as String, port = body['port'] as int;
        validateLanEndpoint(address, port);
        if (guest.deviceId == identity.deviceId) throw lanAuthentication;
        final reverse = body['reverseToken'] as String;
        final token = base64Decode(reverse);
        if (token.length != 32) throw lanAuthentication;
        await guest.validate();
        if (!guest.verify(
          _claim(state.offer, guest, address, port, reverse),
          base64Decode(body['signature'] as String),
        ))
          throw lanAuthentication;
        state.guest = guest;
        state.reverseToken = token;
        if (!_valid(state) ||
            !await confirm(guest).timeout(_remaining(state)) ||
            !_valid(state))
          throw lanAuthentication;
        state.guest = guest;
        state.address = address;
        state.port = port;
        state.reverseToken = token;
        state.session = base64Encode(secureBytes(32));
        return {'session': state.session};
      } on Object {
        state.cancelled = true;
        throw lanAuthentication;
      }
    }
    if (action != 'finalize' ||
        state.session == null ||
        body['session'] != state.session ||
        state.guest == null)
      throw lanAuthentication;
    state.session = null; // One finalize only, including concurrent requests.
    final guest = state.guest!;
    try {
      final grant = await authorizeLedger!(
        state.offer.ledgerId,
      ).timeout(_remaining(state));
      if (!_valid(state) || grant.metadata.id != state.offer.ledgerId)
        throw lanAuthentication;
      final inbound = secureBytes(32);
      final peer = PairedPeer(
        pairingId: newId(),
        ledgerId: state.offer.ledgerId,
        localDeviceId: identity.deviceId,
        localFingerprint: identity.certificate.fingerprint,
        certificate: guest,
        address: state.address!,
        port: state.port!,
        credentialRef:
            'lan.peer.${state.offer.ledgerId}.${guest.deviceId}.secret',
      );
      await peers.save(
        peer,
        inboundToken: inbound,
        outboundToken: state.reverseToken!,
        stillValid: () => _valid(state),
      );
      if (!_valid(state)) {
        await peers.revoke(peer.ledgerId, guest.deviceId);
        throw lanAuthentication;
      }
      state.completed = true;
      return {
        'metadata': grant.metadata.toJson(),
        'root': base64Encode(grant.keys.rootKey),
        'token': base64Encode(inbound),
      };
    } on Object {
      state.cancelled = true;
      rethrow;
    }
  }

  Future<PairedPeer> join(
    PairingOffer offer, {
    CancellationToken? cancellation,
    String localAddress = '127.0.0.1',
    int localPort = 1,
  }) async {
    final elapsed = Stopwatch()..start();
    final lifetime = offer.expiresAt.difference(offer.issuedAt);
    Duration remaining() => lifetime - elapsed.elapsed;
    bool valid() =>
        !_closed &&
        cancellation?.isCancelled != true &&
        remaining() > Duration.zero;
    // The host owns expiry. Bound the guest wait monotonically; an authenticated
    // 120s offer interval does not require identical clocks on two devices.
    if (!valid() || lifetime > const Duration(seconds: 120))
      throw lanAuthentication;
    await offer.certificate.validate();
    await identity.certificate.validate();
    if (!valid() ||
        !await confirm(
          offer.certificate,
        ).timeout(remaining(), onTimeout: () => false) ||
        !valid())
      throw const EchoFailure('cancelled', '配对已取消');
    final client = LanHttp(offer.certificate, offer.address, offer.port);
    _clients.add(client);
    final reverse = secureBytes(32), reverseString = base64Encode(reverse);
    final common = <String, Object?>{
      'ledgerId': offer.ledgerId,
      'secret': base64Encode(offer._secret),
    };
    var succeeded = false;
    try {
      final signature = await identity.sign(
        _claim(
          offer,
          identity.certificate,
          localAddress,
          localPort,
          reverseString,
        ),
      );
      final prepared = await client.json(
        'POST',
        '/pair/prepare',
        {
          ...common,
          'guest': identity.certificate.toJson(),
          'address': localAddress,
          'port': localPort,
          'reverseToken': reverseString,
          'signature': base64Encode(signature),
        },
        cancellation: cancellation,
        budget: remaining(),
      );
      if (!valid()) throw const EchoFailure('cancelled', '配对已取消');
      final grant = await client.json(
        'POST',
        '/pair/finalize',
        {...common, 'session': prepared['session']},
        cancellation: cancellation,
        budget: remaining(),
      );
      if (!valid()) throw lanAuthentication;
      final metadata = LedgerMetadata.fromJson(jsonMap(grant['metadata']));
      if (metadata.id != offer.ledgerId) throw lanAuthentication;
      final authorized = AuthorizedLedger(
        metadata,
        LedgerKeys(offer.ledgerId, base64Decode(grant['root'] as String)),
      );
      final peer = PairedPeer(
        pairingId: newId(),
        ledgerId: offer.ledgerId,
        localDeviceId: identity.deviceId,
        localFingerprint: identity.certificate.fingerprint,
        certificate: offer.certificate,
        address: offer.address,
        port: offer.port,
        credentialRef:
            'lan.peer.${offer.ledgerId}.${offer.certificate.deviceId}.secret',
        authorizedLedger: authorized,
      );
      await peers.save(
        peer,
        inboundToken: reverse,
        outboundToken: base64Decode(grant['token'] as String),
        stillValid: valid,
      );
      succeeded = true;
      return peer;
    } on EchoFailure {
      rethrow;
    } on Object {
      throw lanAuthentication;
    } finally {
      if (!succeeded) {
        final cancel = LanHttp(offer.certificate, offer.address, offer.port);
        try {
          await cancel.json('POST', '/pair/cancel', {
            ...common,
            'reverseToken': reverseString,
          }, budget: const Duration(seconds: 2));
        } on Object {
          /* Remote expiry still fails closed. */
        } finally {
          cancel.close();
        }
      }
      client.close();
      _clients.remove(client);
    }
  }

  Future<void> close() async {
    _closed = true;
    for (final state in _offers.values) {
      state.cancelled = true;
    }
    _offers.clear();
    for (final client in _clients) {
      client.close();
    }
    _clients.clear();
  }
}

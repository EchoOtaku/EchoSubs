import 'dart:async';
import 'dart:io';
import 'package:echo_subs/core/crypto/key_vault.dart';
import 'package:echo_subs/core/crypto/envelope_codec.dart';
import 'package:echo_subs/core/crypto/ledger_metadata.dart';
import 'package:echo_subs/features/sync/sync_engine.dart';
import 'package:echo_subs/features/sync/transports/lan_identity.dart';
import 'package:echo_subs/features/sync/transports/lan_pairing.dart';
import 'package:echo_subs/features/sync/transports/lan_server.dart';
import 'package:echo_subs/features/sync/transports/lan_transport.dart';
import 'package:echo_subs/storage/app_database.dart';
import 'package:echo_subs/storage/ledger_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import '../test/sync/lan_pairing_test.dart' show MemoryVault, Token;
import '../test/sync/sync_fixture.dart';

/// Explicit native test entrypoint, never imports/runs the production bootstrap.
/// Run on Windows and Android together. The controller prepares the guest first,
/// then delivers a fictional 120s offer through `adb shell run-as ... dd` stdin.
/// No secret is passed in dart-defines, logs or an unauthenticated HTTP endpoint.
/// Use support/run_native.ps1: separate Android applicationId, APK guard and
/// --no-uninstall are mandatory. Never run this against the production package.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native Windows Android pinned TLS and two-way authorized exchange',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Center(child: Text('隔离的局域网 TLS 集成测试'))),
        ),
      );
      await tester.runAsync(() async {
        if (Platform.isWindows) {
          await _host();
        } else if (Platform.isAndroid) {
          await _guest();
        } else {
          throw StateError('This test requires Windows or Android.');
        }
      });
    },
    timeout: const Timeout(Duration(minutes: 12)),
  );
}

Future<void> _until(Future<bool> Function() condition, Duration budget) async {
  final end = DateTime.now().add(budget);
  while (!await condition()) {
    if (DateTime.now().isAfter(end))
      throw TimeoutException('native test checkpoint');
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
}

Future<void> _host() async {
  final path = Platform.environment['ECHOSUBS_LAN_TEST_DIR'];
  if (path == null)
    throw StateError('Set the isolated non-secret test directory.');
  final control = Directory(path);
  await control.create(recursive: true);
  final fixture = await SyncFixture.create(await createLedgerBundle(id(1)));
  final vault = KeyVault(storage: MemoryVault());
  final identity = await LanIdentity.loadOrCreate(vault, id(2));
  final peers = LanPeerStore(vault);
  var confirmations = 0;
  final pairing = PairingService(
    identity: identity,
    peers: peers,
    confirm: (peer) async {
      expect(peer.deviceId, id(3));
      confirmations++;
      return true;
    },
    authorizeLedger: (_) async =>
        AuthorizedLedger(fixture.bundle.metadata, fixture.bundle.keys),
  );
  final server = LanServer(
    identity: identity,
    peers: peers,
    pairing: pairing,
    access: LanLedgerAccess(fixture.store, (object) async {
      await fixture.engine.ingest(object);
    }),
  );
  LanTransport? reverse;
  try {
    await fixture.engine.ingest(await fixture.seal(base));
    await server.start(
      enabled: true,
      foreground: true,
      address: InternetAddress.loopbackIPv4,
      port: 43177,
    );
    await _until(
      () => File('${control.path}/guest-ready.txt').exists(),
      const Duration(minutes: 8),
    );
    final offer = await pairing.offer(
      ledgerId: id(1),
      address: '127.0.0.1',
      port: 43177,
    );
    await File(
      '${control.path}/offer.json',
    ).writeAsString(offer.encode(), flush: true);
    // Only non-secret checkpoints are emitted.
    debugPrint('LAN_NATIVE_HOST_OFFER_READY');
    await _until(
      () async => (await fixture.store.objects()).any((o) => o.batchId == a.id),
      const Duration(seconds: 100),
    );
    final peer = await peers.get(id(1), id(3));
    expect(peer, isNotNull);
    expect(confirmations, 1);
    reverse = LanTransport(peer: peer!, localDeviceId: id(2), peers: peers);
    expect((await reverse.readMetadata()).id, id(1));
    final refs = await reverse.listObjects(Token()).toList();
    expect(refs.map((r) => r.batchId), containsAll([base.id, a.id]));
    final guestObject = await reverse.read(
      refs.firstWhere((r) => r.batchId == a.id),
    );
    expect(
      guestObject.bytes,
      (await fixture.store.objects())
          .firstWhere((o) => o.batchId == a.id)
          .bytes,
    );
    await reverse.put(await fixture.seal(b));
    await _until(
      () async => (await reverse!.listObjects(Token()).toList()).any(
        (r) => r.batchId == b.id,
      ),
      const Duration(seconds: 20),
    );
    debugPrint(
      'LAN_NATIVE_HOST_PASS: pinned TLS, approvals, guest upload, reverse read/write',
    );
    await File('${control.path}/host-pass.txt').writeAsString('PASS');
  } finally {
    await reverse?.close();
    await server.close();
    await pairing.close();
    await fixture.close();
    final offerFile = File('${control.path}/offer.json');
    if (await offerFile.exists()) await offerFile.delete();
  }
}

Future<void> _guest() async {
  final support = await getApplicationSupportDirectory();
  if (!support.path
      .replaceAll('\\', '/')
      .contains('/dev.echootaku.echo_subs.integration/')) {
    throw StateError(
      'Refusing native integration work outside the isolated test application.',
    );
  }
  final ready = File('${support.path}/lan-task7-ready.txt');
  final offerFile = File('${support.path}/lan-task7-offer.json');
  final vault = KeyVault(storage: MemoryVault());
  final identity = await LanIdentity.loadOrCreate(vault, id(3));
  final peers = LanPeerStore(vault);
  var confirmations = 0;
  final pairing = PairingService(
    identity: identity,
    peers: peers,
    confirm: (peer) async {
      expect(peer.deviceId, id(2));
      confirmations++;
      return true;
    },
  );
  AppDatabase? db;
  LanTransport? transport;
  LanServer? server;
  try {
    // Identity generation and native startup finish before the short offer exists.
    await ready.writeAsString('READY', flush: true);
    debugPrint('LAN_NATIVE_GUEST_READY');
    await _until(offerFile.exists, const Duration(minutes: 8));
    final peer = await pairing.join(
      PairingOffer.decode(await offerFile.readAsString()),
      localAddress: '127.0.0.1',
      localPort: 43178,
    );
    final grant = peer.authorizedLedger!;
    final temporary = await Directory.systemTemp.createTemp(
      'echosubs-lan-native-',
    );
    db = await AppDatabase.open(File('${temporary.path}/guest.sqlite'));
    final store = LedgerStore(db, grant.metadata.id);
    await store.transaction((tx) => tx.register(grant.metadata));
    final engine = SyncEngine(store, grant.keys);
    transport = LanTransport(peer: peer, localDeviceId: id(3), peers: peers);
    expect((await transport.readMetadata()).encode(), grant.metadata.encode());
    for (final ref in await transport.listObjects(Token()).toList()) {
      await engine.ingest(await transport.read(ref));
    }
    server = LanServer(
      identity: identity,
      peers: peers,
      pairing: pairing,
      access: LanLedgerAccess(store, (object) async {
        await engine.ingest(object);
      }),
    );
    await server.start(
      enabled: true,
      foreground: true,
      address: InternetAddress.loopbackIPv4,
      port: 43178,
    );
    final bytes = await StoredObject.fromBytes(
      a,
      await EnvelopeCodec().seal(a, grant.keys),
    );
    await engine.ingest(bytes);
    await transport.put(bytes);
    await _until(
      () async => (await store.objects()).any((o) => o.batchId == b.id),
      const Duration(seconds: 40),
    );
    expect(confirmations, 1);
    // Leave time for the Windows side to verify the committed reverse write.
    await Future<void>.delayed(const Duration(seconds: 3));
    debugPrint(
      'LAN_NATIVE_GUEST_PASS: Android TLS, pin, root handoff, both directions',
    );
  } finally {
    await transport?.close();
    await server?.close();
    await pairing.close();
    await db?.close();
    if (await ready.exists()) await ready.delete();
    if (await offerFile.exists()) await offerFile.delete();
  }
}

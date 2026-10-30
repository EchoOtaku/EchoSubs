import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:echo_subs/core/crypto/key_vault.dart';
import 'package:echo_subs/core/crypto/ledger_metadata.dart';
import 'package:echo_subs/core/model/errors.dart';
import 'package:echo_subs/features/sync/transports/lan_identity.dart';
import 'package:echo_subs/features/sync/transports/lan_pairing.dart';
import 'package:echo_subs/features/sync/transports/lan_server.dart';
import 'package:echo_subs/features/sync/transports/lan_transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'sync_fixture.dart';

class MemoryVault implements VaultStorage {
  final values = <String, String>{};
  String? failName;
  String? failValue;
  bool failActiveMarker = false;
  bool failReads = false;
  Future<void> Function(String name)? beforeRead;
  Future<void> Function(String name, String value)? beforeWrite;
  @override
  Future<String?> read(String name) async {
    await beforeRead?.call(name);
    if (failReads) throw StateError('test storage unavailable');
    return values[name];
  }

  @override
  Future<void> write(String name, String value) async {
    await beforeWrite?.call(name, value);
    if ((name == failName && (failValue == null || value == failValue)) ||
        (failActiveMarker &&
            name.endsWith('.state') &&
            base64Decode(value).first == 1))
      throw StateError('test interrupted write');
    values[name] = value;
  }
}

class Token implements CancellationToken {
  @override
  bool isCancelled = false;
}

class LanFixture {
  late SyncFixture data;
  late LanIdentity host, guest;
  final hostStorage = MemoryVault(), guestStorage = MemoryVault();
  late KeyVault hostVault = KeyVault(storage: hostStorage);
  late KeyVault guestVault = KeyVault(storage: guestStorage);
  late LanPeerStore hosts = LanPeerStore(hostVault),
      guests = LanPeerStore(guestVault);
  late PairingService hostPairing, guestPairing;
  late LanServer server;
  DateTime now = DateTime.now().toUtc();
  Duration guestClockOffset = Duration.zero;
  Future<bool> Function(LanCertificate)? hostConfirm;
  bool guestConfirm = true;
  static Future<LanFixture> create() async {
    final f = LanFixture();
    f.data = await SyncFixture.create(await createLedgerBundle(id(1)));
    await f.data.engine.ingest(await f.data.seal(base));
    f.host = await LanIdentity.loadOrCreate(f.hostVault, id(2));
    f.guest = await LanIdentity.loadOrCreate(f.guestVault, id(3));
    f.hostPairing = PairingService(
      identity: f.host,
      peers: f.hosts,
      confirm: (peer) => f.hostConfirm?.call(peer) ?? Future.value(true),
      now: () => f.now,
      authorizeLedger: (ledger) async =>
          AuthorizedLedger(f.data.bundle.metadata, f.data.bundle.keys),
    );
    f.guestPairing = PairingService(
      identity: f.guest,
      peers: f.guests,
      confirm: (_) async => f.guestConfirm,
      now: () => f.now.add(f.guestClockOffset),
    );
    f.server = LanServer(
      identity: f.host,
      peers: f.hosts,
      pairing: f.hostPairing,
      access: LanLedgerAccess(f.data.store, (object) async {
        await f.data.engine.ingest(object);
      }),
    );
    await f.server.start(
      enabled: true,
      foreground: true,
      address: InternetAddress.loopbackIPv4,
    );
    return f;
  }

  Future<PairingOffer> offer() => hostPairing.offer(
    ledgerId: id(1),
    address: '127.0.0.1',
    port: server.port,
  );
  Future<void> close() async {
    await server.close();
    await hostPairing.close();
    await guestPairing.close();
    await data.close();
  }
}

void main() {
  late LanFixture f;
  setUp(() async {
    f = await LanFixture.create();
  });
  tearDown(() async {
    await f.close();
  });
  for (final skew in [-3, 3]) {
    test(
      'immediate offer accepts guest clock skew $skew seconds; host TTL remains strict',
      () async {
        f.guestClockOffset = Duration(seconds: skew);
        final peer = await f.guestPairing.join(await f.offer());
        expect(peer.authorizedLedger, isNotNull);
        final expired = await f.offer();
        f.now = f.now.add(const Duration(seconds: 120));
        await expectLater(
          f.guestPairing.join(expired),
          throwsA(isA<EchoFailure>()),
        );
      },
    );
  }
  test('offer expires at 120 seconds and reveals no business data', () async {
    final offer = await f.offer();
    expect(offer.expiresAt.difference(f.now), const Duration(seconds: 120));
    f.now = f.now.add(const Duration(seconds: 120));
    await expectLater(f.guestPairing.join(offer), throwsA(isA<EchoFailure>()));
    expect(await f.hosts.approvedPeerCount(id(1)), 0);
  });
  test(
    'both confirmations required and denied offer cannot be reused',
    () async {
      f.hostConfirm = (_) async => false;
      final offer = await f.offer();
      await expectLater(
        f.guestPairing.join(offer),
        throwsA(isA<EchoFailure>()),
      );
      f.hostConfirm = (_) async => true;
      await expectLater(
        f.guestPairing.join(offer),
        throwsA(isA<EchoFailure>()),
      );
      expect(await f.hosts.approvedPeerCount(id(1)), 0);
      f.guestConfirm = false;
      await expectLater(
        f.guestPairing.join(await f.offer()),
        throwsA(isA<EchoFailure>()),
      );
      expect(await f.guests.approvedPeerCount(id(1)), 0);
    },
  );
  test(
    'approval expiry and cancellation do not persist authorization',
    () async {
      final gate = Completer<bool>();
      f.hostConfirm = (_) => gate.future;
      final offer = await f.offer();
      final pending = f.guestPairing.join(offer);
      final failure = expectLater(pending, throwsA(isA<EchoFailure>()));
      await Future<void>.delayed(const Duration(milliseconds: 150));
      f.now = f.now.add(const Duration(seconds: 121));
      gate.complete(true);
      await failure;
      expect(await f.hosts.approvedPeerCount(id(1)), 0);
    },
  );
  test(
    'concurrent use authorizes only one peer and root stays in memory',
    () async {
      final offer = await f.offer();
      final results = await Future.wait([
        f.guestPairing
            .join(offer)
            .then<Object>((v) => v, onError: (Object e) => e),
        f.guestPairing
            .join(offer)
            .then<Object>((v) => v, onError: (Object e) => e),
      ]);
      expect(results.whereType<PairedPeer>(), hasLength(1));
      expect(results.whereType<EchoFailure>(), hasLength(1));
      final peer = results.whereType<PairedPeer>().single;
      expect(peer.authorizedLedger!.keys.rootKey, f.data.bundle.keys.rootKey);
      expect(await f.hosts.approvedPeerCount(id(1)), 1);
      expect(await f.guests.approvedPeerCount(id(1)), 1);
      expect(
        f.guestStorage.values.keys.any(
          (k) => k.contains('root') || k.contains('recovery'),
        ),
        false,
      );
      final restored = await LanPeerStore(f.guestVault).get(id(1), id(2));
      expect(restored!.authorizedLedger, isNull);
      final transport = LanTransport(
        peer: restored,
        localDeviceId: id(3),
        peers: f.guests,
      );
      try {
        expect(await transport.listObjects(Token()).toList(), hasLength(1));
      } finally {
        await transport.close();
      }
    },
  );
  test('guest cancels while host confirmation is pending', () async {
    final entered = Completer<void>(), gate = Completer<bool>();
    f.hostConfirm = (_) {
      entered.complete();
      return gate.future;
    };
    final token = Token();
    final pending = f.guestPairing.join(await f.offer(), cancellation: token);
    final failed = expectLater(pending, throwsA(isA<EchoFailure>()));
    await entered.future;
    token.isCancelled = true;
    await failed;
    gate.complete(true);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(await f.hosts.approvedPeerCount(id(1)), 0);
  });
  test(
    'host cancels while approval awaits and old offer is invalid after replacement',
    () async {
      final old = await f.offer();
      await f.offer();
      await expectLater(f.guestPairing.join(old), throwsA(isA<EchoFailure>()));
      final offer = await f.offer();
      f.hostConfirm = (_) async {
        f.hostPairing.cancelOffer(offer);
        return true;
      };
      await expectLater(
        f.guestPairing.join(offer),
        throwsA(isA<EchoFailure>()),
      );
      expect(await f.hosts.approvedPeerCount(id(1)), 0);
    },
  );
  test('bad signature consumes offer without invoking host approval', () async {
    var calls = 0;
    f.hostConfirm = (_) async {
      calls++;
      return true;
    };
    final offer = await f.offer();
    final http = LanHttp(f.host.certificate, offer.address, offer.port);
    try {
      await expectLater(
        http.json('POST', '/pair/prepare', {
          'secret': offer.toJson()['secret'],
          'ledgerId': id(1),
          'guest': f.guest.certificate.toJson(),
          'address': '127.0.0.1',
          'port': 1,
          'reverseToken': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
          'signature': 'AA==',
        }),
        throwsA(isA<EchoFailure>()),
      );
      await expectLater(
        f.guestPairing.join(offer),
        throwsA(isA<EchoFailure>()),
      );
      expect(calls, 0);
      expect(await f.hosts.approvedPeerCount(id(1)), 0);
    } finally {
      http.close();
    }
  });
  for (final suffix in ['.secret', '.record', 'index', '.state']) {
    test(
      'vault interrupted $suffix write cannot activate partial peer after reopen',
      () async {
        final offer = await f.offer();
        f.hostStorage.failName = suffix == 'index'
            ? 'echosubs.v1.lan.index.${id(1)}'
            : 'echosubs.v1.lan.peer.${id(1)}.${id(3)}$suffix';
        await expectLater(
          f.guestPairing.join(offer),
          throwsA(isA<EchoFailure>()),
        );
        f.hostStorage.failName = null;
        expect(await LanPeerStore(f.hostVault).get(id(1), id(3)), isNull);
        expect(await f.guests.approvedPeerCount(id(1)), 0);
      },
    );
  }
  test('guest persistence failure cancels the host authorization', () async {
    f.guestStorage.failName = 'echosubs.v1.lan.index.${id(1)}';
    await expectLater(
      f.guestPairing.join(await f.offer()),
      throwsA(isA<EchoFailure>()),
    );
    expect(await LanPeerStore(f.hostVault).get(id(1), id(3)), isNull);
  });
  test('failed final activation marker is unusable after reopen', () async {
    f.hostStorage.failActiveMarker = true;
    await expectLater(
      f.guestPairing.join(await f.offer()),
      throwsA(isA<EchoFailure>()),
    );
    final restoredVault = KeyVault(storage: f.hostStorage);
    expect(await LanPeerStore(restoredVault).get(id(1), id(3)), isNull);
  });
  test(
    'concurrent revoke survives blocked activation and failed tombstone',
    () async {
      final peer = await f.guestPairing.join(await f.offer());
      final replacement = PairedPeer.fromJson({
        ...peer.toJson(),
        'pairingId': id(901),
      });
      final stateName = 'echosubs.v1.lan.peer.${id(1)}.${id(2)}.state';
      final entered = Completer<void>(), release = Completer<void>();
      var blocked = false;
      f.guestStorage.beforeWrite = (name, value) async {
        if (name == stateName && base64Decode(value).first == 1 && !blocked) {
          blocked = true;
          entered.complete();
          await release.future;
        }
      };
      final saving = f.guests
          .save(
            replacement,
            inboundToken: Uint8List.fromList(List.filled(32, 11)),
            outboundToken: Uint8List.fromList(List.filled(32, 12)),
            stillValid: () => true,
          )
          .then<Object?>((_) => null, onError: (Object error) => error);
      await entered.future.timeout(const Duration(seconds: 5));
      f.guestStorage.failName = stateName;
      f.guestStorage.failValue = base64Encode([0]);
      final revoking = f.guests
          .revoke(id(1), id(2))
          .then<Object?>((_) => null, onError: (Object error) => error);
      release.complete();
      expect(await saving, isA<EchoFailure>());
      expect(await revoking, isA<EchoFailure>());
      // A second store sharing this app's Vault must retain the immediate deny
      // even though the storage backend refused the tombstone.
      expect(await LanPeerStore(f.guestVault).get(id(1), id(2)), isNull);
      expect(base64Decode(f.guestStorage.values[stateName]!).first, 1);
      // The failed tombstone is not magically durable. A later explicit
      // re-pair, however, owns the new revision and may activate fresh tokens.
      f.guestStorage.failName = null;
      final approvedLater = PairedPeer.fromJson({
        ...replacement.toJson(),
        'pairingId': id(903),
      });
      await f.guests.save(
        approvedLater,
        inboundToken: Uint8List.fromList(List.filled(32, 13)),
        outboundToken: Uint8List.fromList(List.filled(32, 14)),
        stillValid: () => true,
      );
      expect((await f.guests.get(id(1), id(2)))!.pairingId, id(903));
    },
  );
  test(
    'token read racing re-pair cannot return new credentials to old identity',
    () async {
      final peer = await f.guestPairing.join(await f.offer());
      final replacementIdentity = await LanIdentity.loadOrCreate(
        KeyVault(storage: MemoryVault()),
        id(2),
      );
      final replacement = PairedPeer.fromJson({
        ...peer.toJson(),
        ...replacementIdentity.certificate.toJson(),
        'pairingId': id(902),
        'address': '127.0.0.2',
      });
      final secretName = 'echosubs.v1.${peer.credentialRef}';
      final entered = Completer<void>(), release = Completer<void>();
      var reads = 0;
      f.guestStorage.beforeRead = (name) async {
        // First read belongs to get(), second is token()'s credential fetch.
        if (name == secretName && ++reads == 2) {
          entered.complete();
          await release.future;
        }
      };
      final oldTokenAccepted = f.guests
          .token(peer, inbound: false)
          .then<bool>(
            (_) => true,
            onError: (Object error) {
              expect(error, isA<EchoFailure>());
              return false;
            },
          );
      await entered.future.timeout(const Duration(seconds: 5));
      await f.guests.save(
        replacement,
        inboundToken: Uint8List.fromList(List.filled(32, 21)),
        outboundToken: Uint8List.fromList(List.filled(32, 22)),
        stillValid: () => true,
      );
      release.complete();
      // Assert a boolean so a regression never prints credential material.
      expect(await oldTokenAccepted, false);
      final current = await f.guests.get(id(1), id(2));
      expect(
        current!.certificate.fingerprint,
        replacementIdentity.certificate.fingerprint,
      );
      expect((await f.guests.token(current, inbound: false)).length, 32);
    },
  );
  test(
    'joining never overwrites already registered root and recovery slots',
    () async {
      final root = Uint8List.fromList(List.filled(32, 7)),
          recovery = Uint8List.fromList(List.filled(32, 9));
      await f.guestVault.put('ledger.${id(1)}.root', root);
      await f.guestVault.put('ledger.${id(1)}.recovery', recovery);
      await f.guestPairing.join(await f.offer());
      expect(await f.guestVault.get('ledger.${id(1)}.root'), root);
      expect(await f.guestVault.get('ledger.${id(1)}.recovery'), recovery);
    },
  );
  test(
    'peer capacity is explicit unavailable, never silently truncated',
    () async {
      await f.hostVault.put(
        'lan.index.${id(1)}',
        Uint8List.fromList(
          utf8.encode(jsonEncode(List.generate(64, (n) => id(1000 + n)))),
        ),
      );
      await expectLater(
        f.guestPairing.join(await f.offer()),
        throwsA(
          isA<EchoFailure>().having((e) => e.code, 'code', 'unavailable'),
        ),
      );
    },
  );
  test('offer interval longer than 120 seconds is rejected', () async {
    final offer = await f.offer();
    final map = offer.toJson()
      ..['issuedAt'] = offer.issuedAt
          .subtract(const Duration(seconds: 1))
          .toIso8601String();
    expect(() => PairingOffer.fromJson(map), throwsA(isA<EchoFailure>()));
  });
  test(
    'revocation survives reopen; storage read failures fail closed',
    () async {
      await f.guestPairing.join(await f.offer());
      f.hostStorage.failReads = true;
      await expectLater(f.hosts.get(id(1), id(3)), throwsA(isA<EchoFailure>()));
      f.hostStorage.failReads = false;
      await f.hosts.revoke(id(1), id(3));
      expect(await LanPeerStore(f.hostVault).get(id(1), id(3)), isNull);
    },
  );
  test(
    'identity survives restart and partial identity never silently regenerates',
    () async {
      final identity = await LanIdentity.loadOrCreate(f.hostVault, id(2));
      expect(identity.certificate.der, f.host.certificate.der);
      final storage = MemoryVault();
      final vault = KeyVault(storage: storage);
      await vault.put('lan.identity.${id(9)}.key', Uint8List.fromList([1]));
      await expectLater(
        LanIdentity.loadOrCreate(vault, id(9)),
        throwsA(isA<EchoFailure>()),
      );
      expect(storage.values, hasLength(1));
    },
  );
}

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:basic_utils/basic_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:echo_subs/app/services.dart';
import 'package:echo_subs/core/crypto/key_vault.dart';
import 'package:echo_subs/core/model/errors.dart';
import 'package:echo_subs/core/model/ids.dart';
import 'package:echo_subs/core/model/subscription.dart';
import 'package:echo_subs/features/backup/backup_service.dart';
import 'package:echo_subs/features/sync/sync_state_store.dart';
import 'package:echo_subs/features/sync/sync_status.dart';
import 'package:echo_subs/features/ledger/ledger_repository.dart';
import 'package:echo_subs/features/sync/sync_runtime.dart';
import 'package:echo_subs/features/sync/transports/lan_identity.dart';
import 'package:echo_subs/features/sync/transports/lan_pairing.dart';
import 'package:echo_subs/features/sync/ui/pairing_page.dart';
import '../sync/lan_pairing_test.dart' show LanFixture;
import '../sync/sync_fixture.dart' show id;
import '../support/ledger_harness.dart';

Future<void> expire(LanFixture f) async {
  final bytes = (await f.hostVault.get('lan.identity.${id(2)}.key'))!;
  final key = CryptoUtils.rsaPrivateKeyFromPemPkcs1(utf8.decode(bytes));
  final public = RSAPublicKey(key.modulus!, key.publicExponent!);
  final dns = '${id(2)}.echosubs.invalid';
  final pem = X509Utils.generateSelfSignedCertificate(
    key,
    X509Utils.generateRsaCsrPem({'CN': dns}, key, public),
    365,
    sans: [dns],
    cA: true,
    notBefore: DateTime.utc(2000),
  );
  final der = base64Decode(
    pem
        .split('\n')
        .map((s) => s.trim())
        .where((s) => !s.startsWith('---'))
        .join(),
  );
  await f.hostVault.put('lan.identity.${id(2)}.cert', der);
}

void main() {
  test(
    'I6 corrupt LAN identity does not block local bootstrap edit or backup',
    () async {
      final h = await LedgerHarness.create();
      AppServices? services;
      try {
        await h.vault.put(
          AppServices.deviceIdKey,
          Uint8List.fromList(utf8.encode(h.repo.deviceId)),
        );
        await h.vault.put(
          'lan.identity.${h.repo.deviceId}.cert',
          Uint8List.fromList([1, 2, 3]),
        );
        await h.vault.put(
          'lan.identity.${h.repo.deviceId}.key',
          Uint8List.fromList([4, 5, 6]),
        );
        await SyncStateStore(h.db, h.repo.currentLedgerId!).save(
          ChannelConfig(SyncChannelKind.lan, newId(), true, {
            'address': '127.0.0.1',
            'port': 43177,
          }),
        );
        services = await AppServices.bootstrap(database: h.db, vault: h.vault);
        expect(services.syncRuntime.pairing, isNull);
        expect(services.syncRuntime.runtimeError, isNotNull);
        await services.saveSubscription(
          Subscription(id: newId(), name: '局域网身份损坏仍可本地保存'),
        );
        expect(services.subscriptions.length, 1);
        expect(
          await BackupService(services.ledger).exportEncrypted(),
          isNotEmpty,
        );
      } finally {
        await services?.syncRuntime.close();
        services?.dispose();
        await h.close();
      }
    },
  );
  for (final failSuffix in ['.key', '.cert', '.active']) {
    test(
      'I6 staged identity write failure $failSuffix leaves old slots, revokes old tokens and supports explicit retry',
      () async {
        HttpOverrides.global = null;
        final f = await LanFixture.create();
        final repo = LedgerRepository(f.data.db, f.hostVault, id(2));
        await f.hostVault.put(
          LedgerRepository.rootKeyName(id(1)),
          f.data.bundle.keys.rootKey,
        );
        await repo.selectLedger(id(1));
        final runtime = SyncRuntime(
          repo,
          attach: (_) {},
          detach: () async {},
          select: (_) async {},
        );
        try {
          await f.guestPairing.join(await f.offer());
          final peer = (await f.hosts.list(id(1))).single;
          await expire(f);
          final oldKey = await f.hostVault.get('lan.identity.${id(2)}.key');
          final oldCert = await f.hostVault.get('lan.identity.${id(2)}.cert');
          f.hostStorage.beforeWrite = (name, value) async {
            if (name.startsWith('echosubs.v1.lan.identity.') &&
                name.endsWith(failSuffix))
              throw StateError('synthetic interrupted write');
          };
          await expectLater(
            runtime.renewLanIdentity(confirmed: true, expectedLedgerId: id(1)),
            throwsA(isA<EchoFailure>()),
          );
          final reopened = KeyVault(storage: f.hostStorage);
          expect(await reopened.get('lan.identity.${id(2)}.active'), isNull);
          expect(await reopened.get('lan.identity.${id(2)}.key'), oldKey);
          expect(await reopened.get('lan.identity.${id(2)}.cert'), oldCert);
          await expectLater(
            LanPeerStore(reopened).token(peer, inbound: true),
            throwsA(isA<EchoFailure>()),
          );
          await expectLater(
            LanIdentity.loadOrCreate(reopened, id(2)),
            throwsA(isA<EchoFailure>()),
          );
          f.hostStorage.beforeWrite = null;
          await runtime.renewLanIdentity(
            confirmed: true,
            expectedLedgerId: id(1),
          );
          await (await LanIdentity.loadOrCreate(
            reopened,
            id(2),
          )).certificate.validate();
        } finally {
          await runtime.close();
          await f.close();
        }
      },
    );
  }
  test(
    'I6 explicit renewal handles expired persisted identity, invalidates old token and survives reopen',
    () async {
      HttpOverrides.global = null;
      final f = await LanFixture.create();
      final repo = LedgerRepository(f.data.db, f.hostVault, id(2));
      await f.hostVault.put(
        LedgerRepository.rootKeyName(id(1)),
        f.data.bundle.keys.rootKey,
      );
      await repo.selectLedger(id(1));
      final runtime = SyncRuntime(
        repo,
        attach: (_) {},
        detach: () async {},
        select: (_) async {},
      );
      try {
        final oldPeer = await f.guestPairing.join(await f.offer());
        final hostPeer = (await f.hosts.list(id(1))).single;
        await expire(f);
        final oldSlots = Map.of(f.hostStorage.values);
        final batches = (await repo.snapshot()).batches;
        await expectLater(
          LanIdentity.loadOrCreate(f.hostVault, id(2)),
          throwsA(isA<EchoFailure>()),
        );
        expect(f.hostStorage.values, oldSlots);
        await expectLater(
          runtime.renewLanIdentity(confirmed: false, expectedLedgerId: id(1)),
          throwsA(isA<EchoFailure>()),
        );
        expect(f.hostStorage.values, oldSlots);
        await runtime.renewLanIdentity(
          confirmed: true,
          expectedLedgerId: id(1),
        );
        final reopenedVault = KeyVault(storage: f.hostStorage);
        final identity = await LanIdentity.loadOrCreate(reopenedVault, id(2));
        expect(
          identity.certificate.fingerprint,
          isNot(f.host.certificate.fingerprint),
        );
        final reopenedPeers = LanPeerStore(reopenedVault);
        expect(await reopenedPeers.list(id(1)), isEmpty);
        await expectLater(
          reopenedPeers.token(hostPeer, inbound: true),
          throwsA(isA<EchoFailure>()),
        );
        expect(oldPeer.localFingerprint, f.guest.certificate.fingerprint);
        expect((await repo.snapshot()).batches, batches);
        expect(
          await reopenedVault.get(LedgerRepository.rootKeyName(id(1))),
          f.data.bundle.keys.rootKey,
        );
        for (final suffix in ['key', 'cert']) {
          final name = 'echosubs.v1.lan.identity.${id(2)}.$suffix';
          expect(f.hostStorage.values[name], oldSlots[name]);
        }
      } finally {
        await runtime.close();
        await f.close();
      }
    },
  );
  testWidgets('I6 identity update requires an explicit UI confirmation', (
    tester,
  ) async {
    final h = (await tester.runAsync(LedgerHarness.create))!;
    final services = (await tester.runAsync(() async {
      final s = AppServices(ledger: h.repo);
      await s.ready;
      return s;
    }))!;
    await tester.runAsync(
      () => tester.pumpWidget(
        MaterialApp(
          home: PairingPage(services: services, addresses: () async => []),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('更新本机局域网身份'));
    await tester.pumpAndSettle();
    expect(find.textContaining('旧配对'), findsWidgets);
    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('取消')),
    );
    await tester.pumpAndSettle();
    expect(
      await tester.runAsync(
        () => h.vault.get('lan.identity.${h.repo.deviceId}.active'),
      ),
      isNull,
    );
    await tester.tap(find.text('更新本机局域网身份'));
    await tester.pumpAndSettle();
    await tester.runAsync(() => tester.tap(find.text('确认更新并重新配对')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      await tester.runAsync(
        () => h.vault.get('lan.identity.${h.repo.deviceId}.active'),
      ),
      isNotNull,
    );
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      services.dispose();
      await h.close();
    });
  });
}

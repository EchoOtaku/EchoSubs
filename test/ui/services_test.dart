import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:echo_subs/app/services.dart';
import 'package:echo_subs/core/crypto/ledger_metadata.dart';
import 'package:echo_subs/core/crypto/ledger_keys.dart';
import 'package:echo_subs/core/model/errors.dart';
import 'package:echo_subs/core/model/ids.dart';
import 'package:echo_subs/core/model/ledger.dart';
import 'package:echo_subs/core/model/subscription.dart';
import 'package:echo_subs/features/ledger/ledger_repository.dart';
import '../support/ledger_harness.dart';
import '../ledger/repository_test.dart' show Fixture;
import '../sync/coordinator_test.dart' show MemoryChannel, Token;
import 'package:echo_subs/features/sync/sync_runtime.dart';
import 'package:echo_subs/features/sync/sync_state_store.dart';
import 'package:echo_subs/features/sync/sync_coordinator.dart';
import 'package:echo_subs/features/sync/sync_status.dart';

class GatedRuntime extends SyncRuntime {
  GatedRuntime(super.repository)
    : super(attach: (_) {}, detach: () async {}, select: (_) async {});
  final entered = Completer<void>(), release = Completer<void>();
  @override
  Future<List<ChannelConfig>> configs() async {
    final values = await super.configs();
    entered.complete();
    await release.future;
    return values;
  }

  @override
  Future<void> rebind() async {}
}

void main() {
  for (final switchLedger in [true, false]) {
    test(
      'channel toggle cannot write across awaited ${switchLedger ? 'ledger switch' : 'endpoint replacement'}',
      () async {
        final h = await LedgerHarness.create();
        final first = h.repo.currentLedgerId!;
        final second = newId();
        await h.repo.create(
          LedgerConfig(second, 'UTC'),
          await createLedgerBundle(second),
        );
        await h.repo.selectLedger(first);
        final old = ChannelConfig(
          SyncChannelKind.webdav,
          'first-endpoint',
          false,
          {'root': 'https://fictional.example/first/'},
        );
        final replacement = ChannelConfig(
          SyncChannelKind.webdav,
          'second-endpoint',
          false,
          {'root': 'https://fictional.example/second/'},
        );
        await SyncStateStore(h.db, first).save(old);
        await SyncStateStore(h.db, second).save(replacement);
        final runtime = GatedRuntime(h.repo);
        try {
          final pending = runtime.setEnabled(old, true);
          await runtime.entered.future;
          if (switchLedger) {
            await h.repo.selectLedger(second);
          } else {
            await SyncStateStore(h.db, first).save(replacement);
          }
          runtime.release.complete();
          await expectLater(pending, throwsA(isA<EchoFailure>()));
          final actual = (await SyncStateStore(
            h.db,
            switchLedger ? second : first,
          ).configs()).single;
          expect(actual.endpointId, replacement.endpointId);
          expect(actual.settings, replacement.settings);
          expect(actual.enabled, false);
          if (switchLedger) {
            final untouched = (await SyncStateStore(
              h.db,
              first,
            ).configs()).single;
            expect(untouched.endpointId, old.endpointId);
            expect(untouched.enabled, false);
          }
        } finally {
          await runtime.close();
          await h.close();
        }
      },
    );
  }
  test(
    'selection rollback restores the original sync connection and manual sync',
    () async {
      final f = Fixture();
      await f.init();
      final second = newId();
      await f.repo.create(
        LedgerConfig(second, 'UTC'),
        await createLedgerBundle(second),
      );
      await f.repo.selectLedger(f.id);
      final services = AppServices(ledger: f.repo);
      await services.ready;
      final cloud = MemoryChannel(await f.repo.store.metadata());
      var rebinds = 0;
      services.rebindSync = () async {
        rebinds++;
        services.attachSync(
          SyncCoordinator(
            store: f.repo.store,
            authenticate: f.repo.authenticatedKeys,
            channels: [
              SyncChannel(SyncChannelKind.webdav, 'fake', () async => cloud),
            ],
          ),
        );
      };
      try {
        await services.rebindSync!();
        await services.syncCoordinator!.sync(token: Token());
        f.backend.failAt = f.backend.writes + 1;
        await expectLater(
          services.selectLedger(second),
          throwsA(
            isA<EchoFailure>().having(
              (e) => e.safeMessage,
              'original switch failure',
              '安全存储写入失败',
            ),
          ),
        );
        expect(f.repo.currentLedgerId, f.id);
        expect(services.snapshot!.metadata.id, f.id);
        expect(rebinds, 2);
        expect(services.syncCoordinator, isNotNull);
        final value = Subscription(id: newId(), name: '回滚后本地修改');
        await services.saveSubscription(value);
        await services.syncNow();
        await services.syncCoordinator!.sync(token: Token());
        expect(cloud.objects.length, (await f.repo.store.objects()).length);
        f.backend.failAt = null;
        f.backend.beforeWrite = () async {
          f.backend.refuseRead = true;
          throw StateError('injected');
        };
        await expectLater(
          services.selectLedger(second),
          throwsA(
            isA<EchoFailure>().having(
              (e) => e.safeMessage,
              'original switch failure',
              '安全存储写入失败',
            ),
          ),
        );
        expect(services.syncCoordinator, isNull);
        expect(rebinds, 2);
        expect(services.snapshot, isNull);
        await expectLater(
          services.saveSubscription(value),
          throwsA(
            isA<EchoFailure>().having((e) => e.code, 'write lock', 'locked'),
          ),
        );
      } finally {
        f.backend.refuseRead = false;
        await services.detachSync();
        services.dispose();
        await f.dispose();
      }
    },
  );
  test(
    'bootstrap stable device and active ledger selection, rebind watch',
    () async {
      final h = await LedgerHarness.create();
      addTearDown(h.close);
      final first = h.repo.currentLedgerId!;
      final initial = await AppServices.bootstrap(
        database: h.db,
        vault: h.vault,
      );
      final device = initial.ledger.deviceId;
      expect(initial.ledger.currentLedgerId, first);
      final second = newId();
      await initial.ledger.create(
        LedgerConfig(second, 'America/New_York'),
        await createLedgerBundle(second),
      );
      await initial.selectLedger(second);
      final secondSub = Subscription(id: newId(), name: '第二账本');
      await initial.saveSubscription(secondSub);
      await initial.selectLedger(first);
      expect(initial.subscriptions, isEmpty);
      initial.dispose();
      final again = await AppServices.bootstrap(database: h.db, vault: h.vault);
      addTearDown(again.dispose);
      expect(again.ledger.deviceId, device);
      expect(again.ledger.currentLedgerId, first);
      await again.selectLedger(second);
      expect(again.subscriptions.single.name, '第二账本');
      await again.saveSubscription(
        copySubscription(secondSub, {'name': '第二账本已编辑'}),
      );
      expect(again.subscriptions.single.name, '第二账本已编辑');
    },
  );
  test(
    'invalid active selection and locked root preserve database and key',
    () async {
      final h = await LedgerHarness.create();
      addTearDown(h.close);
      final id = h.repo.currentLedgerId!;
      final before = await h.repo.snapshot();
      await h.vault.put(
        AppServices.activeLedgerKey,
        Uint8List.fromList(utf8.encode(newId())),
      );
      await expectLater(
        AppServices.bootstrap(database: h.db, vault: h.vault),
        throwsA(isA<EchoFailure>()),
      );
      expect((await h.repo.snapshot()).batches, before.batches);
      expect(await h.repo.listLedgers(), [id]);
      await h.vault.put(
        AppServices.activeLedgerKey,
        Uint8List.fromList(utf8.encode(id)),
      );
      final wrongRoot = secureBytes(32);
      await h.vault.put(LedgerRepository.rootKeyName(id), wrongRoot);
      await expectLater(
        AppServices.bootstrap(database: h.db, vault: h.vault),
        throwsA(isA<EchoFailure>()),
      );
      expect(await h.vault.get(LedgerRepository.rootKeyName(id)), wrongRoot);
      expect((await h.repo.snapshot()).batches, before.batches);
      expect(await h.repo.listLedgers(), [id]);
    },
  );
  test(
    'multiple ledgers missing selection and malformed device fail explicitly',
    () async {
      final h = await LedgerHarness.create();
      addTearDown(h.close);
      final second = newId();
      await h.repo.create(
        LedgerConfig(second, 'UTC'),
        await createLedgerBundle(second),
      );
      await expectLater(
        AppServices.bootstrap(database: h.db, vault: h.vault),
        throwsA(isA<EchoFailure>()),
      );
      final invalid = Uint8List.fromList(utf8.encode('invalid-device'));
      await h.vault.put(AppServices.deviceIdKey, invalid);
      await expectLater(
        AppServices.bootstrap(database: h.db, vault: h.vault),
        throwsA(isA<EchoFailure>()),
      );
      expect(await h.vault.get(AppServices.deviceIdKey), invalid);
      expect((await h.repo.listLedgers()).length, 2);
    },
  );
}

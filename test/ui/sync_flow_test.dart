import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:echo_subs/app/services.dart';
import 'package:echo_subs/core/model/ids.dart';
import 'package:echo_subs/core/model/subscription.dart';
import 'package:echo_subs/core/model/change_batch.dart';
import 'package:echo_subs/core/model/ledger.dart';
import 'package:echo_subs/features/ledger/ui/subscription_editor.dart';
import 'package:echo_subs/features/sync/ui/sync_settings_page.dart';
import 'package:echo_subs/features/sync/ui/pairing_page.dart';
import 'package:echo_subs/features/sync/ui/conflicts_page.dart';
import 'package:echo_subs/features/sync/sync_coordinator.dart';
import 'package:echo_subs/features/sync/sync_status.dart';
import 'package:echo_subs/features/sync/sync_state_store.dart';
import 'package:echo_subs/features/sync/sync_engine.dart';
import 'package:echo_subs/core/crypto/envelope_codec.dart';
import 'package:echo_subs/storage/ledger_store.dart';
import '../sync/coordinator_test.dart' show MemoryChannel, Token;
import '../sync/sync_fixture.dart' as f;
import '../support/ledger_harness.dart';

void main() {
  testWidgets(
    'one global configuration read failure leaves retry button usable',
    (tester) async {
      final h = (await tester.runAsync(LedgerHarness.create))!;
      addTearDown(h.close);
      final services = (await tester.runAsync(() async {
        final s = AppServices(ledger: h.repo);
        await s.ready;
        return s;
      }))!;
      addTearDown(services.dispose);
      late String originalBody;
      await tester.runAsync(() async {
        await SyncStateStore(h.db, h.repo.currentLedgerId!).save(
          ChannelConfig(SyncChannelKind.webdav, 'broken-read', true, {
            'root': 'https://fictional.example/app/',
          }),
        );
        originalBody =
            (await h.db.select(h.db.syncChannelConfigs).getSingle()).body;
        await h.db.customStatement('UPDATE sync_channel_configs SET body = ?', [
          'invalid-json',
        ]);
        final cloud = MemoryChannel(await h.repo.store.metadata());
        final coordinator = SyncCoordinator(
          store: h.repo.store,
          authenticate: h.repo.authenticatedKeys,
          channels: [
            SyncChannel(
              SyncChannelKind.webdav,
              'broken-read',
              () async => cloud,
            ),
          ],
        );
        services.attachSync(coordinator);
        await expectLater(
          coordinator.sync(token: Token()),
          throwsA(isA<Exception>()),
        );
        await Future<void>.delayed(Duration.zero);
      });
      await tester.runAsync(
        () => tester.pumpWidget(
          MaterialApp(home: SyncSettingsPage(services: services)),
        ),
      );
      expect(services.syncStatus.running, false);
      expect(services.syncStatus.failureCode, 'unavailable');
      expect(find.text('数据同步完成'), findsNothing);
      final retry = find.widgetWithText(FilledButton, '立即同步 / 重试');
      expect(tester.widget<FilledButton>(retry).onPressed, isNotNull);
      await tester.runAsync(
        () => h.db.customStatement('UPDATE sync_channel_configs SET body = ?', [
          originalBody,
        ]),
      );
      final callback = tester.widget<FilledButton>(retry).onPressed!;
      await tester.runAsync(() => (callback as Future<void> Function())());
      await tester.pump();
      expect(services.syncStatus.report.webdav.succeeded, true);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(services.detachSync);
    },
  );
  for (final pairing in [false, true]) {
    testWidgets(
      '${pairing ? 'pairing' : 'recovery'} controls stay reachable at 1.5 scale with keyboard',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        tester.platformDispatcher.textScaleFactorTestValue = 1.5;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final h = (await tester.runAsync(LedgerHarness.create))!;
        final services = (await tester.runAsync(() async {
          final s = AppServices(ledger: h.repo);
          await s.ready;
          return s;
        }))!;
        await tester.pumpWidget(
          MaterialApp(
            home: pairing
                ? PairingPage(
                    services: services,
                    addresses: () async => ['192.168.1.10'],
                  )
                : DavSettingsForm(services: services, join: true),
          ),
        );
        await tester.pump();
        final save = pairing
            ? find.widgetWithText(FilledButton, '验证并加入账本')
            : find.byKey(const ValueKey('dav.save'));
        final rect = tester.getRect(save);
        expect(rect.bottom, lessThanOrEqualTo(544));
        expect(rect.top, greaterThanOrEqualTo(0));
        expect(find.text('取消').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(() async {
          services.dispose();
          await h.close();
        });
      },
    );
  }
  testWidgets('network failure remains visible while local edit succeeds', (
    tester,
  ) async {
    final h = (await tester.runAsync(LedgerHarness.create))!;
    final services = (await tester.runAsync(() async {
      final s = AppServices(ledger: h.repo);
      await s.ready;
      return s;
    }))!;
    await tester.runAsync(() async {
      final cloud = MemoryChannel(await h.repo.store.metadata())..fail = true;
      final coordinator = SyncCoordinator(
        store: h.repo.store,
        authenticate: h.repo.authenticatedKeys,
        channels: [
          SyncChannel(SyncChannelKind.webdav, 'broken', () async => cloud),
        ],
      );
      services.attachSync(coordinator);
      await coordinator.sync(token: Token());
    });
    await tester.runAsync(
      () => tester.pumpWidget(
        MaterialApp(home: SyncSettingsPage(services: services)),
      ),
    );
    expect(find.text('通道暂不可用'), findsOneWidget);
    expect(find.text('数据同步完成'), findsNothing);
    await tester.runAsync(
      () => services
          .saveSubscription(Subscription(id: newId(), name: '网络失败后仍可写'))
          .timeout(const Duration(seconds: 5)),
    );
    expect(services.subscriptions.single.name, '网络失败后仍可写');
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      await services.detachSync().timeout(const Duration(seconds: 5));
      services.dispose();
      await h.close();
    });
  });
  testWidgets('visible renewal conflict requires every entity before resolve', (
    tester,
  ) async {
    final h = (await tester.runAsync(LedgerHarness.create))!;
    addTearDown(h.close);
    final services = (await tester.runAsync(() async {
      final s = AppServices(ledger: h.repo);
      await s.ready;
      final keys = await h.repo.authenticatedKeys();
      final engine = SyncEngine(h.repo.store, keys);
      for (final original in [f.base, f.renewA, f.renewB]) {
        final batch = ChangeBatch(
          id: original.id,
          ledgerId: keys.ledgerId,
          deviceId: original.deviceId,
          createdAtUtc: original.createdAtUtc,
          mutations: original.mutations,
        );
        await engine.ingest(
          await StoredObject.fromBytes(
            batch,
            await EnvelopeCodec().seal(batch, keys),
          ),
        );
      }
      await s.refresh();
      return s;
    }))!;
    addTearDown(services.dispose);
    await tester.pumpWidget(
      MaterialApp(home: ConflictsPage(services: services)),
    );
    expect(find.textContaining('待确认：3'), findsOneWidget);
    expect(services.payments, isEmpty);
    await tester.tap(find.textContaining('待确认：3'));
    await tester.pumpAndSettle();
    final save = find.widgetWithText(FilledButton, '确认全部选择并解决');
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    final list = find.byType(Scrollable).first;
    for (final ref
        in services.snapshot!.projection.conflicts.single.affectedRefs) {
      final remove = find.byKey(ValueKey('conflict.delete.${ref.id}'));
      await tester.scrollUntilVisible(remove, 150, scrollable: list);
      await tester.ensureVisible(remove);
      await tester.pumpAndSettle();
      await tester.tap(remove);
      await tester.pump();
    }
    final callback = tester.widget<FilledButton>(save).onPressed!;
    await tester.runAsync(() => (callback as Future<void> Function())());
    await tester.pumpAndSettle();
    expect(services.snapshot!.projection.conflicts, isEmpty);
    expect(services.payments, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'open form preserves remote update and retains input on stale save',
    (tester) async {
      final h = (await tester.runAsync(LedgerHarness.create))!;
      final services = (await tester.runAsync(() async {
        final services = AppServices(ledger: h.repo);
        await services.ready;
        return services;
      }))!;
      final value = Subscription(id: newId(), name: '原名');
      await tester.runAsync(() => services.saveSubscription(value));
      await tester.pumpWidget(
        MaterialApp(
          home: SubscriptionEditor(services: services, value: value),
        ),
      );
      final ref = EntityRef(EntityKind.subscription, value.id);
      await tester.runAsync(() async {
        final state = await h.repo.snapshot();
        await h.repo.commit([
          Mutation(
            ref,
            state.causal.parentsFor(ref),
            copySubscription(value, {'provider': '远端提供商'}),
          ),
        ]);
      });
      await tester.enterText(find.byKey(const ValueKey('field.name')), '表单输入');
      final save = tester
          .widget<FilledButton>(find.byKey(const ValueKey('editor.save')))
          .onPressed!;
      await tester.runAsync(() => (save as Future<void> Function())());
      await tester.pump();
      final saved =
          (await tester.runAsync(h.repo.snapshot))!.projection.entities[ref]
              as Subscription;
      expect(saved.provider, '远端提供商');
      expect(find.text('表单输入'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        services.dispose();
        await h.close();
      });
    },
  );
  testWidgets(
    'unconfigured sync keeps local editing available and reminder state honest',
    (tester) async {
      final h = (await tester.runAsync(LedgerHarness.create))!;
      final services = (await tester.runAsync(() async {
        final services = AppServices(ledger: h.repo);
        await services.ready;
        return services;
      }))!;
      await tester.pumpWidget(
        MaterialApp(home: SyncSettingsPage(services: services)),
      );
      expect(find.textContaining('提醒尚未核对'), findsOneWidget);
      await tester.runAsync(
        () =>
            services.saveSubscription(Subscription(id: newId(), name: '离线可写')),
      );
      expect(services.subscriptions.single.name, '离线可写');
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        services.dispose();
        await h.close();
      });
    },
  );
}

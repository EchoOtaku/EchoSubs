import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:echo_subs/app/app.dart';
import 'package:echo_subs/app/services.dart';
import 'dart:io';
import 'dart:async';
import 'package:echo_subs/core/model/subscription.dart';
import 'package:echo_subs/features/ledger/ledger_repository.dart';
import 'package:echo_subs/features/ledger/ui/subscription_editor.dart';
import 'package:echo_subs/features/ledger/ui/subscription_detail_page.dart';
import 'package:echo_subs/core/model/ids.dart';
import 'package:echo_subs/storage/app_database.dart';
import '../support/ledger_harness.dart';

void main() {
  testWidgets('archive and named delete confirmation are real mutations', (
    tester,
  ) async {
    final h = (await tester.runAsync(LedgerHarness.create))!;
    addTearDown(h.close);
    final services = (await tester.runAsync(() async {
      final s = AppServices(ledger: h.repo);
      await s.ready;
      await s.saveSubscription(Subscription(id: newId(), name: '待归档服务'));
      return s;
    }))!;
    addTearDown(services.dispose);
    final id = services.subscriptions.single.id;
    await tester.pumpWidget(EchoSubsApp(services: services));
    await tester.pumpAndSettle();
    final ctx = tester.element(find.byKey(const ValueKey('nav.subscriptions')));
    Navigator.of(ctx).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            SubscriptionDetailPage(services: services, subscriptionId: id),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> tapAndObserve(Finder button, bool Function() condition) async {
      late Completer<void> done;
      void listener() {
        if (condition() && !done.isCompleted) done.complete();
      }

      services.addListener(listener);
      try {
        final callback = tester.widget<ButtonStyleButton>(button).onPressed!;
        await tester.runAsync(() async {
          done = Completer<void>();
          callback();
          await done.future.timeout(const Duration(seconds: 5));
        });
      } finally {
        services.removeListener(listener);
      }
    }

    await tester.ensureVisible(find.byKey(const ValueKey('detail.archive')));
    await tester.pumpAndSettle();
    await tapAndObserve(
      find.byKey(const ValueKey('detail.archive')),
      () => services.subscriptions.single.status == SubscriptionStatus.archived,
    );
    await tester.pumpAndSettle();
    expect(services.subscriptions.single.status, SubscriptionStatus.archived);
    Future<void> confirm(bool shouldDelete) async {
      await tester.ensureVisible(find.byKey(const ValueKey('detail.delete')));
      await tester.pumpAndSettle();
      final callback = tester
          .widget<TextButton>(find.byKey(const ValueKey('detail.delete')))
          .onPressed!;
      await tester.runAsync(() async {
        callback();
      });
      await tester.pumpAndSettle();
      expect(find.textContaining('将删除「待归档服务」'), findsOneWidget);
      if (shouldDelete) {
        await tapAndObserve(
          find.byKey(const ValueKey('delete.confirm')),
          () => services.subscriptions.isEmpty,
        );
      } else {
        await tester.tap(find.text('取消'));
      }
      await tester.pumpAndSettle();
    }

    await confirm(false);
    expect(services.subscriptions.length, 1);
    await confirm(true);
    expect(services.subscriptions, isEmpty);
    final snapshot = (await tester.runAsync(h.repo.snapshot))!;
    expect(snapshot.batches.length, 4);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'four services edit persist and gift renewal records independent dates',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final h = (await tester.runAsync(LedgerHarness.create))!;
      addTearDown(h.close);
      final services = (await tester.runAsync(() async {
        final s = AppServices(ledger: h.repo);
        await s.ready;
        return s;
      }))!;
      await tester.pumpWidget(EchoSubsApp(services: services));
      await tester.pumpAndSettle();
      Future<void> enter(String key, String value) async {
        final finder = find.byKey(ValueKey(key));
        tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .jumpTo(0);
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          finder,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.enterText(finder, value);
      }

      Future<void> choose(String key, String label) async {
        final finder = find.byKey(ValueKey(key));
        tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .jumpTo(0);
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          finder,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(finder);
        await tester.pumpAndSettle();
        await tester.tap(find.text(label).last);
        await tester.pumpAndSettle();
      }

      Future<void> save(String key) async {
        tester.printToConsole('awaiting actual widget callback $key');
        final action = tester
            .widget<FilledButton>(find.byKey(ValueKey(key)))
            .onPressed!;
        // Await the actual widget callback in real async; SQLite is native I/O.
        await tester.runAsync(() => (action as Future<void> Function())());
        tester.printToConsole('callback completed $key');
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }

      const names = ['视频月会员', '云存储年费', '永久许可证', '按量服务'];
      for (int index = 0; index < names.length; index++) {
        tester.printToConsole('enter service ${names[index]}');
        final ctx = tester.element(
          find.byKey(const ValueKey('nav.subscriptions')),
        );
        Navigator.of(ctx).push(
          MaterialPageRoute<void>(
            builder: (_) => SubscriptionEditor(services: services),
          ),
        );
        await tester.pumpAndSettle();
        await enter('field.name', names[index]);
        await enter('field.provider', '虚构服务商');
        await enter('field.category', index == 0 ? '娱乐' : '工具');
        if (index == 2) await choose('field.billingType', '一次性买断');
        if (index == 3) await choose('field.billingType', '按量计费');
        if (index != 3)
          await enter('field.price', index == 2 ? '199.00' : '29.90');
        if (index == 1) await choose('field.cycleUnit', '年');
        await enter('field.start', '2026-10-01');
        if (index == 0) {
          await enter('field.anchor', '2026-10-01');
          await enter('field.end', '2026-12-31');
          await enter('field.renewal', '2026-11-01');
        }
        await enter('field.notes', '本地录入');
        await save('editor.save');
      }
      expect(services.subscriptions.length, 4);
      expect(
        services.subscriptions
            .singleWhere((s) => s.name == names[1])
            .cycle!
            .unit,
        CycleUnit.year,
      );
      expect(
        services.subscriptions
            .singleWhere((s) => s.name == names[2])
            .billingType,
        BillingType.lifetime,
      );
      expect(
        services.subscriptions.singleWhere((s) => s.name == names[3]).price,
        isNull,
      );
      for (final original in services.subscriptions.toList()) {
        final ctx = tester.element(
          find.byKey(const ValueKey('nav.subscriptions')),
        );
        Navigator.of(ctx).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                SubscriptionEditor(services: services, value: original),
          ),
        );
        await tester.pumpAndSettle();
        await enter('field.name', '${original.name} 已编辑');
        await enter('field.channel', '虚构兑换渠道');
        await save('editor.save');
        final edited = services.subscriptions.singleWhere(
          (s) => s.id == original.id,
        );
        expect(edited.purchaseChannel, '虚构兑换渠道');
        expect(edited.provider, original.provider);
      }
      await tester.tap(find.byKey(const ValueKey('nav.subscriptions')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('视频月会员 已编辑'));
      await tester.pumpAndSettle();
      expect(find.text('权益到期：2026-12-31'), findsOneWidget);
      expect(find.text('预计续费：2026-11-01'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('detail.renew')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('detail.renew')));
      await tester.pumpAndSettle();
      await enter('payment.amount', '19.90');
      await enter('payment.paidOn', '2026-10-29');
      await enter('payment.periodStart', '2026-11-01');
      await enter('payment.periodEnd', '2026-11-30');
      await enter('payment.end', '2027-01-31');
      await enter('payment.renewal', '2026-12-01');
      await save('payment.save');
      expect(services.payments.length, 1);
      expect(services.payments.single.amount.minorUnits, 1990);
      expect(
        services.subscriptions
            .singleWhere((s) => s.name.startsWith('视频'))
            .entitlementEnd
            .toString(),
        '2027-01-31',
      );
      await tester.pumpWidget(const SizedBox());
      final reopened = (await tester.runAsync(() async {
        services.dispose();
        await h.db.close();
        final db = await AppDatabase.open(
          File('${h.directory.path}/ledger.sqlite'),
        );
        final repo = LedgerRepository(db, h.vault, h.repo.deviceId);
        await repo.selectLedger(h.repo.currentLedgerId!);
        return (db: db, repo: repo);
      }))!;
      addTearDown(reopened.db.close);
      final state = (await tester.runAsync(reopened.repo.snapshot))!;
      expect(
        state.projection.entities.values.whereType<Subscription>().length,
        4,
      );
      expect(
        state.projection.entities.values.whereType<Subscription>().every(
          (s) => s.name.endsWith('已编辑'),
        ),
        isTrue,
      );
      final again = (await tester.runAsync(() async {
        final s = AppServices(ledger: reopened.repo);
        await s.ready;
        return s;
      }))!;
      addTearDown(again.dispose);
      await tester.pumpWidget(EchoSubsApp(services: again));
      await tester.pumpAndSettle();
      expect(find.text('实际支出'), findsOneWidget);
      expect(find.text('CNY 19.90'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('empty ledger has honest costs and cancellation saves nothing', (
    tester,
  ) async {
    final h = (await tester.runAsync(LedgerHarness.create))!;
    addTearDown(h.close);
    final services = (await tester.runAsync(() async {
      final s = AppServices(ledger: h.repo);
      await s.ready;
      return s;
    }))!;
    addTearDown(services.dispose);
    await tester.pumpWidget(EchoSubsApp(services: services));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('nav.subscriptions')), findsOneWidget);
    expect(find.text('预计支出'), findsOneWidget);
    expect(find.text('实际支出'), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const ValueKey('add.subscription')).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('add.subscription')).first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('field.name')), '视频会员');
    await tester.tap(find.byKey(const ValueKey('editor.cancel')));
    await tester.pumpAndSettle();
    final snapshot = await tester.runAsync(h.repo.snapshot);
    expect(snapshot!.projection.entities.length, 1);
    await tester.pumpWidget(const SizedBox());
  });
}

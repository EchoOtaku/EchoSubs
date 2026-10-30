import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:echo_subs/app/app.dart';
import 'package:echo_subs/app/services.dart';
import 'package:echo_subs/core/model/civil_date.dart';
import 'package:echo_subs/core/model/money.dart';
import 'package:echo_subs/core/model/subscription.dart';
import 'package:echo_subs/features/reminders/reminder_adapter.dart';
import 'package:echo_subs/features/reminders/reminder_reconciler.dart';
import 'package:echo_subs/features/reminders/ui/reminder_settings_page.dart';
import 'package:echo_subs/features/sync/ui/conflicts_page.dart';
import '../support/ledger_harness.dart';

void main() {
  test(
    'conflict nested values use shared Chinese money cycle and enum text',
    () {
      final text = describeConflictEntity(
        Subscription(
          id: '00000000000000000000000000000001',
          name: '虚构会员',
          price: Money('CNY', 1234, 2),
          cycle: BillingCycle(CycleUnit.month, 3),
          nextRenewalDate: CivilDate(2027, 1, 31),
          autoRenew: true,
        ),
      );
      expect(text, contains('CNY 12.34'));
      expect(text, contains('每 3 月'));
      expect(text, contains('使用中'));
      expect(text, contains('提前 7、3、1 天'));
      expect(text, contains('自动续费：是（仅预期）'));
      expect(text, isNot(contains('minorUnits')));
    },
  );
  testWidgets('overview priority and reminder visible on pushed route', (
    tester,
  ) async {
    final h = (await tester.runAsync(LedgerHarness.create))!;
    final services = (await tester.runAsync(() async {
      final s = AppServices(ledger: h.repo);
      await s.ready;
      await s.saveSubscription(
        Subscription(
          id: '00000000000000000000000000000002',
          name: '虚构到期',
          nextRenewalDate: CivilDate(2026, 1, 1),
        ),
      );
      return s;
    }))!;
    final platform = InAppReminderPlatform();
    services.inAppReminders = platform;
    await tester.runAsync(() async {
      services.attachReminders(
        ReminderReconciler(
          snapshot: h.repo.snapshot,
          adapter: DurableReminderAdapter(ReminderStateStore(h.db), platform),
        ),
      );
      await services.reconcileReminders();
    });
    tester.printToConsole('display: attached reminders');
    try {
      await tester.pumpWidget(EchoSubsApp(services: services));
      await tester.pumpAndSettle();
      tester.printToConsole('display: overview rendered');
      expect(
        tester.getTopLeft(find.text('到期与续费')).dy,
        lessThan(tester.getTopLeft(find.text('预计支出')).dy),
      );
      expect(find.text('分类总览'), findsOneWidget);
      expect(find.textContaining('未分类'), findsOneWidget);
      Navigator.of(
        tester.element(find.byKey(const ValueKey('nav.overview'))),
      ).push(
        MaterialPageRoute<void>(
          builder: (_) => ReminderSettingsPage(services: services),
        ),
      );
      await tester.pumpAndSettle();
      tester.printToConsole('display: settings route rendered');
      await tester.tap(find.text('测试提醒'));
      await tester.pumpAndSettle();
      tester.printToConsole('display: test reminder visible');
      expect(
        find.text('EchoSubs 测试提醒：仅在应用运行时显示').hitTestable(),
        findsOneWidget,
      );
    } finally {
      tester.printToConsole('display: cleanup');
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(services.closeReminders);
      tester.printToConsole('display: reminders closed');
      await tester.runAsync(() async {
        services.dispose();
        await h.close();
      });
    }
  });
}

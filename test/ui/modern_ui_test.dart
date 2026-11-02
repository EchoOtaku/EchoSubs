import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:echo_subs/app/app.dart';
import 'package:echo_subs/app/design_system.dart';
import 'package:echo_subs/app/services.dart';
import 'package:echo_subs/core/model/civil_date.dart';
import 'package:echo_subs/core/model/ids.dart';
import 'package:echo_subs/core/model/money.dart';
import 'package:echo_subs/core/model/subscription.dart';
import '../support/ledger_harness.dart';

Future<AppServices> start(WidgetTester tester) async {
  final h = (await tester.runAsync(LedgerHarness.create))!;
  addTearDown(h.close);
  final services = (await tester.runAsync(() async {
    final value = AppServices(ledger: h.repo);
    await value.ready;
    final today = value.today;
    for (final name in ['Alpha 服务', 'Beta 服务']) {
      await value.saveSubscription(
        Subscription(
          id: newId(),
          name: name,
          price: Money('CNY', 1200, 2),
          cycle: BillingCycle(CycleUnit.month, 1),
          nextRenewalDate: CivilDate(today.year, today.month, 20),
        ),
      );
    }
    return value;
  }))!;
  addTearDown(services.dispose);
  return services;
}

void viewport(WidgetTester tester, Size size, double scale) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

void main() {
  test(
    'light and dark text, state labels and field boundaries remain readable',
    () {
      double contrast(Color a, Color b) {
        final first = a.computeLuminance(), second = b.computeLuminance();
        return first > second
            ? (first + .05) / (second + .05)
            : (second + .05) / (first + .05);
      }

      for (final c in [EchoColors.light, EchoColors.dark]) {
        for (final pair in [
          (c.text, c.canvas),
          (c.text, c.panel),
          (c.muted, c.panel),
          (c.muted, c.soft),
          (c.muted, c.accentSoft),
          (c.accent, c.accentSoft),
          (c.warning, c.warningSoft),
          (c.negative, c.negativeSoft),
        ]) {
          expect(contrast(pair.$1, pair.$2), greaterThanOrEqualTo(4.5));
        }
        expect(contrast(c.controlBorder, c.panel), greaterThanOrEqualTo(3));
      }
    },
  );

  testWidgets(
    'tab changes retain search and calendar month, and search can be cleared',
    (tester) async {
      viewport(tester, const Size(390, 844), 1);
      final services = await start(tester);
      await tester.pumpWidget(EchoSubsApp(services: services));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nav.subscriptions')));
      await tester.pumpAndSettle();
      final search = find.byKey(const ValueKey('subscriptions.search'));
      await tester.enterText(search, 'Alpha');
      await tester.pumpAndSettle();
      expect(find.text('Alpha 服务'), findsOneWidget);
      expect(find.text('Beta 服务'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('nav.calendar')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('下个月'));
      await tester.pumpAndSettle();
      final next = DateTime.utc(services.today.year, services.today.month + 1);
      final nextYear = next.year, nextMonth = next.month;
      final monthText = '$nextYear 年 $nextMonth 月';
      expect(find.text(monthText), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('nav.subscriptions')));
      await tester.pumpAndSettle();
      final editable = tester.widget<EditableText>(
        find.descendant(of: search, matching: find.byType(EditableText)),
      );
      expect(editable.controller.text, 'Alpha');
      await tester.tap(find.byTooltip('清空搜索'));
      await tester.pumpAndSettle();
      expect(editable.controller.text, '');
      expect(find.text('Beta 服务'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('nav.calendar')));
      await tester.pumpAndSettle();
      expect(find.text(monthText), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final scenario in [
    (const Size(320, 720), 1.0),
    (const Size(390, 844), 2.0),
    (const Size(844, 390), 1.5),
    (const Size(1280, 800), 2.0),
  ]) {
    testWidgets('adaptive navigation and calendar at $scenario', (
      tester,
    ) async {
      viewport(tester, scenario.$1, scenario.$2);
      final services = await start(tester);
      services.setTheme(ThemeMode.dark);
      await tester.pumpWidget(EchoSubsApp(services: services));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'initial');
      for (final tab in [
        'subscriptions',
        'calendar',
        'payments',
        'settings',
        'overview',
      ]) {
        final nav = find.byKey(ValueKey('nav.$tab'));
        await tester.ensureVisible(nav);
        await tester.tap(nav);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: tab);
        if (tab == 'calendar') {
          final date = CivilDate(
            services.today.year,
            services.today.month,
            20,
          ).toJson();
          final day = find.bySemanticsLabel(RegExp('^$date，'));
          await tester.ensureVisible(day);
          await tester.pumpAndSettle();
          final rect = tester.getRect(day);
          expect(rect.width, greaterThanOrEqualTo(48));
          expect(rect.height, greaterThanOrEqualTo(48));
          expect(day.hitTestable(), findsOneWidget);
        }
      }
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
    'reduced-motion theme changes are visible without transition frames',
    (tester) async {
      viewport(tester, const Size(390, 844), 1);
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final services = await start(tester);
      services.setTheme(ThemeMode.light);
      await tester.pumpWidget(EchoSubsApp(services: services));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('shell.theme')));
      await tester.pump();
      final context = tester.element(
        find.byKey(const ValueKey('nav.overview')),
      );
      expect(Theme.of(context).brightness, Brightness.dark);
      expect(MediaQuery.disableAnimationsOf(context), isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

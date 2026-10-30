import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:echo_subs/app/app.dart';
import 'package:echo_subs/app/services.dart';
import 'package:echo_subs/core/model/civil_date.dart';
import 'package:echo_subs/core/model/ids.dart';
import 'package:echo_subs/core/model/subscription.dart';
import 'package:echo_subs/features/ledger/ui/subscription_editor.dart';
import 'package:echo_subs/features/ledger/ui/subscription_detail_page.dart';
import '../support/ledger_harness.dart';

void main() {
  for (final size in [const Size(390, 844), const Size(1280, 800)]) {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('all pages and forms at $size $mode scale 1.5', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 1.5;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final h = (await tester.runAsync(LedgerHarness.create))!;
        final services = (await tester.runAsync(() async {
          final s = AppServices(ledger: h.repo);
          await s.ready;
          return s;
        }))!;
        addTearDown(h.close);
        addTearDown(services.dispose);
        final sub = Subscription(
          id: newId(),
          name: '视频会员与赠送权益',
          provider: '视频服务提供商',
          entitlementEnd: CivilDate(2026, 12, 31),
          nextRenewalDate: CivilDate(2026, 11, 30),
        );
        await tester.runAsync(() => services.saveSubscription(sub));
        services.setTheme(mode);
        await tester.pumpWidget(EchoSubsApp(services: services));
        await tester.pumpAndSettle();
        for (final key in [
          'subscriptions',
          'calendar',
          'payments',
          'settings',
          'overview',
        ]) {
          await tester.tap(find.byKey(ValueKey('nav.$key')));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        final context = tester.element(
          find.byKey(const ValueKey('nav.overview')),
        );
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SubscriptionEditor(services: services, value: sub),
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('field.notes')),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('editor.save')).hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        Navigator.of(
          tester.element(find.byKey(const ValueKey('editor.save'))),
        ).pop();
        await tester.pumpAndSettle();
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => RenewalEditor(services: services, value: sub),
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('payment.notes')),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('payment.save')).hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}

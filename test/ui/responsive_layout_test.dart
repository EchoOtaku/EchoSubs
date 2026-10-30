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
  for (final renewal in [false, true]) {
    testWidgets(
      '${renewal ? 'renewal' : 'subscription'} save stays outside focused keyboard',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 1.5;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
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
        final context = tester.element(
          find.byKey(const ValueKey('nav.overview')),
        );
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => renewal
                ? RenewalEditor(
                    services: services,
                    value: Subscription(id: newId(), name: '键盘测试服务'),
                  )
                : SubscriptionEditor(services: services),
          ),
        );
        await tester.pumpAndSettle();
        final notes = find.byKey(
          ValueKey(renewal ? 'payment.notes' : 'field.notes'),
        );
        await tester.scrollUntilVisible(
          notes,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.showKeyboard(notes);
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await tester.pumpAndSettle();
        await tester.ensureVisible(notes);
        await tester.pumpAndSettle();
        final textField = tester.widget<EditableText>(
          find.descendant(of: notes, matching: find.byType(EditableText)),
        );
        expect(textField.focusNode.hasFocus, isTrue);
        final save = find.byKey(
          ValueKey(renewal ? 'payment.save' : 'editor.save'),
        );
        final media = MediaQuery.of(tester.element(save));
        expect(media.viewInsets.bottom, 300);
        expect(media.textScaler.scale(10), 15);
        final keyboardTop = media.size.height - media.viewInsets.bottom;
        final rect = tester.getRect(save);
        expect(rect.top, greaterThanOrEqualTo(0));
        expect(
          rect.bottom,
          lessThanOrEqualTo(keyboardTop),
          reason: '保存按钮必须完全处于软键盘顶部之上，不能只依赖hitTestable',
        );
        expect(save.hitTestable(), findsOneWidget);
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(find.text('输入数据无效'), findsOneWidget);
        expect(tester.takeException(), isNull);
        expect((await tester.runAsync(h.repo.snapshot))!.batches.length, 1);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
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

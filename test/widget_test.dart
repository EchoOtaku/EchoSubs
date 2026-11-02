import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:echo_subs/core/model/errors.dart';
import 'package:echo_subs/main.dart';

void main() {
  testWidgets('failed bootstrap preserves data and offers actual retry', (
    tester,
  ) async {
    var attempts = 0;
    await tester.pumpWidget(
      EchoSubsBootstrapApp(
        bootstrap: () async {
          attempts++;
          throw const EchoFailure('locked', '账本密钥不可用');
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('EchoSubs 订阅簿'), findsOneWidget);
    expect(find.text('账本密钥不可用'), findsOneWidget);
    expect(find.text('原有数据库与密钥不会被清空或替换。'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('bootstrap.retry')));
    await tester.pumpAndSettle();
    expect(attempts, 2);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:echo_subs/main.dart';

void main() {
  testWidgets('application shell identifies the subscription ledger', (
    tester,
  ) async {
    await tester.pumpWidget(const EchoSubsApp());
    expect(find.text('EchoSubs 订阅簿'), findsOneWidget);
    expect(find.text('本地账本准备就绪'), findsOneWidget);
  });
}

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import '../test/support/release_scenario.dart';
import '../test/ui/ledger_flow_test.dart' as ui;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (Platform.isAndroid &&
        !(await getApplicationSupportDirectory()).path.contains(
          'dev.echootaku.echo_subs.integration',
        )) {
      throw StateError('Isolated integration package required');
    }
  });
  testWidgets('native offline SQLite restart and independent restore', (
    tester,
  ) async {
    await tester.runAsync(offlineScenario);
  });
  ui.main();
}

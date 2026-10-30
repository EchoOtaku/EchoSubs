import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import '../test/support/release_scenario.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native LAN DAV and complete ledger lifecycle', (tester) async {
    if (Platform.isAndroid &&
        !(await getApplicationSupportDirectory()).path.contains(
          'dev.echootaku.echo_subs.integration',
        )) {
      throw StateError('Isolated integration package required');
    }
    await tester.runAsync(dualTransportScenario);
  }, timeout: const Timeout(Duration(minutes: 3)));
}

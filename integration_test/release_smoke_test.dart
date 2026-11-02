import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:echo_subs/core/crypto/key_vault.dart';
import 'package:echo_subs/core/model/ids.dart';
import '../test/support/release_scenario.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native isolated encrypted transports and complete lifecycle', (
    tester,
  ) async {
    if (Platform.isAndroid &&
        !(await getApplicationSupportDirectory()).path.contains(
          'dev.echootaku.echo_subs.integration',
        )) {
      throw StateError('Isolated integration package required');
    }
    await tester.runAsync(dualTransportScenario);
  }, timeout: const Timeout(Duration(minutes: 3)));
  testWidgets('real native secure storage unique slot roundtrip', (
    tester,
  ) async {
    await tester.runAsync(() async {
      if (Platform.isAndroid &&
          !(await getApplicationSupportDirectory()).path.contains(
            'dev.echootaku.echo_subs.integration',
          )) {
        throw StateError('Isolated integration package required');
      }
      final slot = 'task11.test.${newId()}';
      final value = Uint8List.fromList(List.generate(32, (i) => i));
      try {
        await KeyVault().put(slot, value);
        expect(await KeyVault().get(slot), value);
      } finally {
        await const FlutterSecureStorage().delete(key: 'echosubs.v1.$slot');
      }
      expect(await KeyVault().get(slot), isNull);
    });
  });
}

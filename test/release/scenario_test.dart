import 'package:flutter_test/flutter_test.dart';
import '../support/release_scenario.dart';

void main() {
  test(
    'offline real repository restart and independent backup restore',
    offlineScenario,
  );
  test(
    'real TLS LAN pairing DAV offline relay conflict delete duplicate payment and reminders',
    () => dualTransportScenario(
      omitDav: const bool.fromEnvironment('ECHOSUBS_MISSING_DAV'),
    ),
  );
}

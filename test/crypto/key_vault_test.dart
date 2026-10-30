import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:echo_subs/core/crypto/key_vault.dart';
import 'package:echo_subs/core/model/errors.dart';

class FakeStore implements VaultStorage {
  final values = <String, String>{};
  bool fail = false;
  @override
  Future<String?> read(String name) async {
    if (fail) throw StateError('SECRET');
    return values[name];
  }

  @override
  Future<void> write(String name, String value) async {
    if (fail) throw StateError('SECRET');
    values[name] = value;
  }
}

void main() {
  test(
    'vault fake roundtrip, absent and failures disclose no source',
    () async {
      final store = FakeStore();
      final vault = KeyVault(storage: store);
      expect(await vault.get('root'), isNull);
      await vault.put('root', Uint8List.fromList([1, 2, 3]));
      expect(await vault.get('root'), [1, 2, 3]);
      store.values['echosubs.v1.root'] = 'malformed';
      await expectLater(
        vault.get('root'),
        throwsA(isA<EchoFailure>().having((e) => e.code, 'code', 'locked')),
      );
      store.fail = true;
      for (final action in [
        () => vault.get('root'),
        () => vault.put('root', Uint8List(32)),
      ]) {
        await expectLater(
          action(),
          throwsA(
            isA<EchoFailure>().having(
              (e) => e.toString(),
              'safe',
              isNot(contains('SECRET')),
            ),
          ),
        );
      }
    },
  );
}

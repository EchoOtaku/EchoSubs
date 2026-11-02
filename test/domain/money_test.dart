import 'package:flutter_test/flutter_test.dart';
import 'package:echo_subs/core/model/money.dart';
import 'package:echo_subs/core/model/errors.dart';

void main() {
  test('decimal arithmetic and string JSON are exact', () {
    final tenth = Money.fromDecimal('0.10', 'CNY', 2);
    expect(tenth.minorUnits, 10);
    expect(
      tenth + Money.fromDecimal('0.20', 'CNY', 2),
      Money.fromDecimal('0.30', 'CNY', 2),
    );
    expect(tenth.toJson()['minorUnits'], '10');
    expect(Money.fromJson(tenth.toJson()), tenth);
    expect(
      () => Money.fromDecimal('9223372036854775808', 'CNY', 0),
      throwsA(isA<EchoFailure>()),
    );
  });
  test('invalid negative currency and precision values rejected', () {
    for (final text in ['-1', '1.001', 'NaN', '1e2', '.1', ' 1', '1.']) {
      expect(
        () => Money.fromDecimal(text, 'CNY', 2),
        throwsA(isA<EchoFailure>()),
      );
    }
    expect(() => Money('CNY', -1, 2), throwsA(isA<EchoFailure>()));
    expect(
      () => Money.fromDecimal('1', 'CNY', 2) + Money.fromDecimal('1', 'CNY', 3),
      throwsA(isA<EchoFailure>()),
    );
    expect(
      () => Money.fromDecimal('1', 'CNY', 2) + Money.fromDecimal('1', 'USD', 2),
      throwsA(isA<EchoFailure>()),
    );
  });
  test('large exact integers and zero scale survive JSON', () {
    final largest = Money.fromDecimal('9223372036854775807', 'JPY', 0);
    expect(Money.fromJson(largest.toJson()), largest);
    expect(() => largest + Money('JPY', 1, 0), throwsA(isA<EchoFailure>()));
    expect(
      () => Money.fromJson({'currency': 'CNY', 'minorUnits': 10, 'scale': 2}),
      throwsA(isA<EchoFailure>()),
    );
    expect(() => Money('cny', 10, 2), throwsA(isA<EchoFailure>()));
    expect(() => Money('CNY', 10, -1), throwsA(isA<EchoFailure>()));
  });
}

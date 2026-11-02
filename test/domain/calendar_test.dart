import 'package:flutter_test/flutter_test.dart';
import 'package:echo_subs/core/model/civil_date.dart';
import 'package:echo_subs/core/model/errors.dart';
import 'package:echo_subs/core/model/subscription.dart';
import 'package:echo_subs/features/ledger/cycle_calculator.dart';

void main() {
  test('original anchor prevents month end and leap year drift', () {
    final anchor = CivilDate(2028, 1, 31);
    final cycle = BillingCycle(CycleUnit.month, 1);
    expect(occurrence(anchor, cycle, 1), CivilDate(2028, 2, 29));
    expect(occurrence(anchor, cycle, 2), CivilDate(2028, 3, 31));
    expect(occurrence(anchor, cycle, 0), anchor);
    expect(
      occurrence(CivilDate(2028, 2, 29), BillingCycle(CycleUnit.year, 1), 1),
      CivilDate(2029, 2, 28),
    );
    expect(
      occurrence(CivilDate(2028, 2, 29), BillingCycle(CycleUnit.year, 1), 4),
      CivilDate(2032, 2, 29),
    );
  });
  test('civil day week and quarter arithmetic', () {
    expect(
      occurrence(CivilDate(2028, 3, 11), BillingCycle(CycleUnit.day, 1), 2),
      CivilDate(2028, 3, 13),
    );
    expect(
      occurrence(CivilDate(2028, 12, 28), BillingCycle(CycleUnit.week, 1), 1),
      CivilDate(2029, 1, 4),
    );
    expect(
      occurrence(CivilDate(2028, 1, 31), BillingCycle(CycleUnit.month, 3), 1),
      CivilDate(2028, 4, 30),
    );
  });
  test('invalid date cycle and index rejected', () {
    expect(() => CivilDate(2027, 2, 29), throwsA(isA<EchoFailure>()));
    expect(() => BillingCycle(CycleUnit.month, 0), throwsA(isA<EchoFailure>()));
    expect(
      () =>
          occurrence(CivilDate(2028, 1, 1), BillingCycle(CycleUnit.day, 1), -1),
      throwsA(isA<EchoFailure>()),
    );
    expect(CivilDate.fromJson('2028-02-29').toJson(), '2028-02-29');
  });
  test('calendar boundaries and enormous cycles fail safely', () {
    for (final text in [
      '2028-2-29',
      '2028-02-30',
      '0000-01-01',
      '2028-01-01T00:00:00Z',
    ]) {
      expect(() => CivilDate.fromJson(text), throwsA(isA<EchoFailure>()));
    }
    expect(
      () => occurrence(
        CivilDate(9999, 12, 31),
        BillingCycle(CycleUnit.day, 1),
        1,
      ),
      throwsA(isA<EchoFailure>()),
    );
    expect(
      () => occurrence(
        CivilDate(2028, 1, 1),
        BillingCycle(CycleUnit.year, 9223372036854775807),
        2,
      ),
      throwsA(isA<EchoFailure>()),
    );
    expect(
      CivilDate(2028, 1, 2).compareTo(CivilDate(2028, 1, 1)),
      greaterThan(0),
    );
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:echo_subs/core/model/civil_date.dart';
import 'package:echo_subs/core/model/errors.dart';
import 'package:echo_subs/core/model/money.dart';
import 'package:echo_subs/core/model/payment.dart';
import 'package:echo_subs/core/model/subscription.dart';
import 'package:echo_subs/features/ledger/cost_projection.dart';

Subscription sub({
  String currency = 'CNY',
  int scale = 2,
  String? price = '12',
  BillingType type = BillingType.fixed,
  SubscriptionStatus status = SubscriptionStatus.active,
  CycleUnit unit = CycleUnit.month,
  int count = 1,
  bool autoRenew = false,
}) => Subscription(
  id: '00000000000000000000000000000001',
  name: 'Example',
  status: status,
  billingType: type,
  price: price == null ? null : Money.fromDecimal(price, currency, scale),
  cycle: BillingCycle(unit, count),
  cycleAnchor: CivilDate(2028, 1, 31),
  startDate: CivilDate(2028, 1, 1),
  autoRenew: autoRenew,
);
void main() {
  test('cost summaries compare by immutable currency amounts', () {
    final first = summarizeCosts([sub()], []);
    final second = summarizeCosts([sub()], []);
    expect(first, second);
    expect(first.hashCode, second.hashCode);
  });
  test('only active fixed known prices forecast separately per currency', () {
    final result = summarizeCosts([
      sub(),
      sub(currency: 'USD'),
      sub(price: null),
      sub(type: BillingType.metered),
      sub(type: BillingType.lifetime),
      sub(status: SubscriptionStatus.paused),
      sub(status: SubscriptionStatus.archived),
    ], []);
    expect(result.estimatedMonthly['CNY'], Money.fromDecimal('12', 'CNY', 2));
    expect(result.estimatedYearly['USD'], Money.fromDecimal('144', 'USD', 2));
    expect(result.actualPaid, isEmpty);
  });
  test('rational forecasts accumulate before half up rounding', () {
    expect(
      summarizeCosts([
        sub(price: '100', unit: CycleUnit.year),
      ], []).estimatedMonthly['CNY'],
      Money.fromDecimal('8.33', 'CNY', 2),
    );
    expect(
      summarizeCosts([sub(price: '30', count: 3)], []).estimatedMonthly['CNY'],
      Money.fromDecimal('10', 'CNY', 2),
    );
    expect(
      summarizeCosts([
        sub(price: '1', unit: CycleUnit.day),
      ], []).estimatedYearly['CNY'],
      Money.fromDecimal('365', 'CNY', 2),
    );
    expect(
      summarizeCosts([
        sub(price: '7', unit: CycleUnit.week),
      ], []).estimatedYearly['CNY'],
      Money.fromDecimal('365', 'CNY', 2),
    );
    expect(
      summarizeCosts([
        sub(price: '0.01', count: 2),
        sub(price: '0.01', count: 2),
      ], []).estimatedMonthly['CNY'],
      Money.fromDecimal('0.01', 'CNY', 2),
    );
  });
  test('auto renew neither creates payments nor extends entitlement', () {
    final subscription = sub(autoRenew: true);
    final result = summarizeCosts(
      [subscription],
      [
        Payment(
          id: '00000000000000000000000000000002',
          subscriptionId: subscription.id,
          amount: Money.fromDecimal('99', 'CNY', 2),
          paidOn: CivilDate(2028, 1, 1),
        ),
      ],
    );
    expect(result.actualPaid['CNY'], Money.fromDecimal('99', 'CNY', 2));
    expect(subscription.entitlementEnd, isNull);
    expect(summarizeCosts([subscription], []).actualPaid, isEmpty);
  });
  test('all inputs must agree on currency scale', () {
    expect(
      () =>
          summarizeCosts([sub(), sub(scale: 3, type: BillingType.metered)], []),
      throwsA(isA<EchoFailure>()),
    );
  });
  test('empty projections remain immutable and missing cycle is unknown', () {
    final unknown = Subscription(
      id: '00000000000000000000000000000001',
      name: 'Unknown',
      price: Money('CNY', 100, 2),
    );
    final result = summarizeCosts([unknown], []);
    expect(result.estimatedMonthly, isEmpty);
    expect(result.estimatedYearly, isEmpty);
    expect(
      () => result.actualPaid['CNY'] = Money('CNY', 0, 2),
      throwsUnsupportedError,
    );
  });
}

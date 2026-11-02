import '../../core/model/errors.dart';
import '../../core/model/ids.dart';
import '../../core/model/money.dart';
import '../../core/model/payment.dart';
import '../../core/model/subscription.dart';

class CostSummary extends ModelValue {
  CostSummary({
    required Map<String, Money> estimatedMonthly,
    required Map<String, Money> estimatedYearly,
    required Map<String, Money> actualPaid,
  }) : estimatedMonthly = Map.unmodifiable(estimatedMonthly),
       estimatedYearly = Map.unmodifiable(estimatedYearly),
       actualPaid = Map.unmodifiable(actualPaid);

  /// Estimates only: daily/weekly cycles use 365 days per year.
  final Map<String, Money> estimatedMonthly;
  final Map<String, Money> estimatedYearly;
  final Map<String, Money> actualPaid;
  @override
  Map<String, Object?> toJson() => {
    'estimatedMonthly': estimatedMonthly.map(
      (currency, money) => MapEntry(currency, money.toJson()),
    ),
    'estimatedYearly': estimatedYearly.map(
      (currency, money) => MapEntry(currency, money.toJson()),
    ),
    'actualPaid': actualPaid.map(
      (currency, money) => MapEntry(currency, money.toJson()),
    ),
  };
}

class _Rational {
  _Rational(this.numerator, this.denominator);
  final BigInt numerator;
  final BigInt denominator;
  _Rational operator +(_Rational other) {
    final n = numerator * other.denominator + other.numerator * denominator;
    final d = denominator * other.denominator;
    final gcd = n.gcd(d);
    return _Rational(n ~/ gcd, d ~/ gcd);
  }

  int rounded() => checkedMinorUnits(
    (numerator * BigInt.two + denominator) ~/ (denominator * BigInt.two),
  );
}

CostSummary summarizeCosts(
  List<Subscription> subscriptions,
  List<Payment> payments,
) {
  final scales = <String, int>{};
  void register(Money money) {
    final scale = scales[money.currency];
    if (scale != null && scale != money.scale) invalidModel();
    scales[money.currency] = money.scale;
  }

  for (final subscription in subscriptions) {
    if (subscription.price != null) register(subscription.price!);
  }
  for (final payment in payments) {
    register(payment.amount);
  }
  final monthly = <String, _Rational>{};
  final yearly = <String, _Rational>{};
  final actual = <String, BigInt>{};
  void add(
    Map<String, _Rational> destination,
    String currency,
    _Rational amount,
  ) {
    destination[currency] =
        (destination[currency] ?? _Rational(BigInt.zero, BigInt.one)) + amount;
  }

  for (final subscription in subscriptions) {
    final price = subscription.price;
    final cycle = subscription.cycle;
    if (subscription.status != SubscriptionStatus.active ||
        subscription.billingType != BillingType.fixed ||
        price == null ||
        cycle == null)
      continue;
    final units = BigInt.from(price.minorUnits);
    final count = BigInt.from(cycle.count);
    final (annualNumerator, annualDenominator) = switch (cycle.unit) {
      CycleUnit.month => (units * BigInt.from(12), count),
      CycleUnit.year => (units, count),
      CycleUnit.day => (units * BigInt.from(365), count),
      CycleUnit.week => (units * BigInt.from(365), count * BigInt.from(7)),
    };
    add(yearly, price.currency, _Rational(annualNumerator, annualDenominator));
    add(
      monthly,
      price.currency,
      _Rational(annualNumerator, annualDenominator * BigInt.from(12)),
    );
  }
  for (final payment in payments) {
    final amount = payment.amount;
    actual[amount.currency] =
        (actual[amount.currency] ?? BigInt.zero) +
        BigInt.from(amount.minorUnits);
  }
  return CostSummary(
    estimatedMonthly: {
      for (final entry in monthly.entries)
        entry.key: Money(entry.key, entry.value.rounded(), scales[entry.key]!),
    },
    estimatedYearly: {
      for (final entry in yearly.entries)
        entry.key: Money(entry.key, entry.value.rounded(), scales[entry.key]!),
    },
    actualPaid: {
      for (final entry in actual.entries)
        entry.key: Money(
          entry.key,
          checkedMinorUnits(entry.value),
          scales[entry.key]!,
        ),
    },
  );
}

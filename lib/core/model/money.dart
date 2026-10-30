import 'errors.dart';
import 'ids.dart';

final _maximumMinorUnits = BigInt.parse('9223372036854775807');

int checkedMinorUnits(BigInt amount) {
  if (amount.isNegative || amount > _maximumMinorUnits) invalidModel();
  return amount.toInt();
}

class Money extends ModelValue {
  Money(this.currency, this.minorUnits, this.scale) {
    validateCurrencyScale(currency, scale);
    if (minorUnits < 0) invalidModel();
  }
  final String currency;
  final int minorUnits;
  final int scale;

  static void validateCurrencyScale(String currency, int scale) {
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(currency) || scale < 0 || scale > 18)
      invalidModel();
  }

  factory Money.fromDecimal(String text, String currency, int scale) =>
      parseModel(() {
        validateCurrencyScale(currency, scale);
        if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(text)) invalidModel();
        final parts = text.split('.');
        final fraction = parts.length == 2 ? parts[1] : '';
        if (fraction.length > scale) invalidModel();
        final units =
            BigInt.parse(parts[0]) * BigInt.from(10).pow(scale) +
            BigInt.parse(
              fraction.padRight(scale, '0').isEmpty
                  ? '0'
                  : fraction.padRight(scale, '0'),
            );
        return Money(currency, checkedMinorUnits(units), scale);
      });
  factory Money.fromJson(Map<String, dynamic> value) => parseModel(() {
    final text = value['minorUnits'] as String;
    if (!RegExp(r'^(0|[1-9]\d*)$').hasMatch(text)) invalidModel();
    return Money(
      value['currency'] as String,
      checkedMinorUnits(BigInt.parse(text)),
      value['scale'] as int,
    );
  });
  Money operator +(Money other) {
    if (currency != other.currency || scale != other.scale) invalidModel();
    return Money(
      currency,
      checkedMinorUnits(
        BigInt.from(minorUnits) + BigInt.from(other.minorUnits),
      ),
      scale,
    );
  }

  @override
  Map<String, Object?> toJson() => {
    'currency': currency,
    'minorUnits': minorUnits.toString(),
    'scale': scale,
  };
}

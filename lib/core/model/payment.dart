import 'civil_date.dart';
import 'errors.dart';
import 'ids.dart';
import 'ledger.dart';
import 'money.dart';

class Payment extends LedgerEntity {
  Payment({
    required this.id,
    required this.subscriptionId,
    required this.amount,
    required this.paidOn,
    this.periodStart,
    this.periodEnd,
    this.notes,
  }) {
    validateId(id);
    validateId(subscriptionId);
    if (periodStart != null &&
        periodEnd != null &&
        periodStart!.compareTo(periodEnd!) > 0)
      invalidModel();
  }
  @override
  final EntityId id;
  final EntityId subscriptionId;
  final Money amount;
  final CivilDate paidOn;
  final CivilDate? periodStart;
  final CivilDate? periodEnd;
  final String? notes;
  @override
  EntityKind get kind => EntityKind.payment;
  factory Payment.fromJson(Map<String, dynamic> value) => parseModel(
    () => Payment(
      id: value['id'] as String,
      subscriptionId: value['subscriptionId'] as String,
      amount: Money.fromJson(jsonMap(value['amount'])),
      paidOn: CivilDate.fromJson(value['paidOn'] as String),
      periodStart: value['periodStart'] == null
          ? null
          : CivilDate.fromJson(value['periodStart'] as String),
      periodEnd: value['periodEnd'] == null
          ? null
          : CivilDate.fromJson(value['periodEnd'] as String),
      notes: value['notes'] as String?,
    ),
  );
  @override
  Map<String, Object?> toJson() => {
    'id': id,
    'subscriptionId': subscriptionId,
    'amount': amount.toJson(),
    'paidOn': paidOn.toJson(),
    'periodStart': periodStart?.toJson(),
    'periodEnd': periodEnd?.toJson(),
    'notes': notes,
  };
}

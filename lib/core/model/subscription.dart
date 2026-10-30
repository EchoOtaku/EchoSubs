import 'civil_date.dart';
import 'errors.dart';
import 'ids.dart';
import 'ledger.dart';
import 'money.dart';

enum CycleUnit { day, week, month, year }

enum BillingType { fixed, metered, lifetime }

enum SubscriptionStatus { active, paused, archived }

class BillingCycle extends ModelValue {
  BillingCycle(this.unit, this.count) {
    if (count <= 0) invalidModel();
  }
  final CycleUnit unit;
  final int count;
  factory BillingCycle.fromJson(Map<String, dynamic> value) => parseModel(
    () => BillingCycle(
      enumValue(CycleUnit.values, value['unit']),
      value['count'] as int,
    ),
  );
  @override
  Map<String, Object?> toJson() => {'unit': unit.name, 'count': count};
}

class Subscription extends LedgerEntity {
  Subscription({
    required this.id,
    required this.name,
    this.provider,
    this.purchaseChannel,
    this.paymentMethod,
    this.websiteUrl,
    this.notes,
    this.categoryId,
    this.status = SubscriptionStatus.active,
    this.billingType = BillingType.fixed,
    this.price,
    this.cycle,
    this.cycleAnchor,
    this.startDate,
    this.entitlementEnd,
    this.nextRenewalDate,
    this.autoRenew = false,
    ReminderRule? reminderRule,
  }) : reminderRule = reminderRule ?? ReminderRule() {
    validateId(id);
    if (categoryId != null) validateId(categoryId!);
    if (name.trim().isEmpty) invalidModel();
  }
  @override
  final EntityId id;
  final String name;
  final String? provider;
  final String? purchaseChannel;
  final String? paymentMethod;
  final String? websiteUrl;
  final String? notes;
  final EntityId? categoryId;
  final SubscriptionStatus status;
  final BillingType billingType;
  final Money? price;
  final BillingCycle? cycle;
  final CivilDate? cycleAnchor;
  final CivilDate? startDate;
  final CivilDate? entitlementEnd;
  final CivilDate? nextRenewalDate;
  final bool autoRenew;
  final ReminderRule reminderRule;
  @override
  EntityKind get kind => EntityKind.subscription;
  factory Subscription.fromJson(Map<String, dynamic> value) => parseModel(
    () => Subscription(
      id: value['id'] as String,
      name: value['name'] as String,
      provider: value['provider'] as String?,
      purchaseChannel: value['purchaseChannel'] as String?,
      paymentMethod: value['paymentMethod'] as String?,
      websiteUrl: value['websiteUrl'] as String?,
      notes: value['notes'] as String?,
      categoryId: value['categoryId'] as String?,
      status: enumValue(SubscriptionStatus.values, value['status']),
      billingType: enumValue(BillingType.values, value['billingType']),
      price: value['price'] == null
          ? null
          : Money.fromJson(jsonMap(value['price'])),
      cycle: value['cycle'] == null
          ? null
          : BillingCycle.fromJson(jsonMap(value['cycle'])),
      cycleAnchor: _date(value['cycleAnchor']),
      startDate: _date(value['startDate']),
      entitlementEnd: _date(value['entitlementEnd']),
      nextRenewalDate: _date(value['nextRenewalDate']),
      autoRenew: value['autoRenew'] as bool,
      reminderRule: ReminderRule.fromJson(jsonMap(value['reminderRule'])),
    ),
  );
  static CivilDate? _date(Object? value) =>
      value == null ? null : CivilDate.fromJson(value as String);
  @override
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'provider': provider,
    'purchaseChannel': purchaseChannel,
    'paymentMethod': paymentMethod,
    'websiteUrl': websiteUrl,
    'notes': notes,
    'categoryId': categoryId,
    'status': status.name,
    'billingType': billingType.name,
    'price': price?.toJson(),
    'cycle': cycle?.toJson(),
    'cycleAnchor': cycleAnchor?.toJson(),
    'startDate': startDate?.toJson(),
    'entitlementEnd': entitlementEnd?.toJson(),
    'nextRenewalDate': nextRenewalDate?.toJson(),
    'autoRenew': autoRenew,
    'reminderRule': reminderRule.toJson(),
  };
}

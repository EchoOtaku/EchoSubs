import 'errors.dart';
import 'ids.dart';
import 'payment.dart';
import 'subscription.dart';

enum EntityKind { subscription, payment, category, ledgerConfig }

abstract class LedgerEntity extends ModelValue {
  EntityId get id;
  EntityKind get kind;
  static LedgerEntity fromJson(EntityKind kind, Map<String, dynamic> value) =>
      switch (kind) {
        EntityKind.subscription => Subscription.fromJson(value),
        EntityKind.payment => Payment.fromJson(value),
        EntityKind.category => Category.fromJson(value),
        EntityKind.ledgerConfig => LedgerConfig.fromJson(value),
      };
}

class LedgerConfig extends LedgerEntity {
  LedgerConfig(this.id, this.timeZoneId) {
    validateId(id);
    if (timeZoneId.trim().isEmpty) invalidModel();
  }
  @override
  final EntityId id;
  final String timeZoneId;
  @override
  EntityKind get kind => EntityKind.ledgerConfig;
  factory LedgerConfig.fromJson(Map<String, dynamic> value) => parseModel(
    () => LedgerConfig(value['id'] as String, value['timeZoneId'] as String),
  );
  @override
  Map<String, Object?> toJson() => {'id': id, 'timeZoneId': timeZoneId};
}

class Category extends LedgerEntity {
  Category(this.id, this.name) {
    validateId(id);
    if (name.trim().isEmpty) invalidModel();
  }
  @override
  final EntityId id;
  final String name;
  @override
  EntityKind get kind => EntityKind.category;
  factory Category.fromJson(Map<String, dynamic> value) => parseModel(
    () => Category(value['id'] as String, value['name'] as String),
  );
  @override
  Map<String, Object?> toJson() => {'id': id, 'name': name};
}

class ReminderRule extends ModelValue {
  ReminderRule({
    List<int> daysBefore = const [7, 3, 1],
    this.localHour = 9,
    this.localMinute = 0,
  }) : daysBefore = List.unmodifiable(
         daysBefore.toSet().toList()..sort((a, b) => b.compareTo(a)),
       ) {
    if (daysBefore.any((day) => day < 0) ||
        localHour < 0 ||
        localHour > 23 ||
        localMinute < 0 ||
        localMinute > 59)
      invalidModel();
  }
  final List<int> daysBefore;
  final int localHour;
  final int localMinute;
  factory ReminderRule.fromJson(Map<String, dynamic> value) => parseModel(
    () => ReminderRule(
      daysBefore: jsonList(value['daysBefore']).cast<int>(),
      localHour: value['localHour'] as int,
      localMinute: value['localMinute'] as int,
    ),
  );
  @override
  Map<String, Object?> toJson() => {
    'daysBefore': daysBefore,
    'localHour': localHour,
    'localMinute': localMinute,
  };
}

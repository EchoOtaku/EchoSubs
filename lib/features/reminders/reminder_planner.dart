import 'dart:convert';
import 'package:cryptography/dart.dart';
import 'package:timezone/timezone.dart' as tz;
import '../../core/model/change_batch.dart';
import '../../core/model/ledger.dart';
import '../../core/model/subscription.dart';

class ReminderEvent {
  const ReminderEvent({
    required this.ledgerId,
    required this.stableKey,
    required this.subscriptionId,
    required this.scheduledAtUtc,
    required this.ruleId,
    required this.name,
  });
  final String ledgerId, stableKey, subscriptionId, ruleId, name;
  final DateTime scheduledAtUtc;
  Map<String, Object?> toJson() => {
    'ledger': ledgerId,
    'key': stableKey,
    'subscription': subscriptionId,
    'at': scheduledAtUtc.toUtc().toIso8601String(),
    'rule': ruleId,
    'name': name,
  };
  factory ReminderEvent.fromJson(Map<String, dynamic> v) => ReminderEvent(
    ledgerId: v['ledger'] as String,
    stableKey: v['key'] as String,
    subscriptionId: v['subscription'] as String,
    scheduledAtUtc: DateTime.parse(v['at'] as String).toUtc(),
    ruleId: v['rule'] as String,
    name: v['name'] as String,
  );
}

/// Includes today's elapsed events so reconciliation can retain an inexact alarm
/// already waiting to fire. New alarms are only registered for future instants.
/// No device timezone or clock is read. Timezone data is initialized at startup.
List<ReminderEvent> planReminders(
  LedgerProjection ledger,
  DateTime nowUtc, {
  Set<EntityRef> unsafeRefs = const {},
}) {
  final blocked = {
    ...unsafeRefs,
    ...ledger.conflicts.expand((c) => c.affectedRefs),
  };
  if (blocked.any((r) => r.kind == EntityKind.ledgerConfig)) return [];
  final config = ledger.entities.values.whereType<LedgerConfig>().singleOrNull;
  if (config == null) return [];
  final location = tz.getLocation(config.timeZoneId);
  final today = tz.TZDateTime.from(nowUtc.toUtc(), location);
  final floor = DateTime.utc(today.year, today.month, today.day);
  final resolved = <String, DateTime>{};
  final events = <ReminderEvent>[];
  for (final sub in ledger.entities.values.whereType<Subscription>()) {
    if (sub.status != SubscriptionStatus.active ||
        blocked.contains(EntityRef(sub.kind, sub.id)))
      continue;
    final due = sub.nextRenewalDate ?? sub.entitlementEnd;
    if (due == null) continue;
    for (final days in sub.reminderRule.daysBefore) {
      final date = DateTime.utc(
        due.year,
        due.month,
        due.day,
      ).subtract(Duration(days: days));
      if (date.isBefore(floor)) continue;
      final local = DateTime.utc(
        date.year,
        date.month,
        date.day,
        sub.reminderRule.localHour,
        sub.reminderRule.localMinute,
      );
      final at = resolved.putIfAbsent(
        local.toIso8601String(),
        () => resolveReminderTime(location, local),
      );
      final day = date.toIso8601String().substring(0, 10);
      final rule = 'before:$days';
      events.add(
        ReminderEvent(
          ledgerId: config.id,
          stableKey: '${config.id}/${sub.id}/$day/$rule',
          subscriptionId: sub.id,
          scheduledAtUtc: at,
          ruleId: rule,
          name: sub.name,
        ),
      );
    }
  }
  events.sort((a, b) {
    final t = a.scheduledAtUtc.compareTo(b.scheduledAtUtc);
    return t == 0 ? a.stableKey.compareTo(b.stableKey) : t;
  });
  return List.unmodifiable(events);
}

/// Resolve wall time by validating all IANA offsets, rather than accepting the
/// timezone constructor's gap normalization (02:30 -> 03:30). Gap search advances
/// wall minutes to the FIRST valid instant; overlap candidates sort by UTC.
DateTime resolveReminderTime(tz.Location location, DateTime wall) {
  final offsets = location.zones.map((z) => z.offset).toSet();
  for (var minute = 0; minute <= 2880; minute++) {
    final target = wall.add(Duration(minutes: minute));
    DateTime? earliest;
    for (final offset in offsets) {
      final utc = target.subtract(offset);
      final actual = tz.TZDateTime.from(utc, location);
      if (actual.year == target.year &&
          actual.month == target.month &&
          actual.day == target.day &&
          actual.hour == target.hour &&
          actual.minute == target.minute &&
          actual.second == 0 &&
          (earliest == null || utc.isBefore(earliest)))
        earliest = utc;
    }
    if (earliest != null) return earliest.toUtc();
  }
  throw StateError('No valid reminder wall time');
}

class ReminderBatch {
  ReminderBatch(this.ledgerId, DateTime at, Iterable<ReminderEvent> items)
    : scheduledAtUtc = at.toUtc(),
      events = List.unmodifiable(
        items.toList()..sort((a, b) => a.stableKey.compareTo(b.stableKey)),
      );
  final String ledgerId;
  final DateTime scheduledAtUtc;
  final List<ReminderEvent> events;
  String get stableKey =>
      'reminder.v1/$ledgerId/${scheduledAtUtc.toIso8601String()}';
  // This digest is a readback token, NOT a notification integer ID.
  late final String fingerprint = const DartSha256()
      .hashSync(utf8.encode(jsonEncode(toJson())))
      .bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  Map<String, Object?> toJson() => {
    'ledger': ledgerId,
    'at': scheduledAtUtc.toIso8601String(),
    'events': events.map((e) => e.toJson()).toList(),
  };
  factory ReminderBatch.fromJson(Map<String, dynamic> v) => ReminderBatch(
    v['ledger'] as String,
    DateTime.parse(v['at'] as String),
    (v['events'] as List).map(
      (e) => ReminderEvent.fromJson(e as Map<String, dynamic>),
    ),
  );
}

List<ReminderBatch> groupReminders(List<ReminderEvent> events) {
  final grouped = <String, List<ReminderEvent>>{};
  for (final e in events)
    (grouped['${e.ledgerId}/${e.scheduledAtUtc.toIso8601String()}'] ??= []).add(
      e,
    );
  return grouped.values
      .map((v) => ReminderBatch(v.first.ledgerId, v.first.scheduledAtUtc, v))
      .toList()
    ..sort((a, b) => a.stableKey.compareTo(b.stableKey));
}

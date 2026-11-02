import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:echo_subs/core/model/change_batch.dart';
import 'package:echo_subs/core/model/civil_date.dart';
import 'package:echo_subs/core/model/ledger.dart';
import 'package:echo_subs/core/model/subscription.dart';
import 'package:echo_subs/features/reminders/reminder_planner.dart';

String rid(int n) => n.toRadixString(16).padLeft(32, '0');
LedgerProjection projection(
  List<Subscription> values, {
  String zone = 'Asia/Shanghai',
  List<Conflict> conflicts = const [],
}) => LedgerProjection(
  entities: {
    EntityRef(EntityKind.ledgerConfig, rid(1)): LedgerConfig(rid(1), zone),
    for (final v in values) EntityRef(v.kind, v.id): v,
  },
  conflicts: conflicts,
);
Subscription due({int id = 2, ReminderRule? rule, CivilDate? date}) =>
    Subscription(
      id: rid(id),
      name: '虚构订阅 $id',
      nextRenewalDate: date ?? CivilDate(2026, 10, 31),
      reminderRule: rule,
    );

void main() {
  setUpAll(tzdata.initializeTimeZones);
  test('existing UTC ledger alias remains valid', () {
    final events = planReminders(
      projection([due()], zone: 'UTC'),
      DateTime.utc(2026, 10, 20),
    );
    expect(events.first.scheduledAtUtc, DateTime.utc(2026, 10, 24, 9));
  });
  test('defaults use ledger 09:00 and survive device travel', () {
    final p = projection([due()]);
    final now = DateTime.utc(2026, 10, 20);
    final events = planReminders(p, now);
    final local = events
        .map(
          (e) => tz.TZDateTime.from(
            e.scheduledAtUtc,
            tz.getLocation('Asia/Shanghai'),
          ),
        )
        .toList();
    expect(local.map((d) => d.day), [24, 28, 30]);
    expect(local.map((d) => d.hour).toSet(), {9});
    expect(events.map((e) => e.stableKey).toSet().length, 3);
    final before = tz.local;
    try {
      tz.setLocalLocation(tz.getLocation('Pacific/Honolulu'));
      expect(
        planReminders(p, now).map((e) => e.scheduledAtUtc),
        events.map((e) => e.scheduledAtUtc),
      );
    } finally {
      tz.setLocalLocation(before);
    }
  });
  test('DST gap takes first valid instant, overlap takes earlier UTC once', () {
    final spring = due(
      date: CivilDate(2026, 3, 8),
      rule: ReminderRule(daysBefore: [0], localHour: 2, localMinute: 30),
    );
    expect(
      planReminders(
        projection([spring], zone: 'America/New_York'),
        DateTime.utc(2026, 3, 7),
      ).single.scheduledAtUtc,
      DateTime.utc(2026, 3, 8, 7),
    );
    final fall = due(
      date: CivilDate(2026, 11, 1),
      rule: ReminderRule(daysBefore: [0], localHour: 1, localMinute: 30),
    );
    expect(
      planReminders(
        projection([fall], zone: 'America/New_York'),
        DateTime.utc(2026, 10, 31),
      ).single.scheduledAtUtc,
      DateTime.utc(2026, 11, 1, 5, 30),
    );
    final lordHowe = due(
      date: CivilDate(2026, 10, 4),
      rule: ReminderRule(daysBefore: [0], localHour: 2, localMinute: 15),
    );
    expect(
      planReminders(
        projection([lordHowe], zone: 'Australia/Lord_Howe'),
        DateTime.utc(2026, 10, 2),
      ).single.scheduledAtUtc,
      DateTime.utc(2026, 10, 3, 15, 30),
    );
  });
  test('archived paused deleted lifetime and entitlement fallback', () {
    final p = projection([
      Subscription(
        id: rid(2),
        name: '归档',
        status: SubscriptionStatus.archived,
        nextRenewalDate: CivilDate(2026, 10, 31),
      ),
      Subscription(
        id: rid(3),
        name: '暂停',
        status: SubscriptionStatus.paused,
        nextRenewalDate: CivilDate(2026, 10, 31),
      ),
      Subscription(id: rid(4), name: '买断', billingType: BillingType.lifetime),
      Subscription(
        id: rid(5),
        name: '权益到期',
        entitlementEnd: CivilDate(2026, 10, 31),
      ),
    ]);
    expect(
      planReminders(
        p,
        DateTime.utc(2026, 10, 20),
      ).map((e) => e.subscriptionId).toSet(),
      {rid(5)},
    );
    expect(planReminders(projection([]), DateTime.utc(2026, 10, 20)), isEmpty);
  });
  test(
    'rolled-back confirmed dates suppressed for conflicts and unsafe refs',
    () {
      final ref = EntityRef(EntityKind.subscription, rid(2));
      final conflict = Conflict(
        id: rid(50),
        competingBatchIds: [rid(51), rid(52)],
        affectedRefs: [ref],
      );
      expect(
        planReminders(
          projection([due()], conflicts: [conflict]),
          DateTime.utc(2026, 10, 20),
        ),
        isEmpty,
      );
      expect(
        planReminders(
          projection([due()]),
          DateTime.utc(2026, 10, 20),
          unsafeRefs: {ref},
        ),
        isEmpty,
      );
      expect(
        planReminders(
          projection([due()]),
          DateTime.utc(2026, 10, 20),
          unsafeRefs: {EntityRef(EntityKind.ledgerConfig, rid(1))},
        ),
        isEmpty,
      );
    },
  );
  test(
    '1000 simultaneous subscriptions keep all details in three summaries',
    () {
      final events = planReminders(
        projection([for (var i = 2; i < 1002; i++) due(id: i)]),
        DateTime.utc(2026, 10, 20),
      );
      final groups = groupReminders(events);
      expect(groups.length, 3);
      expect(groups.map((g) => g.events.length), [1000, 1000, 1000]);
      expect(
        groups.first.events.map((e) => e.subscriptionId).toSet().length,
        1000,
      );
    },
  );
}

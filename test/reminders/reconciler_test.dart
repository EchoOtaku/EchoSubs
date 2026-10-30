import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:echo_subs/app/services.dart';
import 'package:echo_subs/core/model/change_batch.dart';
import 'package:echo_subs/core/model/civil_date.dart';
import 'package:echo_subs/core/model/ledger.dart';
import 'package:echo_subs/core/model/errors.dart';
import 'package:echo_subs/core/model/ids.dart';
import 'package:echo_subs/core/crypto/envelope_codec.dart';
import 'package:echo_subs/core/crypto/ledger_metadata.dart';
import 'package:echo_subs/storage/ledger_store.dart';
import 'package:echo_subs/features/reminders/reminder_reconciler.dart';
import 'package:echo_subs/features/reminders/ui/reminder_settings_page.dart';
import 'package:echo_subs/features/sync/sync_coordinator.dart';
import 'package:echo_subs/features/sync/sync_status.dart';
import '../sync/coordinator_test.dart' show MemoryChannel, Token;
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:echo_subs/storage/app_database.dart';
import 'package:echo_subs/features/reminders/reminder_adapter.dart';
import 'package:echo_subs/features/reminders/reminder_planner.dart';
import '../support/ledger_harness.dart';
import 'planner_test.dart';

class FakeReminderPlatform implements ReminderPlatform {
  ReminderPermission access = ReminderPermission.granted;
  final queued = <int, String>{};
  int schedules = 0, cancels = 0;
  int permissionRequests = 0;
  int? limit;
  bool evictInsteadOfFail = false;
  bool failCancel = false, crashAfterSchedule = false;
  @override
  Future<ReminderPermission> permission() async => access;
  @override
  Future<ReminderPermission> requestPermission() async {
    permissionRequests++;
    return access;
  }

  @override
  Future<Map<int, String>> pending() async => Map.of(queued);
  @override
  Future<void> schedule(int id, ReminderBatch batch) async {
    if (limit != null && queued.length >= limit!) {
      if (evictInsteadOfFail) {
        queued.remove(queued.keys.first);
      } else {
        throw StateError('platform limit');
      }
    }
    queued[id] = batch.fingerprint;
    schedules++;
    if (crashAfterSchedule)
      throw StateError('interrupted after plugin accepted');
  }

  @override
  Future<void> cancel(int id) async {
    if (failCancel) throw StateError('cancel failed');
    queued.remove(id);
    cancels++;
  }

  @override
  Future<void> testNotification() async {}
  @override
  Future<void> close() async {}
}

void main() {
  setUpAll(() {
    tzdata.initializeTimeZones();
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });
  test(
    'independent SQLite connections cannot both allocate the same integer',
    () async {
      final h = await LedgerHarness.create();
      final db2 = await AppDatabase.open(
        File('${h.directory.path}/ledger.sqlite'),
      );
      final entered1 = Completer<void>();
      final release1 = Completer<void>();
      try {
        await h.db.customStatement('PRAGMA busy_timeout = 0');
        await db2.customStatement('PRAGMA busy_timeout = 0');
        final groups = groupReminders(
          planReminders(projection([due()]), DateTime.utc(2026, 10, 20)),
        );
        final s1 = ReminderStateStore(
          h.db,
          afterAllocationRead: () async {
            entered1.complete();
            await release1.future;
          },
        );
        final s2 = ReminderStateStore(db2);
        final result1 = s1
            .reserve([groups[0]])
            .then<Object>((v) => v, onError: (Object e) => e);
        await entered1.future.timeout(const Duration(seconds: 5));
        final result2 = s2
            .reserve([groups[1]])
            .then<Object>((v) => v, onError: (Object e) => e);
        // Drift's native transaction is BEGIN IMMEDIATE: the second writer is
        // rejected BEFORE it can read or allocate, while the first holds the lock.
        final two = await result2.timeout(const Duration(seconds: 5));
        expect(two, isNot(isA<List<SavedReminder>>()));
        release1.complete();
        final one = await result1;
        expect(one, isA<List<SavedReminder>>());
        expect(
          [one, two].whereType<List<SavedReminder>>().length,
          lessThanOrEqualTo(1),
        );
        final finalRecords = await ReminderStateStore(h.db).reserve(groups);
        expect(finalRecords.map((r) => r.id).toSet().length, 3);
      } finally {
        if (!release1.isCompleted) release1.complete();
        await db2.close();
        await h.close();
      }
    },
  );
  for (final damage in ['duplicate', 'invalid', 'exhausted']) {
    test('mapping $damage fails safely without allocating', () async {
      final h = await LedgerHarness.create();
      try {
        final groups = groupReminders(
          planReminders(projection([due()]), DateTime.utc(2026, 10, 20)),
        );
        final store = ReminderStateStore(h.db);
        final records = await store.reserve(groups.take(2).toList());
        final data = records.last.toJson();
        data['id'] = damage == 'duplicate'
            ? records.first.id
            : damage == 'invalid'
            ? -1
            : ReminderStateStore.maxId;
        await LedgerStore(h.db, records.last.batch.ledgerId).transaction(
          (tx) => tx.putNotificationState(records.last.key, jsonEncode(data)),
        );
        await expectLater(
          store.reserve([groups.last]),
          throwsA(isA<EchoFailure>()),
        );
        expect((await h.db.select(h.db.notificationStates).get()).length, 2);
      } finally {
        await h.close();
      }
    });
  }
  test(
    'editing time after due instant never duplicates the same day and rule',
    () async {
      final h = await LedgerHarness.create();
      var now = DateTime.utc(2026, 10, 24, 0);
      final p = FakeReminderPlatform();
      final a = DurableReminderAdapter(
        ReminderStateStore(h.db),
        p,
        now: () => now,
      );
      try {
        await a.replace(planReminders(projection([due()]), now));
        expect(p.schedules, 3);
        now = DateTime.utc(2026, 10, 24, 2);
        p.queued.remove(p.queued.keys.first); // delivered 09:00 Shanghai
        await a.replace(
          planReminders(
            projection([due(rule: ReminderRule(localHour: 11))]),
            now,
          ),
        );
        expect(a.status.scheduled.length, 2); // October 28 and 30 only
        expect(
          a.status.scheduled.any((b) => b.scheduledAtUtc.day == 24),
          false,
        );
        expect(p.queued.length, 2);
        await a.replace(
          planReminders(
            projection([due(rule: ReminderRule(localHour: 12))]),
            now,
          ),
        );
        expect(p.queued.length, 2);
      } finally {
        await a.close();
        await h.close();
      }
    },
  );
  test(
    'Windows banner fires only while running/foreground and retains no timers after close',
    () async {
      var now = DateTime.utc(2026, 10, 20);
      final p = InAppReminderPlatform(now: () => now);
      try {
        final batch = groupReminders(
          planReminders(projection([due()]), now),
        ).first;
        await p.schedule(1, batch);
        p.setForeground(false);
        now = DateTime.utc(2026, 10, 24, 2);
        p.tick();
        expect(p.banner.value, isNull);
        p.setForeground(true);
        expect(p.banner.value, contains('1 项订阅'));
        expect(await p.pending(), isEmpty);
        p.dismiss();
        p.tick();
        expect(p.banner.value, isNull);
      } finally {
        await p.close();
      }
    },
  );
  test(
    'services sync apply, conflict resolution, timezone and active ledger selection reconcile independently',
    () async {
      final h = await LedgerHarness.create();
      final s = AppServices(ledger: h.repo);
      final p = FakeReminderPlatform();
      final now = DateTime.utc(2026, 10, 20);
      final a = DurableReminderAdapter(
        ReminderStateStore(h.db),
        p,
        now: () => now,
      );
      final r = ReminderReconciler(
        snapshot: () async => s.snapshot,
        adapter: a,
        now: () => now,
      );
      await s.ready;
      s.attachReminders(r);
      try {
        final sub = due();
        await s.saveSubscription(sub);
        expect(p.queued.length, 3);
        final ledger = h.repo.currentLedgerId!;
        final state = await h.repo.snapshot();
        final ref = EntityRef(sub.kind, sub.id);
        final parents = state.causal.parentsFor(ref);
        final cloud = MemoryChannel(state.metadata);
        Future<void> remote(int n, CivilDate date) async {
          final b = ChangeBatch(
            id: rid(n),
            ledgerId: ledger,
            deviceId: rid(500),
            createdAtUtc: now,
            mutations: [
              Mutation(
                ref,
                parents,
                copySubscription(sub, {'nextRenewalDate': date.toJson()}),
              ),
            ],
          );
          final object = await StoredObject.fromBytes(
            b,
            await EnvelopeCodec().seal(b, await h.repo.authenticatedKeys()),
          );
          cloud.objects[cloud.key(object)] = object;
        }

        await remote(800, CivilDate(2026, 11, 2));
        final coordinator = SyncCoordinator(
          store: h.repo.store,
          authenticate: h.repo.authenticatedKeys,
          channels: [
            SyncChannel(SyncChannelKind.webdav, 'fictional', () async => cloud),
          ],
        );
        s.attachSync(coordinator);
        await coordinator.sync(token: Token());
        await s.refresh();
        expect(s.subscriptions.single.nextRenewalDate, CivilDate(2026, 11, 2));
        expect(a.status.scheduled.first.scheduledAtUtc.day, 26);
        final schedules = p.schedules;
        await coordinator.sync(token: Token());
        await s.refresh();
        expect(p.schedules, schedules);
        await remote(801, CivilDate(2026, 11, 3));
        await coordinator.sync(token: Token());
        await s.refresh();
        expect(r.suppressed, contains(ref));
        expect(p.queued, isEmpty);
        final conflict = s.snapshot!.projection.conflicts.single;
        await s.resolveConflict(ledger, conflict, [
          Mutation(ref, s.snapshot!.causal.heads[ref]!, sub),
        ]);
        expect(p.queued.length, 3);
        final configRef = EntityRef(EntityKind.ledgerConfig, ledger);
        await s.saveLedgerTimeZone(
          'UTC',
          expectedLedgerId: ledger,
          baseParents: AppServices.heads(s.snapshot!, configRef),
        );
        expect(a.status.scheduled.first.scheduledAtUtc.hour, 9);
        p.access = ReminderPermission.denied;
        final report = await coordinator.sync(token: Token());
        await s.refresh();
        expect(
          report.webdav.succeeded,
          true,
          reason:
              'errors=${report.webdav.errors}; pending=${report.webdav.pendingUpload}; conflicts=${report.webdav.conflicts}; quarantined=${report.webdav.quarantined}',
        );
        expect(s.syncStatus.remindersReconciled, false);
        final second = newId();
        await h.repo.create(
          LedgerConfig(second, 'UTC'),
          await createLedgerBundle(second),
        );
        await s.selectLedger(second);
        expect(p.queued, isEmpty);
        p.access = ReminderPermission.granted;
        await s.selectLedger(ledger);
        expect(p.queued.length, 3);
      } finally {
        await s.detachSync();
        await s.closeReminders();
        s.dispose();
        await h.close();
      }
    },
  );
  testWidgets(
    'permission denial is visible and grant only follows an explicit button',
    (tester) async {
      final h = (await tester.runAsync(LedgerHarness.create))!;
      final s = (await tester.runAsync(() async {
        final value = AppServices(ledger: h.repo);
        await value.ready;
        return value;
      }))!;
      final p = FakeReminderPlatform()..access = ReminderPermission.denied;
      final r = (await tester.runAsync(
        () async => ReminderReconciler(
          snapshot: () async => s.snapshot,
          adapter: DurableReminderAdapter(ReminderStateStore(h.db), p),
        ),
      ))!;
      try {
        await tester.runAsync(() async {
          await s.ready;
          s.attachReminders(r);
          await s.reconcileReminders();
        });
        await tester.pumpWidget(
          MaterialApp(home: ReminderSettingsPage(services: s)),
        );
        expect(find.text('通知权限：已关闭'), findsOneWidget);
        expect(find.text('提醒未全部就绪'), findsOneWidget);
        expect(find.text('本地提醒已核对'), findsNothing);
        expect(p.permissionRequests, 0);
        await tester.runAsync(() async {
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, '申请通知权限'))
              .onPressed!();
          await s.reconcileReminders();
        });
        await tester.pumpAndSettle();
        expect(p.permissionRequests, 1);
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        await tester.runAsync(() async {
          await s.closeReminders();
          s.dispose();
          await h.close();
        });
      }
    },
  );
  test(
    'denied permission is explicit and cancels; platform limit retains every failed detail',
    () async {
      final h = await LedgerHarness.create();
      final platform = FakeReminderPlatform()..limit = 1;
      final adapter = DurableReminderAdapter(
        ReminderStateStore(h.db),
        platform,
        now: () => DateTime.utc(2026, 10, 20),
      );
      final events = planReminders(
        projection([due()]),
        DateTime.utc(2026, 10, 20),
      );
      try {
        await adapter.replace(events);
        expect(adapter.status.complete, false);
        expect(adapter.status.unscheduled.length, 2);
        expect(platform.queued.length, 1);
        platform.access = ReminderPermission.denied;
        await adapter.replace(events);
        expect(adapter.status.permission, ReminderPermission.denied);
        expect(adapter.status.complete, false);
        expect(adapter.status.unscheduled.length, 3);
        expect(platform.queued, isEmpty);
      } finally {
        await adapter.close();
        await h.close();
      }
    },
  );
  test(
    '1000 entries register exactly three summaries; rejection preserves all 3000 details',
    () async {
      final h = await LedgerHarness.create();
      final p = FakeReminderPlatform();
      final now = DateTime.utc(2026, 10, 20);
      final a = DurableReminderAdapter(
        ReminderStateStore(h.db),
        p,
        now: () => now,
      );
      try {
        final events = planReminders(
          projection([for (var i = 2; i < 1002; i++) due(id: i)]),
          now,
        );
        await a.replace(events);
        expect(p.queued.length, 3);
        expect(
          (await ReminderStateStore(
            h.db,
          ).all()).map((r) => r.batch.events.length),
          [1000, 1000, 1000],
        );
        await a.replace([]);
        p.limit = 0;
        await a.replace(events);
        expect(a.status.unscheduled.length, 3000);
        expect(
          a.status.unscheduled.map((e) => e.stableKey).toSet().length,
          3000,
        );
        expect(a.status.complete, false);
      } finally {
        await a.close();
        await h.close();
      }
    },
  );
  test(
    'new process repairs OS-lost alarms even when plugin registration cache remains',
    () async {
      final h = await LedgerHarness.create();
      final p = FakeReminderPlatform();
      final now = DateTime.utc(2026, 10, 20);
      final a = DurableReminderAdapter(
        ReminderStateStore(h.db),
        p,
        now: () => now,
      );
      DurableReminderAdapter? reopened;
      try {
        final events = planReminders(projection([due()]), now);
        await a.replace(events);
        final ids = p.queued.keys.toSet();
        p.queued[999999] = 'foreign registration';
        await a.close();
        reopened = DurableReminderAdapter(
          ReminderStateStore(h.db),
          p,
          now: () => now,
        );
        await reopened.replace(events);
        expect(
          p.schedules,
          6,
        ); // fresh native registration using same permanent IDs
        expect(p.queued.keys.toSet(), {...ids, 999999});
        await reopened.replace([]);
        expect(p.queued, {999999: 'foreign registration'});
      } finally {
        await (reopened ?? a).close();
        await h.close();
      }
    },
  );
  test(
    'idempotent readback repairs interrupted calls and cancellation failures stay visible',
    () async {
      final h = await LedgerHarness.create();
      final platform = FakeReminderPlatform()..crashAfterSchedule = true;
      final adapter = DurableReminderAdapter(
        ReminderStateStore(h.db),
        platform,
        now: () => DateTime.utc(2026, 10, 20),
      );
      final events = planReminders(
        projection([due()]),
        DateTime.utc(2026, 10, 20),
      );
      try {
        await adapter.replace(events);
        expect(adapter.status.complete, false);
        platform.crashAfterSchedule = false;
        await adapter.replace(events);
        expect(adapter.status.complete, true);
        expect(platform.schedules, 3);
        platform.failCancel = true;
        await adapter.replace([]);
        expect(adapter.status.complete, false);
        expect(adapter.status.error, isNotNull);
        expect(adapter.status.unscheduled, isNotEmpty);
        platform.failCancel = false;
        await adapter.replace([]);
        expect(platform.queued, isEmpty);
      } finally {
        await adapter.close();
        await h.close();
      }
    },
  );
  test(
    'final readback detects a platform that silently evicts earlier alarms',
    () async {
      final h = await LedgerHarness.create();
      final p = FakeReminderPlatform()
        ..limit = 1
        ..evictInsteadOfFail = true;
      final now = DateTime.utc(2026, 10, 20);
      final a = DurableReminderAdapter(
        ReminderStateStore(h.db),
        p,
        now: () => now,
      );
      try {
        await a.replace(planReminders(projection([due()]), now));
        expect(a.status.complete, false);
        expect(a.status.scheduled.length, 1);
        expect(a.status.unscheduled.length, 2);
      } finally {
        await a.close();
        await h.close();
      }
    },
  );
  test(
    'global permanent integer mappings survive reopening and never reuse cancelled ids',
    () async {
      final h = await LedgerHarness.create();
      final path = File('${h.directory.path}/ledger.sqlite');
      try {
        final store = ReminderStateStore(h.db);
        final first = groupReminders(
          planReminders(projection([due()]), DateTime.utc(2026, 10, 20)),
        );
        final records = await store.reserve(first);
        expect(records.map((r) => r.id).toSet().length, 3);
        final other = first
            .map(
              (b) => ReminderBatch(
                rid(3),
                b.scheduledAtUtc,
                b.events.map(
                  (e) => ReminderEvent(
                    ledgerId: rid(3),
                    stableKey: e.stableKey.replaceFirst(rid(1), rid(3)),
                    subscriptionId: e.subscriptionId,
                    scheduledAtUtc: e.scheduledAtUtc,
                    ruleId: e.ruleId,
                    name: e.name,
                  ),
                ),
              ),
            )
            .toList();
        final second = await store.reserve(other);
        expect(
          {...records.map((r) => r.id), ...second.map((r) => r.id)}.length,
          6,
        );
        final reopened = await AppDatabase.open(path);
        try {
          expect(
            (await ReminderStateStore(
              reopened,
            ).reserve(first)).map((r) => r.id),
            records.map((r) => r.id),
          );
        } finally {
          await reopened.close();
        }
      } finally {
        await h.close();
      }
    },
  );
}

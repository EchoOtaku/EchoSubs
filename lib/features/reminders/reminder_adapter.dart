import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import '../../core/model/errors.dart';
import '../../core/model/ids.dart';
import '../../storage/app_database.dart';
import '../../storage/ledger_store.dart';
import 'reminder_planner.dart';

enum ReminderPermission { unknown, granted, denied, restricted }

class ReminderStatus {
  const ReminderStatus({
    this.permission = ReminderPermission.unknown,
    this.checked = false,
    this.unscheduled = const [],
    this.scheduled = const [],
    this.error,
  });
  final ReminderPermission permission;
  final bool checked;
  final List<ReminderEvent> unscheduled;
  final List<ReminderBatch> scheduled;
  final String? error;
  bool get complete =>
      checked &&
      permission == ReminderPermission.granted &&
      error == null &&
      unscheduled.isEmpty;
}

abstract class ReminderAdapter {
  ReminderStatus get status;
  Future<ReminderPermission> permission();
  Future<ReminderPermission> requestPermission();
  Future<void> replace(List<ReminderEvent> events);
  Future<void> testNotification();
  Future<void> close();
}

/// OS-specific boundary; replace/readback and durable intent belong above it.
abstract class ReminderPlatform {
  Future<ReminderPermission> permission();
  Future<ReminderPermission> requestPermission();
  Future<Map<int, String>> pending();
  Future<void> schedule(int id, ReminderBatch batch);
  Future<void> cancel(int id);
  Future<void> testNotification();
  Future<void> close();
}

enum ReminderPhase {
  reserved,
  scheduling,
  scheduled,
  failed,
  cancelling,
  cancelled,
  elapsed,
}

class SavedReminder {
  SavedReminder(
    this.id,
    this.batch, {
    this.phase = ReminderPhase.reserved,
    Iterable<String> consumed = const [],
  }) : consumed = Set.of(consumed);
  final int id;
  ReminderBatch batch;
  ReminderPhase phase;
  final Set<String> consumed;
  String get key => batch.stableKey;
  Map<String, Object?> toJson() => {
    'version': 1,
    'id': id,
    'batch': batch.toJson(),
    'phase': phase.name,
    'consumed': consumed.toList()..sort(),
  };
}

/// A single transaction reads and validates ALL ledger mappings and writes new
/// IDs. Cancelled records are permanent. No hash IDs, no truncation or recycling.
/// SQLite lock contention is an explicit failure; retry starts a fresh transaction.
class ReminderStateStore {
  ReminderStateStore(this.database, {this.afterAllocationRead});
  final AppDatabase database;
  final Future<void> Function()? afterAllocationRead;
  static const maxId =
      2147483646; // ID zero is reserved for explicit test messages.
  Future<List<SavedReminder>> all() async {
    final rows = await database.select(database.notificationStates).get();
    final ids = <int>{};
    final keys = <String>{};
    final values = <SavedReminder>[];
    try {
      for (final row in rows) {
        final v = jsonDecode(row.body) as Map<String, dynamic>;
        if (v['version'] != 1) throw const FormatException();
        final record = SavedReminder(
          v['id'] as int,
          ReminderBatch.fromJson(v['batch'] as Map<String, dynamic>),
          phase: ReminderPhase.values.byName(v['phase'] as String),
          consumed: (v['consumed'] as List).cast<String>(),
        );
        validateId(record.batch.ledgerId);
        for (final event in record.batch.events) {
          validateId(event.subscriptionId);
          if (event.ledgerId != record.batch.ledgerId ||
              event.scheduledAtUtc != record.batch.scheduledAtUtc ||
              event.stableKey.isEmpty ||
              event.ruleId.isEmpty)
            throw const FormatException();
        }
        if (record.batch.events.isEmpty ||
            record.batch.events.map((e) => e.stableKey).toSet().length !=
                record.batch.events.length)
          throw const FormatException();
        if (record.id < 1 ||
            record.id > maxId ||
            !ids.add(record.id) ||
            !keys.add(record.key) ||
            record.key != row.notificationId ||
            record.batch.ledgerId != row.ledgerId)
          throw const FormatException();
        values.add(record);
      }
    } on Object {
      throw const EchoFailure('integrity', '提醒映射损坏，已停止预约。请保留数据并检查。');
    }
    return values;
  }

  Future<void> save(SavedReminder record) =>
      LedgerStore(database, record.batch.ledgerId).transaction(
        (tx) =>
            tx.putNotificationState(record.key, jsonEncode(record.toJson())),
      );

  Future<List<SavedReminder>> reserve(List<ReminderBatch> batches) =>
      database.transaction(() async {
        final records = await all();
        await afterAllocationRead?.call();
        final byKey = {for (final r in records) r.key: r};
        var highest = records.fold(0, (int v, r) => r.id > v ? r.id : v);
        final result = <SavedReminder>[];
        for (final batch in batches) {
          var record = byKey[batch.stableKey];
          if (record == null) {
            if (highest >= maxId)
              throw const EchoFailure('unavailable', '提醒整数编号已用尽，未安排新提醒');
            record = SavedReminder(++highest, batch);
            await save(record);
            byKey[record.key] = record;
          }
          result.add(record);
        }
        return result;
      });
}

class DurableReminderAdapter implements ReminderAdapter {
  DurableReminderAdapter(this.store, this.platform, {DateTime Function()? now})
    : now = now ?? DateTime.now;
  final ReminderStateStore store;
  final ReminderPlatform platform;
  final DateTime Function() now;
  @override
  ReminderStatus status = const ReminderStatus();
  Future<void> _tail = Future.value();
  bool _closed = false;
  bool _recovering = true;
  @override
  Future<ReminderPermission> permission() => platform.permission();
  @override
  Future<ReminderPermission> requestPermission() =>
      platform.requestPermission();
  @override
  Future<void> testNotification() => platform.testNotification();
  @override
  Future<void> replace(List<ReminderEvent> events) {
    if (_closed) return Future.value();
    final copy = List<ReminderEvent>.of(events);
    return _tail = _tail.then((_) => _replace(copy));
  }

  Future<void> _replace(List<ReminderEvent> events) async {
    status = ReminderStatus(permission: status.permission);
    var access = ReminderPermission.unknown;
    final cancellationRisk = <ReminderEvent>[];
    try {
      access = await permission();
      final time = now().toUtc();
      final previous = await store.all();
      cancellationRisk.addAll(
        previous
            .where((r) => r.phase != ReminderPhase.cancelled)
            .expand((r) => r.batch.events),
      );
      final pending = await platform.pending();
      cancellationRisk.addAll(
        previous
            .where(
              (r) =>
                  r.phase == ReminderPhase.cancelled &&
                  pending.containsKey(r.id),
            )
            .expand((r) => r.batch.events),
      );
      final consumed = <String>{};
      for (final record in previous) {
        // Once the scheduled instant has passed, an interrupted call MAY already
        // have delivered. Conservatively consume before cancelling/replacing it.
        if (!record.batch.scheduledAtUtc.isAfter(time) &&
            [
              ReminderPhase.scheduling,
              ReminderPhase.scheduled,
              ReminderPhase.cancelling,
            ].contains(record.phase)) {
          record.consumed.addAll(record.batch.events.map((e) => e.stableKey));
          await store.save(record);
        }
        consumed.addAll(record.consumed);
      }
      final retained = <String>{
        for (final record in previous)
          if (pending[record.id] == record.batch.fingerprint)
            for (final event in record.batch.events)
              '${event.stableKey}/${event.scheduledAtUtc.toIso8601String()}',
      };
      final desired = groupReminders(
        events
            .where(
              (e) =>
                  !consumed.contains(e.stableKey) ||
                  retained.contains(
                    '${e.stableKey}/${e.scheduledAtUtc.toIso8601String()}',
                  ),
            )
            .toList(),
      );
      final wanted = {for (final batch in desired) batch.stableKey: batch};
      // Only cancel IDs whose durable ownership has just been validated.
      for (final record in previous) {
        final target = wanted[record.key];
        // An unconfirmed write can cross its due instant while waiting for a
        // retry. Do not replay it or silently declare it complete: cancel and
        // durably flush the old registration, preserving consumed event keys.
        final uncertainElapsed =
            !record.batch.scheduledAtUtc.isAfter(time) &&
            (record.phase == ReminderPhase.scheduling ||
                record.phase == ReminderPhase.cancelling);
        if (access != ReminderPermission.granted ||
            target == null ||
            target.fingerprint != record.batch.fingerprint ||
            uncertainElapsed) {
          if (record.phase == ReminderPhase.cancelled &&
              !pending.containsKey(record.id))
            continue;
          record.phase = ReminderPhase.cancelling;
          await store.save(record);
          await platform.cancel(record.id);
          pending.remove(record.id);
          record.phase = ReminderPhase.cancelled;
          await store.save(record);
          final cancelled = record.batch.events
              .map(
                (e) => '${e.stableKey}/${e.scheduledAtUtc.toIso8601String()}',
              )
              .toSet();
          cancellationRisk.removeWhere(
            (e) => cancelled.contains(
              '${e.stableKey}/${e.scheduledAtUtc.toIso8601String()}',
            ),
          );
        }
      }
      if (access != ReminderPermission.granted) {
        status = ReminderStatus(
          permission: access,
          checked: true,
          unscheduled: List.unmodifiable(events),
          error: '通知权限未开启，提醒未安排',
        );
        return;
      }
      final records = await store.reserve(desired);
      final failed = <ReminderEvent>[];
      final scheduled = <ReminderBatch>[];
      for (var i = 0; i < desired.length; i++) {
        final batch = desired[i];
        final record = records[i];
        // Plugin pending() is its persisted registration list, not proof the OS
        // retained an alarm after force-stop. Re-register future IDs once per
        // process start. Reusing the integer replaces the alarm atomically.
        if (record.phase == ReminderPhase.scheduled &&
            pending[record.id] == batch.fingerprint &&
            (!_recovering || !batch.scheduledAtUtc.isAfter(time))) {
          record.batch = batch;
          record.phase = ReminderPhase.scheduled;
          await store.save(record);
          scheduled.add(batch);
          continue;
        }
        if (!batch.scheduledAtUtc.isAfter(time))
          continue; // never replay an elapsed alarm
        record.batch = batch;
        record.phase = ReminderPhase.scheduling;
        await store.save(record); // durable intent BEFORE plugin side effect
        try {
          await platform.schedule(record.id, batch);
          if ((await platform.pending())[record.id] != batch.fingerprint)
            throw StateError('readback mismatch');
          record.phase = ReminderPhase.scheduled;
          await store.save(record);
          scheduled.add(batch);
        } on Object {
          // Keep scheduling phase: an interrupted call may have succeeded. Next
          // run uses OS readback before deciding whether to retry the same ID.
          failed.addAll(batch.events);
        }
      }
      // Check the complete set after all calls: a platform may evict an earlier
      // registration when a later one exceeds its capacity without throwing.
      final finalPending = await platform.pending();
      final idsByKey = {for (final record in records) record.key: record.id};
      scheduled.removeWhere((batch) {
        final missing =
            batch.scheduledAtUtc.isAfter(now().toUtc()) &&
            finalPending[idsByKey[batch.stableKey]] != batch.fingerprint;
        if (missing) failed.addAll(batch.events);
        return missing;
      });
      status = ReminderStatus(
        permission: access,
        checked: true,
        scheduled: List.unmodifiable(scheduled),
        unscheduled: List.unmodifiable(failed),
        error: failed.isEmpty ? null : '部分提醒未安排成功，详情已保留，请重试',
      );
      _recovering = false;
    } on Object catch (e) {
      status = ReminderStatus(
        permission: access,
        checked: true,
        unscheduled: List.unmodifiable(
          {
            for (final e in [...events, ...cancellationRisk])
              '${e.stableKey}/${e.scheduledAtUtc.toIso8601String()}': e,
          }.values,
        ),
        error: e is EchoFailure
            ? '${e.safeMessage}；旧提醒可能仍有效，请重新核对'
            : '提醒核对未完成，旧提醒可能仍有效，请重试（取消或读回失败）',
      );
    }
  }

  @override
  Future<void> close() async {
    _closed = true;
    await _tail;
    await platform.close();
  }
}

class AndroidReminderPlatform implements ReminderPlatform {
  AndroidReminderPlatform({FlutterLocalNotificationsPlugin? plugin})
    : plugin = plugin ?? FlutterLocalNotificationsPlugin();
  final FlutterLocalNotificationsPlugin plugin;
  static const _persistence = MethodChannel(
    'dev.echootaku.echo_subs/reminder_persistence',
  );

  /// The pinned plugin uses apply() on scheduled_notifications. Native commit
  /// must succeed before the caller can claim a durable schedule/cancellation.
  /// Matching in-memory plugin pending entries are not a substitute for this.
  Future<void> _flushScheduledNotifications() async {
    try {
      if (await _persistence.invokeMethod<bool>(
            'flushScheduledNotifications',
          ) ==
          true)
        return;
    } on Object {
      /* Deliberately do not expose native paths or exceptions. */
    }
    throw const EchoFailure('unavailable', '提醒缓存持久化失败，请重试');
  }

  Future<void>? _initialized;
  Future<void> _init() => _initialized ??= _initialize();
  Future<void> _initialize() async {
    try {
      if (await plugin.initialize(
            settings: const InitializationSettings(
              android: AndroidInitializationSettings('@mipmap/ic_launcher'),
            ),
          ) !=
          true)
        throw StateError('notifications initialization failed');
      await android.createNotificationChannel(
        const AndroidNotificationChannel(
          'echosubs_due_v1',
          '到期提醒',
          description: '账本本地到期提醒（约定时刻附近）',
        ),
      );
    } on Object {
      _initialized = null;
      rethrow;
    }
  }

  AndroidFlutterLocalNotificationsPlugin get android => plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()!;
  static const details = NotificationDetails(
    android: AndroidNotificationDetails(
      'echosubs_due_v1',
      '到期提醒',
      channelDescription: '账本本地到期提醒（约定时刻附近）',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      visibility: NotificationVisibility.private,
    ),
  );
  @override
  Future<ReminderPermission> permission() async {
    await _init();
    final enabled = await android.areNotificationsEnabled();
    if (enabled != true)
      return enabled == null
          ? ReminderPermission.unknown
          : ReminderPermission.denied;
    final channel = (await android.getNotificationChannels())
        ?.where((c) => c.id == 'echosubs_due_v1')
        .firstOrNull;
    return channel?.importance == Importance.none
        ? ReminderPermission.restricted
        : ReminderPermission.granted;
  }

  @override
  Future<ReminderPermission> requestPermission() async {
    await _init();
    await android.requestNotificationsPermission();
    return permission();
  }

  @override
  Future<Map<int, String>> pending() async {
    await _init();
    return {
      for (final p in await plugin.pendingNotificationRequests())
        p.id: p.payload ?? '',
    };
  }

  @override
  Future<void> schedule(int id, ReminderBatch batch) async {
    await _init();
    await plugin.zonedSchedule(
      id: id,
      scheduledDate: tz.TZDateTime.from(batch.scheduledAtUtc, tz.UTC),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      notificationDetails: details,
      title: 'EchoSubs 到期提醒',
      body: '${batch.events.length} 项订阅即将到期，请打开应用查看详情',
      payload: batch.fingerprint,
    );
    await _flushScheduledNotifications();
  }

  @override
  Future<void> cancel(int id) async {
    await _init();
    await plugin.cancel(id: id);
    await _flushScheduledNotifications();
  }

  @override
  Future<void> testNotification() async {
    if (await permission() != ReminderPermission.granted)
      throw const EchoFailure('permission', '通知权限未开启');
    await plugin.show(
      id: 0,
      title: 'EchoSubs 测试提醒',
      body: '这是一条本机测试通知，不代表实际订阅到期。',
      notificationDetails: details,
    );
  }

  @override
  Future<void> close() async {} // Android owns persisted one-shot alarms.
}

/// No Windows toast, service, startup registration or process survives close.
class InAppReminderPlatform implements ReminderPlatform {
  InAppReminderPlatform({DateTime Function()? now}) : now = now ?? DateTime.now;
  final DateTime Function() now;
  final banner = ValueNotifier<String?>(null);
  final _pending = <int, ReminderBatch>{};
  Timer? _timer;
  bool foreground = true;
  void setForeground(bool value) {
    foreground = value;
    if (value) tick();
  }

  void dismiss() => banner.value = null;
  void tick() {
    if (!foreground) return;
    final due = _pending.entries
        .where((e) => !e.value.scheduledAtUtc.isAfter(now().toUtc()))
        .toList();
    if (due.isEmpty) return;
    final count = due.fold(0, (int n, e) => n + e.value.events.length);
    for (final e in due) _pending.remove(e.key);
    banner.value = '$count 项订阅即将到期，请查看订阅详情';
  }

  @override
  Future<ReminderPermission> permission() async => ReminderPermission.granted;
  @override
  Future<ReminderPermission> requestPermission() => permission();
  @override
  Future<Map<int, String>> pending() async => {
    for (final e in _pending.entries) e.key: e.value.fingerprint,
  };
  @override
  Future<void> schedule(int id, ReminderBatch batch) async {
    _pending[id] = batch;
    _timer ??= Timer.periodic(const Duration(seconds: 15), (_) => tick());
  }

  @override
  Future<void> cancel(int id) async {
    _pending.remove(id);
  }

  @override
  Future<void> testNotification() async {
    banner.value = 'EchoSubs 测试提醒：仅在应用运行时显示';
  }

  @override
  Future<void> close() async {
    _timer?.cancel();
    _pending.clear();
    banner.dispose();
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import '../core/crypto/key_vault.dart';
import '../core/crypto/ledger_metadata.dart';
import '../core/model/change_batch.dart';
import '../core/model/civil_date.dart';
import '../core/model/errors.dart';
import '../core/model/ids.dart';
import '../core/model/ledger.dart';
import '../core/model/payment.dart';
import '../core/model/subscription.dart';
import '../features/ledger/ledger_repository.dart';
import '../storage/app_database.dart';
import '../storage/ledger_store.dart';
import '../features/sync/sync_coordinator.dart';
import '../features/sync/sync_status.dart';
import '../features/sync/sync_runtime.dart';
import '../features/reminders/reminder_adapter.dart';
import '../features/reminders/reminder_reconciler.dart';
import '../features/backup/backup_service.dart';

/// Local client services. Repository injection keeps widgets platform independent.
class AppServices extends ChangeNotifier {
  AppServices({required this.ledger}) {
    attachBackup(BackupService(ledger));
    syncRuntime = SyncRuntime(
      ledger,
      attach: attachSync,
      detach: detachSync,
      select: selectLedger,
    );
    rebindSync = syncRuntime.rebind;
    syncLifecycle = syncRuntime.foreground;
    closeSyncRuntime = syncRuntime.close;
    ready = reload();
  }
  final LedgerRepository ledger;
  BackupService? backup;
  void attachBackup(BackupService value) {
    if (!identical(value.ledger, ledger)) invalidModel();
    backup = value;
  }

  Future<LedgerId> restoreBackup(RestorePreview preview) async {
    _requireWritable();
    final id = await backup!.restoreAsNew(preview);
    await refresh();
    return id;
  }

  late final SyncRuntime syncRuntime;
  late final Future<void> ready;
  StreamSubscription<LedgerProjection>? _watch;
  LedgerSnapshot? snapshot;
  String? error;
  ThemeMode themeMode = ThemeMode.system;
  bool _disposed = false;
  int _generation = 0;
  int _read = 0;
  bool _switching = false;
  bool _writeLocked = false;
  SyncCoordinator? syncCoordinator;
  SyncStatus syncStatus = const SyncStatus();
  StreamSubscription<SyncStatus>? _syncWatch;
  StreamSubscription<LedgerProjection>? _syncChanges;
  SyncCancellation? _syncToken;
  String? _archiveFingerprint;
  bool _syncAgain = false;
  Future<void> Function()? rebindSync;
  Future<void> Function(bool foreground)? syncLifecycle;
  Future<void> Function()? closeSyncRuntime;
  ReminderReconciler? reminders;
  InAppReminderPlatform? inAppReminders;
  void attachReminders(ReminderReconciler reconciler) {
    if (_disposed) {
      unawaited(reconciler.close());
      return;
    }
    final old = reminders;
    old?.removeListener(_remindersChanged);
    if (old != null && old != reconciler) unawaited(old.close());
    reminders = reconciler;
    reconciler.addListener(_remindersChanged);
    unawaited(reconciler.reconcile());
  }

  SyncStatus _reminderStatus(SyncStatus s) => SyncStatus(
    running: s.running,
    report: s.report,
    remindersReconciled: reminders?.complete ?? false,
    retryMessage: s.retryMessage,
    failure: s.failure,
    failureCode: s.failureCode,
  );
  void _remindersChanged() {
    syncStatus = _reminderStatus(syncStatus);
    _changed();
  }

  Future<void> reconcileReminders() async {
    await reminders?.reconcile();
  }

  Future<void> remindersForeground(bool foreground) async {
    inAppReminders?.setForeground(foreground);
    if (foreground) await refresh();
  }

  Future<void> closeReminders() async {
    final old = reminders;
    reminders = null;
    old?.removeListener(_remindersChanged);
    await old?.close();
    inAppReminders = null;
  }

  void attachSync(SyncCoordinator coordinator) {
    if (coordinator.store.ledgerId != ledger.currentLedgerId || _disposed) {
      unawaited(coordinator.close());
      return;
    }
    final previous = syncCoordinator;
    _syncToken?.cancel();
    unawaited(_syncWatch?.cancel());
    unawaited(_syncChanges?.cancel());
    if (previous != null && previous != coordinator)
      unawaited(previous.close());
    syncCoordinator = coordinator;
    syncStatus = coordinator.status;
    _archiveFingerprint = null;
    _syncWatch = coordinator.watchStatus().listen((value) {
      if (_disposed ||
          syncCoordinator != coordinator ||
          coordinator.store.ledgerId != ledger.currentLedgerId)
        return;
      syncStatus = _reminderStatus(value);
      _changed();
    });
    _syncChanges = coordinator.store.watch().listen((_) async {
      try {
        final objects = [
          ...await coordinator.store.objects(),
          ...(await coordinator.store.quarantinedObjects()).map(
            (q) => q.object,
          ),
        ];
        final ids =
            objects.map((o) => '${o.batchId}:${o.sha256}').toSet().toList()
              ..sort();
        final fingerprint = ids.join(',');
        if (_disposed ||
            syncCoordinator != coordinator ||
            fingerprint == _archiveFingerprint)
          return;
        _archiveFingerprint = fingerprint;
        if (coordinator.status.running) {
          _syncAgain = true;
        } else {
          unawaited(syncNow());
        }
      } on Object catch (e) {
        if (!_disposed && syncCoordinator == coordinator) {
          error = safeError(e);
          _changed();
        }
      }
    }, onError: (Object _) {});
    unawaited(syncNow());
  }

  Future<void> syncNow() async {
    final coordinator = syncCoordinator;
    if (coordinator == null || _disposed || _switching) return;
    if (coordinator.status.running) {
      _syncAgain = true;
      return;
    }
    _syncToken = SyncCancellation();
    try {
      await coordinator.sync(token: _syncToken!);
      if (syncCoordinator == coordinator) await refresh();
    } on Object catch (e) {
      if (syncCoordinator == coordinator) {
        error = safeError(e);
        _changed();
      }
    } finally {
      if (_syncAgain && syncCoordinator == coordinator && !_disposed) {
        _syncAgain = false;
        unawaited(syncNow());
      }
    }
  }

  Future<void> detachSync() async {
    _syncToken?.cancel();
    final previous = syncCoordinator;
    syncCoordinator = null;
    await _syncWatch?.cancel();
    await _syncChanges?.cancel();
    await previous?.close();
    syncStatus = const SyncStatus();
  }

  void _requireWritable([LedgerId? expected]) {
    if (_switching || _writeLocked || snapshot == null)
      throw const EchoFailure('locked', '账本暂不可写');
    if (expected != null && expected != ledger.currentLedgerId)
      throw const EchoFailure('conflict', '账本已切换，请重新打开表单');
  }

  bool get loading => snapshot == null && error == null;
  List<Subscription> get subscriptions =>
      snapshot?.projection.entities.values.whereType<Subscription>().toList() ??
      [];
  List<Payment> get payments =>
      snapshot?.projection.entities.values.whereType<Payment>().toList() ?? [];
  List<Category> get categories =>
      snapshot?.projection.entities.values.whereType<Category>().toList() ?? [];
  LedgerConfig? get config => snapshot?.projection.entities.values
      .whereType<LedgerConfig>()
      .firstOrNull;
  CivilDate get today {
    tzdata.initializeTimeZones();
    final date = tz.TZDateTime.now(tz.getLocation(config?.timeZoneId ?? 'UTC'));
    return CivilDate(date.year, date.month, date.day);
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> reload() async {
    final generation = ++_generation;
    final read = ++_read;
    try {
      await _watch?.cancel();
      final state = await ledger.snapshot();
      if (_disposed || generation != _generation || read != _read) return;
      snapshot = state;
      error = null;
      _watch = ledger.watch().listen(
        (_) {
          if (!_disposed && generation == _generation) refresh();
        },
        onError: (Object e) {
          if (_disposed || generation != _generation) return;
          error = safeError(e);
          _changed();
        },
      );
      await reconcileReminders();
    } on Object catch (e) {
      if (_disposed || generation != _generation || read != _read) return;
      error = safeError(e);
    }
    _changed();
  }

  Future<void> refresh() async {
    final generation = _generation;
    final id = ledger.currentLedgerId;
    final read = ++_read;
    try {
      final state = await ledger.snapshot();
      if (_disposed ||
          generation != _generation ||
          id != ledger.currentLedgerId ||
          read != _read)
        return;
      snapshot = state;
      error = null;
      await reconcileReminders();
    } on Object catch (e) {
      if (_disposed ||
          generation != _generation ||
          id != ledger.currentLedgerId ||
          read != _read)
        return;
      error = safeError(e);
    }
    _changed();
  }

  static const activeLedgerKey = 'active.ledger';
  static const deviceIdKey = 'device.id';
  Future<void> selectLedger(LedgerId id) async {
    if (_switching) throw const EchoFailure('unavailable', '正在切换账本');
    _switching = true;
    final previous = ledger.currentLedgerId;
    var resumeAfterRollback = false;
    ++_generation;
    ++_read;
    try {
      await detachSync();
      await _watch?.cancel();
      await ledger.selectLedger(id);
      await ledger.vault.put(
        activeLedgerKey,
        Uint8List.fromList(utf8.encode(id)),
      );
      _writeLocked = false;
      await reload();
    } on Object catch (switchError) {
      var restored = false;
      try {
        if (previous != null) await ledger.selectLedger(previous);
        await reload();
        if (snapshot == null ||
            snapshot!.metadata.id != previous ||
            error != null) {
          throw const EchoFailure('locked', '原账本暂不可用');
        }
        _writeLocked = false;
        restored = true;
      } on Object {
        _writeLocked = true;
        snapshot = null;
        error = '账本切换未完成，已停止写入。原有数据与密钥已保留。';
        await reconcileReminders();
        _changed();
      }
      if (restored) {
        try {
          await rebindSync?.call();
          resumeAfterRollback = syncCoordinator != null;
        } on Object {
          // A secondary rebind failure must not replace the selection failure.
          // Keep the restored local ledger writable and the partial runtime shut.
          try {
            await detachSync();
          } on Object {
            /* Preserve the original switch failure. */
          }
        }
        error = safeError(switchError);
        _changed();
      }
      rethrow;
    } finally {
      _switching = false;
      if (resumeAfterRollback) unawaited(syncNow());
    }
    await rebindSync?.call();
  }

  void setTheme(ThemeMode mode) {
    themeMode = mode;
    _changed();
  }

  Future<void> saveLedgerTimeZone(
    String zone, {
    required LedgerId expectedLedgerId,
    required List<BatchId> baseParents,
  }) async {
    _requireWritable(expectedLedgerId);
    tz.getLocation(zone);
    final config = LedgerConfig(expectedLedgerId, zone);
    await ledger.commit([
      Mutation(EntityRef(config.kind, config.id), baseParents, config),
    ], expectedLedgerId: expectedLedgerId);
    await refresh();
  }

  /// The shared causal analyzer excludes pending/invalid data and rejects conflicts.
  static List<BatchId> heads(LedgerSnapshot state, EntityRef ref) {
    return state.causal.parentsFor(ref);
  }

  Future<void> saveSubscription(
    Subscription value, {
    String? categoryName,
    LedgerId? expectedLedgerId,
    List<BatchId>? baseParents,
  }) async {
    _requireWritable(expectedLedgerId);
    final targetId = expectedLedgerId ?? ledger.currentLedgerId!;
    final state = await ledger.snapshot();
    final changes = <Mutation>[];
    var actual = value;
    if (categoryName != null && categoryName.trim().isNotEmpty) {
      final name = categoryName.trim();
      final existing = state.projection.entities.values
          .whereType<Category>()
          .where((c) => c.name == name)
          .firstOrNull;
      final category = existing ?? Category(newId(), name);
      if (existing == null)
        changes.add(
          Mutation(EntityRef(category.kind, category.id), [], category),
        );
      actual = copySubscription(value, {'categoryId': category.id});
    }
    final ref = EntityRef(actual.kind, actual.id);
    changes.add(Mutation(ref, baseParents ?? heads(state, ref), actual));
    _requireWritable(targetId);
    await ledger.commit(changes, expectedLedgerId: targetId);
    await refresh();
  }

  Future<void> deleteSubscription(Subscription value) async {
    _requireWritable();
    final targetId = ledger.currentLedgerId!;
    final state = await ledger.snapshot();
    final ref = EntityRef(value.kind, value.id);
    await ledger.commit([
      Mutation(ref, heads(state, ref), null),
    ], expectedLedgerId: targetId);
    await refresh();
  }

  Future<void> renew(
    Subscription value,
    Payment payment, {
    LedgerId? expectedLedgerId,
    List<BatchId>? baseParents,
  }) async {
    _requireWritable(expectedLedgerId);
    await ledger.renew(
      value,
      payment,
      expectedLedgerId: expectedLedgerId ?? ledger.currentLedgerId!,
      baseParents: baseParents,
    );
    await refresh();
  }

  Future<void> resolveConflict(
    LedgerId id,
    Conflict conflict,
    List<Mutation> changes,
  ) async {
    _requireWritable(id);
    await ledger.resolve(conflict, changes, expectedLedgerId: id);
    await refresh();
  }

  @override
  void dispose() {
    _disposed = true;
    _watch?.cancel();
    unawaited(detachSync());
    unawaited(closeSyncRuntime?.call());
    unawaited(closeReminders());
    super.dispose();
  }

  /// Never replaces existing data or keys after an unlock failure.
  static Future<AppServices> bootstrap({
    AppDatabase? database,
    KeyVault? vault,
    Future<String> Function()? timeZone,
  }) async {
    final db = database ?? await AppDatabase.openDefault();
    try {
      final keys = vault ?? KeyVault();
      final stored = await keys.get(deviceIdKey);
      final device = stored == null ? newId() : utf8.decode(stored);
      validateId(device);
      if (stored == null)
        await keys.put(deviceIdKey, Uint8List.fromList(utf8.encode(device)));
      final repository = LedgerRepository(db, keys, device);
      final ids = await repository.listLedgers();
      if (ids.isEmpty) {
        final zone =
            await (timeZone?.call() ??
                FlutterTimezone.getLocalTimezone().then(
                  (info) => info.identifier,
                ));
        tzdata.initializeTimeZones();
        tz.getLocation(zone);
        final id = newId();
        await repository.create(
          LedgerConfig(id, zone),
          await createLedgerBundle(id),
        );
        await keys.put(activeLedgerKey, Uint8List.fromList(utf8.encode(id)));
      } else {
        final storedSelection = await keys.get(activeLedgerKey);
        if (storedSelection == null && ids.length > 1)
          throw const EchoFailure('locked', '存在多个账本，但本地选择缺失。请先明确选择账本，原有数据已保留。');
        final selected = storedSelection == null
            ? ids.single
            : utf8.decode(storedSelection);
        validateId(selected);
        if (!ids.contains(selected))
          throw const EchoFailure('locked', '本地选择的账本不存在，原有数据已保留。');
        await repository.selectLedger(selected);
        if (storedSelection == null)
          await keys.put(
            activeLedgerKey,
            Uint8List.fromList(utf8.encode(selected)),
          );
      }
      final services = AppServices(ledger: repository);
      await services.ready;
      if (database == null) {
        final ReminderPlatform platform;
        if (defaultTargetPlatform == TargetPlatform.android) {
          platform = AndroidReminderPlatform();
        } else {
          platform = services.inAppReminders = InAppReminderPlatform();
        }
        services.attachReminders(
          ReminderReconciler(
            snapshot: () async => services.snapshot,
            adapter: DurableReminderAdapter(ReminderStateStore(db), platform),
          ),
        );
        await services.reconcileReminders();
      }
      try {
        await services.syncRuntime.rebind();
      } on Object catch (e) {
        services.error = safeError(e);
      }
      return services;
    } on Object {
      if (database == null) await db.close();
      rethrow;
    }
  }
}

String safeError(Object e) =>
    e is EchoFailure ? e.safeMessage : '操作未完成，请重试。原有账本与密钥已保留。';
Subscription copySubscription(
  Subscription value,
  Map<String, Object?> changes,
) => Subscription.fromJson({...value.toJson(), ...changes});

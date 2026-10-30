import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
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

/// Local client services. Repository injection keeps widgets platform independent.
class AppServices extends ChangeNotifier {
  AppServices({required this.ledger}) {
    ready = reload();
  }
  final LedgerRepository ledger;
  late final Future<void> ready;
  StreamSubscription<LedgerProjection>? _watch;
  LedgerSnapshot? snapshot;
  String? error;
  ThemeMode themeMode = ThemeMode.system;
  bool _disposed = false;
  int _generation = 0;
  int _read = 0;
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
    final previous = ledger.currentLedgerId;
    await ledger.selectLedger(id);
    try {
      await ledger.vault.put(
        activeLedgerKey,
        Uint8List.fromList(utf8.encode(id)),
      );
    } on Object {
      if (previous != null) await ledger.selectLedger(previous);
      rethrow;
    }
    await reload();
  }

  void setTheme(ThemeMode mode) {
    themeMode = mode;
    _changed();
  }

  /// Heads are derived from the full causal history, including tombstones.
  static List<BatchId> heads(LedgerSnapshot state, EntityRef ref) {
    final tips = <BatchId>{};
    final parents = <BatchId>{};
    for (final batch in state.batches) {
      for (final change in batch.mutations.where((m) => m.ref == ref)) {
        tips.add(batch.id);
        parents.addAll(change.parentBatchIds);
      }
    }
    return (tips.difference(parents).toList()..sort());
  }

  Future<void> saveSubscription(
    Subscription value, {
    String? categoryName,
  }) async {
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
    changes.add(Mutation(ref, heads(state, ref), actual));
    await ledger.commit(changes);
    await refresh();
  }

  Future<void> deleteSubscription(Subscription value) async {
    final state = await ledger.snapshot();
    final ref = EntityRef(value.kind, value.id);
    await ledger.commit([Mutation(ref, heads(state, ref), null)]);
    await refresh();
  }

  Future<void> renew(Subscription value, Payment payment) async {
    await ledger.renew(value, payment);
    await refresh();
  }

  @override
  void dispose() {
    _disposed = true;
    _watch?.cancel();
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

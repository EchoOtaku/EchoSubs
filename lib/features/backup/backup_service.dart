import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import '../../core/crypto/envelope_codec.dart';
import '../../core/crypto/key_vault.dart';
import '../../core/crypto/ledger_keys.dart';
import '../../core/crypto/ledger_metadata.dart';
import '../../core/model/change_batch.dart';
import '../../core/model/errors.dart';
import '../../core/model/ids.dart';
import '../../core/model/ledger.dart';
import '../../storage/app_database.dart';
import '../../storage/ledger_store.dart';
import '../ledger/ledger_repository.dart';
import '../sync/materializer.dart';
import 'backup_format.dart';

/// Opaque authenticated content. Public preview fields contain only statistics.
/// No root/recovery key is retained here or included in diagnostics.
class RestorePreview {
  RestorePreview._(this._owner, this._batches, this._analysis);
  final BackupService _owner;
  final List<ChangeBatch> _batches;
  final CausalAnalysis _analysis;
  int get formatVersion => 1;
  int get batchCount => _batches.length;
  int get entityCount => _analysis.projection.entities.length;
  int get conflictCount => _analysis.projection.conflicts.length;
  int get quarantinedBatchCount => _analysis.quarantinedBatchIds.length;
  bool get configurationNeedsConfirmation {
    final ref = EntityRef(EntityKind.ledgerConfig, _batches.first.ledgerId);
    return !_analysis.projection.entities.containsKey(ref) ||
        _analysis.unsafeRefs.contains(ref) ||
        _analysis.projection.conflicts.any((c) => c.affectedRefs.contains(ref));
  }

  int get paymentVersionCount => _batches
      .expand((b) => b.mutations)
      .where((m) => m.ref.kind == EntityKind.payment && m.value != null)
      .length;
  @override
  String toString() =>
      'RestorePreview(version: 1, batches: $batchCount, conflicts: $conflictCount)';
}

class _ArchiveState {
  _ArchiveState(this.archive, this.batches, this.analysis);
  final BackupArchive archive;
  final List<ChangeBatch> batches;
  final CausalAnalysis analysis;
}

class BackupService {
  BackupService(this.ledger);
  final LedgerRepository ledger;
  final BackupFormat _format = BackupFormat();

  Future<_ArchiveState> _validate(
    BackupArchive archive,
    LedgerKeys keys,
  ) async {
    final batches = <ChangeBatch>[];
    final seen = <String>{};
    final variants = <String, int>{};
    for (final bytes in archive.objects) {
      final batch = await EnvelopeCodec().open(bytes, keys);
      final object = await StoredObject.fromBytes(batch, bytes);
      if (!seen.add('${batch.id}:${object.sha256}')) {
        throw const EchoFailure('integrity', '备份包含重复对象');
      }
      batches.add(batch);
      variants.update(batch.id, (n) => n + 1, ifAbsent: () => 1);
    }
    final allIds = batches.map((b) => b.id).toSet();
    // Missing dependencies in quarantined evidence also make an archive incomplete.
    if (batches
        .expand((b) => b.mutations)
        .expand((m) => m.parentBatchIds)
        .any((p) => !allIds.contains(p))) {
      throw const EchoFailure('conflict', '历史仍缺少依赖，请先补齐同步后备份');
    }
    final analysis = analyzeBatches(
      batches,
      quarantinedBatchIds: {
        for (final e in variants.entries)
          if (e.value > 1) e.key,
      },
    );
    validateLedgerImportHistory(
      archive.metadata.id,
      batches,
      analysis,
      policy: LedgerImportPolicy.backupRestore,
    );
    return _ArchiveState(archive, List.unmodifiable(batches), analysis);
  }

  Future<_ArchiveState> _read() async {
    final store = ledger.store;
    return ledger.database.transaction(() async {
      final keys = await ledger.authenticatedKeys(store.ledgerId);
      final snapshot = await store.snapshot();
      if (snapshot.projection.pendingBatchIds.isNotEmpty) {
        throw const EchoFailure('conflict', '历史仍缺少依赖，请先补齐同步后备份');
      }
      final objects = <String, StoredObject>{};
      for (final object in [
        ...await store.objects(),
        ...snapshot.quarantinedObjects.map((q) => q.object),
      ]) {
        objects['${object.batchId}:${object.sha256}'] = object;
      }
      final result = await _validate(
        BackupArchive(snapshot.metadata, objects.values.map((o) => o.bytes)),
        keys,
      );
      if (_signature(result.analysis) != _signature(snapshot.causal)) {
        throw const EchoFailure('integrity', '账本历史与本地投影不一致');
      }
      final storedBodies = [
        ...snapshot.batches,
        ...snapshot.quarantinedObjects.map((q) => q.batch),
      ].map((b) => canonicalJson(b.toJson())).toSet();
      if (storedBodies.length != result.batches.toSet().length ||
          !storedBodies.containsAll(
            result.batches.map((b) => canonicalJson(b.toJson())),
          )) {
        throw const EchoFailure('integrity', '账本历史验证失败');
      }
      return result;
    });
  }

  Future<Uint8List> exportEncrypted() async {
    final state = await _read();
    final keys = await ledger.authenticatedKeys(state.archive.metadata.id);
    return _format.seal(state.archive, keys);
  }

  Future<RestorePreview> inspect(Uint8List bytes, RecoveryCode recovery) async {
    final archive = await _format.open(bytes, recovery);
    final state = await _validate(
      archive,
      await unwrapKeys(archive.metadata, recovery),
    );
    return RestorePreview._(this, state.batches, state.analysis);
  }

  Future<LedgerId> restoreAsNew(RestorePreview preview) async {
    if (!identical(preview._owner, this))
      throw const EchoFailure('validation', '请重新校验备份');
    final bundle = await createLedgerBundle(newId());
    final map = _IdentityMap(
      preview._batches.first.ledgerId,
      bundle.metadata.id,
    );
    final batches = preview._batches.map(map.forward).toList();
    final objects = <StoredObject>[];
    for (final batch in batches) {
      objects.add(
        await StoredObject.fromBytes(
          batch,
          await EnvelopeCodec().seal(batch, bundle.keys),
        ),
      );
    }
    // This temporary database has no connection to the app's default path.
    final directory = await Directory.systemTemp.createTemp(
      'echosubs-restore-',
    );
    final file = File(
      '${directory.path}${Platform.pathSeparator}validation.sqlite',
    );
    AppDatabase? db;
    final temporaryVault = _TransientVault();
    late final List<StoredObject> validatedObjects;
    try {
      db = await AppDatabase.open(file);
      final temporary = LedgerRepository(
        db,
        KeyVault(storage: temporaryVault),
        newId(),
      );
      await temporary.importLedger(
        bundle.metadata,
        bundle.keys,
        objects,
        recovery: bundle.recovery,
        policy: LedgerImportPolicy.backupRestore,
      );
      final snapshot = await LedgerStore(db, bundle.metadata.id).snapshot();
      final persisted = {
        for (final o in [
          ...await LedgerStore(db, bundle.metadata.id).objects(),
          ...snapshot.quarantinedObjects.map((q) => q.object),
        ])
          '${o.batchId}:${o.sha256}': o,
      };
      final reverted = <ChangeBatch>[];
      for (final o in persisted.values) {
        reverted.add(
          map.backward(await EnvelopeCodec().open(o.bytes, bundle.keys)),
        );
      }
      final originalBodies =
          preview._batches.map((b) => canonicalJson(b.toJson())).toList()
            ..sort();
      final restoredBodies =
          reverted.map((b) => canonicalJson(b.toJson())).toList()..sort();
      final backAnalysis = analyzeBatches(
        reverted,
        quarantinedBatchIds: snapshot.quarantinedBatchIds
            .map(map.oldBatch)
            .toSet(),
      );
      if (canonicalJson(originalBodies) != canonicalJson(restoredBodies) ||
          _signature(preview._analysis) != _signature(backAnalysis)) {
        throw const EchoFailure('integrity', '恢复历史或冲突语义校验失败');
      }
      validatedObjects = List.unmodifiable(persisted.values);
    } on EchoFailure {
      rethrow;
    } on Object {
      throw const EchoFailure('unavailable', '恢复未完成，原账本与密钥已保留');
    } finally {
      await db?.close();
      temporaryVault.values.clear();
      // Remove only explicitly owned SQLite files, never recurse or touch source.
      for (final suffix in ['', '-journal', '-wal', '-shm']) {
        final owned = File('${file.path}$suffix');
        if (await owned.exists()) await owned.delete();
      }
      if (await directory.exists()) await directory.delete();
    }
    // Temporary resources are closed before final registration; cleanup cannot
    // turn a successful committed restore into an apparent failure.
    await ledger.importLedger(
      bundle.metadata,
      bundle.keys,
      validatedObjects,
      recovery: bundle.recovery,
      policy: LedgerImportPolicy.backupRestore,
    );
    return bundle.metadata.id;
  }

  /// Explicit display only. A paired device may have no locally saved recovery.
  Future<RecoveryCode?> recoveryFor(LedgerId id) async {
    final keys = await ledger.authenticatedKeys(id);
    final bytes = await ledger.vault.get(LedgerRepository.recoveryKeyName(id));
    if (bytes == null) return null;
    final code = RecoveryCode.parse(utf8.decode(bytes, allowMalformed: false));
    final recovered = await unwrapKeys(
      await LedgerStore(ledger.database, id).metadata(),
      code,
    );
    if (base64Encode(keys.rootKey) != base64Encode(recovered.rootKey))
      throw const EchoFailure('locked', '恢复密钥不可用');
    return code;
  }

  Future<Uint8List> exportPlain({required bool confirmed}) async {
    if (!confirmed) throw const EchoFailure('cancelled', '请先确认明文包含私人订阅与付款信息');
    final state = await _read();
    final result = canonicalBytes({
      'version': 1,
      'purpose': 'plain-export',
      'ledgerId': state.archive.metadata.id,
      'batches': state.batches.map((b) => b.toJson()).toList(),
      'projection': state.analysis.projection.toJson(),
      'quarantinedBatchIds': state.analysis.quarantinedBatchIds.toList()
        ..sort(),
    });
    if (result.length > maxBackupBytes)
      throw const EchoFailure('validation', '导出超过 100 MiB 上限');
    return result;
  }
}

String _signature(CausalAnalysis a) => canonicalJson({
  'projection': a.projection.toJson(),
  'quarantined': a.quarantinedBatchIds.toList()..sort(),
  'unsafe': (a.unsafeRefs.toList()..sort()).map((r) => r.toJson()).toList(),
  'heads': (a.heads.keys.toList()..sort())
      .map((r) => {'ref': r.toJson(), 'ids': a.heads[r]!.toList()..sort()})
      .toList(),
});

class _TransientVault implements VaultStorage {
  final values = <String, String>{};
  @override
  Future<String?> read(String name) async => values[name];
  @override
  Future<void> write(String name, String value) async {
    values[name] = value;
  }
}

/// Typed ID positions only: notes, names, dates and money are never rewritten.
class _IdentityMap {
  _IdentityMap(this.oldLedger, this.newLedger);
  final String oldLedger, newLedger;
  final _batch = <String, String>{},
      _entity = <String, String>{},
      _device = <String, String>{};
  String _id(Map<String, String> map, String value, bool reverse) {
    if (reverse) return map.entries.singleWhere((e) => e.value == value).key;
    return map.putIfAbsent(value, newId);
  }

  String oldBatch(String value) => _id(_batch, value, true);
  String _entityId(EntityKind kind, String id, bool reverse) {
    if (kind == EntityKind.ledgerConfig &&
        id == (reverse ? newLedger : oldLedger))
      return reverse ? oldLedger : newLedger;
    // Kind-scoped namespaces avoid accidental cross-kind identity aliasing.
    final key = '${kind.name}:$id';
    if (!reverse) return _entity.putIfAbsent(key, newId);
    return _entity.entries
        .singleWhere((e) => e.value == id)
        .key
        .split(':')
        .last;
  }

  ChangeBatch forward(ChangeBatch b) => _map(b, false);
  ChangeBatch backward(ChangeBatch b) => _map(b, true);
  ChangeBatch _map(ChangeBatch b, bool reverse) => ChangeBatch(
    id: _id(_batch, b.id, reverse),
    ledgerId: reverse ? oldLedger : newLedger,
    deviceId: _id(_device, b.deviceId, reverse),
    createdAtUtc: b.createdAtUtc,
    mutations: b.mutations.map((m) {
      final id = _entityId(m.ref.kind, m.ref.id, reverse);
      final value = m.value?.toJson();
      if (value != null) {
        value['id'] = id;
        if (m.ref.kind == EntityKind.subscription &&
            value['categoryId'] != null)
          value['categoryId'] = _entityId(
            EntityKind.category,
            value['categoryId'] as String,
            reverse,
          );
        if (m.ref.kind == EntityKind.payment)
          value['subscriptionId'] = _entityId(
            EntityKind.subscription,
            value['subscriptionId'] as String,
            reverse,
          );
      }
      return Mutation(
        EntityRef(m.ref.kind, id),
        m.parentBatchIds.map((p) => _id(_batch, p, reverse)),
        value == null ? null : LedgerEntity.fromJson(m.ref.kind, value),
      );
    }),
  );
}

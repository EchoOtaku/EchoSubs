import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart' show SqliteException;
import '../core/crypto/envelope_codec.dart';
import '../core/crypto/ledger_metadata.dart';
import '../core/model/change_batch.dart';
import '../core/model/errors.dart';
import '../core/model/ids.dart';
import '../core/model/ledger.dart';
import '../features/sync/materializer.dart';
import 'app_database.dart';

class StoredObject {
  StoredObject(this.batchId, this.ledgerId, this.sha256, Uint8List bytes)
    : _bytes = Uint8List.fromList(bytes);
  final BatchId batchId;
  final LedgerId ledgerId;
  final String sha256;
  final Uint8List _bytes;
  Uint8List get bytes => Uint8List.fromList(_bytes);
  static Future<StoredObject> fromBytes(
    ChangeBatch batch,
    Uint8List bytes,
  ) async {
    final digest = await Sha256().hash(bytes);
    return StoredObject(
      batch.id,
      batch.ledgerId,
      digest.bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join(),
      bytes,
    );
  }
}

/// One persisted ciphertext and its corresponding immutable causal record.
class LedgerKeyProof {
  const LedgerKeyProof(this.object, this.batch);
  final StoredObject object;
  final ChangeBatch batch;
}

class LedgerSnapshot {
  LedgerSnapshot(
    this.metadata,
    Iterable<ChangeBatch> batches,
    this.projection,
    Iterable<BatchId> pendingBatchIds, {
    Iterable<QuarantineCandidate> quarantinedObjects = const [],
  }) : batches = List.unmodifiable(batches),
       pendingBatchIds = List.unmodifiable(pendingBatchIds),
       quarantinedObjects = List.unmodifiable(quarantinedObjects);
  final LedgerMetadata metadata;
  final List<ChangeBatch> batches;
  final LedgerProjection projection;
  final List<BatchId> pendingBatchIds;

  /// Legacy pendingBatchIds denotes only transport outbox, never causal pending.
  List<BatchId> get pendingUploadIds => pendingBatchIds;
  final List<QuarantineCandidate> quarantinedObjects;
  late final CausalAnalysis causal = analyzeBatches([
    ...batches,
    ...quarantinedObjects.map((q) => q.batch),
  ], quarantinedBatchIds: quarantinedObjects.map((q) => q.batch.id).toSet());
  Set<BatchId> get quarantinedBatchIds => causal.quarantinedBatchIds;
}

enum QuarantineReason { idCollision, invalidCausality }

class QuarantineCandidate {
  const QuarantineCandidate(this.object, this.batch, this.reason);
  final StoredObject object;
  final ChangeBatch batch;
  final QuarantineReason reason;
}

enum StorageCheckpoint { afterPaymentWrite, beforeObjectWrite, beforeSyncState }

typedef StorageObserver = Future<void> Function(StorageCheckpoint checkpoint);

/// Bound to one ledger. All business/sync writes must use [transaction].
class LedgerStore {
  LedgerStore(this.database, this.ledgerId, {this.observer}) {
    validateId(ledgerId);
  }
  final AppDatabase database;
  final LedgerId ledgerId;
  final StorageObserver? observer;
  Future<T> transaction<T>(
    Future<T> Function(LedgerTransaction tx) action,
  ) async {
    try {
      return await database.transaction(() async {
        final tx = LedgerTransaction._(this);
        try {
          return await action(tx);
        } finally {
          tx._active = false;
        }
      });
    } on SqliteException catch (error) {
      if (error.resultCode == 19)
        throw const EchoFailure('conflict', '记录已存在或对象冲突');
      if (error.resultCode == 11 || error.resultCode == 26)
        throw const EchoFailure('integrity', '数据库完整性异常');
      throw const EchoFailure('unavailable', '数据库暂不可写');
    }
  }

  Future<LedgerMetadata> metadata() async {
    final row = await (database.select(
      database.ledgerRecords,
    )..where((r) => r.ledgerId.equals(ledgerId))).getSingleOrNull();
    if (row == null) throw const EchoFailure('unavailable', '账本不存在');
    return LedgerMetadata.decode(row.metadata);
  }

  Future<List<StoredObject>> objects() async => List.unmodifiable([
    for (final r
        in await (database.select(database.cipherObjects)
              ..where((r) => r.ledgerId.equals(ledgerId))
              ..orderBy([(r) => OrderingTerm.asc(r.batchId)]))
            .get())
      StoredObject(r.batchId, r.ledgerId, r.sha256, r.bytes),
  ]);

  /// Full authenticated evidence for conflict UI and lossless backups.
  Future<List<QuarantineCandidate>> quarantinedObjects() async =>
      List.unmodifiable([
        for (final r
            in await (database.select(database.quarantinedObjects)
                  ..where((r) => r.ledgerId.equals(ledgerId))
                  ..orderBy([
                    (r) => OrderingTerm.asc(r.batchId),
                    (r) => OrderingTerm.asc(r.sha256),
                  ]))
                .get())
          QuarantineCandidate(
            StoredObject(r.batchId, r.ledgerId, r.sha256, r.bytes),
            ChangeBatch.fromJson(jsonDecode(r.body) as Map<String, dynamic>),
            QuarantineReason.values.byName(r.reason),
          ),
      ]);

  /// Reads at most one blob; absence cannot establish ownership of a root key.
  Future<LedgerKeyProof?> keyProof() => database.transaction(() async {
    final row =
        await (database.select(database.cipherObjects)
              ..where((r) => r.ledgerId.equals(ledgerId))
              ..orderBy([(r) => OrderingTerm.asc(r.batchId)])
              ..limit(1))
            .getSingleOrNull();
    if (row == null) return null;
    final record =
        await (database.select(database.changeBatches)..where(
              (r) =>
                  r.ledgerId.equals(ledgerId) & r.batchId.equals(row.batchId),
            ))
            .getSingleOrNull();
    if (record == null) throw const EchoFailure('integrity', '账本证明记录缺失');
    return LedgerKeyProof(
      StoredObject(row.batchId, row.ledgerId, row.sha256, row.bytes),
      ChangeBatch.fromJson(jsonDecode(record.body) as Map<String, dynamic>),
    );
  });
  Future<LedgerSnapshot> snapshot() => database.transaction(() async {
    final meta = await metadata();
    final rows =
        await (database.select(database.changeBatches)
              ..where((r) => r.ledgerId.equals(ledgerId))
              ..orderBy([(r) => OrderingTerm.asc(r.batchId)]))
            .get();
    final batches = rows
        .map(
          (r) =>
              ChangeBatch.fromJson(jsonDecode(r.body) as Map<String, dynamic>),
        )
        .toList();
    final pending =
        (await (database.select(
              database.pendingUploads,
            )..where((r) => r.ledgerId.equals(ledgerId))).get())
            .map((r) => r.batchId)
            .toList()
          ..sort();
    final quarantined = await quarantinedObjects();
    final analysis = analyzeBatches([
      ...batches,
      ...quarantined.map((q) => q.batch),
    ], quarantinedBatchIds: quarantined.map((q) => q.batch.id).toSet());
    return LedgerSnapshot(
      meta,
      batches,
      analysis.projection,
      pending,
      quarantinedObjects: quarantined,
    );
  });
  Stream<LedgerProjection> watch() => database
      .customSelect(
        'SELECT ledger_id FROM ledger_records WHERE ledger_id = ?',
        variables: [Variable(ledgerId)],
        readsFrom: {
          database.ledgerRecords,
          database.changeBatches,
          database.pendingUploads,
          database.storedConflicts,
          database.quarantinedObjects,
        },
      )
      .watch()
      .asyncMap((_) async => (await snapshot()).projection);
  Future<Set<BatchId>> receivedBatchIds() async => Set.unmodifiable(
    (await (database.select(
      database.receivedBatches,
    )..where((r) => r.ledgerId.equals(ledgerId))).get()).map((r) => r.batchId),
  );
  Future<Map<String, String>> notificationStates() async => Map.unmodifiable({
    for (final row in await (database.select(
      database.notificationStates,
    )..where((r) => r.ledgerId.equals(ledgerId))).get())
      row.notificationId: row.body,
  });
}

/// Valid only during its callback. Incoming objects must be authenticated by codec first.
class LedgerTransaction {
  LedgerTransaction._(this._store);
  final LedgerStore _store;
  bool _active = true;
  void _checkActive() {
    if (!_active) throw const EchoFailure('unavailable', '事务已经结束');
  }

  AppDatabase get _db {
    _checkActive();
    return _store.database;
  }

  String get _id => _store.ledgerId;
  Future<LedgerSnapshot> snapshot() {
    _checkActive();
    return _store.snapshot();
  }

  Future<void> register(LedgerMetadata metadata) async {
    if (metadata.id != _id) invalidModel();
    await _db
        .into(_db.ledgerRecords)
        .insert(
          LedgerRecordsCompanion.insert(
            ledgerId: _id,
            metadata: metadata.encode(),
          ),
        );
  }

  Future<void> validateParents(List<Mutation> changes) async {
    final causal = (await snapshot()).causal;
    for (final m in changes) {
      final expected = causal.parentsFor(m.ref).toSet();
      if (expected.length != m.parentBatchIds.length ||
          !expected.containsAll(m.parentBatchIds)) {
        throw const EchoFailure('conflict', '记录已更新，请重新加载');
      }
    }
  }

  /// Call only with the matching authenticated batch and immutable ciphertext.
  Future<void> quarantine(
    ChangeBatch batch,
    StoredObject object,
    QuarantineReason reason,
  ) async {
    if (batch.ledgerId != _id ||
        object.ledgerId != _id ||
        batch.id != object.batchId ||
        (await StoredObject.fromBytes(batch, object.bytes)).sha256 !=
            object.sha256 ||
        object.bytes.length > maxCryptoObjectBytes) {
      throw const EchoFailure('integrity', '隔离对象不匹配');
    }
    await _db
        .into(_db.quarantinedObjects)
        .insert(
          QuarantinedObjectsCompanion.insert(
            ledgerId: _id,
            batchId: batch.id,
            sha256: object.sha256,
            bytes: object.bytes,
            body: canonicalJson(batch.toJson()),
            reason: reason.name,
          ),
          mode: InsertMode.insertOrIgnore,
        );
    await acknowledge(batch.id);
  }

  Future<void> append(
    ChangeBatch batch,
    StoredObject object, {
    bool pending = true,
    bool received = false,
  }) async {
    _checkActive();
    await _store.metadata();
    if (batch.ledgerId != _id ||
        object.ledgerId != _id ||
        batch.id != object.batchId)
      invalidModel();
    final verified = await StoredObject.fromBytes(batch, object.bytes);
    final envelope = decodeCryptoObject(object.bytes);
    if (verified.sha256 != object.sha256 ||
        envelope['ledgerId'] != _id ||
        envelope['batchId'] != batch.id ||
        envelope['purpose'] != 'sync') {
      throw const EchoFailure('integrity', '密文对象不匹配');
    }
    await _db
        .into(_db.changeBatches)
        .insert(
          ChangeBatchesCompanion.insert(
            ledgerId: _id,
            batchId: batch.id,
            body: canonicalJson(batch.toJson()),
          ),
        );
    for (final m in batch.mutations) {
      await _db
          .into(_db.entityVersions)
          .insert(
            EntityVersionsCompanion.insert(
              ledgerId: _id,
              kind: m.ref.kind.name,
              entityId: m.ref.id,
              batchId: batch.id,
              valueJson: Value(
                m.value == null ? null : canonicalJson(m.value!.toJson()),
              ),
            ),
          );
      if (m.ref.kind == EntityKind.payment)
        await _store.observer?.call(StorageCheckpoint.afterPaymentWrite);
    }
    await _store.observer?.call(StorageCheckpoint.beforeObjectWrite);
    await _db
        .into(_db.cipherObjects)
        .insert(
          CipherObjectsCompanion.insert(
            ledgerId: _id,
            batchId: batch.id,
            sha256: object.sha256,
            nonce: envelope['nonce'] as String,
            bytes: object.bytes,
          ),
        );
    await _store.observer?.call(StorageCheckpoint.beforeSyncState);
    if (pending)
      await _db
          .into(_db.pendingUploads)
          .insert(
            PendingUploadsCompanion.insert(ledgerId: _id, batchId: batch.id),
          );
    if (received) await markReceived(batch.id);
  }

  Future<void> acknowledge(BatchId id) async {
    await _store.observer?.call(StorageCheckpoint.beforeSyncState);
    await (_db.delete(
      _db.pendingUploads,
    )..where((r) => r.ledgerId.equals(_id) & r.batchId.equals(id))).go();
  }

  Future<void> markReceived(BatchId id) async {
    await _db
        .into(_db.receivedBatches)
        .insert(
          ReceivedBatchesCompanion.insert(ledgerId: _id, batchId: id),
          mode: InsertMode.insertOrIgnore,
        );
  }

  Future<void> replaceConflicts(List<Conflict> conflicts) async {
    await (_db.delete(
      _db.storedConflicts,
    )..where((r) => r.ledgerId.equals(_id))).go();
    for (final c in conflicts) {
      await _db
          .into(_db.storedConflicts)
          .insert(
            StoredConflictsCompanion.insert(
              ledgerId: _id,
              conflictId: c.id,
              body: canonicalJson(c.toJson()),
            ),
          );
    }
  }

  Future<void> putNotificationState(String notificationId, String body) async {
    await _db
        .into(_db.notificationStates)
        .insertOnConflictUpdate(
          NotificationStatesCompanion.insert(
            ledgerId: _id,
            notificationId: notificationId,
            body: body,
          ),
        );
  }
}

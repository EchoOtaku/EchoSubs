import 'dart:convert';
import 'dart:typed_data';
import '../../core/crypto/envelope_codec.dart';
import '../../core/crypto/key_vault.dart';
import '../../core/crypto/ledger_keys.dart';
import '../../core/crypto/ledger_metadata.dart';
import '../../core/model/change_batch.dart';
import '../../core/model/errors.dart';
import '../../core/model/ids.dart';
import '../../core/model/ledger.dart';
import '../../core/model/payment.dart';
import '../../core/model/subscription.dart';
import '../../storage/app_database.dart';
import '../../storage/ledger_store.dart';
import '../sync/conflict_resolution.dart';
import '../sync/materializer.dart';

class LedgerRepository {
  LedgerRepository(
    this.database,
    this.vault,
    this.deviceId, {
    EnvelopeCodec? codec,
    this.observer,
  }) : codec = codec ?? EnvelopeCodec() {
    validateId(deviceId);
  }
  final AppDatabase database;
  final KeyVault vault;
  final DeviceId deviceId;
  final EnvelopeCodec codec;
  final StorageObserver? observer;
  LedgerId? _current;
  LedgerId? get currentLedgerId => _current;
  static String rootKeyName(LedgerId id) => 'ledger.$id.root';
  static String recoveryKeyName(LedgerId id) => 'ledger.$id.recovery';
  LedgerStore get store {
    final id = _current;
    if (id == null) throw const EchoFailure('locked', '尚未选择账本');
    return LedgerStore(database, id, observer: observer);
  }

  Future<List<LedgerId>> listLedgers() async => List.unmodifiable(
    (await database.select(database.ledgerRecords).get())
        .map((r) => r.ledgerId)
        .toList()
      ..sort(),
  );
  Future<LedgerKeys> _keys(LedgerId id) async {
    final bytes = await vault.get(rootKeyName(id));
    if (bytes == null || bytes.length != 32)
      throw const EchoFailure('locked', '账本密钥不可用');
    final keys = LedgerKeys(id, bytes);
    final bound = LedgerStore(database, id);
    try {
      await database.transaction(() async {
        final metadata = await bound.metadata();
        final proof = await bound.keyProof();
        if (metadata.id != id ||
            proof == null ||
            proof.object.ledgerId != id ||
            proof.batch.ledgerId != id ||
            proof.batch.id != proof.object.batchId) {
          throw const EchoFailure('locked', '无法验证账本密钥');
        }
        final decoded = await EnvelopeCodec().open(proof.object.bytes, keys);
        final digest = await StoredObject.fromBytes(
          decoded,
          proof.object.bytes,
        );
        if (decoded != proof.batch ||
            decoded.id != proof.object.batchId ||
            digest.sha256 != proof.object.sha256) {
          throw const EchoFailure('locked', '无法验证账本密钥');
        }
      });
    } on Object {
      throw const EchoFailure('locked', '无法验证账本密钥');
    }
    return keys;
  }

  Future<void> selectLedger(LedgerId id) async {
    await _keys(id);
    _current = id;
  }

  Future<void> create(LedgerConfig config, LedgerBundle bundle) async {
    final id = bundle.metadata.id;
    if (bundle.keys.ledgerId != id ||
        config.id != id ||
        (await listLedgers()).contains(id))
      invalidModel();
    final recovered = await unwrapKeys(bundle.metadata, bundle.recovery);
    if (!_equalBytes(recovered.rootKey, bundle.keys.rootKey)) invalidModel();
    await LedgerStore(database, id, observer: observer).transaction((tx) async {
      // The uncommitted unique registration reserves SQLite's writer lock.
      // Other connections/processes fail or wait before touching vault keys.
      await tx.register(bundle.metadata);
      if (await vault.get(rootKeyName(id)) != null ||
          await vault.get(recoveryKeyName(id)) != null) {
        throw const EchoFailure('conflict', '账本密钥已存在');
      }
      await vault.put(rootKeyName(id), bundle.keys.rootKey);
      await vault.put(
        recoveryKeyName(id),
        Uint8List.fromList(utf8.encode(bundle.recovery.encoded)),
      );
      final batch = _batch(id, [
        Mutation(EntityRef(config.kind, config.id), [], config),
      ]);
      final object = await StoredObject.fromBytes(
        batch,
        await codec.seal(batch, bundle.keys),
      );
      await tx.append(batch, object);
    });
    _current = id;
  }

  ChangeBatch _batch(LedgerId id, List<Mutation> changes) => ChangeBatch(
    id: newId(),
    ledgerId: id,
    deviceId: deviceId,
    createdAtUtc: DateTime.now().toUtc(),
    mutations: changes,
  );
  Future<BatchId> commit(List<Mutation> changes) =>
      _commitTo(store, List.unmodifiable(changes));
  Future<BatchId> resolve(Conflict conflict, List<Mutation> resolution) =>
      _commitTo(store, List.unmodifiable(resolution), resolutionOf: conflict);

  Future<BatchId> _commitTo(
    LedgerStore target,
    List<Mutation> changes, {
    Conflict? resolutionOf,
  }) async {
    final keys = await _keys(target.ledgerId);
    final batch = _batch(target.ledgerId, changes);
    final object = await StoredObject.fromBytes(
      batch,
      await codec.seal(batch, keys),
    );
    await target.transaction((tx) async {
      if (resolutionOf == null) {
        await tx.validateParents(changes);
      } else {
        validateConflictResolution(
          (await tx.snapshot()).causal,
          resolutionOf,
          changes,
        );
      }
      final state = await tx.snapshot();
      final proposed = analyzeBatches([
        ...state.batches,
        batch,
        ...state.quarantinedObjects.map((q) => q.batch),
      ], quarantinedBatchIds: state.quarantinedBatchIds);
      if (proposed.quarantinedBatchIds.contains(batch.id) ||
          proposed.projection.pendingBatchIds.contains(batch.id)) {
        throw const EchoFailure('conflict', '变更没有完整且有效的因果依赖');
      }
      await tx.append(batch, object);
      await tx.replaceConflicts(proposed.projection.conflicts);
    });
    return batch.id;
  }

  Future<BatchId> renew(Subscription updated, Payment payment) async {
    final target = store;
    if (payment.subscriptionId != updated.id) invalidModel();
    final snapshot = await target.snapshot();
    final ref = EntityRef(updated.kind, updated.id);
    if (!snapshot.projection.entities.containsKey(ref)) invalidModel();
    final parents = snapshot.causal.parentsFor(ref);
    return _commitTo(target, [
      Mutation(ref, parents, updated),
      Mutation(EntityRef(payment.kind, payment.id), [], payment),
    ]);
  }

  Future<LedgerSnapshot> snapshot() => store.snapshot();
  Stream<LedgerProjection> watch() => store.watch();
}

// Constant-time equality is not required for comparing two local generated keys.
bool _equalBytes(List<int> a, List<int> b) =>
    a.length == b.length &&
    Iterable<int>.generate(a.length).every((i) => a[i] == b[i]);

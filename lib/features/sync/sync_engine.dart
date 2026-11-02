import '../../core/crypto/envelope_codec.dart';
import '../../core/crypto/ledger_keys.dart';
import '../../core/model/errors.dart';
import '../../storage/ledger_store.dart';

enum IngestResult { applied, duplicate, pending, conflict, quarantined }

/// The only transport-independent incoming boundary. Authentication precedes
/// every lookup or mutation of collision/quarantine state.
class SyncEngine {
  SyncEngine(this.store, this.keys, {EnvelopeCodec? codec})
    : codec = codec ?? EnvelopeCodec();
  final LedgerStore store;
  final LedgerKeys keys;
  final EnvelopeCodec codec;

  Future<IngestResult> ingest(StoredObject object) async {
    if (object.ledgerId != store.ledgerId || keys.ledgerId != store.ledgerId) {
      throw const EchoFailure('integrity', '同步对象属于其他账本');
    }
    final batch = await codec.open(object.bytes, keys);
    final verified = await StoredObject.fromBytes(batch, object.bytes);
    if (batch.ledgerId != store.ledgerId ||
        batch.id != object.batchId ||
        verified.sha256 != object.sha256) {
      throw const EchoFailure('integrity', '同步对象标识或摘要不匹配');
    }
    return store.transaction((tx) async {
      final before = await tx.snapshot();
      final objects = await store.objects();
      final existing = objects.where((o) => o.batchId == batch.id).firstOrNull;
      if (existing != null && !_sameBytes(existing.bytes, object.bytes)) {
        await tx.quarantine(
          before.batches.singleWhere((b) => b.id == batch.id),
          existing,
          QuarantineReason.idCollision,
        );
        await tx.quarantine(batch, object, QuarantineReason.idCollision);
      } else if (existing != null) {
        if (before.quarantinedBatchIds.contains(batch.id))
          return IngestResult.quarantined;
        return IngestResult.duplicate;
      } else {
        await tx.append(batch, object, pending: false, received: true);
      }
      var snapshot = await tx.snapshot();
      final invalid = snapshot.causal.quarantinedBatchIds;
      final currentObjects = {
        for (final o in await store.objects()) o.batchId: o,
      };
      for (final b in snapshot.batches.where((b) => invalid.contains(b.id))) {
        if (!snapshot.quarantinedObjects.any(
          (q) =>
              q.object.sha256 == currentObjects[b.id]!.sha256 &&
              q.batch.id == b.id,
        )) {
          await tx.quarantine(
            b,
            currentObjects[b.id]!,
            QuarantineReason.invalidCausality,
          );
        }
      }
      snapshot = await tx.snapshot();
      await tx.replaceConflicts(snapshot.projection.conflicts);
      if (snapshot.quarantinedBatchIds.contains(batch.id))
        return IngestResult.quarantined;
      if (snapshot.projection.pendingBatchIds.contains(batch.id))
        return IngestResult.pending;
      if (snapshot.projection.conflicts.any(
        (c) => c.competingBatchIds.contains(batch.id),
      ))
        return IngestResult.conflict;
      return IngestResult.applied;
    });
  }
}

bool _sameBytes(List<int> a, List<int> b) =>
    a.length == b.length &&
    Iterable<int>.generate(a.length).every((i) => a[i] == b[i]);

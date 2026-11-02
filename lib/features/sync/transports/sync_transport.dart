import '../../../core/crypto/ledger_metadata.dart';
import '../../../core/model/errors.dart';
import '../../../core/model/ids.dart';
import '../../../storage/ledger_store.dart';

class ObjectRef {
  const ObjectRef(this.batchId, this.sha256, this.relativePath);
  final BatchId batchId;
  final String sha256;

  /// Relative to the ledger root, always objects/<batchId>-<sha256>.bin.
  final String relativePath;
}

abstract interface class SyncTransport {
  Future<LedgerMetadata> readMetadata();
  Future<void> publishMetadata(LedgerMetadata metadata);
  Stream<ObjectRef> listObjects(CancellationToken token);
  Future<StoredObject> read(ObjectRef ref);
  Future<void> put(StoredObject object);
  Future<void> close();
}

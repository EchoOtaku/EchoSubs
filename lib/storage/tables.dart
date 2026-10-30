import 'package:drift/drift.dart';

class LedgerRecords extends Table {
  TextColumn get ledgerId => text()();
  BlobColumn get metadata => blob()();
  @override
  Set<Column> get primaryKey => {ledgerId};
}

class EntityVersions extends Table {
  TextColumn get ledgerId => text()();
  TextColumn get kind => text()();
  TextColumn get entityId => text()();
  TextColumn get batchId => text()();
  TextColumn get valueJson => text().nullable()();
  @override
  Set<Column> get primaryKey => {ledgerId, kind, entityId, batchId};
}

class ChangeBatches extends Table {
  TextColumn get ledgerId => text()();
  TextColumn get batchId => text()();
  TextColumn get body => text()();
  @override
  Set<Column> get primaryKey => {ledgerId, batchId};
}

class CipherObjects extends Table {
  TextColumn get ledgerId => text()();
  TextColumn get batchId => text()();
  TextColumn get sha256 => text()();
  TextColumn get nonce => text()();
  BlobColumn get bytes => blob()();
  @override
  Set<Column> get primaryKey => {ledgerId, batchId};
  @override
  List<Set<Column>> get uniqueKeys => [
    {ledgerId, nonce},
  ];
}

class PendingUploads extends Table {
  TextColumn get ledgerId => text()();
  TextColumn get batchId => text()();
  @override
  Set<Column> get primaryKey => {ledgerId, batchId};
}

class ReceivedBatches extends Table {
  TextColumn get ledgerId => text()();
  TextColumn get batchId => text()();
  @override
  Set<Column> get primaryKey => {ledgerId, batchId};
}

class StoredConflicts extends Table {
  TextColumn get ledgerId => text()();
  TextColumn get conflictId => text()();
  TextColumn get body => text()();
  @override
  Set<Column> get primaryKey => {ledgerId, conflictId};
}

class NotificationStates extends Table {
  TextColumn get ledgerId => text()();
  TextColumn get notificationId => text()();
  TextColumn get body => text()();
  @override
  Set<Column> get primaryKey => {ledgerId, notificationId};
}

/// Authenticated immutable candidates only. Reason is a fixed protocol code.
class QuarantinedObjects extends Table {
  TextColumn get ledgerId => text()();
  TextColumn get batchId => text()();
  TextColumn get sha256 => text()();
  BlobColumn get bytes => blob()();
  TextColumn get body => text()();
  TextColumn get reason => text()();
  @override
  Set<Column> get primaryKey => {ledgerId, batchId, sha256};
}

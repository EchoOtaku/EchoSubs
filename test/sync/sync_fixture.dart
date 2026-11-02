import 'dart:io';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:echo_subs/core/crypto/envelope_codec.dart';
import 'package:echo_subs/core/crypto/ledger_metadata.dart';
import 'package:echo_subs/core/model/change_batch.dart';
import 'package:echo_subs/core/model/civil_date.dart';
import 'package:echo_subs/core/model/ledger.dart';
import 'package:echo_subs/core/model/money.dart';
import 'package:echo_subs/core/model/payment.dart';
import 'package:echo_subs/core/model/subscription.dart';
import 'package:echo_subs/features/sync/sync_engine.dart';
import 'package:echo_subs/storage/app_database.dart';
import 'package:echo_subs/storage/ledger_store.dart';

String id(int n) => n.toRadixString(16).padLeft(32, '0');
final sRef = EntityRef(EntityKind.subscription, id(10));
final paRef = EntityRef(EntityKind.payment, id(11));
final pbRef = EntityRef(EntityKind.payment, id(12));
Subscription sub(String name) => Subscription(id: sRef.id, name: name);
Payment payment(EntityRef ref) => Payment(
  id: ref.id,
  subscriptionId: sRef.id,
  amount: Money('CNY', 1000, 2),
  paidOn: CivilDate(2026, 10, 30),
);
ChangeBatch batch(int n, List<Mutation> changes, {String? ledger}) =>
    ChangeBatch(
      id: id(n),
      ledgerId: ledger ?? id(1),
      deviceId: id(2),
      createdAtUtc: DateTime.utc(2026, 10, 30),
      mutations: changes,
    );
final base = batch(100, [Mutation(sRef, [], sub('base'))]);
final a = batch(101, [
  Mutation(sRef, [base.id], sub('A')),
]);
final b = batch(102, [
  Mutation(sRef, [base.id], sub('B')),
]);
final renewA = batch(103, [
  Mutation(sRef, [base.id], sub('A')),
  Mutation(paRef, [], payment(paRef)),
]);
final renewB = batch(104, [
  Mutation(sRef, [base.id], sub('B')),
  Mutation(pbRef, [], payment(pbRef)),
]);

class SyncFixture {
  SyncFixture(this.bundle, this.file, this.db, this.store);
  final LedgerBundle bundle;
  final File file;
  final AppDatabase db;
  final LedgerStore store;
  SyncEngine get engine => SyncEngine(store, bundle.keys);
  static Future<SyncFixture> create(
    LedgerBundle bundle, {
    StorageObserver? observer,
  }) async {
    // Each replica below owns a distinct file and QueryExecutor by construction.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final dir = await Directory.systemTemp.createTemp('echosubs-sync-');
    final file = File('${dir.path}/ledger.sqlite');
    final db = await AppDatabase.open(file);
    final store = LedgerStore(db, bundle.metadata.id, observer: observer);
    await store.transaction((tx) => tx.register(bundle.metadata));
    return SyncFixture(bundle, file, db, store);
  }

  Future<StoredObject> seal(ChangeBatch value) async => StoredObject.fromBytes(
    value,
    await EnvelopeCodec().seal(value, bundle.keys),
  );
  Future<LedgerProjection> projectInOrder(List<StoredObject> values) async {
    for (final value in [...values, ...values, ...values]) {
      await engine.ingest(value);
    }
    return (await store.snapshot()).projection;
  }

  Future<void> close() => db.close();
}

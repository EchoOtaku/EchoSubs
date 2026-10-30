import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:echo_subs/core/crypto/envelope_codec.dart';
import 'package:echo_subs/core/crypto/ledger_metadata.dart';
import 'package:echo_subs/core/model/change_batch.dart';
import 'package:echo_subs/core/model/errors.dart';
import 'package:echo_subs/core/model/ledger.dart';
import 'package:echo_subs/features/sync/materializer.dart';
import 'package:echo_subs/features/sync/sync_engine.dart';
import 'package:echo_subs/storage/app_database.dart';
import 'package:echo_subs/storage/ledger_store.dart';
import 'sync_fixture.dart';

void main() {
  test(
    'unverified, mislabeled, wrong digest and unknown version cannot quarantine a valid ID',
    () async {
      final f = await SyncFixture.create(await createLedgerBundle(id(1)));
      try {
        final original = await f.seal(base);
        await f.engine.ingest(original);
        final different = await f.seal(a);
        final map = decodeCryptoObject(original.bytes);
        final tag = cryptoBase64(map['tag']);
        tag[0] ^= 1;
        final tampered = canonicalBytes({...map, 'tag': base64Encode(tag)});
        final unknown = canonicalBytes({...map, 'version': 2});
        final inputs = [
          StoredObject(base.id, id(1), original.sha256, tampered),
          StoredObject(base.id, id(1), different.sha256, different.bytes),
          StoredObject(base.id, id(1), '0' * 64, original.bytes),
          await StoredObject.fromBytes(base, unknown),
        ];
        for (final object in inputs) {
          await expectLater(
            f.engine.ingest(object),
            throwsA(isA<EchoFailure>()),
          );
          expect((await f.store.snapshot()).projection.entities, {
            sRef: sub('base'),
          });
          expect(await f.store.quarantinedObjects(), isEmpty);
        }
        expect(await f.store.receivedBatchIds(), {base.id});
      } finally {
        await f.close();
      }
    },
  );
  test(
    'same-ID different refs retain both authenticated candidates and taint descendants after restart',
    () async {
      final f = await SyncFixture.create(await createLedgerBundle(id(1)));
      final otherRef = EntityRef(EntityKind.category, id(21));
      final fork = batch(100, [
        Mutation(otherRef, [], Category(otherRef.id, 'fork')),
      ]);
      final original = await f.seal(base);
      final competing = await f.seal(fork);
      try {
        await f.engine.ingest(original);
        await f.engine.ingest(await f.seal(a));
        expect(await f.engine.ingest(competing), IngestResult.quarantined);
        final q = await f.store.quarantinedObjects();
        expect(q.where((q) => q.batch.id == base.id), hasLength(2));
        for (final candidate in q) {
          expect(
            await EnvelopeCodec().open(candidate.object.bytes, f.bundle.keys),
            candidate.batch,
          );
          expect(
            (await StoredObject.fromBytes(
              candidate.batch,
              candidate.object.bytes,
            )).sha256,
            candidate.object.sha256,
          );
        }
      } finally {
        await f.close();
      }
      final reopened = await AppDatabase.open(f.file);
      try {
        final store = LedgerStore(reopened, id(1));
        final state = await store.snapshot();
        expect(state.projection.entities, isEmpty);
        expect(state.projection.pendingBatchIds, isEmpty);
        expect(state.quarantinedBatchIds, containsAll([base.id, a.id]));
        expect(state.causal.unsafeRefs, containsAll([sRef, otherRef]));
        expect(state.causal.heads, isEmpty);
        expect(
          await SyncEngine(store, f.bundle.keys).ingest(original),
          IngestResult.quarantined,
        );
        expect(
          await SyncEngine(store, f.bundle.keys).ingest(competing),
          IngestResult.quarantined,
        );
        expect(
          (await store.quarantinedObjects()).where(
            (q) => q.batch.id == base.id,
          ),
          hasLength(2),
        );
      } finally {
        await reopened.close();
      }
    },
  );
  for (final checkpoint in StorageCheckpoint.values) {
    test('incoming atomic rollback and crash replay at $checkpoint', () async {
      var fail = false;
      final f = await SyncFixture.create(
        await createLedgerBundle(id(1)),
        observer: (point) async {
          if (fail && point == checkpoint) throw StateError('simulated crash');
        },
      );
      final object = await f.seal(renewA);
      try {
        await f.engine.ingest(await f.seal(base));
        fail = true;
        await expectLater(f.engine.ingest(object), throwsStateError);
        expect((await f.store.snapshot()).projection.entities, {
          sRef: sub('base'),
        });
        expect((await f.store.objects()).map((o) => o.batchId), [base.id]);
        expect(await f.store.receivedBatchIds(), {base.id});
      } finally {
        await f.close();
      }
      final db = await AppDatabase.open(f.file);
      try {
        final store = LedgerStore(db, id(1));
        final engine = SyncEngine(store, f.bundle.keys);
        expect(await engine.ingest(object), IngestResult.applied);
        expect(await engine.ingest(object), IngestResult.duplicate);
        expect((await store.snapshot()).projection.entities, {
          sRef: sub('A'),
          paRef: payment(paRef),
        });
        expect(
          (await store.objects())
              .singleWhere((o) => o.batchId == renewA.id)
              .bytes,
          object.bytes,
        );
      } finally {
        await db.close();
      }
    });
  }
  test(
    'collision evidence and removal roll back atomically before retry',
    () async {
      var fail = false;
      final f = await SyncFixture.create(
        await createLedgerBundle(id(1)),
        observer: (point) async {
          if (fail && point == StorageCheckpoint.beforeSyncState)
            throw StateError('simulated crash');
        },
      );
      try {
        await f.engine.ingest(await f.seal(base));
        final fork = await f.seal(
          batch(100, [Mutation(sRef, [], sub('fork'))]),
        );
        fail = true;
        await expectLater(f.engine.ingest(fork), throwsStateError);
        expect(await f.store.quarantinedObjects(), isEmpty);
        expect((await f.store.snapshot()).projection.entities, {
          sRef: sub('base'),
        });
        fail = false;
        expect(await f.engine.ingest(fork), IngestResult.quarantined);
        expect((await f.store.snapshot()).projection.entities, isEmpty);
      } finally {
        await f.close();
      }
    },
  );
  test(
    'missing and malformed parents, cycles and invalid descendants are separate states',
    () {
      final p = batch(130, [
        Mutation(sRef, [id(131)], sub('cycle')),
      ]);
      final q = batch(131, [
        Mutation(sRef, [p.id], sub('cycle')),
      ]);
      final missing = batch(132, [
        Mutation(sRef, [id(999)], sub('missing')),
      ]);
      final wrong = batch(133, [
        Mutation(paRef, [base.id], payment(paRef)),
      ]);
      final downstream = batch(134, [
        Mutation(paRef, [wrong.id], payment(paRef)),
      ]);
      final state = analyzeBatches([base, p, q, missing, wrong, downstream]);
      expect(state.quarantinedBatchIds, {p.id, q.id, wrong.id, downstream.id});
      expect(state.projection.pendingBatchIds, [missing.id]);
      expect(state.projection.entities, {sRef: sub('base')});
      expect(state.heads[sRef], {base.id});
      expect(state.heads[paRef], isNull);
    },
  );
  for (final interrupt in [true, false]) {
    test(
      'schema2 to schema3 interruption=$interrupt retains original ciphertext',
      () async {
        final f = await SyncFixture.create(await createLedgerBundle(id(1)));
        final object = await f.seal(base);
        await f.engine.ingest(object);
        await f.db.customStatement('DROP TABLE quarantined_objects');
        await f.db.customStatement('PRAGMA user_version = 2');
        await f.close();
        if (interrupt) {
          await expectLater(
            AppDatabase.open(
              f.file,
              migrationCheckpoint: () async => throw StateError('crash'),
            ),
            throwsStateError,
          );
          expect((await f.file.readAsBytes())[63], 2);
        }
        final db = await AppDatabase.open(f.file);
        try {
          expect(
            (await db.customSelect('PRAGMA user_version').getSingle())
                .read<int>('user_version'),
            3,
          );
          expect(
            (await LedgerStore(db, id(1)).objects()).single.bytes,
            object.bytes,
          );
          expect(await LedgerStore(db, id(1)).quarantinedObjects(), isEmpty);
        } finally {
          await db.close();
        }
      },
    );
  }
}

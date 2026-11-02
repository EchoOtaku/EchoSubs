import 'package:flutter_test/flutter_test.dart';
import 'package:echo_subs/app/services.dart';
import 'package:echo_subs/core/crypto/key_vault.dart';
import 'package:echo_subs/core/crypto/ledger_metadata.dart';
import 'package:echo_subs/core/model/change_batch.dart';
import 'package:echo_subs/core/model/errors.dart';
import 'package:echo_subs/core/model/ledger.dart';
import 'package:echo_subs/features/ledger/ledger_repository.dart';
import 'package:echo_subs/features/sync/materializer.dart';
import 'package:echo_subs/features/sync/sync_engine.dart';
import '../support/ledger_harness.dart';
import 'sync_fixture.dart';

final completeResolution = batch(110, [
  Mutation(sRef, [renewA.id, renewB.id], sub('resolved')),
  Mutation(paRef, [renewA.id], payment(paRef)),
  Mutation(pbRef, [renewB.id], null),
]);

void main() {
  test(
    'subscription-only incoming resolution is quarantined and never releases payments',
    () async {
      final f = await SyncFixture.create(await createLedgerBundle(id(1)));
      try {
        final partial = batch(109, [
          Mutation(sRef, [renewA.id, renewB.id], sub('partial')),
        ]);
        await f.projectInOrder(
          await Future.wait([base, renewA, renewB].map(f.seal)),
        );
        expect(
          await f.engine.ingest(await f.seal(partial)),
          IngestResult.quarantined,
        );
        final state = await f.store.snapshot();
        expect(state.projection.entities, {sRef: sub('base')});
        expect(
          state.projection.conflicts.single.affectedRefs,
          containsAll([sRef, paRef, pbRef]),
        );
        expect(state.quarantinedBatchIds, contains(partial.id));
        expect(state.projection.pendingBatchIds, isEmpty);
      } finally {
        await f.close();
      }
    },
  );
  test(
    'explicit full component resolution confirms one payment and a tombstone',
    () {
      final p = materialize({base, renewA, renewB, completeResolution});
      expect(p.conflicts, isEmpty);
      expect(p.entities, {sRef: sub('resolved'), paRef: payment(paRef)});
    },
  );
  test(
    'future unseen child creates new conflict in either arrival order',
    () async {
      final bundle = await createLedgerBundle(id(1));
      final fs = await Future.wait(
        List.generate(3, (_) => SyncFixture.create(bundle)),
      );
      final child = batch(111, [
        Mutation(sRef, [renewA.id], sub('unseen')),
        Mutation(paRef, [renewA.id], payment(paRef)),
      ]);
      try {
        final objects = await Future.wait(
          [base, renewA, renewB, completeResolution, child].map(fs.first.seal),
        );
        final ps = await Future.wait([
          fs[0].projectInOrder(objects),
          fs[1].projectInOrder(objects.reversed.toList()),
          fs[2].projectInOrder([
            objects[4],
            objects[2],
            objects[0],
            objects[3],
            objects[1],
          ]),
        ]);
        expect(ps[0], ps[1]);
        expect(ps[1], ps[2]);
        expect(ps.first.conflicts, hasLength(1));
        expect(ps.first.entities, {sRef: sub('base')});
        for (final f in fs) {
          expect((await f.store.snapshot()).quarantinedBatchIds, isEmpty);
        }
      } finally {
        for (final f in fs) {
          await f.close();
        }
      }
    },
  );
  test(
    'multi-entity descendants propagate conflict and require complete closure',
    () {
      final cRef = EntityRef(EntityKind.category, id(20));
      final d = batch(112, [
        Mutation(paRef, [renewA.id], payment(paRef)),
        Mutation(cRef, [], Category(cRef.id, 'dependent')),
      ]);
      final e = batch(113, [
        Mutation(cRef, [d.id], Category(cRef.id, 'later')),
      ]);
      final state = analyzeBatches([base, renewA, renewB, d, e]);
      expect(state.projection.entities, {sRef: sub('base')});
      expect(
        state.projection.conflicts.single.competingBatchIds,
        containsAll([renewA.id, renewB.id, d.id, e.id]),
      );
      expect(
        state.projection.conflicts.single.affectedRefs,
        containsAll([sRef, paRef, pbRef, cRef]),
      );
      final partial = batch(114, [
        Mutation(sRef, [renewA.id, renewB.id], sub('bad')),
        Mutation(paRef, [d.id], payment(paRef)),
        Mutation(pbRef, [renewB.id], null),
      ]);
      expect(
        analyzeBatches([
          base,
          renewA,
          renewB,
          d,
          e,
          partial,
        ]).quarantinedBatchIds,
        contains(partial.id),
      );
      final fixed = batch(115, [
        Mutation(sRef, [renewA.id, renewB.id], sub('good')),
        Mutation(paRef, [d.id], payment(paRef)),
        Mutation(pbRef, [renewB.id], null),
        Mutation(cRef, [e.id], null),
      ]);
      expect(materialize({base, renewA, renewB, d, e, fixed}).entities, {
        sRef: sub('good'),
        paRef: payment(paRef),
      });
      expect(
        materialize({base, renewA, renewB, d, e, fixed}).conflicts,
        isEmpty,
      );
    },
  );
  test(
    'ordinary forms and renewal refuse conflicts; resolve checks stale/full parents with key proof',
    () async {
      final f = await SyncFixture.create(await createLedgerBundle(id(1)));
      try {
        await f.projectInOrder(
          await Future.wait([base, renewA, renewB].map(f.seal)),
        );
        final vault = KeyVault(storage: MemoryVault());
        await vault.put(
          LedgerRepository.rootKeyName(id(1)),
          f.bundle.keys.rootKey,
        );
        final repo = LedgerRepository(f.db, vault, id(2));
        await repo.selectLedger(id(1));
        final state = await f.store.snapshot();
        expect(
          () => AppServices.heads(state, sRef),
          throwsA(isA<EchoFailure>()),
        );
        await expectLater(
          repo.commit([
            Mutation(sRef, [renewA.id, renewB.id], sub('ordinary')),
          ]),
          throwsA(isA<EchoFailure>()),
        );
        await expectLater(
          repo.renew(
            sub('ordinary'),
            payment(EntityRef(EntityKind.payment, id(90))),
          ),
          throwsA(isA<EchoFailure>()),
        );
        final conflict = state.projection.conflicts.single;
        await expectLater(
          repo.resolve(conflict, [
            Mutation(sRef, [renewA.id, renewB.id], sub('partial')),
          ]),
          throwsA(isA<EchoFailure>()),
        );
        final rid = await repo.resolve(conflict, completeResolution.mutations);
        final resolved = await repo.snapshot();
        expect(resolved.projection.entities, {
          sRef: sub('resolved'),
          paRef: payment(paRef),
        });
        expect(resolved.projection.conflicts, isEmpty);
        expect(resolved.pendingUploadIds, contains(rid));
        expect(resolved.projection.pendingBatchIds, isEmpty);
        await expectLater(
          repo.resolve(conflict, completeResolution.mutations),
          throwsA(isA<EchoFailure>()),
        );
      } finally {
        await f.close();
      }
    },
  );
  test('divergent ancestor before branch head is not partially confirmed', () {
    final child = batch(116, [
      Mutation(sRef, [a.id], sub('A2')),
    ]);
    expect(materialize({base, a, b, child}).entities, {sRef: sub('base')});
  });
}

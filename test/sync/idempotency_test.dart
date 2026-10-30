import 'package:flutter_test/flutter_test.dart';
import 'package:echo_subs/core/crypto/ledger_metadata.dart';
import 'package:echo_subs/core/model/change_batch.dart';
import 'package:echo_subs/features/sync/sync_engine.dart';
import 'sync_fixture.dart';

void main() {
  test(
    'authenticated replay is idempotent and same-ID forks quarantine both orders',
    () async {
      final bundle = await createLedgerBundle(id(1));
      final replicas = await Future.wait(
        List.generate(3, (_) => SyncFixture.create(bundle)),
      );
      try {
        final object = await replicas.first.seal(base);
        expect(
          await replicas.first.engine.ingest(object),
          IngestResult.applied,
        );
        expect(
          await replicas.first.engine.ingest(object),
          IngestResult.duplicate,
        );
        final fork = await replicas.first.seal(
          batch(100, [Mutation(sRef, [], sub('fork'))]),
        );
        final left = await replicas[0].projectInOrder([object, fork]);
        final right = await replicas[1].projectInOrder([fork, object]);
        final third = await replicas[2].projectInOrder([object, fork, object]);
        expect(left, right);
        expect(right, third);
        expect(left.entities, isEmpty);
        expect(
          (await replicas.first.store.snapshot()).quarantinedBatchIds,
          contains(base.id),
        );
      } finally {
        for (final f in replicas) {
          await f.close();
        }
      }
    },
  );
  test('cross-ledger data is rejected without registering receipt', () async {
    final f = await SyncFixture.create(await createLedgerBundle(id(1)));
    final foreign = await SyncFixture.create(await createLedgerBundle(id(99)));
    try {
      final object = await foreign.seal(
        batch(100, [Mutation(sRef, [], sub('foreign'))], ledger: id(99)),
      );
      await expectLater(f.engine.ingest(object), throwsA(isA<Exception>()));
      expect(await f.store.receivedBatchIds(), isEmpty);
      expect((await f.store.snapshot()).batches, isEmpty);
    } finally {
      await f.close();
      await foreign.close();
    }
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:echo_subs/core/crypto/ledger_metadata.dart';
import 'package:echo_subs/features/sync/sync_engine.dart';
import 'sync_fixture.dart';

void main() {
  test(
    'child waits for parent and transport outbox is not causal pending',
    () async {
      final f = await SyncFixture.create(await createLedgerBundle(id(1)));
      try {
        expect(await f.engine.ingest(await f.seal(a)), IngestResult.pending);
        expect((await f.store.snapshot()).projection.pendingBatchIds, [a.id]);
        expect((await f.store.snapshot()).projection.entities, isEmpty);
        await f.engine.ingest(await f.seal(base));
        final p = (await f.store.snapshot()).projection;
        expect(p.pendingBatchIds, isEmpty);
        expect(p.entities[sRef], sub('A'));
      } finally {
        await f.close();
      }
    },
  );
}

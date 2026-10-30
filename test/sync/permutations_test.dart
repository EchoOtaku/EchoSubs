import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:echo_subs/core/crypto/ledger_metadata.dart';
import 'package:echo_subs/core/model/change_batch.dart';
import 'package:echo_subs/core/model/ledger.dart';
import 'package:echo_subs/features/sync/materializer.dart';
import 'resolution_test.dart' show completeResolution;
import 'sync_fixture.dart';

void main() {
  for (var seed = 0; seed < 100; seed++) {
    test('three isolated replicas reorder and replay seed $seed', () async {
      final bundle = await createLedgerBundle(id(1));
      final fs = await Future.wait(
        List.generate(3, (_) => SyncFixture.create(bundle)),
      );
      try {
        final cRef = EntityRef(EntityKind.category, id(20));
        final independent = batch(120, [
          Mutation(cRef, [], Category(cRef.id, 'independent')),
        ]);
        final future = batch(121, [
          Mutation(sRef, [renewA.id], sub('future')),
        ]);
        final history = [
          base,
          renewA,
          renewB,
          independent,
          if (seed.isEven) completeResolution,
          if (seed % 3 == 0) future,
        ];
        final objects = await Future.wait(history.map(fs.first.seal));
        final ps = <LedgerProjection>[];
        for (var replica = 0; replica < 3; replica++) {
          final order = [...objects, ...objects.take(2)]
            ..shuffle(Random(seed * 3 + replica));
          ps.add(await fs[replica].projectInOrder(order));
        }
        expect(ps[0], ps[1]);
        expect(ps[1], ps[2]);
        expect(ps[0], materialize(history.toSet()));
        expect(ps[0].pendingBatchIds, isEmpty);
        expect(ps[0].entities[cRef], Category(cRef.id, 'independent'));
        if (seed.isEven && seed % 3 != 0) {
          expect(ps[0].conflicts, isEmpty);
          expect(ps[0].entities[paRef], payment(paRef));
          expect(ps[0].entities.containsKey(pbRef), isFalse);
        } else {
          expect(ps[0].conflicts, isNotEmpty);
          expect(ps[0].entities[sRef], sub('base'));
          expect(ps[0].entities.containsKey(paRef), isFalse);
          expect(ps[0].entities.containsKey(pbRef), isFalse);
        }
      } finally {
        for (final f in fs) {
          await f.close();
        }
      }
    });
  }
}

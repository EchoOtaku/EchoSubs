import 'package:flutter_test/flutter_test.dart';
import 'package:echo_subs/core/crypto/ledger_metadata.dart';
import 'package:echo_subs/core/model/change_batch.dart';
import 'package:echo_subs/core/model/payment.dart';
import 'package:echo_subs/core/model/subscription.dart';
import 'package:echo_subs/features/ledger/cost_projection.dart';
import 'sync_fixture.dart';

void main() {
  for (final pair in [
    [a, b],
    [
      batch(105, [
        Mutation(sRef, [base.id], null),
      ]),
      b,
    ],
    [renewA, renewB],
  ]) {
    test('atomic conflict converges for ${pair.first.id}', () async {
      final bundle = await createLedgerBundle(id(1));
      final replicas = await Future.wait(
        List.generate(3, (_) => SyncFixture.create(bundle)),
      );
      try {
        final root = await replicas.first.seal(base);
        final x = await replicas.first.seal(pair[0]);
        final y = await replicas.first.seal(pair[1]);
        final projections = await Future.wait([
          replicas[0].projectInOrder([root, x, y]),
          replicas[1].projectInOrder([y, x, root]),
          replicas[2].projectInOrder([x, root, y, x]),
        ]);
        expect(projections[0], projections[1]);
        expect(projections[1], projections[2]);
        final p = projections.first;
        expect(p.conflicts, hasLength(1));
        expect(p.entities[sRef], sub('base'));
        expect(
          summarizeCosts(
            p.entities.values.whereType<Subscription>().toList(),
            p.entities.values.whereType<Payment>().toList(),
          ).actualPaid,
          isEmpty,
        );
      } finally {
        for (final f in replicas) {
          await f.close();
        }
      }
    });
  }
}

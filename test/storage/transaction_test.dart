import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:echo_subs/storage/app_database.dart';
import 'package:echo_subs/core/model/ledger.dart';
import 'package:echo_subs/core/model/change_batch.dart';
import 'package:echo_subs/core/crypto/envelope_codec.dart';
import 'package:echo_subs/core/crypto/ledger_metadata.dart';
import 'package:echo_subs/core/model/ids.dart';
import 'package:echo_subs/core/model/errors.dart';
import 'package:echo_subs/features/ledger/ledger_repository.dart';
import 'package:echo_subs/storage/ledger_store.dart';
import '../ledger/repository_test.dart' as fixtures;

void main() {
  test(
    'failed ledger registration never activates an editable ledger',
    () async {
      final f = fixtures.Fixture();
      await f.init();
      try {
        final bundle = await createLedgerBundle(newId());
        final repo = LedgerRepository(
          f.db,
          f.vault,
          f.device,
          observer: (_) async => throw StateError('injected'),
        );
        await repo.selectLedger(f.id);
        await expectLater(
          repo.create(LedgerConfig(bundle.metadata.id, 'UTC'), bundle),
          throwsStateError,
        );
        expect(repo.currentLedgerId, f.id);
        expect(await repo.listLedgers(), [f.id]);
        expect(
          await f.vault.get(LedgerRepository.rootKeyName(bundle.metadata.id)),
          bundle.keys.rootKey,
        );
        expect((await f.db.select(f.db.changeBatches).get()).length, 2);
      } finally {
        await f.dispose();
      }
    },
  );
  test('duplicate nonce rolls back all candidate versions', () async {
    final f = fixtures.Fixture();
    await f.init();
    try {
      final batch = ChangeBatch(
        id: newId(),
        ledgerId: f.id,
        deviceId: f.device,
        createdAtUtc: DateTime.now().toUtc(),
        mutations: [
          Mutation(EntityRef(EntityKind.category, newId()), [], null),
        ],
      );
      final bytes = await EnvelopeCodec().seal(batch, f.bundle.keys);
      final envelope = decodeCryptoObject(bytes);
      final existing = decodeCryptoObject(
        (await f.repo.store.objects()).first.bytes,
      );
      envelope['nonce'] = existing['nonce'];
      final object = await StoredObject.fromBytes(
        batch,
        Uint8List.fromList(utf8.encode(canonicalJson(envelope))),
      );
      await expectLater(
        f.repo.store.transaction((tx) => tx.append(batch, object)),
        throwsA(isA<Exception>()),
      );
      expect((await f.repo.snapshot()).batches.length, 2);
      expect((await f.db.select(f.db.entityVersions).get()).length, 3);
    } finally {
      await f.dispose();
    }
  });
  test(
    'closed transaction cannot write and pending acknowledgement notifies watch',
    () async {
      final f = fixtures.Fixture();
      await f.init();
      try {
        late LedgerTransaction escaped;
        await f.repo.store.transaction((tx) async {
          escaped = tx;
        });
        await expectLater(
          escaped.markReceived(f.originalBatch),
          throwsA(isA<EchoFailure>()),
        );
        final events = <LedgerProjection>[];
        final stream = f.repo.watch().listen(events.add);
        await Future<void>.delayed(const Duration(milliseconds: 30));
        await f.repo.store.transaction((tx) async {
          await tx.acknowledge(f.originalBatch);
          await tx.markReceived(f.originalBatch);
          await tx.putNotificationState('test', 'scheduled');
        });
        for (
          var n = 0;
          n < 50 &&
              events.every((p) => p.pendingBatchIds.contains(f.originalBatch));
          n++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        await stream.cancel();
        expect(events.last.pendingBatchIds, isNot(contains(f.originalBatch)));
        expect(await f.repo.store.receivedBatchIds(), {f.originalBatch});
        expect(await f.repo.store.notificationStates(), {'test': 'scheduled'});
      } finally {
        await f.dispose();
      }
    },
  );
  for (final checkpoint in StorageCheckpoint.values) {
    test('renewal rollback at $checkpoint survives reopening', () async {
      final f = fixtures.Fixture();
      await f.init();
      try {
        final repo = LedgerRepository(
          f.db,
          f.vault,
          f.device,
          observer: (point) async {
            if (point == checkpoint) throw StateError('injected');
          },
        );
        await repo.selectLedger(f.id);
        await expectLater(
          repo.renew(f.subscription(endMonth: 2), f.payment()),
          throwsStateError,
        );
        await f.db.close();
        f.db = await AppDatabase.open(f.file);
        f.repo = LedgerRepository(f.db, f.vault, f.device);
        await f.repo.selectLedger(f.id);
        final s = await f.repo.snapshot();
        expect(s.batches.length, 2);
        expect(
          s.projection.entities.values.where(
            (e) => e.kind == EntityKind.payment,
          ),
          isEmpty,
        );
        expect(
          s.projection.entities[EntityRef(
            EntityKind.subscription,
            f.subscriptionId,
          )],
          f.subscription(),
        );
        expect((await f.repo.store.objects()).length, 2);
        expect(s.pendingBatchIds.length, 2);
        final payments = await f.db
            .customSelect(
              "SELECT COUNT(*) AS n FROM entity_versions WHERE kind='payment'",
            )
            .getSingle();
        expect(payments.read<int>('n'), 0);
      } finally {
        await f.dispose();
      }
    });
  }
  test(
    'acknowledgement rollback leaves original immutable object and pending state',
    () async {
      final f = fixtures.Fixture();
      await f.init();
      try {
        final object = (await f.repo.store.objects()).first;
        final store = LedgerStore(
          f.db,
          f.id,
          observer: (_) async => throw StateError('injected'),
        );
        await expectLater(
          store.transaction((tx) => tx.acknowledge(object.batchId)),
          throwsStateError,
        );
        expect(
          (await f.repo.snapshot()).pendingBatchIds,
          contains(object.batchId),
        );
        await f.repo.store.transaction((tx) => tx.acknowledge(object.batchId));
        expect(
          (await f.repo.snapshot()).pendingBatchIds,
          isNot(contains(object.batchId)),
        );
        expect((await f.repo.store.objects()).first.bytes, object.bytes);
      } finally {
        await f.dispose();
      }
    },
  );
  test('real SQLite database reopens and rejects future schemas', () async {
    final dir = await Directory.systemTemp.createTemp('echosubs-storage-');
    final file = File('${dir.path}/test.sqlite');
    try {
      final db = await AppDatabase.open(file);
      expect(
        await db
            .customSelect('PRAGMA user_version')
            .getSingle()
            .then((r) => r.read<int>('user_version')),
        2,
      );
      await db.close();
      final reopened = await AppDatabase.open(file);
      await reopened.customStatement('PRAGMA user_version = 999');
      await reopened.close();
      final before = await file.readAsBytes();
      await expectLater(AppDatabase.open(file), throwsA(isA<Exception>()));
      expect(await file.readAsBytes(), before);
    } finally {
      await dir.delete(recursive: true);
    }
  });
}

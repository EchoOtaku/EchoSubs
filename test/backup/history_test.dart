import 'dart:convert';
import 'dart:typed_data';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:echo_subs/core/crypto/envelope_codec.dart';
import 'package:echo_subs/core/crypto/key_vault.dart';
import 'package:echo_subs/core/model/change_batch.dart';
import 'package:echo_subs/core/model/ids.dart';
import 'package:echo_subs/core/model/ledger.dart';
import 'package:echo_subs/core/model/errors.dart';
import 'package:echo_subs/core/model/payment.dart';
import 'package:echo_subs/core/model/subscription.dart';
import 'package:echo_subs/features/backup/backup_format.dart';
import 'package:echo_subs/features/backup/backup_service.dart';
import 'package:echo_subs/features/ledger/ledger_repository.dart';
import 'package:echo_subs/features/sync/sync_engine.dart';
import 'package:echo_subs/storage/ledger_store.dart';
import '../support/ledger_harness.dart';
import '../sync/sync_fixture.dart' as f;

class FailingVault implements VaultStorage {
  @override
  Future<String?> read(String name) async => null;
  @override
  Future<void> write(String name, String value) async =>
      throw StateError('fictional vault failure');
}

Future<void> ingest(LedgerHarness h, ChangeBatch b) async {
  final keys = await h.repo.authenticatedKeys();
  final translated = ChangeBatch(
    id: b.id,
    ledgerId: keys.ledgerId,
    deviceId: b.deviceId,
    createdAtUtc: b.createdAtUtc,
    mutations: b.mutations,
  );
  await SyncEngine(h.repo.store, keys).ingest(
    await StoredObject.fromBytes(
      translated,
      await EnvelopeCodec().seal(translated, keys),
    ),
  );
}

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  test(
    'renewal disputes, dependent history, collision variants and unchanged original survive restoration',
    () async {
      final h = await LedgerHarness.create();
      try {
        for (final b in [f.base, f.renewA, f.renewB]) {
          await ingest(h, b);
        }
        final qref = EntityRef(EntityKind.category, f.id(33));
        await ingest(
          h,
          f.batch(300, [Mutation(qref, [], Category(qref.id, '中文分类甲'))]),
        );
        await ingest(
          h,
          f.batch(300, [Mutation(qref, [], Category(qref.id, '中文分类乙'))]),
        );
        await ingest(
          h,
          f.batch(301, [
            Mutation(qref, [f.id(300)], Category(qref.id, '隔离依赖')),
          ]),
        );
        final before = await h.repo.snapshot();
        final originalObjects = [
          ...await h.repo.store.objects(),
          ...before.quarantinedObjects.map((q) => q.object),
        ].map((o) => o.sha256).toSet();
        expect(before.projection.conflicts, hasLength(1));
        expect(before.projection.entities.values.whereType<Payment>(), isEmpty);
        final service = BackupService(h.repo);
        final recovery = (await service.recoveryFor(h.repo.currentLedgerId!))!;
        final bytes = await service.exportEncrypted();
        final preview = await service.inspect(bytes, recovery);
        expect(preview.paymentVersionCount, 2);
        expect(preview.conflictCount, 1);
        expect(preview.quarantinedBatchCount, 2);
        final restored = await service.restoreAsNew(preview);
        final store = LedgerStore(h.db, restored);
        final after = await store.snapshot();
        expect(after.projection.conflicts, hasLength(1));
        expect(after.projection.entities.values.whereType<Payment>(), isEmpty);
        expect(
          after.batches
              .expand((b) => b.mutations)
              .where((m) => m.value is Payment),
          hasLength(2),
        );
        final payments = after.batches
            .expand((b) => b.mutations)
            .map((m) => m.value)
            .whereType<Payment>()
            .toList();
        expect(
          payments.every(
            (p) =>
                p.amount == f.payment(f.paRef).amount &&
                p.paidOn == f.payment(f.paRef).paidOn,
          ),
          true,
        );
        expect(
          payments.map((p) => p.id).toSet().intersection({
            f.paRef.id,
            f.pbRef.id,
          }),
          isEmpty,
        );
        expect(after.quarantinedBatchIds, hasLength(2));
        expect(
          after.quarantinedObjects.where(
            (q) => q.batch.mutations.any(
              (m) =>
                  m.value is Category &&
                  (m.value as Category).name.startsWith('中文'),
            ),
          ),
          hasLength(2),
        );
        final newObjects = [
          ...await store.objects(),
          ...after.quarantinedObjects.map((q) => q.object),
        ];
        expect(
          newObjects.any((o) => originalObjects.contains(o.sha256)),
          false,
        );
        for (final o in newObjects) {
          expect(
            (await EnvelopeCodec().open(
              o.bytes,
              await h.repo.authenticatedKeys(restored),
            )).ledgerId,
            restored,
          );
        }
        expect((await h.repo.snapshot()).batches, before.batches);
        expect((await h.repo.snapshot()).projection, before.projection);
        expect(
          (await h.repo.store.objects()).every(
            (o) => originalObjects.contains(o.sha256),
          ),
          true,
        );
      } finally {
        await h.close();
      }
    },
  );
  test(
    'same plaintext different ciphertext collision remains a collision',
    () async {
      final h = await LedgerHarness.create();
      try {
        await ingest(h, f.base);
        await ingest(h, f.base);
        final s = BackupService(h.repo);
        final p = await s.inspect(
          await s.exportEncrypted(),
          (await s.recoveryFor(h.repo.currentLedgerId!))!,
        );
        expect(p.quarantinedBatchCount, 1);
        final id = await s.restoreAsNew(p);
        expect(
          (await LedgerStore(h.db, id).quarantinedObjects()).where(
            (q) => q.batch.mutations.any((m) => m.value is Subscription),
          ),
          hasLength(2),
        );
      } finally {
        await h.close();
      }
    },
  );
  test(
    'root-only paired device exports original metadata and missing causal history blocks export',
    () async {
      final h = await LedgerHarness.create();
      try {
        final s = BackupService(h.repo), oldId = h.repo.currentLedgerId!;
        final recovery = (await s.recoveryFor(oldId))!;
        final keys = await h.repo.authenticatedKeys();
        final onlyRoot = KeyVault(storage: MemoryVault());
        await onlyRoot.put(LedgerRepository.rootKeyName(oldId), keys.rootKey);
        final paired = LedgerRepository(h.db, onlyRoot, newId());
        await paired.selectLedger(oldId);
        final exporter = BackupService(paired);
        expect(await exporter.recoveryFor(oldId), isNull);
        expect(
          (await exporter.inspect(
            await exporter.exportEncrypted(),
            recovery,
          )).batchCount,
          1,
        );
        expect(
          await onlyRoot.get(LedgerRepository.recoveryKeyName(oldId)),
          isNull,
        );
        await ingest(h, f.a); // missing f.base
        await expectLater(
          s.exportEncrypted(),
          throwsA(isA<EchoFailure>().having((e) => e.code, 'code', 'conflict')),
        );
        await expectLater(
          s.exportPlain(confirmed: true),
          throwsA(isA<EchoFailure>()),
        );
      } finally {
        await h.close();
      }
    },
  );
  test(
    'vault failure rolls back only new registration, original archive and selected ledger survive',
    () async {
      final h = await LedgerHarness.create();
      try {
        final original = await h.repo.snapshot();
        final normal = BackupService(h.repo);
        final failing = BackupService(
          LedgerRepository(h.db, KeyVault(storage: FailingVault()), newId()),
        );
        final p = await failing.inspect(
          await normal.exportEncrypted(),
          (await normal.recoveryFor(original.metadata.id))!,
        );
        await expectLater(failing.restoreAsNew(p), throwsA(isA<EchoFailure>()));
        expect(await h.repo.listLedgers(), [original.metadata.id]);
        expect(h.repo.currentLedgerId, original.metadata.id);
        expect((await h.repo.snapshot()).projection, original.projection);
        expect((await normal.recoveryFor(original.metadata.id)), isNotNull);
      } finally {
        await h.close();
      }
    },
  );
  test(
    'strict parser bounds stay separate and aggregate exceeds 1MiB without relaxing sync',
    () async {
      final large = canonicalBytes({'payload': 'x' * maxCryptoObjectBytes});
      expect(() => decodeCryptoObject(large), throwsA(isA<EchoFailure>()));
      expect(
        () => decodeBoundedCryptoObject(large, maxBytes: 0),
        throwsA(isA<EchoFailure>()),
      );
      expect(
        decodeBoundedCryptoObject(large, maxBytes: maxBackupBytes)['payload'],
        hasLength(maxCryptoObjectBytes),
      );
      for (final malformed in [
        utf8.encode('{"a":1,"a":1}'),
        [0xff],
        utf8.encode('{"a":"\\ud800"}'),
      ]) {
        expect(
          () => decodeBoundedCryptoObject(
            Uint8List.fromList(malformed),
            maxBytes: maxBackupBytes,
          ),
          throwsA(isA<EchoFailure>()),
        );
      }
      final h = await LedgerHarness.create();
      try {
        for (var i = 0; i < 3; i++) {
          final sub = Subscription(id: newId(), name: '合法大对象' + ('中' * 90000));
          await h.repo.commit([Mutation(EntityRef(sub.kind, sub.id), [], sub)]);
        }
        final s = BackupService(h.repo);
        final bytes = await s.exportEncrypted();
        expect(bytes.length, greaterThan(maxCryptoObjectBytes));
        final recovery = (await s.recoveryFor(h.repo.currentLedgerId!))!;
        expect((await s.inspect(bytes, recovery)).batchCount, 4);
        await expectLater(
          BackupFormat().seal(
            BackupArchive(await h.repo.store.metadata(), [large]),
            await h.repo.authenticatedKeys(),
          ),
          throwsA(isA<EchoFailure>()),
        );
        await expectLater(
          s.inspect(Uint8List(maxBackupBytes + 1), recovery),
          throwsA(isA<EchoFailure>()),
        );
      } finally {
        await h.close();
      }
    },
  );
}

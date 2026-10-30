import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:echo_subs/core/model/change_batch.dart';
import 'package:echo_subs/core/model/civil_date.dart';
import 'package:echo_subs/core/model/ids.dart';
import 'package:echo_subs/core/model/ledger.dart';
import 'package:echo_subs/core/model/subscription.dart';
import 'package:echo_subs/features/sync/sync_engine.dart';
import 'package:echo_subs/features/reminders/reminder_planner.dart';
import 'package:echo_subs/app/services.dart';
import 'package:echo_subs/features/reminders/reminder_adapter.dart';
import 'package:echo_subs/features/reminders/reminder_reconciler.dart';
import 'package:echo_subs/features/backup/backup_format.dart';
import '../reminders/reconciler_test.dart' show FakeReminderPlatform;
import 'package:echo_subs/core/crypto/ledger_keys.dart';
import 'package:echo_subs/core/crypto/envelope_codec.dart';
import 'package:echo_subs/core/crypto/ledger_metadata.dart';
import 'package:echo_subs/core/model/errors.dart';
import 'package:echo_subs/features/backup/backup_service.dart';
import 'package:echo_subs/features/ledger/ledger_repository.dart';
import 'package:echo_subs/features/sync/sync_state_store.dart';
import 'package:echo_subs/storage/ledger_store.dart';
import '../support/ledger_harness.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  for (final scenario in [
    'no-config',
    'foreign-config',
    'deleted-config',
    'missing-quarantine-parent',
  ]) {
    test(
      'backup restore import rejects $scenario without touching existing ledger',
      () async {
        final h = await LedgerHarness.create();
        try {
          final selected = h.repo.currentLedgerId!;
          final before = await h.repo.snapshot();
          final bundle = await createLedgerBundle(newId());
          final id = bundle.metadata.id,
              ref = EntityRef(EntityKind.ledgerConfig, bundle.metadata.id);
          const first = '00000000000000000000000000000001';
          const second = '00000000000000000000000000000002';
          const absent = '00000000000000000000000000000009';
          final other = newId();
          final mutations = switch (scenario) {
            'no-config' => [
              Mutation(
                EntityRef(EntityKind.category, other),
                [],
                Category(other, '虚构类别'),
              ),
            ],
            'foreign-config' => [
              Mutation(
                EntityRef(EntityKind.ledgerConfig, other),
                [],
                LedgerConfig(other, 'UTC'),
              ),
            ],
            'missing-quarantine-parent' => [
              Mutation(ref, [absent], LedgerConfig(id, 'UTC')),
            ],
            _ => [Mutation(ref, [], LedgerConfig(id, 'UTC'))],
          };
          final batch = ChangeBatch(
            id: first,
            ledgerId: id,
            deviceId: newId(),
            createdAtUtc: DateTime.utc(2026, 10, 30),
            mutations: mutations,
          );
          final objects = <StoredObject>[
            await StoredObject.fromBytes(
              batch,
              await EnvelopeCodec().seal(batch, bundle.keys),
            ),
          ];
          if (scenario == 'deleted-config') {
            final deletion = ChangeBatch(
              id: second,
              ledgerId: id,
              deviceId: batch.deviceId,
              createdAtUtc: batch.createdAtUtc,
              mutations: [
                Mutation(ref, [first], null),
              ],
            );
            objects.add(
              await StoredObject.fromBytes(
                deletion,
                await EnvelopeCodec().seal(deletion, bundle.keys),
              ),
            );
          }
          if (scenario == 'missing-quarantine-parent') {
            objects.add(
              await StoredObject.fromBytes(
                batch,
                await EnvelopeCodec().seal(batch, bundle.keys),
              ),
            );
          }
          for (final policy in LedgerImportPolicy.values) {
            await expectLater(
              h.repo.importLedger(
                bundle.metadata,
                bundle.keys,
                objects,
                recovery: bundle.recovery,
                policy: policy,
              ),
              throwsA(isA<EchoFailure>()),
            );
          }
          final service = BackupService(h.repo);
          final encoded = await BackupFormat().seal(
            BackupArchive(bundle.metadata, objects.map((o) => o.bytes)),
            bundle.keys,
          );
          await expectLater(
            service.inspect(encoded, bundle.recovery),
            throwsA(isA<EchoFailure>()),
          );
          expect(await h.repo.listLedgers(), [selected]);
          expect(h.repo.currentLedgerId, selected);
          expect((await h.repo.snapshot()).projection, before.projection);
          expect(await h.vault.get(LedgerRepository.rootKeyName(id)), isNull);
        } finally {
          await h.close();
        }
      },
    );
  }

  for (final sameBody in [true, false]) {
    test(
      'complete quarantined genesis restores without invented config (same body: $sameBody)',
      () async {
        final h = await LedgerHarness.create();
        final join = await LedgerHarness.create();
        try {
          final originalId = h.repo.currentLedgerId!;
          final keys = await h.repo.authenticatedKeys();
          final genesis = (await h.repo.snapshot()).batches.single;
          final configRef = EntityRef(EntityKind.ledgerConfig, originalId);
          await h.repo.commit([
            Mutation(configRef, [
              genesis.id,
            ], LedgerConfig(originalId, 'Europe/London')),
          ]);
          final subscription = Subscription(
            id: newId(),
            name: '配置待确认时不得提醒',
            nextRenewalDate: CivilDate(2026, 11, 1),
          );
          await h.repo.commit([
            Mutation(
              EntityRef(subscription.kind, subscription.id),
              [],
              subscription,
            ),
          ]);
          final variant = sameBody
              ? genesis
              : ChangeBatch(
                  id: genesis.id,
                  ledgerId: originalId,
                  deviceId: genesis.deviceId,
                  createdAtUtc: genesis.createdAtUtc,
                  mutations: [
                    Mutation(
                      configRef,
                      [],
                      LedgerConfig(originalId, 'America/New_York'),
                    ),
                  ],
                );
          final secondCipher = await EnvelopeCodec().seal(variant, keys);
          await SyncEngine(
            h.repo.store,
            keys,
          ).ingest(await StoredObject.fromBytes(variant, secondCipher));
          final before = await h.repo.snapshot();
          expect(
            before.projection.entities.values.whereType<LedgerConfig>(),
            isEmpty,
          );
          expect(before.projection.pendingBatchIds, isEmpty);
          expect(before.causal.unsafeRefs, contains(configRef));
          expect(before.quarantinedBatchIds, hasLength(2));
          expect((await h.repo.authenticatedKeys()).rootKey, keys.rootKey);
          final sourceObjects = <String, StoredObject>{
            for (final o in [
              ...await h.repo.store.objects(),
              ...before.quarantinedObjects.map((q) => q.object),
            ])
              '${o.batchId}:${o.sha256}': o,
          };
          final sourceDigests = sourceObjects.keys.toSet();
          final joinSelection = join.repo.currentLedgerId;
          await expectLater(
            join.repo.importLedger(before.metadata, keys, sourceObjects.values),
            throwsA(isA<EchoFailure>()),
          );
          expect(await join.repo.listLedgers(), [joinSelection]);
          final service = BackupService(h.repo);
          final recovery = (await service.recoveryFor(originalId))!;
          final plain =
              jsonDecode(
                    utf8.decode(await service.exportPlain(confirmed: true)),
                  )
                  as Map;
          expect(plain['batches'], hasLength(4));
          final preview = await service.inspect(
            await service.exportEncrypted(),
            recovery,
          );
          expect(preview.batchCount, 4);
          expect(preview.configurationNeedsConfirmation, true);
          expect(preview.quarantinedBatchCount, 2);
          final restoredId = await service.restoreAsNew(preview);
          expect(restoredId, isNot(originalId));
          expect(h.repo.currentLedgerId, originalId);
          final restored = await LedgerStore(h.db, restoredId).snapshot();
          expect(restored.batches, hasLength(3));
          expect(restored.quarantinedObjects, hasLength(3));
          expect(
            restored.projection.entities.values.whereType<LedgerConfig>(),
            isEmpty,
          );
          expect(restored.quarantinedBatchIds, hasLength(2));
          expect(restored.causal.unsafeRefs, {
            EntityRef(EntityKind.ledgerConfig, restoredId),
          });
          expect(
            restored.projection.entities.values.whereType<Subscription>(),
            hasLength(1),
          );
          expect(
            planReminders(
              restored.projection,
              DateTime.utc(2026, 10, 30),
              unsafeRefs: restored.causal.unsafeRefs,
            ),
            isEmpty,
          );
          final viewRepo = LedgerRepository(h.db, h.vault, newId());
          await viewRepo.selectLedger(restoredId);
          final services = AppServices(ledger: viewRepo);
          final platform = FakeReminderPlatform();
          try {
            await services.ready;
            services.attachReminders(
              ReminderReconciler(
                snapshot: () async => services.snapshot,
                adapter: DurableReminderAdapter(
                  ReminderStateStore(h.db),
                  platform,
                ),
                now: () => DateTime.utc(2026, 10, 30),
              ),
            );
            await services.reconcileReminders();
            expect(services.config, isNull);
            expect(services.configurationNeedsConfirmation, true);
            expect(
              services.reminders!.suppressed,
              contains(EntityRef(EntityKind.ledgerConfig, restoredId)),
            );
            expect(services.reminders!.complete, false);
            expect(services.syncStatus.remindersReconciled, false);
            expect(platform.schedules, 0);
          } finally {
            await services.closeReminders();
            services.dispose();
            await Future<void>.delayed(Duration.zero);
          }
          expect(
            (await SyncStateStore(
              h.db,
              restoredId,
            ).configs()).where((c) => c.enabled),
            isEmpty,
          );
          expect(
            (await h.repo.authenticatedKeys(restoredId)).rootKey,
            isNot(keys.rootKey),
          );
          expect(
            (await service.recoveryFor(restoredId))!.encoded,
            isNot(recovery.encoded),
          );
          expect((await h.repo.snapshot()).projection, before.projection);
          expect((await h.repo.snapshot()).batches, before.batches);
          expect({
            for (final o in [
              ...await h.repo.store.objects(),
              ...(await h.repo.store.quarantinedObjects()).map((q) => q.object),
            ])
              '${o.batchId}:${o.sha256}',
          }, sourceDigests);
        } finally {
          await join.close();
          await h.close();
        }
      },
    );
  }
  test(
    'same recovery opens repeated exports, restore is new and original unchanged',
    () async {
      final h = await LedgerHarness.create();
      try {
        final service = BackupService(h.repo);
        final original = await h.repo.snapshot();
        final keys = await h.repo.authenticatedKeys();
        final recovery = RecoveryCode.parse(
          utf8.decode(
            (await h.vault.get(
              LedgerRepository.recoveryKeyName(original.metadata.id),
            ))!,
          ),
        );
        final first = await service.exportEncrypted();
        final second = await service.exportEncrypted();
        expect(first, isNot(second));
        final preview = await service.inspect(first, recovery);
        expect(
          (await service.inspect(second, recovery)).batchCount,
          preview.batchCount,
        );
        expect(preview.toString(), isNot(contains(recovery.encoded)));
        final id = await service.restoreAsNew(preview);
        expect(id, isNot(original.metadata.id));
        expect(h.repo.currentLedgerId, original.metadata.id);
        expect((await h.repo.snapshot()).projection, original.projection);
        expect((await h.repo.snapshot()).batches, original.batches);
        expect(
          (await h.repo.authenticatedKeys(id)).rootKey,
          isNot(keys.rootKey),
        );
        final restoredRecovery = await service.recoveryFor(id);
        expect(restoredRecovery!.encoded, isNot(recovery.encoded));
        expect(
          (await unwrapKeys(
            await LedgerStore(h.db, id).metadata(),
            restoredRecovery,
          )).ledgerId,
          id,
        );
        expect(
          (await SyncStateStore(h.db, id).configs()).where((c) => c.enabled),
          isEmpty,
        );
        await expectLater(
          service.exportPlain(confirmed: false),
          throwsA(isA<EchoFailure>()),
        );
        expect(
          utf8.decode(await service.exportPlain(confirmed: true)),
          isNot(contains(recovery.encoded)),
        );
      } finally {
        await h.close();
      }
    },
  );
  test(
    'wrong recovery, truncation, unknown version, tampering fail without registration',
    () async {
      final h = await LedgerHarness.create();
      try {
        final service = BackupService(h.repo);
        final recovery = (await service.recoveryFor(h.repo.currentLedgerId!))!;
        final bytes = await service.exportEncrypted();
        await expectLater(
          service.inspect(bytes, RecoveryCode.generate()),
          throwsA(isA<EchoFailure>()),
        );
        await expectLater(
          service.inspect(
            Uint8List.sublistView(bytes, 0, bytes.length - 1),
            recovery,
          ),
          throwsA(isA<EchoFailure>()),
        );
        final map = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
        await expectLater(
          service.inspect(canonicalBytes({...map, 'version': 99}), recovery),
          throwsA(isA<EchoFailure>()),
        );
        final tag = cryptoBase64(map['tag']);
        tag[0] ^= 1;
        await expectLater(
          service.inspect(
            canonicalBytes({...map, 'tag': base64Encode(tag)}),
            recovery,
          ),
          throwsA(isA<EchoFailure>()),
        );
        expect(await h.repo.listLedgers(), hasLength(1));
      } finally {
        await h.close();
      }
    },
  );
}

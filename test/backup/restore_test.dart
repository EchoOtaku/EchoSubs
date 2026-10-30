import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
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

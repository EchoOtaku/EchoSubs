import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:echo_subs/app/services.dart';
import 'package:echo_subs/core/crypto/ledger_metadata.dart';
import 'package:echo_subs/core/crypto/ledger_keys.dart';
import 'package:echo_subs/core/model/errors.dart';
import 'package:echo_subs/core/model/ids.dart';
import 'package:echo_subs/core/model/ledger.dart';
import 'package:echo_subs/core/model/subscription.dart';
import 'package:echo_subs/features/ledger/ledger_repository.dart';
import '../support/ledger_harness.dart';

void main() {
  test(
    'bootstrap stable device and active ledger selection, rebind watch',
    () async {
      final h = await LedgerHarness.create();
      addTearDown(h.close);
      final first = h.repo.currentLedgerId!;
      final initial = await AppServices.bootstrap(
        database: h.db,
        vault: h.vault,
      );
      final device = initial.ledger.deviceId;
      expect(initial.ledger.currentLedgerId, first);
      final second = newId();
      await initial.ledger.create(
        LedgerConfig(second, 'America/New_York'),
        await createLedgerBundle(second),
      );
      await initial.selectLedger(second);
      final secondSub = Subscription(id: newId(), name: '第二账本');
      await initial.saveSubscription(secondSub);
      await initial.selectLedger(first);
      expect(initial.subscriptions, isEmpty);
      initial.dispose();
      final again = await AppServices.bootstrap(database: h.db, vault: h.vault);
      addTearDown(again.dispose);
      expect(again.ledger.deviceId, device);
      expect(again.ledger.currentLedgerId, first);
      await again.selectLedger(second);
      expect(again.subscriptions.single.name, '第二账本');
      await again.saveSubscription(
        copySubscription(secondSub, {'name': '第二账本已编辑'}),
      );
      expect(again.subscriptions.single.name, '第二账本已编辑');
    },
  );
  test(
    'invalid active selection and locked root preserve database and key',
    () async {
      final h = await LedgerHarness.create();
      addTearDown(h.close);
      final id = h.repo.currentLedgerId!;
      final before = await h.repo.snapshot();
      await h.vault.put(
        AppServices.activeLedgerKey,
        Uint8List.fromList(utf8.encode(newId())),
      );
      await expectLater(
        AppServices.bootstrap(database: h.db, vault: h.vault),
        throwsA(isA<EchoFailure>()),
      );
      expect((await h.repo.snapshot()).batches, before.batches);
      expect(await h.repo.listLedgers(), [id]);
      await h.vault.put(
        AppServices.activeLedgerKey,
        Uint8List.fromList(utf8.encode(id)),
      );
      final wrongRoot = secureBytes(32);
      await h.vault.put(LedgerRepository.rootKeyName(id), wrongRoot);
      await expectLater(
        AppServices.bootstrap(database: h.db, vault: h.vault),
        throwsA(isA<EchoFailure>()),
      );
      expect(await h.vault.get(LedgerRepository.rootKeyName(id)), wrongRoot);
      expect((await h.repo.snapshot()).batches, before.batches);
      expect(await h.repo.listLedgers(), [id]);
    },
  );
  test(
    'multiple ledgers missing selection and malformed device fail explicitly',
    () async {
      final h = await LedgerHarness.create();
      addTearDown(h.close);
      final second = newId();
      await h.repo.create(
        LedgerConfig(second, 'UTC'),
        await createLedgerBundle(second),
      );
      await expectLater(
        AppServices.bootstrap(database: h.db, vault: h.vault),
        throwsA(isA<EchoFailure>()),
      );
      final invalid = Uint8List.fromList(utf8.encode('invalid-device'));
      await h.vault.put(AppServices.deviceIdKey, invalid);
      await expectLater(
        AppServices.bootstrap(database: h.db, vault: h.vault),
        throwsA(isA<EchoFailure>()),
      );
      expect(await h.vault.get(AppServices.deviceIdKey), invalid);
      expect((await h.repo.listLedgers()).length, 2);
    },
  );
}

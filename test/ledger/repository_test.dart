import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:echo_subs/core/crypto/envelope_codec.dart';
import 'package:echo_subs/core/crypto/key_vault.dart';
import 'package:echo_subs/core/crypto/ledger_keys.dart';
import 'package:echo_subs/core/crypto/ledger_metadata.dart';
import 'package:echo_subs/core/model/change_batch.dart';
import 'package:echo_subs/core/model/civil_date.dart';
import 'package:echo_subs/core/model/errors.dart';
import 'package:echo_subs/core/model/ids.dart';
import 'package:echo_subs/core/model/ledger.dart';
import 'package:echo_subs/core/model/money.dart';
import 'package:echo_subs/core/model/payment.dart';
import 'package:echo_subs/core/model/subscription.dart';
import 'package:echo_subs/features/ledger/ledger_repository.dart';
import 'package:echo_subs/storage/app_database.dart';

class FakeVault implements VaultStorage {
  final values = <String, String>{};
  int writes = 0;
  int? failAt;
  bool refuseRead = false;
  Future<void> Function()? beforeWrite;
  @override
  Future<String?> read(String name) async {
    if (refuseRead) throw StateError('fake');
    return values[name];
  }

  @override
  Future<void> write(String name, String value) async {
    if (++writes == failAt) throw StateError('fake');
    await beforeWrite?.call();
    values[name] = value;
  }
}

class CountingCodec extends EnvelopeCodec {
  int seals = 0;
  bool fail = false;
  @override
  Future<Uint8List> seal(ChangeBatch batch, LedgerKeys keys) async {
    seals++;
    if (fail) throw const EchoFailure('unavailable', '测试加密失败');
    return super.seal(batch, keys);
  }
}

class Fixture {
  late Directory dir;
  late File file;
  late AppDatabase db;
  final backend = FakeVault();
  late KeyVault vault;
  late LedgerRepository repo;
  late LedgerBundle bundle;
  final id = newId();
  final device = newId();
  final subscriptionId = newId();
  final categoryId = newId();
  late String originalBatch;
  Subscription subscription({
    int endMonth = 1,
    SubscriptionStatus status = SubscriptionStatus.active,
  }) => Subscription(
    id: subscriptionId,
    name: '虚构订阅',
    categoryId: categoryId,
    entitlementEnd: CivilDate(2026, endMonth, 28),
    status: status,
  );
  Payment payment() => Payment(
    id: newId(),
    subscriptionId: subscriptionId,
    amount: Money('CNY', 0, 2),
    paidOn: CivilDate(2026, 1, 28),
  );
  Future<void> init() async {
    dir = await Directory.systemTemp.createTemp('echosubs-repository-');
    file = File('${dir.path}/ledger.sqlite');
    db = await AppDatabase.open(file);
    vault = KeyVault(storage: backend);
    repo = LedgerRepository(db, vault, device);
    bundle = await createLedgerBundle(id);
    await repo.create(LedgerConfig(id, 'Asia/Shanghai'), bundle);
    originalBatch = await repo.commit([
      Mutation(
        EntityRef(EntityKind.subscription, subscriptionId),
        [],
        subscription(),
      ),
      Mutation(
        EntityRef(EntityKind.category, categoryId),
        [],
        Category(categoryId, '虚构分类'),
      ),
    ]);
  }

  Future<void> dispose() async {
    await db.close();
    await dir.delete(recursive: true);
  }
}

void main() {
  late Fixture f;
  setUp(() async {
    f = Fixture();
    await f.init();
  });
  tearDown(() => f.dispose());
  test(
    'two database connections reserve creation before touching shared vault',
    () async {
      final otherDb = await AppDatabase.open(f.file);
      final entered = Completer<void>();
      final release = Completer<void>();
      final before = f.backend.writes;
      final id = newId();
      final a = await createLedgerBundle(id);
      final b = await createLedgerBundle(id);
      f.backend.beforeWrite = () async {
        if (f.backend.writes == before + 1) {
          entered.complete();
          await release.future;
        }
      };
      final winner = f.repo.create(LedgerConfig(id, 'UTC'), a);
      try {
        await entered.future.timeout(const Duration(seconds: 3));
        final other = LedgerRepository(otherDb, f.vault, newId());
        final succeeded = await other
            .create(LedgerConfig(id, 'UTC'), b)
            .then((_) => true, onError: (Object _) => false)
            .timeout(const Duration(seconds: 3));
        expect(succeeded, false);
        expect(f.backend.writes, before + 1);
      } finally {
        release.complete();
        try {
          await winner;
        } finally {
          await otherDb.close();
        }
      }
      expect(
        await f.vault.get(LedgerRepository.rootKeyName(id)),
        a.keys.rootKey,
      );
      expect((await f.repo.snapshot()).metadata.encode(), a.metadata.encode());
    },
  );
  test(
    'seal happens once per commit and encryption failure cannot persist changes',
    () async {
      final codec = CountingCodec();
      final repo = LedgerRepository(f.db, f.vault, f.device, codec: codec);
      await repo.selectLedger(f.id);
      final category = Category(newId(), '单次加密');
      await repo.commit([
        Mutation(EntityRef(category.kind, category.id), [], category),
      ]);
      expect(codec.seals, 1);
      final count = (await repo.snapshot()).batches.length;
      codec.fail = true;
      await expectLater(
        repo.commit([
          Mutation(EntityRef(EntityKind.category, newId()), [], null),
        ]),
        throwsA(isA<EchoFailure>()),
      );
      expect(codec.seals, 2);
      expect((await repo.snapshot()).batches.length, count);
      expect((await repo.store.objects()).length, count);
      f.backend.refuseRead = true;
      await expectLater(repo.selectLedger(f.id), throwsA(isA<EchoFailure>()));
      expect(repo.currentLedgerId, f.id);
      expect((await repo.snapshot()).batches.length, count);
    },
  );
  test(
    'duplicate and concurrent create never overwrite the winning vault keys',
    () async {
      final originalRoot = await f.vault.get(
        LedgerRepository.rootKeyName(f.id),
      );
      final originalRecovery = await f.vault.get(
        LedgerRepository.recoveryKeyName(f.id),
      );
      final writes = f.backend.writes;
      final duplicate = await createLedgerBundle(f.id);
      await expectLater(
        f.repo.create(LedgerConfig(f.id, 'UTC'), duplicate),
        throwsA(isA<EchoFailure>()),
      );
      expect(f.backend.writes, writes);
      expect(
        await f.vault.get(LedgerRepository.rootKeyName(f.id)),
        originalRoot,
      );
      expect(
        await f.vault.get(LedgerRepository.recoveryKeyName(f.id)),
        originalRecovery,
      );
      final id = newId();
      final a = await createLedgerBundle(id);
      final b = await createLedgerBundle(id);
      final other = LedgerRepository(f.db, f.vault, newId());
      final outcomes = await Future.wait([
        f.repo
            .create(LedgerConfig(id, 'UTC'), a)
            .then((_) => true, onError: (Object _) => false),
        other
            .create(LedgerConfig(id, 'UTC'), b)
            .then((_) => true, onError: (Object _) => false),
      ]);
      expect(outcomes.where((value) => value).length, 1);
      final winner = outcomes.first ? a : b;
      expect(
        await f.vault.get(LedgerRepository.rootKeyName(id)),
        winner.keys.rootKey,
      );
      expect(
        utf8.decode((await f.vault.get(LedgerRepository.recoveryKeyName(id)))!),
        winner.recovery.encoded,
      );
      await f.repo.selectLedger(id);
      final object = (await f.repo.store.objects()).single;
      expect(
        (await EnvelopeCodec().open(object.bytes, winner.keys)).ledgerId,
        id,
      );
    },
  );
  test(
    'zero renewal persists one envelope and immutable retry bytes',
    () async {
      final payment = f.payment();
      final batchId = await f.repo.renew(f.subscription(endMonth: 2), payment);
      final first = (await f.repo.store.objects()).singleWhere(
        (o) => o.batchId == batchId,
      );
      final decoded = await EnvelopeCodec().open(first.bytes, f.bundle.keys);
      expect(decoded.mutations.length, 2);
      first.bytes[0] = 0;
      await f.db.close();
      f.db = await AppDatabase.open(f.file);
      f.repo = LedgerRepository(f.db, f.vault, f.device);
      await f.repo.selectLedger(f.id);
      final second = (await f.repo.store.objects()).singleWhere(
        (o) => o.batchId == batchId,
      );
      expect(second.bytes, first.bytes);
      expect(second.sha256, first.sha256);
      expect(
        (await f.repo.snapshot()).projection.entities[EntityRef(
          EntityKind.payment,
          payment.id,
        )],
        payment,
      );
    },
  );
  test(
    'archive retains payment, category tombstone retains subscription, timezone is synced',
    () async {
      final renewal = await f.repo.renew(
        f.subscription(endMonth: 2),
        f.payment(),
      );
      await f.repo.commit([
        Mutation(EntityRef(EntityKind.subscription, f.subscriptionId), [
          renewal,
        ], f.subscription(endMonth: 2, status: SubscriptionStatus.archived)),
        Mutation(EntityRef(EntityKind.category, f.categoryId), [
          f.originalBatch,
        ], null),
      ]);
      final configBatch = (await f.repo.snapshot()).batches.singleWhere(
        (b) => b.mutations.any((m) => m.ref.kind == EntityKind.ledgerConfig),
      );
      final zone = await f.repo.commit([
        Mutation(EntityRef(EntityKind.ledgerConfig, f.id), [
          configBatch.id,
        ], LedgerConfig(f.id, 'Europe/London')),
      ]);
      final s = await f.repo.snapshot();
      expect(s.projection.entities.values.whereType<Payment>().length, 1);
      expect(
        s.projection.entities.values.whereType<Subscription>().single.status,
        SubscriptionStatus.archived,
      );
      expect(
        s.projection.entities.containsKey(
          EntityRef(EntityKind.category, f.categoryId),
        ),
        false,
      );
      expect(
        s.projection.entities.values
            .whereType<LedgerConfig>()
            .single
            .timeZoneId,
        'Europe/London',
      );
      expect(s.pendingBatchIds, contains(zone));
    },
  );
  test(
    'stale parents roll back and missing keys never replace existing ledger',
    () async {
      await f.repo.renew(f.subscription(endMonth: 2), f.payment());
      final count = (await f.repo.snapshot()).batches.length;
      await expectLater(
        f.repo.commit([
          Mutation(EntityRef(EntityKind.subscription, f.subscriptionId), [
            f.originalBatch,
          ], f.subscription()),
        ]),
        throwsA(isA<EchoFailure>()),
      );
      expect((await f.repo.snapshot()).batches.length, count);
      f.backend.values.remove(
        'echosubs.v1.${LedgerRepository.rootKeyName(f.id)}',
      );
      await expectLater(
        f.repo.renew(f.subscription(), f.payment()),
        throwsA(isA<EchoFailure>()),
      );
      expect((await f.repo.snapshot()).batches.length, count);
      expect(await f.repo.listLedgers(), [f.id]);
    },
  );
  test(
    'creation registers multiple partitions and persists recovery encoding',
    () async {
      final second = await createLedgerBundle(newId());
      await f.repo.create(LedgerConfig(second.metadata.id, 'UTC'), second);
      expect(f.repo.currentLedgerId, second.metadata.id);
      expect((await f.repo.snapshot()).batches.length, 1);
      expect(
        await f.repo.listLedgers(),
        containsAll([f.id, second.metadata.id]),
      );
      final saved = await f.vault.get(
        LedgerRepository.recoveryKeyName(second.metadata.id),
      );
      expect(utf8.decode(saved!), second.recovery.encoded);
      await f.repo.selectLedger(f.id);
      expect((await f.repo.snapshot()).batches.length, 2);
    },
  );
  test('vault failure leaves current ledger and database unchanged', () async {
    final second = await createLedgerBundle(newId());
    f.backend.failAt = f.backend.writes + 2;
    await expectLater(
      f.repo.create(LedgerConfig(second.metadata.id, 'UTC'), second),
      throwsA(isA<EchoFailure>()),
    );
    expect(f.repo.currentLedgerId, f.id);
    expect(await f.repo.listLedgers(), [f.id]);
  });
}

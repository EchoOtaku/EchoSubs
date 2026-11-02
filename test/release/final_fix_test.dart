import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:echo_subs/main.dart';
import 'package:echo_subs/app/services.dart';
import 'package:echo_subs/app/startup_recovery.dart';
import 'package:echo_subs/features/backup/backup_service.dart';
import 'package:echo_subs/features/backup/document_access.dart';
import 'package:echo_subs/core/crypto/envelope_codec.dart';
import 'package:echo_subs/core/crypto/ledger_metadata.dart';
import 'package:echo_subs/core/model/change_batch.dart';
import 'package:echo_subs/core/model/errors.dart';
import 'package:echo_subs/core/model/ids.dart';
import 'package:echo_subs/core/model/ledger.dart';
import 'package:echo_subs/core/model/subscription.dart';
import 'package:echo_subs/features/ledger/ledger_repository.dart';
import 'package:echo_subs/features/ledger/ui/subscription_detail_page.dart';
import 'package:echo_subs/features/ledger/ui/subscription_editor.dart';
import 'package:echo_subs/features/ledger/ui/overview_page.dart';
import 'package:echo_subs/features/reminders/reminder_adapter.dart';
import 'package:echo_subs/features/reminders/reminder_reconciler.dart';
import 'package:echo_subs/features/sync/sync_engine.dart';
import 'package:echo_subs/features/sync/sync_status.dart';
import 'package:echo_subs/features/sync/ui/conflicts_page.dart';
import 'package:echo_subs/storage/ledger_store.dart';
import '../support/ledger_harness.dart';
import '../reminders/reconciler_test.dart' show FakeReminderPlatform;
import '../ledger/repository_test.dart' show Fixture;

class FailedSnapshotRepository extends LedgerRepository {
  FailedSnapshotRepository(super.database, super.vault, super.deviceId);
  String? failLedger;
  @override
  Future<LedgerSnapshot> snapshot() async {
    if (currentLedgerId == failLedger) {
      throw const EchoFailure('integrity', '目标完整快照读取失败');
    }
    return super.snapshot();
  }
}

class BackupDocuments implements DocumentAccess {
  BackupDocuments(this.bytes);
  final Uint8List bytes;
  @override
  Future<Uint8List?> pick() async => bytes;
  @override
  Future<bool> save(Uint8List bytes, String name) async => false;
}

Future<void> ioPump(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 200)),
  );
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> ingest(LedgerRepository repo, List<Mutation> changes) async {
  final b = ChangeBatch(
    id: newId(),
    ledgerId: repo.currentLedgerId!,
    deviceId: newId(),
    createdAtUtc: DateTime.now().toUtc(),
    mutations: changes,
  );
  final keys = await repo.authenticatedKeys();
  await SyncEngine(repo.store, keys).ingest(
    await StoredObject.fromBytes(b, await EnvelopeCodec().seal(b, keys)),
  );
}

Future<Subscription> conflict(LedgerHarness h) async {
  final s = Subscription(id: newId(), name: '共同确认版本');
  final ref = EntityRef(s.kind, s.id);
  final parent = await h.repo.commit([Mutation(ref, [], s)]);
  for (final name in ['远端 A', '远端 B']) {
    await ingest(h.repo, [
      Mutation(ref, [parent], copySubscription(s, {'name': name})),
    ]);
  }
  return s;
}

Future<AppServices> createServices(LedgerHarness h) async {
  final services = AppServices(ledger: h.repo);
  await services.ready;
  return services;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'I1 actual startup recovery validates backup then imports without changing old selection or slots',
    (tester) async {
      final h = (await tester.runAsync(LedgerHarness.create))!;
      final oldId = h.repo.currentLedgerId!;
      final backup = BackupService(h.repo);
      final bytes = (await tester.runAsync(backup.exportEncrypted))!;
      final code = (await tester.runAsync(() => backup.recoveryFor(oldId)))!;
      final before = (await tester.runAsync(h.repo.snapshot))!;
      final wrongRoot = Uint8List(32);
      await tester.runAsync(() async {
        await h.vault.put(LedgerRepository.rootKeyName(oldId), wrongRoot);
        await h.vault.put(
          AppServices.activeLedgerKey,
          Uint8List.fromList(utf8.encode(oldId)),
        );
      });
      AppServices? reopened;
      await tester.runAsync(
        () => tester.pumpWidget(
          EchoSubsBootstrapApp(
            documents: BackupDocuments(bytes),
            bootstrap: () async => reopened = await AppServices.bootstrap(
              database: h.db,
              vault: h.vault,
            ),
          ),
        ),
      );
      await ioPump(tester);
      await tester.tap(find.text('从备份独立恢复'));
      await tester.pumpAndSettle();
      await tester.runAsync(() => tester.tap(find.text('选择备份并预览')));
      await ioPump(tester);
      await tester.enterText(find.byType(TextField), code.encoded);
      await tester.runAsync(() => tester.tap(find.text('校验并预览')));
      await ioPump(tester);
      await tester.runAsync(() => tester.tap(find.text('确认恢复为新账本')));
      await ioPump(tester);
      expect(find.text('新账本恢复密钥'), findsOneWidget);
      await tester.tap(find.text('我已保存恢复密钥'));
      await ioPump(tester);
      final ids = (await tester.runAsync(h.repo.listLedgers))!;
      expect(ids.length, 2);
      expect((await tester.runAsync(h.repo.snapshot))!.batches, before.batches);
      expect(
        await tester.runAsync(
          () => h.vault.get(LedgerRepository.rootKeyName(oldId)),
        ),
        wrongRoot,
      );
      final selection = await tester.runAsync<Uint8List?>(
        () => h.vault.get(AppServices.activeLedgerKey),
      );
      expect(utf8.decode(selection!), oldId);
      await tester.tap(find.text('明确选择恢复后的新账本'));
      await ioPump(tester);
      await tester.runAsync(() => tester.tap(find.text('确认')));
      await ioPump(tester);
      expect(reopened, isNotNull);
      expect(
        reopened!.ledger.currentLedgerId,
        ids.singleWhere((id) => id != oldId),
      );
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        reopened!.dispose();
        await h.close();
      });
    },
  );
  testWidgets(
    'I1 storage unavailable and incompatible startup never offer recovery bypass',
    (tester) async {
      for (final failure in [
        const EchoFailure('unavailable', 'profile busy'),
        const EchoFailure('incompatible', 'future schema'),
        const EchoFailure('locked', '安全存储密钥不可用'),
      ]) {
        await tester.pumpWidget(
          EchoSubsBootstrapApp(
            key: UniqueKey(),
            bootstrap: () async => throw failure,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('从备份独立恢复'), findsNothing);
      }
    },
  );
  test('I1 incorrect backup recovery retains old DB and selection', () async {
    final h = await LedgerHarness.create();
    try {
      final old = h.repo.currentLedgerId!;
      final backup = BackupService(h.repo);
      final bytes = await backup.exportEncrypted();
      final before = (await h.repo.snapshot()).batches;
      await h.vault.put(LedgerRepository.rootKeyName(old), Uint8List(32));
      StartupRecovery? recovery;
      try {
        await AppServices.bootstrap(database: h.db, vault: h.vault);
      } on StartupRecovery catch (e) {
        recovery = e;
      }
      expect(recovery, isNotNull);
      final bad = await createLedgerBundle(newId());
      await expectLater(
        recovery!.backup.inspect(bytes, bad.recovery),
        throwsA(isA<EchoFailure>()),
      );
      expect(await h.repo.listLedgers(), [old]);
      expect((await h.repo.snapshot()).batches, before);
    } finally {
      await h.close();
    }
  });
  test(
    'I1 new-slot write failure rolls back registration and preserves old data',
    () async {
      final f = Fixture();
      await f.init();
      try {
        final backup = BackupService(f.repo);
        final bytes = await backup.exportEncrypted();
        final before = (await f.repo.snapshot()).batches;
        await f.vault.put(LedgerRepository.rootKeyName(f.id), Uint8List(32));
        StartupRecovery? recovery;
        try {
          await AppServices.bootstrap(database: f.db, vault: f.vault);
        } on StartupRecovery catch (e) {
          recovery = e;
        }
        final preview = await recovery!.backup.inspect(
          bytes,
          f.bundle.recovery,
        );
        f.backend.failAt = f.backend.writes + 1;
        await expectLater(
          recovery.restore(preview),
          throwsA(isA<EchoFailure>()),
        );
        expect(await f.repo.listLedgers(), [f.id]);
        expect((await f.repo.snapshot()).batches, before);
        expect(
          await f.vault.get(LedgerRepository.rootKeyName(f.id)),
          Uint8List(32),
        );
      } finally {
        await f.dispose();
      }
    },
  );
  testWidgets('I1 locked startup exposes explicit independent recovery', (
    tester,
  ) async {
    final h = (await tester.runAsync(LedgerHarness.create))!;
    await tester.runAsync(
      () => h.vault.put(
        LedgerRepository.rootKeyName(h.repo.currentLedgerId!),
        Uint8List(32),
      ),
    );
    await tester.pumpWidget(
      EchoSubsBootstrapApp(
        bootstrap: () => AppServices.bootstrap(database: h.db, vault: h.vault),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pump();
    expect(find.text('从备份独立恢复'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(h.close);
  });
  test(
    'I2 successful key proof and failed full snapshot rolls selection back',
    () async {
      final h = await LedgerHarness.create();
      final first = h.repo.currentLedgerId!;
      final second = newId();
      await h.repo.create(
        LedgerConfig(second, 'UTC'),
        await createLedgerBundle(second),
      );
      final repo = FailedSnapshotRepository(h.db, h.vault, h.repo.deviceId);
      await repo.selectLedger(first);
      await h.vault.put(
        AppServices.activeLedgerKey,
        Uint8List.fromList(utf8.encode(first)),
      );
      final services = AppServices(ledger: repo);
      await services.ready;
      repo.failLedger = second;
      try {
        await expectLater(
          services.selectLedger(second),
          throwsA(isA<EchoFailure>()),
        );
        expect(repo.currentLedgerId, first);
        expect(services.snapshot!.metadata.id, first);
        expect(
          utf8.decode((await h.vault.get(AppServices.activeLedgerKey))!),
          first,
        );
      } finally {
        services.dispose();
        await h.close();
      }
    },
  );
  test(
    'I2 stale snapshot cannot authorize writes to a differently selected ledger',
    () async {
      final h = await LedgerHarness.create();
      final services = await createServices(h);
      try {
        final second = newId();
        await h.repo.create(
          LedgerConfig(second, 'UTC'),
          await createLedgerBundle(second),
        );
        await expectLater(
          services.saveSubscription(Subscription(id: newId(), name: '拒绝跨账本')),
          throwsA(isA<EchoFailure>()),
        );
        expect(
          (await h.repo.snapshot()).projection.entities.values
              .whereType<Subscription>(),
          isEmpty,
        );
      } finally {
        services.dispose();
        await h.close();
      }
    },
  );
  for (final form in [false, true]) {
    testWidgets(
      'I3 defensive ${form ? 'payment' : 'subscription'} form initialization',
      (tester) async {
        final h = (await tester.runAsync(LedgerHarness.create))!;
        final s = (await tester.runAsync(() => conflict(h)))!;
        final services = (await tester.runAsync(() => createServices(h)))!;
        await tester.pumpWidget(
          MaterialApp(
            home: form
                ? RenewalEditor(services: services, value: s)
                : SubscriptionEditor(services: services, value: s),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.textContaining('待确认'), findsWidgets);
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(() async {
          services.dispose();
          await h.close();
        });
      },
    );
  }
  testWidgets(
    'I3 detail labels uncertain baseline and exposes conflict resolver',
    (tester) async {
      final h = (await tester.runAsync(LedgerHarness.create))!;
      final s = (await tester.runAsync(() => conflict(h)))!;
      final services = (await tester.runAsync(() => createServices(h)))!;
      await tester.pumpWidget(
        MaterialApp(
          home: SubscriptionDetailPage(
            services: services,
            subscriptionId: s.id,
          ),
        ),
      );
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('detail.edit')))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('detail.renew')))
            .onPressed,
        isNull,
      );
      expect(find.textContaining('共同确认'), findsWidgets);
      await tester.tap(find.text('处理冲突'));
      await tester.pumpAndSettle();
      expect(find.text('同步冲突'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        services.dispose();
        await h.close();
      });
    },
  );
  test(
    'I4 required config cannot be deleted by local commit or resolution',
    () async {
      final h = await LedgerHarness.create();
      try {
        final id = h.repo.currentLedgerId!;
        final ref = EntityRef(EntityKind.ledgerConfig, id);
        final parents = (await h.repo.snapshot()).causal.parentsFor(ref);
        await expectLater(
          h.repo.commit([Mutation(ref, parents, null)]),
          throwsA(isA<EchoFailure>()),
        );
        for (final zone in ['UTC', 'Asia/Tokyo']) {
          await ingest(h.repo, [
            Mutation(ref, parents, LedgerConfig(id, zone)),
          ]);
        }
        final state = await h.repo.snapshot();
        await expectLater(
          h.repo.resolve(state.projection.conflicts.single, [
            Mutation(ref, state.causal.heads[ref]!.toList(), null),
          ]),
          throwsA(isA<EchoFailure>()),
        );
      } finally {
        await h.close();
      }
    },
  );
  test('I4 historical missing config keeps reminders not ready', () async {
    final h = await LedgerHarness.create();
    final ref = EntityRef(EntityKind.ledgerConfig, h.repo.currentLedgerId!);
    await ingest(h.repo, [
      Mutation(ref, (await h.repo.snapshot()).causal.parentsFor(ref), null),
    ]);
    final adapter = DurableReminderAdapter(
      ReminderStateStore(h.db),
      FakeReminderPlatform(),
    );
    final r = ReminderReconciler(snapshot: h.repo.snapshot, adapter: adapter);
    try {
      await r.reconcile();
      expect(r.complete, false);
      expect(r.error, isNotNull);
    } finally {
      await r.close();
      await h.close();
    }
  });
  testWidgets(
    'I4 timezone conflict UI offers only valid configuration choices',
    (tester) async {
      final h = (await tester.runAsync(LedgerHarness.create))!;
      final id = h.repo.currentLedgerId!;
      final ref = EntityRef(EntityKind.ledgerConfig, id);
      await tester.runAsync(() async {
        final parents = (await h.repo.snapshot()).causal.parentsFor(ref);
        for (final zone in ['UTC', 'Asia/Tokyo']) {
          await ingest(h.repo, [
            Mutation(ref, parents, LedgerConfig(id, zone)),
          ]);
        }
      });
      final services = (await tester.runAsync(() => createServices(h)))!;
      await tester.pumpWidget(
        MaterialApp(home: ConflictsPage(services: services)),
      );
      await tester.tap(find.textContaining('待确认：'));
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('conflict.delete.$id')), findsNothing);
      expect(find.textContaining('账本配置不可删除'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        services.dispose();
        await h.close();
      });
    },
  );
  for (final archived in [false, true]) {
    testWidgets(
      'I5 stale ${archived ? 'reactivation' : 'archive'} cannot overwrite remote fields',
      (tester) async {
        final h = (await tester.runAsync(LedgerHarness.create))!;
        final s = Subscription(
          id: newId(),
          name: '旧视图',
          status: archived
              ? SubscriptionStatus.archived
              : SubscriptionStatus.active,
        );
        final ref = EntityRef(s.kind, s.id);
        await tester.runAsync(() => h.repo.commit([Mutation(ref, [], s)]));
        final services = (await tester.runAsync(() => createServices(h)))!;
        await tester.pumpWidget(
          MaterialApp(
            home: SubscriptionDetailPage(
              services: services,
              subscriptionId: s.id,
            ),
          ),
        );
        final callback = tester
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('detail.archive')),
            )
            .onPressed!;
        await tester.runAsync(() async {
          await ingest(h.repo, [
            Mutation(
              ref,
              (await h.repo.snapshot()).causal.parentsFor(ref),
              copySubscription(s, {'name': '远端新字段'}),
            ),
          ]);
          callback();
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pump();
        expect(
          (await tester.runAsync(
            h.repo.snapshot,
          ))!.projection.entities[ref]!.toJson()['name'],
          '远端新字段',
        );
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(() async {
          services.dispose();
          await h.close();
        });
      },
    );
  }
  testWidgets('M1 dual sync errors identify both channels', (tester) async {
    final h = (await tester.runAsync(LedgerHarness.create))!;
    final services = (await tester.runAsync(() => createServices(h)))!;
    services.syncStatus = const SyncStatus(
      report: SyncReport(
        ChannelReport(enabled: true, errors: ['网盘错误']),
        ChannelReport(enabled: true, errors: ['直连错误']),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OverviewPage(services: services, onAdd: () {}, onOpen: (_) {}),
        ),
      ),
    );
    expect(find.textContaining('WebDAV 同步待处理'), findsOneWidget);
    expect(find.textContaining('局域网同步待处理'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      services.dispose();
      await h.close();
    });
  });
  test('M2 notification permission failure uses approved error code', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    const channel = MethodChannel('dexterous.com/flutter/local_notifications');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async =>
              call.method == 'areNotificationsEnabled' ? false : true,
        );
    final adapter = AndroidReminderPlatform();
    try {
      await expectLater(
        adapter.testNotification(),
        throwsA(
          isA<EchoFailure>().having(
            (e) => e.code,
            'allowed code',
            'unavailable',
          ),
        ),
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  });
}

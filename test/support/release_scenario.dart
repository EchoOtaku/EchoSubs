import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:echo_subs/app/services.dart';
import 'package:echo_subs/core/crypto/key_vault.dart';
import 'package:echo_subs/core/crypto/ledger_metadata.dart';
import 'package:echo_subs/core/model/change_batch.dart';
import 'package:echo_subs/core/model/civil_date.dart';
import 'package:echo_subs/core/model/ids.dart';
import 'package:echo_subs/core/model/ledger.dart';
import 'package:echo_subs/core/model/money.dart';
import 'package:echo_subs/core/model/payment.dart';
import 'package:echo_subs/core/model/subscription.dart';
import 'package:echo_subs/features/ledger/ledger_repository.dart';
import 'package:echo_subs/features/reminders/reminder_adapter.dart';
import 'package:echo_subs/features/reminders/reminder_reconciler.dart';
import 'package:echo_subs/features/sync/sync_coordinator.dart';
import 'package:echo_subs/features/sync/sync_engine.dart';
import 'package:echo_subs/features/sync/sync_state_store.dart';
import 'package:echo_subs/features/sync/sync_status.dart';
import 'package:echo_subs/features/sync/transports/lan_identity.dart';
import 'package:echo_subs/features/sync/transports/lan_pairing.dart';
import 'package:echo_subs/features/sync/transports/lan_server.dart';
import 'package:echo_subs/features/sync/transports/lan_transport.dart';
import 'package:echo_subs/features/sync/transports/webdav_transport.dart';
import 'package:echo_subs/storage/app_database.dart';
import 'package:echo_subs/storage/ledger_store.dart';
import 'ledger_harness.dart';
import 'fake_dav_server.dart';

List<Subscription> fictionalServices() => [
  Subscription(
    id: newId(),
    name: '虚构影音月卡',
    provider: '虚构影音商',
    purchaseChannel: '赠送兑换',
    price: Money('CNY', 1990, 2),
    cycle: BillingCycle(CycleUnit.month, 1),
    nextRenewalDate: CivilDate(2035, 1, 31),
    entitlementEnd: CivilDate(2035, 4, 30),
  ),
  Subscription(
    id: newId(),
    name: '虚构域名年费',
    provider: '虚构注册商',
    price: Money('USD', 1299, 2),
    cycle: BillingCycle(CycleUnit.year, 1),
    nextRenewalDate: CivilDate(2035, 2, 28),
  ),
  Subscription(
    id: newId(),
    name: '虚构永久许可',
    billingType: BillingType.lifetime,
    price: Money('CNY', 9990, 2),
  ),
  Subscription(id: newId(), name: '虚构按量存储', billingType: BillingType.metered),
];

Future<void> verifyRestore(AppServices services) async {
  final repo = services.ledger;
  final before = await repo.snapshot();
  final archive = await repo.store.objects();
  final recovery = (await services.backup!.recoveryFor(before.metadata.id))!;
  final bytes = await services.backup!.exportEncrypted();
  final preview = await services.backup!.inspect(bytes, recovery);
  expect(preview.configurationNeedsConfirmation, false);
  final restored = await services.restoreBackup(preview);
  expect(restored, isNot(before.metadata.id));
  expect(repo.currentLedgerId, before.metadata.id);
  expect((await repo.snapshot()).projection, before.projection);
  expect(
    (await repo.store.objects()).map((o) => o.sha256),
    archive.map((o) => o.sha256),
  );
  expect(await SyncStateStore(repo.database, restored).configs(), isEmpty);
  final recovered = await LedgerStore(repo.database, restored).snapshot();
  expect(recovered.batches.length, before.batches.length);
  expect(
    recovered.projection.entities.values
        .whereType<Subscription>()
        .map((s) => s.name)
        .toSet(),
    services.subscriptions.map((s) => s.name).toSet(),
  );
  expect(
    recovered.projection.entities.values.whereType<Payment>().map(
      (p) => p.amount,
    ),
    services.payments.map((p) => p.amount),
  );
}

Future<void> offlineScenario() async {
  final h = await LedgerHarness.create();
  var services = AppServices(ledger: h.repo);
  await services.ready;
  AppDatabase? reopened;
  try {
    for (final sub in fictionalServices()) {
      await services.saveSubscription(sub);
    }
    final first = services.subscriptions.firstWhere(
      (s) => s.name.contains('影音'),
    );
    final edit = copySubscription(first, {'purchaseChannel': '虚构新渠道'});
    await services.saveSubscription(edit);
    expect(
      services.subscriptions.singleWhere((s) => s.id == first.id).provider,
      first.provider,
    );
    await services.renew(
      edit,
      Payment(
        id: newId(),
        subscriptionId: first.id,
        amount: Money('CNY', 1990, 2),
        paidOn: CivilDate(2026, 10, 30),
      ),
    );
    expect(services.payments, hasLength(1));
    await verifyRestore(services);
    final id = h.repo.currentLedgerId!;
    await services.closeReminders();
    await services.detachSync();
    services.dispose();
    await h.db.close();
    reopened = await AppDatabase.open(
      File('${h.directory.path}/ledger.sqlite'),
    );
    final repo = LedgerRepository(reopened, h.vault, h.repo.deviceId);
    await repo.selectLedger(id);
    services = AppServices(ledger: repo);
    await services.ready;
    expect(services.subscriptions, hasLength(4));
    expect(services.payments, hasLength(1));
    expect(
      services.subscriptions
          .singleWhere((s) => s.id == first.id)
          .purchaseChannel,
      '虚构新渠道',
    );
  } finally {
    await services.closeReminders();
    await services.detachSync();
    services.dispose();
    await (reopened ?? h.db).close();
  }
}

/// Real transport implementations over owned loopback TLS and isolated SQLite.
Future<void> dualTransportScenario({bool omitDav = false}) async {
  final dir = await Directory.systemTemp.createTemp('echosubs-release-');
  final aDb = await AppDatabase.open(File('${dir.path}/a.sqlite'));
  final bDb = await AppDatabase.open(File('${dir.path}/b.sqlite'));
  final aVault = KeyVault(storage: MemoryVault()),
      bVault = KeyVault(storage: MemoryVault());
  final aRepo = LedgerRepository(aDb, aVault, newId()),
      bRepo = LedgerRepository(bDb, bVault, newId());
  final bundle = await createLedgerBundle(FakeDavServer.ledger);
  await aRepo.create(LedgerConfig(bundle.metadata.id, 'Asia/Shanghai'), bundle);
  final a = AppServices(ledger: aRepo);
  await a.ready;
  AppServices? b;
  final host = await LanIdentity.loadOrCreate(aVault, aRepo.deviceId),
      guest = await LanIdentity.loadOrCreate(bVault, bRepo.deviceId);
  final hostPeers = LanPeerStore(aVault), guestPeers = LanPeerStore(bVault);
  var approvals = 0;
  final hostPairing = PairingService(
    identity: host,
    peers: hostPeers,
    confirm: (_) async {
      approvals++;
      return true;
    },
    authorizeLedger: (_) async =>
        AuthorizedLedger(bundle.metadata, bundle.keys),
  );
  final guestPairing = PairingService(
    identity: guest,
    peers: guestPeers,
    confirm: (_) async {
      approvals++;
      return true;
    },
  );
  LanServer newServer() => LanServer(
    identity: host,
    peers: hostPeers,
    pairing: hostPairing,
    access: LanLedgerAccess(aRepo.store, (object) async {
      await SyncEngine(aRepo.store, bundle.keys).ingest(object);
    }),
  );
  var server = newServer();
  final dav = await FakeDavServer.start();
  final coordinators = <SyncCoordinator>[];
  Future<SyncReport> sync(
    LedgerRepository repo,
    List<SyncChannel> channels,
  ) async {
    final c = SyncCoordinator(
      store: repo.store,
      authenticate: repo.authenticatedKeys,
      channels: channels,
    );
    coordinators.add(c);
    return c.sync(token: SyncCancellation());
  }

  SyncChannel cloud() => SyncChannel(
    SyncChannelKind.webdav,
    'fictional-loopback',
    () async => WebDavTransport(
      root: dav.root,
      ledgerId: bundle.metadata.id,
      credentials: const DavCredentials('fictional', 'test-only'),
      clientFactory: dav.client,
    ),
  );
  try {
    for (final sub in fictionalServices()) {
      await a.saveSubscription(sub);
    }
    await server.start(
      enabled: true,
      foreground: true,
      address: InternetAddress.loopbackIPv4,
    );
    final peer = await guestPairing.join(
      await hostPairing.offer(
        ledgerId: bundle.metadata.id,
        address: '127.0.0.1',
        port: server.port,
      ),
    );
    expect(approvals, 2);
    final port = server.port;
    final transport = LanTransport(
      peer: peer,
      localDeviceId: bRepo.deviceId,
      peers: guestPeers,
    );
    final archive = <StoredObject>[];
    try {
      for (final ref
          in await transport.listObjects(SyncCancellation()).toList()) {
        archive.add(await transport.read(ref));
      }
    } finally {
      await transport.close();
    }
    await bRepo.importLedger(
      peer.authorizedLedger!.metadata,
      peer.authorizedLedger!.keys,
      archive,
    );
    await bRepo.selectLedger(bundle.metadata.id);
    b = AppServices(ledger: bRepo);
    await b.ready;
    final lan = SyncChannel(
      SyncChannelKind.lan,
      'paired-host',
      () async => LanTransport(
        peer: peer,
        localDeviceId: bRepo.deviceId,
        peers: guestPeers,
      ),
    );
    final first = a.subscriptions.firstWhere((s) => s.name.contains('影音'));
    final second = b.subscriptions.firstWhere((s) => s.name.contains('域名'));
    await a.saveSubscription(copySubscription(first, {'notes': '电脑离线修改'}));
    await b.saveSubscription(copySubscription(second, {'notes': '手机离线修改'}));
    await sync(aRepo, omitDav ? [] : [cloud()]);
    await server.close();
    final cloudReport = await sync(bRepo, omitDav ? [] : [cloud()]);
    expect(
      cloudReport.webdav.succeeded,
      true,
      reason: 'WebDAV is an independently required capability',
    );
    await sync(aRepo, [cloud()]);
    await a.refresh();
    await b.refresh();
    expect(a.snapshot!.projection, b.snapshot!.projection);
    server = newServer();
    await server.start(
      enabled: true,
      foreground: true,
      address: InternetAddress.loopbackIPv4,
      port: port,
    );
    final current = a.subscriptions.singleWhere((s) => s.id == first.id);
    await a.renew(
      copySubscription(current, {'entitlementEnd': '2036-01-31'}),
      Payment(
        id: newId(),
        subscriptionId: first.id,
        amount: Money('CNY', 1990, 2),
        paidOn: CivilDate(2026, 10, 30),
      ),
    );
    await b.renew(
      copySubscription(current, {'entitlementEnd': '2037-01-31'}),
      Payment(
        id: newId(),
        subscriptionId: first.id,
        amount: Money('CNY', 2990, 2),
        paidOn: CivilDate(2026, 10, 30),
      ),
    );
    await sync(bRepo, [cloud(), lan]);
    await sync(aRepo, [cloud()]);
    await sync(bRepo, [cloud(), lan]);
    await a.refresh();
    await b.refresh();
    expect(a.snapshot!.projection.conflicts, hasLength(1));
    expect(a.payments, isEmpty);
    final state = a.snapshot!;
    final conflict = state.projection.conflicts.single;
    final winner = state.batches.lastWhere(
      (batch) =>
          batch.deviceId == aRepo.deviceId &&
          batch.mutations.any((m) => m.ref.kind == EntityKind.payment),
    );
    await a.resolveConflict(bundle.metadata.id, conflict, [
      for (final ref in conflict.affectedRefs)
        Mutation(
          ref,
          state.causal.heads[ref]!.toList(),
          winner.mutations.where((m) => m.ref == ref).firstOrNull?.value,
        ),
    ]);
    await sync(aRepo, [cloud()]);
    await sync(bRepo, [cloud(), lan]);
    await a.refresh();
    await b.refresh();
    expect(a.payments, hasLength(1));
    expect(b.payments, hasLength(1));
    final deleted = a.subscriptions.firstWhere(
      (s) => s.billingType == BillingType.metered,
    );
    await a.deleteSubscription(deleted);
    await sync(bRepo, [lan, cloud()]);
    await sync(aRepo, [cloud()]);
    await a.refresh();
    await b.refresh();
    expect(b.subscriptions.any((s) => s.id == deleted.id), false);
    final before = b.snapshot!.batches.length;
    await sync(bRepo, [cloud(), lan]);
    await b.refresh();
    expect(b.snapshot!.batches.length, before);
    expect(b.payments, hasLength(1));
    expect(a.snapshot!.projection, b.snapshot!.projection);
    final platform = InAppReminderPlatform(now: () => DateTime.utc(2034));
    b.attachReminders(
      ReminderReconciler(
        snapshot: bRepo.snapshot,
        adapter: DurableReminderAdapter(
          ReminderStateStore(bDb),
          platform,
          now: () => DateTime.utc(2034),
        ),
        now: () => DateTime.utc(2034),
      ),
    );
    await b.reconcileReminders();
    final alarms = await platform.pending();
    await b.reconcileReminders();
    expect(await platform.pending(), alarms);
    expect(b.reminders!.complete, true);
    await verifyRestore(a);
    expect(dav.requestsOutsideLedgerRoot, isEmpty);
  } finally {
    for (final c in coordinators) {
      await c.close();
    }
    await b?.closeReminders();
    await a.closeReminders();
    await b?.detachSync();
    await a.detachSync();
    b?.dispose();
    a.dispose();
    await server.close();
    await hostPairing.close();
    await guestPairing.close();
    await dav.close();
    await aDb.close();
    await bDb.close();
  }
}

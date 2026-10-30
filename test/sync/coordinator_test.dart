import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:echo_subs/core/crypto/ledger_metadata.dart';
import 'package:echo_subs/core/model/errors.dart';
import 'package:echo_subs/core/model/change_batch.dart';
import 'package:echo_subs/core/model/ledger.dart';
import 'package:echo_subs/core/crypto/key_vault.dart';
import 'package:echo_subs/core/crypto/ledger_keys.dart';
import 'package:echo_subs/features/ledger/ledger_repository.dart';
import 'package:echo_subs/features/sync/sync_state_store.dart';
import 'package:echo_subs/app/services.dart';
import 'package:echo_subs/features/sync/sync_coordinator.dart';
import 'package:echo_subs/features/sync/sync_status.dart';
import 'package:echo_subs/features/sync/transports/webdav_transport.dart';
import 'package:echo_subs/storage/ledger_store.dart';
import 'sync_fixture.dart';
import '../support/ledger_harness.dart';
import '../ledger/repository_test.dart' show FakeVault, Fixture;

class Token implements CancellationToken {
  @override
  bool isCancelled = false;
}

class MemoryChannel implements SyncTransport {
  MemoryChannel(this.metadata);
  final LedgerMetadata metadata;
  final objects = <String, StoredObject>{};
  bool fail = false;
  int puts = 0;
  int closes = 0;
  Future<void> Function()? beforeList;
  String key(StoredObject object) => '${object.batchId}:${object.sha256}';
  @override
  Future<LedgerMetadata> readMetadata() async {
    if (fail) throw const EchoFailure('unavailable', '通道暂不可用');
    return metadata;
  }

  @override
  Future<void> publishMetadata(LedgerMetadata value) async {
    await readMetadata();
    if (value.id != metadata.id) throw const EchoFailure('conflict', '不同账本');
  }

  @override
  Stream<ObjectRef> listObjects(CancellationToken token) async* {
    await beforeList?.call();
    for (final object in objects.values.toList()) {
      yield ObjectRef(
        object.batchId,
        object.sha256,
        'objects/${object.batchId}-${object.sha256}.bin',
      );
    }
  }

  @override
  Future<StoredObject> read(ObjectRef ref) async =>
      objects['${ref.batchId}:${ref.sha256}']!;
  @override
  Future<void> put(StoredObject object) async {
    puts++;
    objects[key(object)] = object;
  }

  @override
  Future<void> close() async {
    closes++;
  }
}

void main() {
  late SyncFixture local, second, third;
  late MemoryChannel cloud, lan;
  late SyncCoordinator coordinator;
  setUp(() async {
    final bundle = await createLedgerBundle(id(1));
    local = await SyncFixture.create(bundle);
    second = await SyncFixture.create(bundle);
    third = await SyncFixture.create(bundle);
    cloud = MemoryChannel(bundle.metadata);
    lan = MemoryChannel(bundle.metadata);
    coordinator = SyncCoordinator(
      store: local.store,
      authenticate: () async => bundle.keys,
      channels: [
        SyncChannel(SyncChannelKind.webdav, 'cloud', () async => cloud),
        SyncChannel(SyncChannelKind.lan, 'peer', () async => lan),
      ],
    );
  });
  tearDown(() async {
    await coordinator.close();
    await local.close();
    await second.close();
    await third.close();
  });
  Future<void> configureCloud({
    String endpoint = 'cloud',
    bool enabled = true,
  }) => SyncStateStore(local.db, id(1)).save(
    ChannelConfig(SyncChannelKind.webdav, endpoint, enabled, {
      'root': 'https://fictional.example/dedicated/',
    }),
  );
  SyncCoordinator reopened({
    String endpoint = 'cloud',
    bool waiting = false,
  }) => SyncCoordinator(
    store: local.store,
    authenticate: () async => local.bundle.keys,
    channels: waiting
        ? []
        : [SyncChannel(SyncChannelKind.webdav, endpoint, () async => cloud)],
  );
  test(
    'success timestamp survives coordinator reconstruction and failed retry',
    () async {
      await configureCloud();
      final first = (await coordinator.sync(token: Token())).webdav.lastSuccess;
      expect(first, isNotNull);
      await coordinator.close();
      coordinator = reopened();
      await coordinator.restoreStatus();
      expect(coordinator.status.report.webdav.lastSuccess, first);
      expect(coordinator.status.report.webdav.succeeded, false);
      cloud.fail = true;
      final failed = await coordinator.sync(token: Token());
      expect(failed.webdav.succeeded, false);
      expect(failed.webdav.lastSuccess, first);
    },
  );
  test(
    'success timestamp is not inherited by a replacement endpoint',
    () async {
      await configureCloud();
      await coordinator.sync(token: Token());
      await configureCloud(endpoint: 'replacement');
      await coordinator.close();
      coordinator = reopened(endpoint: 'replacement');
      cloud.fail = true;
      expect(
        (await coordinator.sync(token: Token())).webdav.lastSuccess,
        isNull,
      );
    },
  );
  test(
    'completion timestamp cannot re-enable a concurrent disabled channel',
    () async {
      await configureCloud();
      final entered = Completer<void>(), release = Completer<void>();
      cloud.beforeList = () async {
        entered.complete();
        await release.future;
      };
      final flight = coordinator.sync(token: Token());
      await entered.future;
      await configureCloud(enabled: false);
      release.complete();
      final completed = (await flight).webdav.lastSuccess;
      expect(completed, isNotNull);
      expect(
        (await SyncStateStore(local.db, id(1)).configs()).single.enabled,
        false,
      );
      await coordinator.close();
      coordinator = reopened(waiting: true);
      expect(
        (await coordinator.sync(token: Token())).webdav.lastSuccess,
        completed,
      );
      expect(
        (await SyncStateStore(local.db, id(1)).configs()).single.enabled,
        false,
      );
    },
  );
  test(
    'late success cannot write timestamp into replacement endpoint',
    () async {
      await configureCloud();
      final entered = Completer<void>(), release = Completer<void>();
      cloud.beforeList = () async {
        entered.complete();
        await release.future;
      };
      final flight = coordinator.sync(token: Token());
      await entered.future;
      await configureCloud(endpoint: 'replacement');
      release.complete();
      await flight;
      await coordinator.close();
      coordinator = reopened(endpoint: 'replacement');
      cloud.fail = true;
      expect(
        (await coordinator.sync(token: Token())).webdav.lastSuccess,
        isNull,
      );
    },
  );
  test(
    'cancelled empty transfer preserves the earlier success timestamp',
    () async {
      await configureCloud();
      final previous = (await coordinator.sync(
        token: Token(),
      )).webdav.lastSuccess;
      final entered = Completer<void>(), release = Completer<void>();
      cloud.beforeList = () async {
        entered.complete();
        await release.future;
      };
      final token = Token();
      final flight = coordinator.sync(token: token);
      await entered.future;
      token.isCancelled = true;
      release.complete();
      expect((await flight).webdav.lastSuccess, previous);
      expect(coordinator.status.report.webdav.cancelled, true);
    },
  );
  test(
    'LAN success is persisted per pairing endpoint and retained while waiting',
    () async {
      final state = SyncStateStore(local.db, id(1));
      await state.save(
        ChannelConfig(SyncChannelKind.lan, 'lan-config', true, {
          'address': '192.168.1.10',
          'port': 43177,
        }),
      );
      await coordinator.close();
      coordinator = SyncCoordinator(
        store: local.store,
        authenticate: () async => local.bundle.keys,
        channels: [
          SyncChannel(
            SyncChannelKind.lan,
            'lan-config.pair-a',
            () async => lan,
            configEndpointId: 'lan-config',
          ),
        ],
      );
      final previous = (await coordinator.sync(token: Token())).lan.lastSuccess;
      await coordinator.close();
      coordinator = reopened(waiting: true);
      await coordinator.restoreStatus();
      expect(coordinator.status.report.lan.lastSuccess, previous);
      expect(coordinator.status.report.lan.succeeded, false);
      await coordinator.close();
      coordinator = SyncCoordinator(
        store: local.store,
        authenticate: () async => local.bundle.keys,
        channels: [
          SyncChannel(
            SyncChannelKind.lan,
            'lan-config.pair-b',
            () async => lan,
            configEndpointId: 'lan-config',
          ),
        ],
      );
      lan.fail = true;
      expect((await coordinator.sync(token: Token())).lan.lastSuccess, isNull);
    },
  );
  test(
    'failed cloud does not prevent LAN and relays to cloud on retry',
    () async {
      final object = await second.seal(base);
      await second.engine.ingest(object);
      lan.objects[lan.key(object)] = object;
      cloud.fail = true;
      final report = await coordinator.sync(token: Token());
      expect(report.webdav.succeeded, false);
      expect(report.lan.succeeded, true);
      expect(
        (await local.store.snapshot()).batches
            .where((b) => b.id == base.id)
            .length,
        1,
      );
      cloud.fail = false;
      await coordinator.sync(token: Token());
      expect(cloud.objects.containsKey(cloud.key(object)), true);
      await third.engine.ingest(cloud.objects.values.single);
      expect(
        (await third.store.snapshot()).projection.entities[sRef],
        sub('base'),
      );
    },
  );
  test(
    'duplicate channels apply once and missing remote object is repaired despite ack',
    () async {
      final object = await second.seal(base);
      cloud.objects[cloud.key(object)] = object;
      lan.objects[lan.key(object)] = object;
      await coordinator.sync(token: Token());
      expect((await local.store.snapshot()).batches.length, 1);
      cloud.objects.clear();
      await coordinator.sync(token: Token());
      expect(cloud.objects.length, 1);
    },
  );
  test(
    'a late LAN conflict updates both final reports and cloud pending count',
    () async {
      await local.engine.ingest(await local.seal(base));
      final editA = await local.seal(a), editB = await local.seal(b);
      cloud.objects[cloud.key(editA)] = editA;
      lan.objects[lan.key(editB)] = editB;
      final report = await coordinator.sync(token: Token());
      expect(report.webdav.succeeded, false);
      expect(report.webdav.conflicts, 1);
      expect(report.webdav.pendingUpload, 1);
      expect(report.lan.conflicts, 1);
    },
  );
  test(
    'selection persistence failure rolls back or locks writes if unlock fails',
    () async {
      final f = Fixture();
      await f.init();
      final original = f.id;
      final second = await createLedgerBundle(id(888));
      await f.repo.create(LedgerConfig(id(888), 'UTC'), second);
      await f.repo.selectLedger(original);
      final services = AppServices(ledger: f.repo);
      await services.ready;
      try {
        f.backend.failAt = f.backend.writes + 1;
        await expectLater(
          services.selectLedger(id(888)),
          throwsA(isA<EchoFailure>()),
        );
        expect(f.repo.currentLedgerId, original);
        expect(services.snapshot!.metadata.id, original);
        f.backend.failAt = null;
        f.backend.beforeWrite = () async {
          f.backend.refuseRead = true;
          throw StateError('write failed');
        };
        await expectLater(
          services.selectLedger(id(888)),
          throwsA(isA<EchoFailure>()),
        );
        expect(services.snapshot, isNull);
        await expectLater(
          services.saveSubscription(sub('blocked')),
          throwsA(isA<EchoFailure>()),
        );
      } finally {
        f.backend.refuseRead = false;
        services.dispose();
        await f.dispose();
      }
    },
  );
  test(
    'single flight includes edit during transfer and cancellation is retryable',
    () async {
      final entered = Completer<void>(), release = Completer<void>();
      cloud.beforeList = () async {
        entered.complete();
        await release.future;
      };
      final first = coordinator.sync(token: Token());
      await entered.future;
      final shared = coordinator.sync(token: Token());
      final object = await local.seal(base);
      await local.engine.ingest(object);
      release.complete();
      await Future.wait([first, shared]);
      expect(cloud.puts, 1);
      cloud.beforeList = null;
      final cancelled = Token()..isCancelled = true;
      final report = await coordinator.sync(token: cancelled);
      expect(report.webdav.succeeded, false);
      expect((await coordinator.sync(token: Token())).webdav.succeeded, true);
    },
  );
  test(
    'collision candidates relay intact to third replica and never show complete',
    () async {
      final first = await second.seal(base);
      final competing = await second.seal(
        batch(100, [Mutation(sRef, [], sub('collision'))]),
      );
      await local.engine.ingest(first);
      await local.engine.ingest(competing);
      final report = await coordinator.sync(token: Token());
      expect(report.lan.succeeded, false);
      expect(report.webdav.quarantined, 1);
      expect(lan.objects.length, 2);
      for (final object in lan.objects.values) {
        await third.engine.ingest(object);
      }
      expect((await third.store.snapshot()).quarantinedObjects.length, 2);
      expect(
        (await third.store.snapshot()).projection.entities.containsKey(sRef),
        false,
      );
      final acks = await SyncStateStore(
        local.db,
        id(1),
      ).acknowledgements(SyncChannelKind.lan, 'peer');
      expect(acks.length, 2);
      expect(
        lan.objects.values.any(
          (o) =>
              o.sha256 == competing.sha256 &&
              o.bytes.length == competing.bytes.length,
        ),
        true,
      );
    },
  );
  test('new endpoint receives full archive after legacy global ack', () async {
    final object = await local.seal(base);
    await local.engine.ingest(object);
    await local.store.transaction((tx) => tx.acknowledge(base.id));
    await coordinator.sync(token: Token());
    final replacement = MemoryChannel(local.bundle.metadata);
    final next = SyncCoordinator(
      store: local.store,
      authenticate: () async => local.bundle.keys,
      channels: [
        SyncChannel(
          SyncChannelKind.webdav,
          'replacement',
          () async => replacement,
        ),
      ],
    );
    try {
      await next.sync(token: Token());
      expect(replacement.objects.length, 1);
      expect(
        await SyncStateStore(
          local.db,
          id(1),
        ).acknowledgements(SyncChannelKind.webdav, 'replacement'),
        hasLength(1),
      );
    } finally {
      await next.close();
    }
  });
  test(
    'global success write failure clears running and preserves successful retry',
    () async {
      await configureCloud();
      final earlier = (await coordinator.sync(
        token: Token(),
      )).webdav.lastSuccess;
      await local.db.customStatement(
        'CREATE TRIGGER fail_sync_success BEFORE UPDATE OF body ON sync_channel_configs BEGIN SELECT RAISE(FAIL, \'injected\'); END',
      );
      try {
        await expectLater(
          coordinator.sync(token: Token()),
          throwsA(isA<Exception>()),
        );
        expect(coordinator.status.running, false);
        expect(coordinator.status.failureCode, 'unavailable');
        expect(coordinator.status.report.webdav.succeeded, false);
        expect(coordinator.status.report.webdav.lastSuccess, earlier);
        expect(cloud.closes, 2);
      } finally {
        await local.db.customStatement('DROP TRIGGER fail_sync_success');
      }
      expect((await coordinator.sync(token: Token())).webdav.succeeded, true);
      expect(cloud.closes, 3);
    },
  );
  test(
    'authenticated pending dependencies differ from transport outbox',
    () async {
      final child = await local.seal(a);
      cloud.objects[cloud.key(child)] = child;
      final report = await coordinator.sync(token: Token());
      expect(report.webdav.pendingDependencies, 1);
      expect(report.webdav.pendingUpload, 0);
      expect(report.webdav.succeeded, false);
      expect((await local.store.snapshot()).pendingUploadIds, isEmpty);
    },
  );
  test(
    'real import preserves selection, collision evidence and root-only unlock',
    () async {
      final h = await LedgerHarness.create();
      try {
        final before = h.repo.currentLedgerId;
        final genesis = await local.seal(
          batch(90, [
            Mutation(
              EntityRef(EntityKind.ledgerConfig, id(1)),
              [],
              LedgerConfig(id(1), 'UTC'),
            ),
          ]),
        );
        final first = await local.seal(base);
        final competing = await local.seal(
          batch(100, [Mutation(sRef, [], sub('collision'))]),
        );
        await h.repo.importLedger(local.bundle.metadata, local.bundle.keys, [
          genesis,
          first,
          competing,
        ]);
        expect(h.repo.currentLedgerId, before);
        expect(await h.repo.listLedgers(), hasLength(2));
        expect(
          await h.vault.get(LedgerRepository.recoveryKeyName(id(1))),
          isNull,
        );
        await h.repo.selectLedger(id(1));
        expect((await h.repo.snapshot()).quarantinedObjects, hasLength(2));
        await h.repo.authenticatedKeys();
        await h.repo.importLedger(local.bundle.metadata, local.bundle.keys, [
          genesis,
          first,
          competing,
        ]);
        expect(await h.repo.store.objects(), hasLength(2));
      } finally {
        await h.close();
      }
    },
  );
  test(
    'failed import retries same orphan keys without replacing existing ledger',
    () async {
      final h = await LedgerHarness.create();
      final backend = FakeVault();
      final vault = KeyVault(storage: backend);
      final repo = LedgerRepository(h.db, vault, id(30));
      try {
        final genesis = await local.seal(
          batch(90, [
            Mutation(
              EntityRef(EntityKind.ledgerConfig, id(1)),
              [],
              LedgerConfig(id(1), 'UTC'),
            ),
          ]),
        );
        backend.failAt = 2;
        await expectLater(
          repo.importLedger(local.bundle.metadata, local.bundle.keys, [
            genesis,
          ], recovery: local.bundle.recovery),
          throwsA(isA<EchoFailure>()),
        );
        expect((await repo.listLedgers()).contains(id(1)), false);
        final rootBefore = await vault.get(LedgerRepository.rootKeyName(id(1)));
        expect(rootBefore != null, true);
        backend.failAt = null;
        await repo.importLedger(local.bundle.metadata, local.bundle.keys, [
          genesis,
        ], recovery: local.bundle.recovery);
        expect(
          (await vault.get(LedgerRepository.rootKeyName(id(1))))!.join(',') ==
              rootBefore!.join(','),
          true,
        );
        await vault.put(LedgerRepository.rootKeyName(id(1)), secureBytes(32));
        final wrongBefore = await vault.get(
          LedgerRepository.rootKeyName(id(1)),
        );
        await expectLater(
          repo.importLedger(local.bundle.metadata, local.bundle.keys, [
            genesis,
          ]),
          throwsA(isA<EchoFailure>()),
        );
        expect(
          (await vault.get(LedgerRepository.rootKeyName(id(1))))!.join(',') ==
              wrongBefore!.join(','),
          true,
        );
      } finally {
        await h.close();
      }
    },
  );
  test(
    'incomplete and unauthenticated joins never create an empty remote ledger',
    () async {
      final h = await LedgerHarness.create();
      try {
        final before = await h.repo.listLedgers();
        await expectLater(
          h.repo.importLedger(local.bundle.metadata, local.bundle.keys, []),
          throwsA(isA<EchoFailure>()),
        );
        await expectLater(
          h.repo.importLedger(local.bundle.metadata, local.bundle.keys, [
            await local.seal(a),
          ]),
          throwsA(isA<EchoFailure>()),
        );
        final services = AppServices(ledger: h.repo);
        await services.ready;
        try {
          await expectLater(
            services.syncRuntime.joinDav(
              Uri.parse('https://127.0.0.1:1/dedicated/${id(1)}/'),
              const DavCredentials('fictional', 'unused'),
              local.bundle.recovery,
              Token(),
            ),
            throwsA(isA<EchoFailure>()),
          );
        } finally {
          services.dispose();
        }
        expect(await h.repo.listLedgers(), before);
        expect(await h.vault.get(LedgerRepository.rootKeyName(id(1))), isNull);
      } finally {
        await h.close();
      }
    },
  );
  test('stale renewal transaction rejects without adding payment', () async {
    final h = await LedgerHarness.create();
    final services = AppServices(ledger: h.repo);
    await services.ready;
    try {
      await services.saveSubscription(sub('base'));
      final state = await h.repo.snapshot();
      await services.saveSubscription(sub('remote'));
      await expectLater(
        services.renew(
          sub('stale'),
          payment(paRef),
          expectedLedgerId: state.metadata.id,
          baseParents: state.causal.parentsFor(sRef),
        ),
        throwsA(isA<EchoFailure>()),
      );
      expect(services.payments, isEmpty);
      expect(
        (await h.repo.snapshot()).projection.entities[sRef],
        sub('remote'),
      );
      final another = await createLedgerBundle(id(777));
      await h.repo.create(LedgerConfig(id(777), 'UTC'), another);
      await services.selectLedger(id(777));
      await expectLater(
        services.saveSubscription(
          sub('old form'),
          expectedLedgerId: state.metadata.id,
          baseParents: state.causal.parentsFor(sRef),
        ),
        throwsA(isA<EchoFailure>()),
      );
      expect(services.subscriptions, isEmpty);
    } finally {
      services.dispose();
      await h.close();
    }
  });
}

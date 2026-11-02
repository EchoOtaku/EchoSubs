import 'package:flutter_test/flutter_test.dart';
import 'package:echo_subs/features/sync/transports/webdav_transport.dart';
import 'dart:async';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:echo_subs/core/crypto/ledger_metadata.dart';
import 'package:echo_subs/core/model/errors.dart';
import 'package:echo_subs/storage/ledger_store.dart';
import '../support/fake_dav_server.dart';

class Token implements CancellationToken {
  @override
  bool isCancelled = false;
}

const ledger = FakeDavServer.ledger;
const batch = '22222222222222222222222222222222';
const credentials = DavCredentials('fictional', 'never-log-me');
final failure = isA<EchoFailure>();
Matcher failureCode(String code) =>
    isA<EchoFailure>().having((e) => e.code, 'code', code);
Future<StoredObject> object([List<int> data = const [1, 2, 3]]) async {
  final bytes = Uint8List.fromList(data);
  final digest = (await Sha256().hash(
    bytes,
  )).bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  return StoredObject(batch, ledger, digest, bytes);
}

void main() {
  late FakeDavServer fake;
  late WebDavTransport dav;
  setUp(() async {
    fake = await FakeDavServer.start();
    dav = WebDavTransport(
      root: fake.root,
      ledgerId: ledger,
      credentials: credentials,
      clientFactory: fake.client,
    );
  });
  tearDown(() async {
    await dav.close();
    await fake.close();
  });
  test('rejects plaintext endpoints before connecting', () {
    expect(
      () => WebDavTransport(
        root: Uri.parse('http://localhost/app/'),
        ledgerId: '11111111111111111111111111111111',
        credentials: const DavCredentials('fictional', 'secret'),
      ),
      throwsA(anything),
    );
  });
  test(
    'HTTPS conditional immutable object and Depth=1 listing round trip',
    () async {
      final a = await object();
      await dav.put(a);
      await dav.put(a);
      expect(fake.successfulObjectWrites, 1);
      final refs = await dav.listObjects(Token()).toList();
      expect(refs, hasLength(1));
      expect((await dav.read(refs.single)).bytes, a.bytes);
      expect(fake.deletes, hasLength(1));
      expect(fake.deletes.single, contains('/.echosubs-probe-'));
      expect(fake.requestsOutsideLedgerRoot, isEmpty);
      expect(
        () => dav.put(StoredObject(batch, ledger, '0' * 64, a.bytes)),
        throwsA(failure),
      );
      expect(fake.successfulObjectWrites, 1);
    },
  );
  test('metadata immutability and explicit ledgerRoot probe', () async {
    final meta = (await createLedgerBundle(ledger)).metadata;
    await dav.publishMetadata(meta);
    await dav.publishMetadata(meta);
    expect((await dav.readMetadata()).encode(), meta.encode());
    expect(
      (await WebDavTransport.probeMetadata(
        dav.ledgerRoot,
        credentials,
        clientFactory: fake.client,
      )).id,
      ledger,
    );
    final other = (await createLedgerBundle(ledger)).metadata;
    await expectLater(dav.publishMetadata(other), throwsA(failure));
    expect((await dav.readMetadata()).encode(), meta.encode());
    expect(fake.requestsOutsideLedgerRoot, isEmpty);
  });
  test('412 object different bytes fails without overwriting', () async {
    final a = await object();
    await dav.put(a);
    fake.files['${fake.scope}objects/$batch-${a.sha256}.bin'] = [9];
    await expectLater(dav.put(a), throwsA(failureCode('integrity')));
    expect(fake.successfulObjectWrites, 1);
  });
  test(
    'partial upload cannot be mistaken for acknowledged immutable object',
    () async {
      fake.partialPut = true;
      await expectLater(dav.put(await object()), throwsA(failure));
      expect(fake.successfulObjectWrites, 0);
      expect(fake.files.values.single, [1]);
      expect(fake.requestsOutsideLedgerRoot, isEmpty);
    },
  );
  test('same batch multiple digests retained for engine quarantine', () async {
    await dav.put(await object());
    await dav.put(await object([4, 5, 6]));
    final refs = await dav.listObjects(Token()).toList();
    expect(refs, hasLength(2));
    expect(refs.map((r) => r.batchId).toSet(), {batch});
    expect(refs.map((r) => r.sha256).toSet(), hasLength(2));
  });
  test(
    'lying conditional server disables writes and cleans only its probe',
    () async {
      fake.lieAboutConditional = true;
      await expectLater(dav.put(await object()), throwsA(failure));
      final count = fake.requests.length;
      await expectLater(dav.put(await object()), throwsA(failure));
      expect(fake.requests.length, count);
      expect(fake.successfulObjectWrites, 0);
      expect(fake.deletes, hasLength(1));
      expect(fake.files, isEmpty);
    },
  );
  for (final status in [401, 403, 507, 302, 307, 404, 409, 500]) {
    test(
      'HTTP $status contract code and bounded retry without redirect',
      () async {
        fake.forcedStatus = status;
        final code = switch (status) {
          401 || 403 => 'authentication',
          507 || 404 || 500 => 'unavailable',
          409 => 'conflict',
          _ => 'incompatible',
        };
        await expectLater(dav.readMetadata(), throwsA(failureCode(code)));
        expect(fake.requests, hasLength(status == 500 ? 3 : 1));
      },
    );
  }
  for (final status in [401, 507, 404, 409, 302, 500]) {
    test(
      'HTTP $status codes propagate through probe read put publish',
      () async {
        fake.forcedStatus = status;
        final code = switch (status) {
          401 => 'authentication',
          507 || 404 || 500 => 'unavailable',
          409 => 'conflict',
          _ => 'incompatible',
        };
        final a = await object();
        final ref = ObjectRef(
          batch,
          a.sha256,
          'objects/$batch-${a.sha256}.bin',
        );
        final metadata = (await createLedgerBundle(ledger)).metadata;
        await expectLater(
          WebDavTransport.probeMetadata(
            dav.ledgerRoot,
            credentials,
            clientFactory: fake.client,
          ),
          throwsA(failureCode(code)),
        );
        await expectLater(dav.read(ref), throwsA(failureCode(code)));
        await expectLater(dav.put(a), throwsA(failureCode(code)));
        final publisher = WebDavTransport(
          root: fake.root,
          ledgerId: ledger,
          credentials: credentials,
          clientFactory: fake.client,
        );
        try {
          await expectLater(
            publisher.publishMetadata(metadata),
            throwsA(failureCode(code)),
          );
        } finally {
          await publisher.close();
        }
        expect(fake.requests, hasLength(status == 500 ? 12 : 4));
      },
    );
  }
  test('untrusted TLS certificate rejected', () async {
    final untrusted = WebDavTransport(
      root: fake.root,
      ledgerId: ledger,
      credentials: credentials,
    );
    try {
      await expectLater(
        untrusted.readMetadata(),
        throwsA(failureCode('authentication')),
      );
      expect(fake.requests, isEmpty);
    } finally {
      await untrusted.close();
    }
  });
  test(
    'TLS authentication code propagates through probe read put publish without retry',
    () async {
      final retries = <int>[];
      final untrusted = WebDavTransport(
        root: fake.root,
        ledgerId: ledger,
        credentials: credentials,
        onRetry: retries.add,
      );
      final a = await object();
      final ref = ObjectRef(batch, a.sha256, 'objects/$batch-${a.sha256}.bin');
      final metadata = (await createLedgerBundle(ledger)).metadata;
      try {
        await expectLater(
          WebDavTransport.probeMetadata(dav.ledgerRoot, credentials),
          throwsA(failureCode('authentication')),
        );
        await expectLater(
          untrusted.read(ref),
          throwsA(failureCode('authentication')),
        );
        await expectLater(
          untrusted.put(a),
          throwsA(failureCode('authentication')),
        );
        await expectLater(
          untrusted.publishMetadata(metadata),
          throwsA(failureCode('authentication')),
        );
        expect(retries, isEmpty);
        expect(fake.requests, isEmpty);
      } finally {
        await untrusted.close();
      }
    },
  );
  for (final href in [
    'https://elsewhere.invalid/no',
    '/outside.bin',
    '${'/dedicated/$ledger/objects/'}%252e%252e/file',
    '/dedicated/$ledger/objects/%2e%2e/file',
    '/dedicated/$ledger/objects/nested/other.bin',
    '/dedicated/$ledger/objects/%2fescape.bin',
  ]) {
    test('rejects unsafe href $href before GET', () async {
      fake.listing = FakeDavServer.multistatus([FakeDavServer.item(href)]);
      await expectLater(dav.listObjects(Token()).toList(), throwsA(failure));
      expect(fake.requests.every((r) => r.startsWith('PROPFIND ')), isTrue);
    });
  }
  test('207 child 403 fails listing', () async {
    fake.listing = FakeDavServer.multistatus([
      FakeDavServer.item('${fake.scope}objects/', status: 403),
    ]);
    await expectLater(dav.listObjects(Token()).toList(), throwsA(failure));
  });
  test('DTD and oversize XML rejected', () async {
    fake.listing = '<!DOCTYPE x [<!ENTITY y SYSTEM "file:///secret">]><x/>';
    await expectLater(dav.listObjects(Token()).toList(), throwsA(failure));
    fake.listing = 'x' * (10 * 1024 * 1024 + 1);
    await expectLater(dav.listObjects(Token()).toList(), throwsA(failure));
  });
  test('wrong digest, oversized and partial objects rejected', () async {
    final a = await object();
    await dav.put(a);
    final ref = (await dav.listObjects(Token()).toList()).single;
    fake.files['${fake.scope}${ref.relativePath}'] = [9];
    await expectLater(dav.read(ref), throwsA(failure));
    fake.files['${fake.scope}${ref.relativePath}'] = List.filled(
      1024 * 1024 + 1,
      1,
    );
    await expectLater(dav.read(ref), throwsA(failure));
    fake.files['${fake.scope}${ref.relativePath}'] = a.bytes;
    fake.partialGet = true;
    await expectLater(dav.read(ref), throwsA(failure));
  });
  test('transient errors retry twice and report progress', () async {
    final progress = <int>[];
    final retrying = WebDavTransport(
      root: fake.root,
      ledgerId: ledger,
      credentials: credentials,
      clientFactory: fake.client,
      onRetry: progress.add,
    );
    try {
      fake.transientFailures = 3;
      await expectLater(retrying.readMetadata(), throwsA(failure));
      expect(progress, [1, 2]);
      expect(fake.requests, hasLength(3));
    } finally {
      await retrying.close();
    }
  });
  test('cancel stalled response closes transfer promptly', () async {
    fake.stallListing = true;
    final token = Token();
    final timer = Timer(
      const Duration(milliseconds: 150),
      () => token.isCancelled = true,
    );
    try {
      await expectLater(
        dav.listObjects(token).toList().timeout(const Duration(seconds: 2)),
        throwsA(isA<EchoFailure>().having((e) => e.code, 'code', 'cancelled')),
      );
    } finally {
      timer.cancel();
    }
  });
  test('pre-cancelled request and forged ref do not connect', () async {
    await expectLater(
      dav.listObjects(Token()..isCancelled = true).toList(),
      throwsA(failure),
    );
    final a = await object();
    await expectLater(
      dav.read(ObjectRef(batch, a.sha256, '../outside')),
      throwsA(failure),
    );
    expect(fake.requests, isEmpty);
  });
}

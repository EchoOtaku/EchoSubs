import 'package:echo_subs/core/model/errors.dart';
import 'dart:convert';
import 'package:bonsoir/bonsoir.dart';
import 'package:echo_subs/core/model/change_batch.dart';
import 'package:echo_subs/features/sync/transports/lan_discovery.dart';
import 'package:echo_subs/features/sync/transports/lan_identity.dart';
import 'package:echo_subs/features/sync/transports/lan_server.dart';
import 'package:echo_subs/features/sync/transports/lan_pairing.dart';
import 'package:echo_subs/features/sync/transports/lan_transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'lan_pairing_test.dart' show LanFixture, Token;
import 'sync_fixture.dart';

void main() {
  late LanFixture f;
  setUp(() async {
    f = await LanFixture.create();
  });
  tearDown(() async {
    await f.close();
  });
  test(
    'approved TLS connection exchanges immutable objects in both directions; revoke denies all reads',
    () async {
      final peer = await f.guestPairing.join(await f.offer());
      final transport = LanTransport(
        peer: peer,
        localDeviceId: id(3),
        peers: f.guests,
      );
      try {
        expect((await transport.readMetadata()).id, id(1));
        final first = (await transport.listObjects(Token()).toList()).single;
        expect(
          (await transport.read(first)).bytes,
          (await f.data.store.objects()).single.bytes,
        );
        final upload = await f.data.seal(a);
        await transport.put(upload);
        expect(
          (await f.data.store.objects()).map((o) => o.sha256),
          contains(upload.sha256),
        );
        await f.hosts.revoke(id(1), id(3));
        await expectLater(
          transport.listObjects(Token()).toList(),
          throwsA(isA<EchoFailure>()),
        );
        await expectLater(
          transport.readMetadata(),
          throwsA(isA<EchoFailure>()),
        );
      } finally {
        await transport.close();
      }
    },
  );
  test(
    'fingerprint mismatch and wrong DNS identity fail before approval',
    () async {
      final offer = await f.offer();
      final map = offer.toJson();
      map['fingerprint'] = '0' * 64;
      await expectLater(
        Future(() => f.guestPairing.join(PairingOffer.fromJson(map))),
        throwsA(isA<EchoFailure>()),
      );
      final wrongDns = offer.toJson()..['dnsName'] = 'wrong.echosubs.invalid';
      await expectLater(
        Future(() => f.guestPairing.join(PairingOffer.fromJson(wrongDns))),
        throwsA(isA<EchoFailure>()),
      );
      expect(await f.hosts.approvedPeerCount(id(1)), 0);
    },
  );
  test(
    'native TLS refuses a different pinned certificate before pairing credentials',
    () async {
      final offer = await f.offer();
      final map = offer.toJson()..addAll(f.guest.certificate.toJson());
      await expectLater(
        f.guestPairing.join(PairingOffer.fromJson(map)),
        throwsA(
          isA<EchoFailure>().having((e) => e.code, 'code', 'authentication'),
        ),
      );
      expect(await f.hosts.approvedPeerCount(id(1)), 0);
    },
  );
  test(
    'expired and not-yet-valid certificates are rejected without rotation',
    () async {
      await expectLater(
        f.host.certificate.validate(
          now: DateTime.now().add(const Duration(days: 400)),
        ),
        throwsA(isA<EchoFailure>()),
      );
      await expectLater(
        f.host.certificate.validate(
          now: DateTime.now().subtract(const Duration(days: 1)),
        ),
        throwsA(isA<EchoFailure>()),
      );
      final mismatched = LanCertificate(
        id(3),
        f.host.certificate.der,
        f.host.certificate.fingerprint,
      );
      await expectLater(mismatched.validate(), throwsA(isA<EchoFailure>()));
    },
  );
  test(
    'unpaired and cross-ledger requests never read metadata or object names',
    () async {
      final offer = await f.offer();
      final http = LanHttp(f.host.certificate, offer.address, offer.port);
      try {
        for (final route in [
          'objects',
          'ledger.json',
          'objects/${base.id}-${'0' * 64}.bin',
        ]) {
          await expectLater(
            http.request('GET', '/ledger/${id(1)}/$route'),
            throwsA(isA<EchoFailure>()),
          );
        }
        final map = offer.toJson()..['ledgerId'] = id(99);
        await expectLater(
          f.guestPairing.join(PairingOffer.fromJson(map)),
          throwsA(isA<EchoFailure>()),
        );
        final peer = await f.guestPairing.join(offer);
        final token = await f.guests.token(peer, inbound: false);
        await expectLater(
          http.request(
            'GET',
            '/ledger/${id(99)}/objects',
            headers: {
              'Authorization': 'Bearer ${base64Encode(token)}',
              'X-Echo-Device': id(3),
            },
          ),
          throwsA(isA<EchoFailure>()),
        );
      } finally {
        http.close();
      }
    },
  );
  test(
    'all authenticated collision evidence is addressable by id and digest',
    () async {
      final collision = await f.data.seal(
        batch(100, [Mutation(sRef, [], sub('collision'))]),
      );
      await f.data.engine.ingest(collision);
      final peer = await f.guestPairing.join(await f.offer());
      final transport = LanTransport(
        peer: peer,
        localDeviceId: id(3),
        peers: f.guests,
      );
      try {
        final refs = await transport.listObjects(Token()).toList();
        expect(refs, hasLength(2));
        expect(refs.map((r) => r.batchId).toSet(), {base.id});
        expect(refs.map((r) => r.sha256).toSet(), hasLength(2));
        for (final ref in refs) {
          expect((await transport.read(ref)).sha256, ref.sha256);
        }
        await expectLater(
          transport.read(
            ObjectRef(base.id, collision.sha256, '../ledger.json'),
          ),
          throwsA(isA<EchoFailure>()),
        );
        final token = Token()..isCancelled = true;
        await expectLater(
          transport.listObjects(token).toList(),
          throwsA(isA<EchoFailure>()),
        );
      } finally {
        await transport.close();
      }
    },
  );
  test(
    'forged mDNS hint cannot alter certificate pin and verified hints reconnect',
    () async {
      final peer = await f.guestPairing.join(await f.offer());
      final wrong = BonsoirService(
        name: 'forged',
        type: LanDiscovery.serviceType,
        port: f.server.port,
        hostAddresses: ['127.0.0.1'],
        attributes: {'device': id(4), 'version': '1'},
      );
      await expectLater(
        LanDiscovery.connect(wrong, peer, f.guests),
        throwsA(isA<EchoFailure>()),
      );
      final correct = BonsoirService(
        name: 'hint',
        type: LanDiscovery.serviceType,
        port: f.server.port,
        hostAddresses: ['127.0.0.1'],
        attributes: {'device': id(2), 'version': '1'},
      );
      final transport = await LanDiscovery.connect(correct, peer, f.guests);
      try {
        expect((await transport.readMetadata()).id, id(1));
      } finally {
        await transport.close();
      }
    },
  );
  test(
    'background/disabled state closes listener and pending offers',
    () async {
      final offer = await f.offer();
      await f.server.start(enabled: true, foreground: false);
      expect(f.server.isListening, false);
      await expectLater(
        f.guestPairing.join(offer),
        throwsA(isA<EchoFailure>()),
      );
    },
  );
  test(
    'close racing startup cannot leave a late foreground listener',
    () async {
      final pairing = PairingService(
        identity: f.host,
        peers: f.hosts,
        confirm: (_) async => true,
      );
      final server = LanServer(
        identity: f.host,
        peers: f.hosts,
        pairing: pairing,
        access: LanLedgerAccess(f.data.store, (_) async {}),
      );
      final start = server
          .start(enabled: true, foreground: true)
          .then<Object?>((_) => null, onError: (Object error) => error);
      await server.close();
      final error = await start;
      expect(error == null || error is EchoFailure, true);
      try {
        expect(server.isListening, false);
      } finally {
        await server.close();
      }
    },
  );
}

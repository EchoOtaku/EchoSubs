import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:echo_subs/core/crypto/envelope_codec.dart';
import 'package:echo_subs/core/crypto/ledger_keys.dart';
import 'package:echo_subs/core/crypto/ledger_metadata.dart';
import 'package:echo_subs/core/model/change_batch.dart';
import 'package:echo_subs/core/model/ledger.dart';
import 'package:echo_subs/core/model/errors.dart';
import 'package:echo_subs/core/model/subscription.dart';

const ledger = '11111111111111111111111111111111';
final batch = ChangeBatch(
  id: '22222222222222222222222222222222',
  ledgerId: ledger,
  deviceId: '33333333333333333333333333333333',
  createdAtUtc: DateTime.utc(2026),
  mutations: [
    Mutation(
      EntityRef(EntityKind.category, '44444444444444444444444444444444'),
      [],
      Category('44444444444444444444444444444444', 'fictional-private-name'),
    ),
  ],
);
Uint8List change(Uint8List bytes, void Function(Map<String, dynamic>) edit) {
  final map = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  edit(map);
  return Uint8List.fromList(utf8.encode(canonicalJson(map)));
}

Uint8List flipCiphertextBit(Uint8List bytes) => change(bytes, (map) {
  final data = base64Decode(map['ciphertext'] as String);
  data[0] ^= 1;
  map['ciphertext'] = base64Encode(data);
});
void main() {
  final codec = EnvelopeCodec();
  test('round trip, independent random seals, defensive key copies', () async {
    final source = Uint8List(32);
    final keys = LedgerKeys(ledger, source);
    source[0] = 9;
    keys.rootKey[0] = 8;
    expect(keys.rootKey[0], 0);
    final first = await codec.seal(batch, keys);
    final second = await codec.seal(batch, keys);
    expect(first, isNot(second));
    expect(await codec.open(first, keys), batch);
    expect((await codec.open(first, keys)).mutations, batch.mutations);
    expect(utf8.decode(first), isNot(contains('fictional-private-name')));
  });
  test(
    'authenticated headers, ciphertext, tag and wrong key fail safely',
    () async {
      final keys = LedgerKeys(ledger, Uint8List(32));
      final bytes = await codec.seal(batch, keys);
      for (final corrupted in [
        flipCiphertextBit(bytes),
        change(
          bytes,
          (m) => m['ledgerId'] = '55555555555555555555555555555555',
        ),
        change(bytes, (m) => m['batchId'] = '55555555555555555555555555555555'),
        change(bytes, (m) => m['tag'] = base64Encode(Uint8List(16))),
        change(bytes, (m) => m['purpose'] = 'backup'),
      ]) {
        await expectLater(
          codec.open(corrupted, keys),
          throwsA(isA<EchoFailure>()),
        );
      }
      await expectLater(
        codec.open(
          bytes,
          LedgerKeys(ledger, Uint8List.fromList(List.filled(32, 1))),
        ),
        throwsA(isA<EchoFailure>()),
      );
      await expectLater(
        codec.open(change(bytes, (m) => m['version'] = 2), keys),
        throwsA(
          isA<EchoFailure>().having((e) => e.code, 'code', 'incompatible'),
        ),
      );
    },
  );
  test(
    'reject malformed, duplicate, noncanonical and oversized objects',
    () async {
      final keys = LedgerKeys(ledger, Uint8List(32));
      final bytes = await codec.seal(batch, keys);
      for (final text in [
        '{"version":1,"version":1}',
        ' ${utf8.decode(bytes)}',
        utf8.decode(bytes).replaceFirst('"version":1', '"version":1.0'),
        '{"x":NaN}',
      ]) {
        await expectLater(
          codec.open(Uint8List.fromList(utf8.encode(text)), keys),
          throwsA(isA<EchoFailure>()),
        );
      }
      await expectLater(
        codec.open(Uint8List(1048577), keys),
        throwsA(isA<EchoFailure>()),
      );
      await expectLater(
        codec.open(change(bytes, (m) => m['purpose'] = 'unknown'), keys),
        throwsA(isA<EchoFailure>()),
      );
    },
  );
  test(
    'recover same root, reusable metadata and strict recovery format',
    () async {
      final bundle = await createLedgerBundle(ledger);
      final metadata = LedgerMetadata.decode(bundle.metadata.encode());
      expect(
        (await unwrapKeys(
          metadata,
          RecoveryCode.parse(bundle.recovery.encoded),
        )).rootKey,
        bundle.keys.rootKey,
      );
      expect(
        (await unwrapKeys(metadata, bundle.recovery)).rootKey,
        bundle.keys.rootKey,
      );
      await expectLater(
        unwrapKeys(metadata, RecoveryCode.generate()),
        throwsA(isA<EchoFailure>()),
      );
      expect(() => RecoveryCode.parse('password'), throwsA(isA<EchoFailure>()));
    },
  );
  test('fixed fictional interoperability vector', () async {
    final root = Uint8List.fromList(List.generate(32, (i) => i));
    final salt = Uint8List.fromList(List.generate(32, (i) => i + 64));
    final nonce = Uint8List.fromList(List.generate(12, (i) => i + 96));
    final key = await deriveCryptoKey(root, salt, 'sync', ledger);
    final box = await envelopeCipher.encrypt(
      canonicalBytes(batch.toJson()),
      secretKey: key,
      nonce: nonce,
      aad: cryptoAad('sync', ledger, batch.id),
    );
    final vector = canonicalJson({
      'key': base64Encode(await key.extractBytes()),
      'ciphertext': base64Encode(box.cipherText),
      'tag': base64Encode(box.mac.bytes),
    });
    expect(
      vector,
      '{"ciphertext":"WcqMKM5EOlqA1OCVMoQjJYDXIZzzh9k3ipeBKKJ4x/8MQHtMKr63cJB/+tVCNfGTce4gz/8+jKbzdIiK09pYhLN71uDbtf6OJji1LY8Mi5r0FW37bqqI6tE5wXeBuG0z7ccLAJBfJd60EH3wuRuTdTlbKtacBH7x9arv85EN04pswJy2pKrIqCoBh02UXuDqL+6rWlaCHmoJv2lg1DBchnaIZnP0Ep++baVdd1s/4EkJ2HUyJWNWQDpTvhIjGR50eu1sMtNCEhmxFeqgVoFN0BwVoH3jjiffQ4dDx8BcYhFjv+ZGRkqLQu5ttXyA5NCKsPNKtV42FC9NjqKYu7HLfXcsX8dEh52eFiuMnCLaDGVfPZ54eVl4Ahefz5ITEjtgv3lrbKHR1/eny49K+r6eDXGT01NmV46GQe2+hj0iBrroqdn2YrLnefo2kE0QVfjxhzl16whBdudVmctEMfIWTPVlbsajYoM=","key":"lfQt/d8trCf72D9ClOpDZESRF19gT5Q264yW6PZlk+Y=","tag":"lqWtw78WCysg+I4k19ZNwA=="}',
    );
    final envelope = canonicalBytes({
      'version': 1,
      'purpose': 'sync',
      'ledgerId': ledger,
      'batchId': batch.id,
      'salt': base64Encode(salt),
      'nonce': base64Encode(nonce),
      'ciphertext': base64Encode(box.cipherText),
      'tag': base64Encode(box.mac.bytes),
    });
    expect(await codec.open(envelope, LedgerKeys(ledger, root)), batch);
  });
  test(
    'authenticated malformed body and mismatched ids are rejected',
    () async {
      final keys = LedgerKeys(ledger, Uint8List(32));
      final salt = Uint8List(32);
      final nonce = Uint8List(12);
      final valid = canonicalJson(batch.toJson());
      for (final body in [
        valid.replaceFirst('"deviceId":', '"extra":1,"deviceId":'),
        valid.replaceFirst(
          '"deviceId":',
          '"deviceId":"${batch.deviceId}","deviceId":',
        ),
        valid.replaceFirst(batch.id, '55555555555555555555555555555555'),
        valid.replaceFirst('fictional-private-name', r'\ud800'),
        valid.replaceFirst('"parentBatchIds":[]', '"parentBatchIds":[1e999]'),
      ]) {
        final box = await envelopeCipher.encrypt(
          utf8.encode(body),
          secretKey: await deriveCryptoKey(keys.rootKey, salt, 'sync', ledger),
          nonce: nonce,
          aad: cryptoAad('sync', ledger, batch.id),
        );
        final encoded = canonicalBytes({
          'version': 1,
          'purpose': 'sync',
          'ledgerId': ledger,
          'batchId': batch.id,
          'salt': base64Encode(salt),
          'nonce': base64Encode(nonce),
          'tag': base64Encode(box.mac.bytes),
          'ciphertext': base64Encode(box.cipherText),
        });
        await expectLater(
          codec.open(encoded, keys),
          throwsA(isA<EchoFailure>()),
        );
      }
    },
  );
  test('UTF8, base64, field set, depth and note byte limits', () async {
    final keys = LedgerKeys(ledger, Uint8List(32));
    final encoded = await codec.seal(batch, keys);
    for (final bytes in [
      Uint8List.fromList([255]),
      change(encoded, (m) => m['extra'] = true),
      change(encoded, (m) => m['nonce'] = 'AA=='),
      change(encoded, (m) => m['salt'] = '${m['salt']}\n'),
      Uint8List.fromList(utf8.encode('${'[' * 65}0${']' * 65}')),
    ]) {
      await expectLater(codec.open(bytes, keys), throwsA(isA<EchoFailure>()));
    }
    ChangeBatch withNotes(String notes) => ChangeBatch(
      id: batch.id,
      ledgerId: ledger,
      deviceId: batch.deviceId,
      createdAtUtc: batch.createdAtUtc,
      mutations: [
        Mutation(
          EntityRef(
            EntityKind.subscription,
            '44444444444444444444444444444444',
          ),
          [],
          Subscription(
            id: '44444444444444444444444444444444',
            name: 'fake',
            notes: notes,
          ),
        ),
      ],
    );
    final boundary = withNotes('文' * 5461 + 'a');
    expect(await codec.open(await codec.seal(boundary, keys), keys), boundary);
    await expectLater(
      codec.seal(withNotes('文' * 5462), keys),
      throwsA(isA<EchoFailure>()),
    );
    final backup = EnvelopeCodec(purpose: 'backup');
    expect(await backup.open(await backup.seal(batch, keys), keys), batch);
    await expectLater(
      codec.open(await backup.seal(batch, keys), keys),
      throwsA(isA<EchoFailure>()),
    );
  });
  test(
    'metadata headers and copied bytes cannot alter persisted recovery',
    () async {
      final bundle = await createLedgerBundle(ledger);
      final metadata = bundle.metadata;
      metadata.salt[0] ^= 1;
      metadata.wrappedRoot[0] ^= 1;
      expect(
        (await unwrapKeys(metadata, bundle.recovery)).rootKey,
        bundle.keys.rootKey,
      );
      for (final edit in <void Function(Map<String, dynamic>)>[
        (m) => m['ledgerId'] = '55555555555555555555555555555555',
        (m) => m['tag'] = base64Encode(Uint8List(16)),
        (m) => m['salt'] = base64Encode(Uint8List(32)),
      ]) {
        final altered = LedgerMetadata.decode(change(metadata.encode(), edit));
        await expectLater(
          unwrapKeys(altered, bundle.recovery),
          throwsA(isA<EchoFailure>().having((e) => e.code, 'code', 'locked')),
        );
      }
    },
  );
}

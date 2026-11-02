import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import '../model/change_batch.dart';
import '../model/errors.dart';
import '../model/ids.dart';
import 'ledger_keys.dart';

const maxCryptoObjectBytes = 1048576;
const maxNoteBytes = 16384;
final envelopeCipher = AesGcm.with256bits();

String canonicalJson(Object? value) => canonicalModelJson(value);
Uint8List canonicalBytes(Object? value) =>
    Uint8List.fromList(utf8.encode(canonicalJson(value)));

/// Bounded parsing, exact canonical encoding also rejects duplicate JSON keys.
Map<String, dynamic> decodeCryptoObject(Uint8List bytes) =>
    decodeBoundedCryptoObject(bytes, maxBytes: maxCryptoObjectBytes);

/// Aggregate callers must explicitly choose their own limit; sync stays 1 MiB.
Map<String, dynamic> decodeBoundedCryptoObject(
  Uint8List bytes, {
  required int maxBytes,
}) => parseModel(() {
  if (maxBytes <= 0 || bytes.isEmpty || bytes.length > maxBytes) invalidModel();
  final text = utf8.decode(bytes, allowMalformed: false);
  var depth = 0;
  var quoted = false;
  var escaped = false;
  for (final unit in text.codeUnits) {
    if (quoted) {
      if (escaped) {
        escaped = false;
      } else if (unit == 92) {
        escaped = true;
      } else if (unit == 34) {
        quoted = false;
      }
    } else if (unit == 34) {
      quoted = true;
    } else if (unit == 123 || unit == 91) {
      if (++depth > 64) invalidModel();
    } else if (unit == 125 || unit == 93) {
      depth--;
    }
  }
  final value = jsonMap(jsonDecode(text));
  _validateJson(value);
  if (canonicalJson(value) != text) invalidModel();
  return value;
});

void _validateJson(Object? value) {
  if (value is double) invalidModel();
  if (value is String) {
    final units = value.codeUnits;
    for (var i = 0; i < units.length; i++) {
      final unit = units[i];
      if (unit >= 0xd800 && unit <= 0xdbff) {
        if (++i >= units.length || units[i] < 0xdc00 || units[i] > 0xdfff)
          invalidModel();
      } else if (unit >= 0xdc00 && unit <= 0xdfff) {
        invalidModel();
      }
    }
  }
  if (value is List) {
    for (final item in value) {
      _validateJson(item);
    }
  }
  if (value is Map) {
    for (final entry in value.entries) {
      _validateJson(entry.key);
      _validateJson(entry.value);
      if (entry.key == 'notes' &&
          entry.value is String &&
          utf8.encode(entry.value as String).length > maxNoteBytes)
        invalidModel();
    }
  }
}

void exactFields(Map<String, dynamic> map, List<String> names) {
  if (map.length != names.length || names.any((name) => !map.containsKey(name)))
    invalidModel();
}

Uint8List cryptoBase64(Object? value, {int? length}) => parseModel(() {
  final text = value as String;
  final bytes = base64Decode(text);
  if (base64Encode(bytes) != text || (length != null && bytes.length != length))
    invalidModel();
  return bytes;
});
void cryptoVersion(Object? version) {
  if (version is! int) invalidModel();
  if (version != 1) throw const EchoFailure('incompatible', '不支持的数据版本');
}

Uint8List cryptoAad(String purpose, String ledgerId, String batchId) =>
    canonicalBytes(['EchoSubs', 1, purpose, ledgerId, batchId]);
Future<SecretKey> deriveCryptoKey(
  Uint8List root,
  Uint8List salt,
  String purpose,
  String ledgerId,
) => Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
  secretKey: SecretKey(root),
  nonce: salt,
  info: canonicalBytes(['EchoSubs', 1, purpose, ledgerId]),
);

class EnvelopeCodec {
  EnvelopeCodec({this.purpose = 'sync'}) {
    if (purpose != 'sync' && purpose != 'backup') invalidModel();
  }
  final String purpose;
  Future<Uint8List> seal(ChangeBatch batch, LedgerKeys keys) async {
    if (batch.ledgerId != keys.ledgerId) invalidModel();
    final body = canonicalBytes(batch.toJson());
    decodeCryptoObject(body);
    final salt = secureBytes(32);
    final nonce = secureBytes(12);
    final box = await envelopeCipher.encrypt(
      body,
      secretKey: await deriveCryptoKey(
        keys.rootKey,
        salt,
        purpose,
        keys.ledgerId,
      ),
      nonce: nonce,
      aad: cryptoAad(purpose, keys.ledgerId, batch.id),
    );
    final bytes = canonicalBytes({
      'version': 1,
      'purpose': purpose,
      'ledgerId': keys.ledgerId,
      'batchId': batch.id,
      'salt': base64Encode(salt),
      'nonce': base64Encode(nonce),
      'ciphertext': base64Encode(box.cipherText),
      'tag': base64Encode(box.mac.bytes),
    });
    if (bytes.length > maxCryptoObjectBytes) invalidModel();
    return bytes;
  }

  Future<ChangeBatch> open(Uint8List bytes, LedgerKeys keys) async {
    try {
      final map = decodeCryptoObject(bytes);
      exactFields(map, [
        'version',
        'purpose',
        'ledgerId',
        'batchId',
        'salt',
        'nonce',
        'ciphertext',
        'tag',
      ]);
      cryptoVersion(map['version']);
      if (map['purpose'] != purpose)
        throw const EchoFailure('incompatible', '不支持的数据用途');
      final ledgerId = map['ledgerId'] as String;
      final batchId = map['batchId'] as String;
      validateId(ledgerId);
      validateId(batchId);
      if (ledgerId != keys.ledgerId)
        throw const EchoFailure('integrity', '账本标识不匹配');
      final salt = cryptoBase64(map['salt'], length: 32);
      final nonce = cryptoBase64(map['nonce'], length: 12);
      final tag = cryptoBase64(map['tag'], length: 16);
      final ciphertext = cryptoBase64(map['ciphertext']);
      if (ciphertext.isEmpty) invalidModel();
      final plaintext = await envelopeCipher.decrypt(
        SecretBox(ciphertext, nonce: nonce, mac: Mac(tag)),
        secretKey: await deriveCryptoKey(keys.rootKey, salt, purpose, ledgerId),
        aad: cryptoAad(purpose, ledgerId, batchId),
      );
      final body = decodeCryptoObject(Uint8List.fromList(plaintext));
      final batch = ChangeBatch.fromJson(body);
      if (batch.id != batchId ||
          batch.ledgerId != ledgerId ||
          canonicalJson(batch.toJson()) != canonicalJson(body))
        invalidModel();
      return batch;
    } on EchoFailure {
      rethrow;
    } on SecretBoxAuthenticationError {
      throw const EchoFailure('integrity', '数据认证失败');
    } on Object {
      throw const EchoFailure('validation', '加密对象无效');
    }
  }
}

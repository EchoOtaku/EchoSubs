import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import '../model/errors.dart';
import '../model/ids.dart';
import 'envelope_codec.dart';
import 'ledger_keys.dart';

/// Immutable persistent recovery object. All byte getters return copies.
class LedgerMetadata {
  LedgerMetadata._(
    this.id,
    this.version,
    this._salt,
    this._nonce,
    this._wrappedRoot,
    this._tag,
  );
  final LedgerId id;
  final int version;
  final Uint8List _salt, _nonce, _wrappedRoot, _tag;
  Uint8List get salt => Uint8List.fromList(_salt);
  Uint8List get nonce => Uint8List.fromList(_nonce);
  Uint8List get wrappedRoot => Uint8List.fromList(_wrappedRoot);
  Uint8List get tag => Uint8List.fromList(_tag);
  Map<String, Object?> toJson() => {
    'version': version,
    'purpose': 'wrapping',
    'ledgerId': id,
    'batchId': '',
    'salt': base64Encode(_salt),
    'nonce': base64Encode(_nonce),
    'wrappedRoot': base64Encode(_wrappedRoot),
    'tag': base64Encode(_tag),
  };
  Uint8List encode() => canonicalBytes(toJson());
  factory LedgerMetadata.decode(Uint8List bytes) =>
      LedgerMetadata.fromJson(decodeCryptoObject(bytes));
  factory LedgerMetadata.fromJson(Map<String, dynamic> json) => parseModel(() {
    final map = decodeCryptoObject(canonicalBytes(json));
    exactFields(map, [
      'version',
      'purpose',
      'ledgerId',
      'batchId',
      'salt',
      'nonce',
      'wrappedRoot',
      'tag',
    ]);
    cryptoVersion(map['version']);
    if (map['purpose'] != 'wrapping')
      throw const EchoFailure('incompatible', '不支持的数据用途');
    if (map['batchId'] != '') invalidModel();
    final id = map['ledgerId'] as String;
    validateId(id);
    return LedgerMetadata._(
      id,
      1,
      cryptoBase64(map['salt'], length: 32),
      cryptoBase64(map['nonce'], length: 12),
      cryptoBase64(map['wrappedRoot'], length: 32),
      cryptoBase64(map['tag'], length: 16),
    );
  });
}

class LedgerBundle {
  const LedgerBundle(this.keys, this.metadata, this.recovery);
  final LedgerKeys keys;
  final LedgerMetadata metadata;
  final RecoveryCode recovery;
}

Future<LedgerBundle> createLedgerBundle(LedgerId id) async {
  validateId(id);
  final keys = LedgerKeys(id, secureBytes(32));
  final recovery = RecoveryCode.generate();
  return LedgerBundle(keys, await wrapKeys(keys, recovery), recovery);
}

Future<LedgerMetadata> wrapKeys(LedgerKeys keys, RecoveryCode recovery) async {
  final salt = secureBytes(32);
  final nonce = secureBytes(12);
  final box = await envelopeCipher.encrypt(
    keys.rootKey,
    secretKey: await deriveCryptoKey(
      recovery.secret,
      salt,
      'wrapping',
      keys.ledgerId,
    ),
    nonce: nonce,
    aad: cryptoAad('wrapping', keys.ledgerId, ''),
  );
  return LedgerMetadata._(
    keys.ledgerId,
    1,
    salt,
    nonce,
    Uint8List.fromList(box.cipherText),
    Uint8List.fromList(box.mac.bytes),
  );
}

Future<LedgerKeys> unwrapKeys(
  LedgerMetadata metadata,
  RecoveryCode recovery,
) async {
  try {
    final root = await envelopeCipher.decrypt(
      SecretBox(
        metadata.wrappedRoot,
        nonce: metadata.nonce,
        mac: Mac(metadata.tag),
      ),
      secretKey: await deriveCryptoKey(
        recovery.secret,
        metadata.salt,
        'wrapping',
        metadata.id,
      ),
      aad: cryptoAad('wrapping', metadata.id, ''),
    );
    return LedgerKeys(metadata.id, Uint8List.fromList(root));
  } on Object {
    throw const EchoFailure('locked', '无法恢复账本密钥');
  }
}

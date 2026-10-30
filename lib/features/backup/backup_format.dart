import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import '../../core/crypto/envelope_codec.dart';
import '../../core/crypto/ledger_keys.dart';
import '../../core/crypto/ledger_metadata.dart';
import '../../core/model/errors.dart';
import '../../core/model/ids.dart';

const maxBackupBytes = 100 * 1024 * 1024;
const backupExtension = 'echosubsbackup';
const backupSuggestedName = '订阅账本.echosubsbackup';
const plainSuggestedName = '订阅账本.echosubs-plain.json';

class BackupArchive {
  BackupArchive(this.metadata, Iterable<Uint8List> objects)
    : _objects = objects.map(Uint8List.fromList).toList();
  final LedgerMetadata metadata;
  final List<Uint8List> _objects;
  List<Uint8List> get objects => _objects.map(Uint8List.fromList).toList();
}

/// V1 canonical JSON; the entire ordered archive is one AES-256-GCM message.
/// Original wrapping metadata remains immutable; paired root-only devices can
/// export without knowing or replacing the ledger's existing recovery secret.
class BackupFormat {
  static const purpose = 'backup-container';
  Map<String, Object?> _header(
    LedgerMetadata meta,
    String salt,
    String nonce,
  ) => {
    'version': 1,
    'purpose': purpose,
    'ledgerId': meta.id,
    'metadata': meta.toJson(),
    'salt': salt,
    'nonce': nonce,
  };
  Future<Uint8List> seal(BackupArchive archive, LedgerKeys keys) async {
    if (keys.ledgerId != archive.metadata.id) invalidModel();
    final objects = archive.objects;
    if (objects.isEmpty) invalidModel();
    for (final bytes in objects) {
      decodeCryptoObject(bytes);
    }
    final body = canonicalBytes({
      'objects': objects.map(base64Encode).toList(),
    });
    decodeBoundedCryptoObject(body, maxBytes: maxBackupBytes);
    final salt = secureBytes(32), nonce = secureBytes(12);
    final header = _header(
      archive.metadata,
      base64Encode(salt),
      base64Encode(nonce),
    );
    final box = await envelopeCipher.encrypt(
      body,
      secretKey: await deriveCryptoKey(
        keys.rootKey,
        salt,
        purpose,
        keys.ledgerId,
      ),
      nonce: nonce,
      aad: canonicalBytes(header),
    );
    final result = canonicalBytes({
      ...header,
      'ciphertext': base64Encode(box.cipherText),
      'tag': base64Encode(box.mac.bytes),
    });
    if (result.length > maxBackupBytes) {
      throw const EchoFailure('validation', '备份超过 100 MiB 上限');
    }
    return result;
  }

  Future<BackupArchive> open(Uint8List bytes, RecoveryCode recovery) async {
    try {
      final map = decodeBoundedCryptoObject(bytes, maxBytes: maxBackupBytes);
      exactFields(map, [
        'version',
        'purpose',
        'ledgerId',
        'metadata',
        'salt',
        'nonce',
        'ciphertext',
        'tag',
      ]);
      cryptoVersion(map['version']);
      if (map['purpose'] != purpose)
        throw const EchoFailure('incompatible', '不支持的备份格式');
      final meta = LedgerMetadata.fromJson(jsonMap(map['metadata']));
      if (map['ledgerId'] != meta.id)
        throw const EchoFailure('integrity', '备份账本标识不匹配');
      final salt = cryptoBase64(map['salt'], length: 32),
          nonce = cryptoBase64(map['nonce'], length: 12);
      final keys = await unwrapKeys(meta, recovery);
      final plain = await envelopeCipher.decrypt(
        SecretBox(
          cryptoBase64(map['ciphertext']),
          nonce: nonce,
          mac: Mac(cryptoBase64(map['tag'], length: 16)),
        ),
        secretKey: await deriveCryptoKey(keys.rootKey, salt, purpose, meta.id),
        aad: canonicalBytes(
          _header(meta, map['salt'] as String, map['nonce'] as String),
        ),
      );
      final body = decodeBoundedCryptoObject(
        Uint8List.fromList(plain),
        maxBytes: maxBackupBytes,
      );
      exactFields(body, ['objects']);
      final objects = jsonList(body['objects']).map(cryptoBase64).toList();
      if (objects.isEmpty) invalidModel();
      for (final object in objects) {
        decodeCryptoObject(object);
      }
      return BackupArchive(meta, objects);
    } on EchoFailure {
      rethrow;
    } on SecretBoxAuthenticationError {
      throw const EchoFailure('integrity', '备份完整性认证失败');
    } on Object {
      throw const EchoFailure('validation', '备份文件无效');
    }
  }
}

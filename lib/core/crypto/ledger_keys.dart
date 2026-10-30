import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import '../model/errors.dart';
import '../model/ids.dart';

/// Owns a defensive copy. Never include this object in diagnostics.
class LedgerKeys {
  LedgerKeys(this.ledgerId, Uint8List rootKey)
    : _rootKey = Uint8List.fromList(rootKey) {
    validateId(ledgerId);
    if (_rootKey.length != 32) throw const EchoFailure('locked', '账本密钥不可用');
  }
  final LedgerId ledgerId;
  final Uint8List _rootKey;
  Uint8List get rootKey => Uint8List.fromList(_rootKey);
}

Uint8List secureBytes(int length) {
  final random = Random.secure();
  return Uint8List.fromList(List.generate(length, (_) => random.nextInt(256)));
}

/// A random 256-bit secret, not a user-selected password or password KDF.
class RecoveryCode {
  RecoveryCode._(this._bytes);
  final Uint8List _bytes;
  factory RecoveryCode.generate() => RecoveryCode._(secureBytes(32));
  factory RecoveryCode.parse(String encoded) => parseModel(() {
    if (!RegExp(r'^ES1-[A-Za-z0-9_-]{43}$').hasMatch(encoded)) invalidModel();
    final bytes = base64Url.decode('${encoded.substring(4)}=');
    final code = RecoveryCode._(Uint8List.fromList(bytes));
    if (bytes.length != 32 || code.encoded != encoded) invalidModel();
    return code;
  });
  String get encoded => 'ES1-${base64Url.encode(_bytes).replaceAll('=', '')}';
  Uint8List get secret => Uint8List.fromList(_bytes);
}

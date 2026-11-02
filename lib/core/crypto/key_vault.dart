import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../model/errors.dart';

abstract interface class VaultStorage {
  Future<void> write(String name, String value);
  Future<String?> read(String name);
}

class SecureVaultStorage implements VaultStorage {
  SecureVaultStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _storage;
  @override
  Future<void> write(String name, String value) =>
      _storage.write(key: name, value: value);
  @override
  Future<String?> read(String name) => _storage.read(key: name);
}

class KeyVault {
  KeyVault({VaultStorage? storage})
    : _storage = storage ?? SecureVaultStorage();
  final VaultStorage _storage;
  String _name(String name) {
    if (!RegExp(r'^[A-Za-z0-9_.-]{1,128}$').hasMatch(name)) invalidModel();
    return 'echosubs.v1.$name';
  }

  Future<void> put(String name, Uint8List secret) async {
    final key = _name(name);
    if (secret.isEmpty || secret.length > 4096) invalidModel();
    final encoded = base64Encode(secret);
    try {
      await _storage.write(key, encoded);
    } on Object {
      throw const EchoFailure('unavailable', '安全存储写入失败');
    }
  }

  Future<Uint8List?> get(String name) async {
    final key = _name(name);
    try {
      final value = await _storage.read(key);
      if (value == null) return null;
      if (value.length > 5464) throw const FormatException();
      final secret = base64Decode(value);
      if (secret.isEmpty ||
          secret.length > 4096 ||
          base64Encode(secret) != value)
        throw const FormatException();
      return secret;
    } on Object {
      throw const EchoFailure('locked', '安全存储密钥不可用');
    }
  }
}

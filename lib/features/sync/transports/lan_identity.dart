import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:basic_utils/basic_utils.dart';
import 'package:cryptography/cryptography.dart';
import '../../../core/crypto/key_vault.dart';
import '../../../core/crypto/ledger_keys.dart';
import '../../../core/model/errors.dart';
import '../../../core/model/ids.dart';

const lanAuthentication = EchoFailure('authentication', '局域网设备认证失败，请重新确认配对');
const lanUnavailable = EchoFailure('unavailable', '局域网连接不可用，请检查应用及网络');

String certificatePem(List<int> der) =>
    '-----BEGIN CERTIFICATE-----\n${base64Encode(der)}\n-----END CERTIFICATE-----\n';
Future<String> lanDigest(List<int> bytes) async => (await Sha256().hash(
  bytes,
)).bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
bool lanEqual(List<int> a, List<int> b) {
  var diff = a.length ^ b.length;
  for (var i = 0; i < a.length && i < b.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

/// Public device identity. Endpoint addresses never replace this DNS identity.
class LanCertificate {
  LanCertificate(this.deviceId, Uint8List der, this.fingerprint)
    : _der = Uint8List.fromList(der) {
    validateId(deviceId);
    if (der.isEmpty ||
        der.length > 3072 ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(fingerprint))
      invalidModel();
  }
  final DeviceId deviceId;
  final Uint8List _der;
  final String fingerprint;
  String get dnsName => '$deviceId.echosubs.invalid';
  Uint8List get der => Uint8List.fromList(_der);
  String get pem => certificatePem(_der);
  Future<void> validate({DateTime? now}) async {
    try {
      final cert = X509Utils.x509CertificateFromPem(pem).tbsCertificate!;
      final time = (now ?? DateTime.now()).toUtc();
      if (await lanDigest(_der) != fingerprint ||
          !time.isBefore(cert.validity.notAfter) ||
          time.isBefore(cert.validity.notBefore) ||
          !(cert.extensions?.subjectAlternativNames ?? []).contains(dnsName) ||
          (cert.subjectPublicKeyInfo.length ?? 0) < 2048 ||
          !X509Utils.checkX509Signature(pem))
        throw lanAuthentication;
    } on Object {
      throw lanAuthentication;
    }
  }

  bool verify(Uint8List message, Uint8List signature) {
    try {
      final key = X509Utils.x509CertificateFromPem(
        pem,
      ).tbsCertificate!.subjectPublicKeyInfo;
      final der = Uint8List.fromList(
        List.generate(
          key.bytes!.length ~/ 2,
          (i) => int.parse(key.bytes!.substring(i * 2, i * 2 + 2), radix: 16),
        ),
      );
      return CryptoUtils.rsaVerify(
        CryptoUtils.rsaPublicKeyFromDERBytes(der),
        message,
        signature,
      );
    } on Object {
      return false;
    }
  }

  Map<String, Object?> toJson() => {
    'deviceId': deviceId,
    'dnsName': dnsName,
    'certificate': base64Encode(_der),
    'fingerprint': fingerprint,
  };
  factory LanCertificate.fromJson(Map<String, dynamic> map) => parseModel(() {
    final value = LanCertificate(
      map['deviceId'] as String,
      base64Decode(map['certificate'] as String),
      map['fingerprint'] as String,
    );
    if (map['dnsName'] != value.dnsName) throw lanAuthentication;
    return value;
  });
}

/// Stable app DeviceId is supplied by AppServices. Never silently rotates trust.
class LanIdentity {
  LanIdentity._(this.certificate, this.privateKeyRef, this._vault);
  final LanCertificate certificate;
  final String privateKeyRef;
  final KeyVault _vault;
  DeviceId get deviceId => certificate.deviceId;
  static Future<LanIdentity> loadOrCreate(
    KeyVault vault,
    DeviceId deviceId,
  ) async {
    validateId(deviceId);
    final keyName = 'lan.identity.$deviceId.key';
    final certName = 'lan.identity.$deviceId.cert';
    var der = await vault.get(certName);
    var key = await vault.get(keyName);
    if (der == null && key == null) {
      final pair = CryptoUtils.generateRSAKeyPair(keySize: 2048);
      final privateKey = pair.privateKey as RSAPrivateKey;
      final publicKey = pair.publicKey as RSAPublicKey;
      final dns = '$deviceId.echosubs.invalid';
      final csr = X509Utils.generateRsaCsrPem(
        {'CN': dns},
        privateKey,
        publicKey,
      );
      final pem = X509Utils.generateSelfSignedCertificate(
        privateKey,
        csr,
        365,
        sans: [dns],
        cA: true,
        serialNumber: BigInt.parse(newId(), radix: 16).toString(),
        notBefore: DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
      );
      der = base64Decode(
        pem
            .split('\n')
            .map((s) => s.trim())
            .where((s) => !s.startsWith('---'))
            .join(),
      );
      key = Uint8List.fromList(
        utf8.encode(CryptoUtils.encodeRSAPrivateKeyToPemPkcs1(privateKey)),
      );
      await vault.put(keyName, key);
      await vault.put(certName, der);
    }
    if (der == null || key == null)
      throw const EchoFailure('locked', '局域网设备身份不完整');
    final cert = LanCertificate(deviceId, der, await lanDigest(der));
    await cert.validate();
    final identity = LanIdentity._(cert, keyName, vault);
    final challenge = secureBytes(32);
    if (!cert.verify(challenge, await identity.sign(challenge)))
      throw lanAuthentication;
    return identity;
  }

  Future<Uint8List> sign(Uint8List message) async {
    final bytes = await _vault.get(privateKeyRef);
    if (bytes == null) throw const EchoFailure('locked', '局域网设备私钥不可用');
    try {
      return CryptoUtils.rsaSign(
        CryptoUtils.rsaPrivateKeyFromPemPkcs1(utf8.decode(bytes)),
        message,
      );
    } on Object {
      throw const EchoFailure('locked', '局域网设备私钥不可用');
    }
  }

  Future<SecurityContext> serverContext() async {
    await certificate.validate();
    final key = await _vault.get(privateKeyRef);
    if (key == null) throw const EchoFailure('locked', '局域网设备私钥不可用');
    return SecurityContext(withTrustedRoots: false)
      ..useCertificateChainBytes(utf8.encode(certificate.pem))
      ..usePrivateKeyBytes(key);
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import '../../../core/crypto/ledger_metadata.dart';
import '../../../core/model/errors.dart';
import '../../../core/model/ids.dart';
import '../../../storage/ledger_store.dart';
import 'lan_identity.dart';
import 'lan_pairing.dart';
import 'sync_transport.dart';
export 'sync_transport.dart';

void validateLanEndpoint(String host, int port) {
  final address = InternetAddress.tryParse(host);
  if (address == null || port < 1 || port > 65535) invalidModel();
  final b = address.rawAddress;
  final local =
      address.isLoopback ||
      address.isLinkLocal ||
      (b.length == 4
          ? b[0] == 10 ||
                (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
                (b[0] == 192 && b[1] == 168)
          : (b[0] & 0xfe) == 0xfc);
  if (!local) throw const EchoFailure('validation', '仅支持局域网地址');
}

String lanObjectPath(BatchId id, String digest) {
  validateId(id);
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(digest)) invalidModel();
  return 'objects/$id-$digest.bin';
}

ObjectRef lanObjectRef(String path) {
  final match = RegExp(
    r'^objects/([0-9a-f]{32})-([0-9a-f]{64})\.bin$',
  ).firstMatch(path);
  if (match == null) invalidModel();
  return ObjectRef(match[1]!, match[2]!, path);
}

Future<void> validateLanObject(StoredObject object, LedgerId ledger) async {
  lanObjectPath(object.batchId, object.sha256);
  if (object.ledgerId != ledger ||
      object.bytes.isEmpty ||
      object.bytes.length > 1024 * 1024 ||
      await lanDigest(object.bytes) != object.sha256)
    throw const EchoFailure('integrity', '局域网对象完整性验证失败');
}

Future<Uint8List> readLanBody(
  Stream<List<int>> stream,
  int contentLength, {
  int limit = 1024 * 1024,
}) async {
  if (contentLength > limit) throw const EchoFailure('integrity', '局域网数据超出限制');
  final builder = BytesBuilder(copy: false);
  await for (final bytes in stream) {
    if (builder.length + bytes.length > limit)
      throw const EchoFailure('integrity', '局域网数据超出限制');
    builder.add(bytes);
  }
  if (contentLength >= 0 && builder.length != contentLength)
    throw const EchoFailure('integrity', '局域网数据不完整');
  return builder.takeBytes();
}

/// Normal TLS hostname validation to <deviceId>.echosubs.invalid with one pinned
/// certificate trust root. connectionFactory only redirects the TCP destination.
/// Its socket is upgraded with the original DNS name and checked before HTTP
/// sends any headers/body. It never returns a raw socket for an HTTPS request.
class LanHttp {
  LanHttp(this.certificate, this.address, this.port) {
    validateLanEndpoint(address, port);
  }
  final LanCertificate certificate;
  final String address;
  final int port;
  final Set<HttpClient> _active = {};
  bool _closed = false;
  Future<Uint8List> request(
    String method,
    String path, {
    List<int>? body,
    Map<String, String> headers = const {},
    CancellationToken? cancellation,
    Duration budget = const Duration(seconds: 30),
    int limit = 1024 * 1024,
  }) async {
    if (_closed) throw lanUnavailable;
    if (cancellation?.isCancelled == true)
      throw const EchoFailure('cancelled', '局域网操作已取消');
    await certificate.validate();
    if (_closed) throw lanUnavailable;
    if (cancellation?.isCancelled == true)
      throw const EchoFailure('cancelled', '局域网操作已取消');
    final context = SecurityContext(withTrustedRoots: false)
      ..setTrustedCertificatesBytes(utf8.encode(certificate.pem));
    final client = HttpClient(context: context)
      ..connectionTimeout = const Duration(seconds: 10);
    client.findProxy = (_) => 'DIRECT';
    _active.add(client);
    final sockets = <Socket>{};
    var stopped = false;
    void stop() {
      if (stopped) return;
      stopped = true;
      client.close(force: true);
      for (final socket in sockets) {
        socket.destroy();
      }
    }

    client.connectionFactory = (uri, proxyHost, proxyPort) async {
      if (uri.host != certificate.dnsName ||
          uri.port != port ||
          uri.scheme != 'https' ||
          proxyHost != null)
        throw lanAuthentication;
      final task = await Socket.startConnect(address, port);
      final future = () async {
        final raw = await task.socket;
        sockets.add(raw);
        if (stopped) {
          raw.destroy();
          throw lanUnavailable;
        }
        final secure = await SecureSocket.secure(
          raw,
          host: certificate.dnsName,
          context: context,
        );
        sockets.add(secure);
        final cert = secure.peerCertificate;
        if (stopped ||
            cert == null ||
            await lanDigest(cert.der) != certificate.fingerprint ||
            !DateTime.now().isBefore(cert.endValidity) ||
            DateTime.now().isBefore(cert.startValidity)) {
          secure.destroy();
          throw lanAuthentication;
        }
        return secure;
      }();
      return ConnectionTask.fromSocket(future, () {
        task.cancel();
        stop();
      });
    };
    Timer? polling;
    final cancelled = Completer<Uint8List>();
    if (cancellation != null) {
      polling = Timer.periodic(const Duration(milliseconds: 20), (_) {
        if (cancellation.isCancelled && !cancelled.isCompleted) {
          cancelled.completeError(const EchoFailure('cancelled', '局域网操作已取消'));
          stop();
        }
      });
    }
    try {
      final operation = () async {
        final request = await client.openUrl(
          method,
          Uri(
            scheme: 'https',
            host: certificate.dnsName,
            port: port,
            path: path,
          ),
        );
        request.followRedirects = false;
        for (final entry in headers.entries) {
          request.headers.set(entry.key, entry.value);
        }
        if (body != null) {
          request.contentLength = body.length;
          request.add(body);
        }
        final response = await request.close();
        if (response.statusCode == 401 || response.statusCode == 403)
          throw lanAuthentication;
        if (response.statusCode == 409)
          throw const EchoFailure('conflict', '局域网对象冲突');
        if (response.statusCode != 200 && response.statusCode != 204)
          throw lanUnavailable;
        return readLanBody(response, response.contentLength, limit: limit);
      }();
      return await (cancellation == null
              ? operation
              : Future.any([operation, cancelled.future]))
          .timeout(budget);
    } on EchoFailure {
      rethrow;
    } on HandshakeException {
      throw lanAuthentication;
    } on TlsException {
      throw lanAuthentication;
    } on Object {
      if (cancellation?.isCancelled == true)
        throw const EchoFailure('cancelled', '局域网操作已取消');
      throw lanUnavailable;
    } finally {
      polling?.cancel();
      stop();
      _active.remove(client);
    }
  }

  Future<Map<String, dynamic>> json(
    String method,
    String path,
    Map<String, Object?> body, {
    CancellationToken? cancellation,
    Duration budget = const Duration(seconds: 30),
  }) async {
    final bytes = await request(
      method,
      path,
      body: utf8.encode(jsonEncode(body)),
      cancellation: cancellation,
      budget: budget,
      limit: 16384,
    );
    return parseModel(
      () => jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>,
    );
  }

  void close() {
    _closed = true;
    for (final client in _active) {
      client.close(force: true);
    }
    _active.clear();
  }
}

class LanTransport implements SyncTransport {
  LanTransport({
    required this.peer,
    required this.localDeviceId,
    required this.peers,
    String? address,
    int? port,
  }) : _http = LanHttp(
         peer.certificate,
         address ?? peer.address,
         port ?? peer.port,
       ) {
    if (localDeviceId != peer.localDeviceId) throw lanAuthentication;
  }
  final PairedPeer peer;
  final DeviceId localDeviceId;
  final LanPeerStore peers;
  final LanHttp _http;
  Future<Uint8List> _request(
    String method,
    String relative, {
    List<int>? body,
    CancellationToken? cancellation,
    int limit = 1024 * 1024,
  }) async {
    final token = await peers.token(peer, inbound: false);
    return _http.request(
      method,
      '/ledger/${peer.ledgerId}/$relative',
      body: body,
      cancellation: cancellation,
      limit: limit,
      headers: {
        'Authorization': 'Bearer ${base64Encode(token)}',
        'X-Echo-Device': localDeviceId,
      },
    );
  }

  @override
  Future<LedgerMetadata> readMetadata() async {
    final metadata = LedgerMetadata.decode(
      await _request('GET', 'ledger.json'),
    );
    if (metadata.id != peer.ledgerId) throw lanAuthentication;
    return metadata;
  }

  @override
  Future<void> publishMetadata(LedgerMetadata metadata) async {
    if (metadata.id != peer.ledgerId) throw lanAuthentication;
    await _request('PUT', 'ledger.json', body: metadata.encode());
  }

  @override
  Stream<ObjectRef> listObjects(CancellationToken token) async* {
    final bytes = await _request(
      'GET',
      'objects',
      cancellation: token,
      limit: 10 * 1024 * 1024,
    );
    final paths = parseModel(
      () => (jsonDecode(utf8.decode(bytes)) as List).cast<String>(),
    );
    if (paths.length > 100000 || paths.toSet().length != paths.length)
      invalidModel();
    final refs = paths.map(lanObjectRef).toList();
    for (final ref in refs) {
      if (token.isCancelled) throw const EchoFailure('cancelled', '局域网操作已取消');
      yield ref;
    }
  }

  @override
  Future<StoredObject> read(ObjectRef ref) async {
    if (ref.relativePath != lanObjectPath(ref.batchId, ref.sha256))
      invalidModel();
    final object = StoredObject(
      ref.batchId,
      peer.ledgerId,
      ref.sha256,
      await _request('GET', ref.relativePath),
    );
    await validateLanObject(object, peer.ledgerId);
    return object;
  }

  @override
  Future<void> put(StoredObject object) async {
    await validateLanObject(object, peer.ledgerId);
    await _request(
      'PUT',
      lanObjectPath(object.batchId, object.sha256),
      body: object.bytes,
    );
  }

  @override
  Future<void> close() async {
    _http.close();
  }
}

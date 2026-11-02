import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../../../core/crypto/ledger_metadata.dart';
import '../../../core/model/errors.dart';
import '../../../storage/ledger_store.dart';
import 'lan_identity.dart';
import 'lan_pairing.dart';
import 'lan_transport.dart';

/// Reads authenticated archives only; uploads are handed to the existing engine.
class LanLedgerAccess {
  LanLedgerAccess(this.store, this.onPut);
  final LedgerStore store;
  final Future<void> Function(StoredObject object) onPut;
  Future<Map<String, StoredObject>> objects() async {
    final all = [
      ...await store.objects(),
      ...(await store.quarantinedObjects()).map((q) => q.object),
    ];
    return {
      for (final object in all)
        lanObjectPath(object.batchId, object.sha256): object,
    };
  }
}

class LanServer {
  LanServer({
    required this.identity,
    required this.peers,
    required this.pairing,
    required this.access,
  });
  final LanIdentity identity;
  final LanPeerStore peers;
  final PairingService pairing;
  final LanLedgerAccess access;
  HttpServer? _server;
  bool _closed = false;
  Future<void>? _starting;
  int _pending = 0;
  int get port => _server?.port ?? (throw lanUnavailable);
  bool get isListening => _server != null;
  Future<void> start({
    required bool enabled,
    required bool foreground,
    InternetAddress? address,
    int port = 0,
  }) async {
    if (!enabled || !foreground) {
      await close();
      return;
    }
    if (_closed) throw lanUnavailable;
    if (_server != null) return;
    final running = _starting;
    if (running != null) return running;
    final operation = _listen(address, port);
    _starting = operation;
    try {
      await operation;
    } finally {
      _starting = null;
    }
  }

  Future<void> _listen(InternetAddress? address, int port) async {
    final context = await identity.serverContext();
    if (_closed) throw const EchoFailure('cancelled', '局域网服务已关闭');
    final server = await HttpServer.bindSecure(
      address ?? InternetAddress.anyIPv4,
      port,
      context,
    );
    if (_closed) {
      await server.close(force: true);
      throw const EchoFailure('cancelled', '局域网服务已关闭');
    }
    server.idleTimeout = const Duration(seconds: 10);
    _server = server;
    server.listen(
      (request) async {
        if (_pending >= 32) {
          request.response.statusCode = 503;
          await request.response.close();
          return;
        }
        _pending++;
        try {
          await _handle(request).timeout(const Duration(seconds: 125));
        } on Object catch (error) {
          // Never echo payloads, object paths, tokens, root keys or internal errors.
          request.response.statusCode =
              error is EchoFailure && error.code == 'conflict'
              ? 409
              : error is EchoFailure &&
                    (error.code == 'unavailable' || error.code == 'locked')
              ? 503
              : 403;
        } finally {
          try {
            await request.response.close();
          } on Object {
            /* Peer disconnected. */
          }
          _pending--;
        }
      },
      onError: (Object _) {
        /* Handshake failures never reach business routes. */
      },
    );
  }

  Future<void> _authorize(HttpRequest request) async {
    if (_server == null) throw lanUnavailable;
    final device = request.headers.value('X-Echo-Device');
    if (device == null) throw lanAuthentication;
    final peer = await peers.get(access.store.ledgerId, device);
    if (peer == null ||
        peer.localDeviceId != identity.deviceId ||
        peer.localFingerprint != identity.certificate.fingerprint)
      throw lanAuthentication;
    await peer.certificate.validate();
    await identity.certificate.validate();
    final token = await peers.token(peer, inbound: true);
    final auth = request.headers.value(HttpHeaders.authorizationHeader);
    if (auth == null ||
        !lanEqual(
          utf8.encode(auth),
          utf8.encode('Bearer ${base64Encode(token)}'),
        ))
      throw lanAuthentication;
  }

  Future<void> _handle(HttpRequest request) async {
    if (request.uri.hasQuery || request.uri.toString().contains('%'))
      throw lanAuthentication;
    final path = request.uri.path;
    if (path.startsWith('/pair/')) {
      if (request.method != 'POST') throw lanAuthentication;
      final body = await readLanBody(
        request,
        request.contentLength,
        limit: 8192,
      ).timeout(const Duration(seconds: 10));
      final parsed = jsonDecode(utf8.decode(body)) as Map<String, dynamic>;
      // Pairing cannot authorize a different ledger through this listener.
      if (parsed['ledgerId'] != access.store.ledgerId) throw lanAuthentication;
      final reply = await pairing.handle(
        path.substring('/pair/'.length),
        parsed,
      );
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(reply));
      return;
    }
    await _authorize(
      request,
    ); // Before even naming a ledger/object in a response.
    final prefix = '/ledger/${access.store.ledgerId}/';
    if (!path.startsWith(prefix)) throw lanAuthentication;
    final relative = path.substring(prefix.length);
    if (relative == 'ledger.json') {
      final metadata = await access.store.metadata();
      if (request.method == 'GET') {
        await _authorize(request);
        request.response.add(metadata.encode());
      } else if (request.method == 'PUT') {
        final body = await readLanBody(
          request,
          request.contentLength,
        ).timeout(const Duration(seconds: 30));
        final incoming = LedgerMetadata.decode(body);
        await _authorize(request);
        if (incoming.id != metadata.id ||
            !lanEqual(incoming.encode(), metadata.encode()))
          throw const EchoFailure('conflict', '账本元数据不一致');
        request.response.statusCode = 204;
      } else {
        throw lanAuthentication;
      }
    } else if (relative == 'objects' && request.method == 'GET') {
      final objects = await access.objects();
      final bytes = utf8.encode(jsonEncode(objects.keys.toList()..sort()));
      if (bytes.length > 10 * 1024 * 1024 || objects.length > 100000)
        throw lanUnavailable;
      await _authorize(request);
      request.response.add(bytes);
    } else {
      final ref = lanObjectRef(relative);
      if (request.method == 'GET') {
        final object = (await access.objects())[relative];
        if (object == null) throw lanUnavailable;
        await _authorize(request);
        request.response.add(object.bytes);
      } else if (request.method == 'PUT') {
        final bytes = await readLanBody(
          request,
          request.contentLength,
        ).timeout(const Duration(seconds: 30));
        final object = StoredObject(
          ref.batchId,
          access.store.ledgerId,
          ref.sha256,
          bytes,
        );
        await validateLanObject(object, access.store.ledgerId);
        await _authorize(request);
        await access.onPut(
          object,
        ); // AEAD, ledger binding and causal ingest live here.
        request.response.statusCode = 204;
      } else {
        throw lanAuthentication;
      }
    }
  }

  Future<void> close() async {
    _closed = true;
    final server = _server;
    _server = null;
    await pairing.close();
    await server?.close(force: true);
  }
}

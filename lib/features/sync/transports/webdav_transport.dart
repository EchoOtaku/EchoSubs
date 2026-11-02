import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import '../../../core/crypto/ledger_metadata.dart';
import '../../../core/model/errors.dart';
import '../../../core/model/ids.dart';
import '../../../storage/ledger_store.dart';
import 'dav_response_parser.dart';
import 'sync_transport.dart';
export 'sync_transport.dart';

class DavCredentials {
  const DavCredentials(this.username, this.secret);
  final String username, secret;
  @override
  String toString() => 'DavCredentials(<redacted>)';
}

/// Owns the client returned by clientFactory and closes it. Production uses
/// system TLS verification. The seam allows a scoped trusted test CA only.
class WebDavTransport implements SyncTransport {
  WebDavTransport({
    required Uri root,
    required this.ledgerId,
    required DavCredentials credentials,
    HttpClient Function()? clientFactory,
    this.onRetry,
  }) : root = checkedDavRoot(root),
       _credentials = credentials,
       _client = _createClient(root, ledgerId, credentials, clientFactory) {
    _client.connectionTimeout = const Duration(seconds: 10);
    _client.autoUncompress = false;
  }

  /// Explicit application root, with ledgerId appended exactly once.
  final Uri root;
  final LedgerId ledgerId;
  final DavCredentials _credentials;
  final HttpClient _client;

  /// Safe progress signal: the next retry number (1 or 2), without URLs/errors.
  final void Function(int retry)? onRetry;
  bool _closed = false;
  Future<void>? _writeReady;
  Uri get ledgerRoot => root.resolve('$ledgerId/');
  Uri get _objects => ledgerRoot.resolve('objects/');

  /// ledgerRoot is already the ledger directory. Never appends another ID.
  /// Only validates the metadata format; Task8 must unwrap and verify recovery.
  static Future<LedgerMetadata> probeMetadata(
    Uri ledgerRoot,
    DavCredentials credentials, {
    HttpClient Function()? clientFactory,
  }) async {
    final scope = checkedDavRoot(ledgerRoot);
    final parts = scope.pathSegments.where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) invalidDav();
    final id = parts.last;
    validateId(id);
    final parent = scope.resolve('../');
    final transport = WebDavTransport(
      root: parent,
      ledgerId: id,
      credentials: credentials,
      clientFactory: clientFactory,
    );
    try {
      return await transport.readMetadata();
    } finally {
      await transport.close();
    }
  }

  @override
  Future<LedgerMetadata> readMetadata() async {
    final response = await _request('GET', ledgerRoot.resolve('ledger.json'));
    _expect(response.status, [200]);
    final metadata = LedgerMetadata.decode(response.bytes);
    if (metadata.id != ledgerId) invalidDav();
    return metadata;
  }

  @override
  Future<void> publishMetadata(LedgerMetadata metadata) async {
    validateId(metadata.id);
    if (metadata.id != ledgerId) invalidDav();
    final bytes = metadata.encode();
    LedgerMetadata.decode(bytes);
    await _ready();
    await _immutablePut(ledgerRoot.resolve('ledger.json'), bytes);
  }

  @override
  Stream<ObjectRef> listObjects(CancellationToken token) async* {
    final response = await _request(
      'PROPFIND',
      _objects,
      body: utf8.encode(
        '<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop><d:resourcetype/></d:prop></d:propfind>',
      ),
      limit: maxDavListingBytes,
      token: token,
    );
    _expect(response.status, [207]);
    for (final ref in parseDavListing(response.bytes, _objects)) {
      _check(token);
      yield ref;
    }
  }

  Uri _refUri(ObjectRef ref) {
    validateId(ref.batchId);
    final name = '${ref.batchId}-${ref.sha256}.bin';
    if (!objectNamePattern.hasMatch(name) ||
        ref.relativePath != 'objects/$name')
      invalidDav();
    return _objects.resolve(name);
  }

  @override
  Future<StoredObject> read(ObjectRef ref) async {
    final response = await _request('GET', _refUri(ref));
    _expect(response.status, [200]);
    await _verify(response.bytes, ref.sha256);
    return StoredObject(ref.batchId, ledgerId, ref.sha256, response.bytes);
  }

  @override
  Future<void> put(StoredObject object) async {
    if (object.ledgerId != ledgerId) invalidDav();
    final uri = _refUri(
      ObjectRef(
        object.batchId,
        object.sha256,
        'objects/${object.batchId}-${object.sha256}.bin',
      ),
    );
    final bytes = object.bytes;
    await _verify(bytes, object.sha256);
    await _ready();
    await _immutablePut(uri, bytes);
  }

  Future<void> _verify(Uint8List bytes, String digest) async {
    if (bytes.isEmpty || bytes.length > 1024 * 1024) invalidDav();
    final actual = (await Sha256().hash(
      bytes,
    )).bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    if (actual != digest) invalidDav();
  }

  Future<void> _immutablePut(Uri uri, List<int> bytes) async {
    final response = await _request('PUT', uri, body: bytes, conditional: true);
    if (response.status == 412) {
      final old = await _request('GET', uri);
      _expect(old.status, [200]);
      if (!_same(bytes, old.bytes)) invalidDav();
    } else {
      _expect(response.status, [201, 204]);
    }
  }

  Future<void> _ready() => _writeReady ??= _probeWrites();
  Future<void> _probeWrites() async {
    for (final dir in [ledgerRoot, _objects]) {
      final response = await _request('MKCOL', dir);
      _expect(response.status, [201, 405]);
    }
    final uri = ledgerRoot.resolve('.echosubs-probe-${newId()}');
    final first = utf8.encode(newId());
    var created = false;
    try {
      final a = await _request(
        'PUT',
        uri,
        body: first,
        conditional: true,
        retries: false,
      );
      _expect(a.status, [201]);
      created = true;
      final b = await _request(
        'PUT',
        uri,
        body: utf8.encode(newId()),
        conditional: true,
        retries: false,
      );
      final stored = await _request('GET', uri);
      _expect(stored.status, [200]);
      if (b.status != 412 || !_same(stored.bytes, first)) {
        throw const EchoFailure('incompatible', 'WebDAV 不支持安全的条件写入');
      }
    } finally {
      if (created) {
        final deleted = await _request('DELETE', uri, retries: false);
        _expect(deleted.status, [200, 204, 404]);
      }
    }
  }

  void _check([CancellationToken? token]) {
    if (_closed) throw const EchoFailure('unavailable', 'WebDAV 通道已关闭');
    if (token?.isCancelled ?? false)
      throw const EchoFailure('cancelled', '同步已取消');
  }

  Future<_Response> _request(
    String method,
    Uri uri, {
    List<int>? body,
    int limit = 1024 * 1024,
    CancellationToken? token,
    bool conditional = false,
    bool retries = true,
  }) async {
    final elapsed = Stopwatch()..start();
    for (var attempt = 0; ; attempt++) {
      _check(token);
      HttpClientRequest? request;
      Timer? cancellation;
      var cancelled = false;
      var interrupted = false;
      StreamSubscription<List<int>>? subscription;
      final interruption = Completer<_Response>();
      void interrupt(Object error) {
        interrupted = true;
        request?.abort();
        if (!interruption.isCompleted) interruption.completeError(error);
      }

      final remaining = const Duration(seconds: 30) - elapsed.elapsed;
      if (remaining <= Duration.zero)
        throw const EchoFailure('unavailable', 'WebDAV 传输超时');
      final deadline = Timer(
        remaining,
        () => interrupt(const EchoFailure('unavailable', 'WebDAV 传输超时')),
      );
      final headersDeadline = Timer(
        const Duration(seconds: 10),
        () => interrupt(TimeoutException('WebDAV 请求头超时')),
      );
      cancellation = Timer.periodic(const Duration(milliseconds: 20), (_) {
        if (token?.isCancelled ?? false) {
          cancelled = true;
          interrupt(const EchoFailure('cancelled', '同步已取消'));
        }
      });
      try {
        Future<_Response> perform() async {
          request = await _client.openUrl(method, uri);
          if (interrupted) {
            unawaited(request!.done.then<void>((_) {}, onError: (Object _) {}));
            request!.abort();
            throw const EchoFailure('cancelled', '同步已中止');
          }
          _check(token);
          request!.followRedirects = false;
          request!.headers.set(
            HttpHeaders.authorizationHeader,
            'Basic ${base64Encode(utf8.encode('${_credentials.username}:${_credentials.secret}'))}',
          );
          if (conditional) request!.headers.set('If-None-Match', '*');
          if (method == 'PROPFIND') {
            request!.headers.set('Depth', '1');
            request!.headers.contentType = ContentType(
              'application',
              'xml',
              charset: 'utf-8',
            );
          }
          if (body != null) {
            request!.contentLength = body.length;
            request!.add(body);
          }
          final response = await request!.close();
          headersDeadline.cancel();
          if (interrupted) {
            await response.listen((_) {}).cancel();
            throw const EchoFailure('cancelled', '同步已中止');
          }
          // Stop on authentication/capacity/redirect headers without waiting
          // for an untrusted error body (which could stall or contain secrets).
          if (response.statusCode == 401 ||
              response.statusCode == 403 ||
              response.statusCode == 507 ||
              (response.statusCode >= 300 && response.statusCode < 400)) {
            await response.listen((_) {}).cancel();
            _expect(response.statusCode, []);
          }
          if (response.contentLength > limit) {
            await response.listen((_) {}).cancel();
            invalidDav();
          }
          final builder = BytesBuilder(copy: false);
          final consumed = Completer<void>();
          subscription = response.listen(
            (chunk) {
              if (consumed.isCompleted) return;
              if (builder.length + chunk.length > limit) {
                consumed.completeError(
                  const EchoFailure('integrity', 'WebDAV 响应超出大小限制'),
                );
                return;
              }
              builder.add(chunk);
            },
            onError: (Object error, StackTrace stack) {
              if (!consumed.isCompleted) consumed.completeError(error, stack);
            },
            onDone: () {
              if (!consumed.isCompleted) consumed.complete();
            },
          );
          await consumed.future;
          _check(token);
          return _Response(response.statusCode, builder.takeBytes());
        }

        final response = await Future.any([perform(), interruption.future]);
        if (response.status >= 500 &&
            response.status != 507 &&
            retries &&
            attempt < 2) {
          onRetry?.call(attempt + 1);
          continue;
        }
        return response;
      } on EchoFailure {
        rethrow;
      } on HandshakeException {
        throw const EchoFailure('authentication', 'WebDAV 证书验证失败');
      } on Object {
        request?.abort();
        if (cancelled || (token?.isCancelled ?? false))
          throw const EchoFailure('cancelled', '同步已取消');
        _check(token);
        if (retries && attempt < 2) {
          onRetry?.call(attempt + 1);
          continue;
        }
        throw const EchoFailure('unavailable', 'WebDAV 网络传输失败');
      } finally {
        interrupted = true;
        deadline.cancel();
        headersDeadline.cancel();
        cancellation.cancel();
        await subscription?.cancel();
      }
    }
  }

  @override
  Future<void> close() async {
    _closed = true;
    _client.close(force: true);
  }
}

HttpClient _createClient(
  Uri root,
  LedgerId id,
  DavCredentials credentials,
  HttpClient Function()? factory,
) {
  checkedDavRoot(root);
  validateId(id);
  if (credentials.username.contains(':') ||
      '${credentials.username}${credentials.secret}'.contains(
        RegExp(r'[\r\n]'),
      ))
    invalidDav();
  return (factory ?? HttpClient.new)();
}

class _Response {
  const _Response(this.status, this.bytes);
  final int status;
  final Uint8List bytes;
}

void _expect(int code, List<int> accepted) {
  if (accepted.contains(code)) return;
  if (code == 401 || code == 403)
    throw const EchoFailure('authentication', 'WebDAV 访问被拒绝');
  if (code == 507) throw const EchoFailure('unavailable', 'WebDAV 存储空间不足');
  if (code == 404 || code >= 500)
    throw const EchoFailure('unavailable', 'WebDAV 请求失败');
  if (code == 409 || code == 412)
    throw const EchoFailure('conflict', 'WebDAV 请求失败');
  throw const EchoFailure('incompatible', 'WebDAV 请求失败');
}

bool _same(List<int> a, List<int> b) =>
    a.length == b.length &&
    Iterable<int>.generate(a.length).every((i) => a[i] == b[i]);

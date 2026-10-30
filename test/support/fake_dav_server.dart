import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:basic_utils/basic_utils.dart';

/// Actual HTTPS, an ephemeral test-only CA and random loopback port. No files,
/// real accounts, system trust changes or permissive certificate callbacks.
class FakeDavServer {
  FakeDavServer._(this.server, this.certificate) {
    server.listen((request) async {
      try {
        await _handle(request);
      } on Object {
        /* Deliberate disconnect tests. */
      }
    });
  }
  final HttpServer server;
  final String certificate;
  final Map<String, List<int>> files = {};
  final List<String> requests = [],
      deletes = [],
      requestsOutsideLedgerRoot = [];
  int successfulObjectWrites = 0;
  int? forcedStatus;
  int transientFailures = 0;
  bool lieAboutConditional = false,
      partialGet = false,
      partialPut = false,
      stallListing = false;
  String? listing;
  final _stop = Completer<void>();
  static String? _certificate, _key;
  static Future<FakeDavServer> start() async {
    if (_certificate == null) {
      final pair = CryptoUtils.generateRSAKeyPair();
      final privateKey = pair.privateKey as RSAPrivateKey;
      final publicKey = pair.publicKey as RSAPublicKey;
      final csr = X509Utils.generateRsaCsrPem(
        {'CN': 'localhost'},
        privateKey,
        publicKey,
      );
      _key = CryptoUtils.encodeRSAPrivateKeyToPemPkcs1(privateKey);
      _certificate = X509Utils.generateSelfSignedCertificate(
        privateKey,
        csr,
        2,
        sans: ['localhost'],
        cA: true,
        notBefore: DateTime.now().subtract(const Duration(days: 1)),
      );
    }
    final context = SecurityContext()
      ..useCertificateChainBytes(utf8.encode(_certificate!))
      ..usePrivateKeyBytes(utf8.encode(_key!));
    final server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      context,
    );
    return FakeDavServer._(server, _certificate!);
  }

  Uri get root => Uri.parse('https://localhost:${server.port}/dedicated/');
  HttpClient client() => HttpClient(
    context: SecurityContext(withTrustedRoots: false)
      ..setTrustedCertificatesBytes(utf8.encode(certificate)),
  );
  static const ledger = '11111111111111111111111111111111';
  String get scope => '/dedicated/$ledger/';
  Future<void> _handle(HttpRequest request) async {
    final path = request.uri.path;
    requests.add('${request.method} $path');
    if (!path.startsWith(scope)) requestsOutsideLedgerRoot.add(path);
    final response = request.response;
    if (forcedStatus != null) {
      response.statusCode = forcedStatus!;
      response.headers.set('location', 'https://credential-trap.invalid/');
      await response.close();
      return;
    }
    if (transientFailures > 0) {
      transientFailures--;
      response.statusCode = 503;
      await response.close();
      return;
    }
    switch (request.method) {
      case 'MKCOL':
        response.statusCode = 201;
      case 'PUT':
        final bytes = await request.fold<List<int>>([], (a, b) => a..addAll(b));
        if (request.headers.value('if-none-match') != '*')
          throw StateError('missing conditional');
        if (partialPut &&
            path.contains('/objects/') &&
            !files.containsKey(path)) {
          files[path] = bytes.take(1).toList();
          final socket = await response.detachSocket(writeHeaders: false);
          socket.destroy();
          return;
        }
        if (files.containsKey(path) && !lieAboutConditional) {
          response.statusCode = 412;
        } else {
          files[path] = bytes;
          response.statusCode = 201;
          if (path.contains('/objects/')) successfulObjectWrites++;
        }
      case 'GET':
        if (!files.containsKey(path)) {
          response.statusCode = 404;
        } else if (partialGet) {
          final socket = await response.detachSocket(writeHeaders: false);
          socket.add(
            utf8.encode(
              'HTTP/1.1 200 OK\r\nContent-Length: ${files[path]!.length + 100}\r\nConnection: close\r\n\r\n',
            ),
          );
          socket.add(files[path]!);
          await socket.flush();
          socket.destroy();
          return;
        } else {
          response.add(files[path]!);
        }
      case 'DELETE':
        deletes.add(path);
        files.remove(path);
        response.statusCode = 204;
      case 'PROPFIND':
        if (request.headers.value('depth') != '1') throw StateError('depth');
        response.statusCode = 207;
        if (stallListing) {
          response.write('<');
          await response.flush();
          await _stop.future;
          return;
        }
        response.write(
          listing ??
              multistatus([
                item(path),
                for (final name in files.keys.where((p) => p.startsWith(path)))
                  item(name),
              ]),
        );
      default:
        response.statusCode = 405;
    }
    await response.close();
  }

  static String item(String href, {int status = 200}) =>
      '<d:response><d:href>$href</d:href><d:propstat><d:prop><d:resourcetype/></d:prop><d:status>HTTP/1.1 $status Test</d:status></d:propstat></d:response>';
  static String multistatus(List<String> items) =>
      '<?xml version="1.0"?><d:multistatus xmlns:d="DAV:">${items.join()}</d:multistatus>';
  Future<void> close() async {
    if (!_stop.isCompleted) _stop.complete();
    await server.close(force: true);
  }
}

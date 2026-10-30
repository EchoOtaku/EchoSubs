import 'dart:convert';
import 'dart:typed_data';
import 'package:xml/xml.dart';
import '../../../core/model/errors.dart';
import 'sync_transport.dart';

const maxDavListingBytes = 10 * 1024 * 1024;
final objectNamePattern = RegExp(r'^([0-9a-f]{32})-([0-9a-f]{64})\.bin$');
Never invalidDav() => throw const EchoFailure('integrity', 'WebDAV 响应或路径无效');

/// Reject ambiguous encoding before resolving, so normalization cannot hide traversal.
Uri checkedDavRoot(Uri uri) {
  if (uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment)
    invalidDav();
  checkedSegments(uri);
  return uri.replace(path: uri.path.endsWith('/') ? uri.path : '${uri.path}/');
}

List<String> checkedSegments(Uri uri) {
  final segments = uri.pathSegments.toList();
  for (var i = 0; i < segments.length; i++) {
    final s = segments[i];
    if (s == '.' ||
        s == '..' ||
        s.contains('%') ||
        s.contains('/') ||
        s.contains('\\') ||
        s.contains(RegExp(r'[\x00-\x1f\x7f]')) ||
        (s.isEmpty && i != segments.length - 1))
      invalidDav();
  }
  return segments;
}

List<ObjectRef> parseDavListing(Uint8List bytes, Uri directory) {
  if (bytes.length > maxDavListingBytes) invalidDav();
  try {
    final text = utf8.decode(bytes);
    if (text.contains('<!'))
      invalidDav(); // DTD, entities and other declarations.
    var depth = 0;
    var count = 0;
    for (final tag in RegExp(r'<[^>]*>').allMatches(text)) {
      final value = tag.group(0)!;
      if (++count > 100000) invalidDav();
      if (value.startsWith('</')) {
        depth--;
      } else if (!value.startsWith('<?') && !value.endsWith('/>')) {
        depth++;
      }
      if (depth < 0 || depth > 64) invalidDav();
    }
    final document = XmlDocument.parse(text);
    final root = document.rootElement;
    if (root.name.local != 'multistatus' || root.namespaceUri != 'DAV:')
      invalidDav();
    final result = <ObjectRef>[];
    final seen = <String>{};
    for (final response in root.childElements) {
      if (response.name.local != 'response' || response.namespaceUri != 'DAV:')
        invalidDav();
      final hrefs = response
          .findElements('href', namespaceUri: 'DAV:')
          .toList();
      if (hrefs.length != 1) invalidDav();
      final href = Uri.parse(hrefs.single.innerText);
      checkedSegments(href);
      if (href.hasQuery || href.hasFragment || href.userInfo.isNotEmpty)
        invalidDav();
      final target = directory.resolveUri(href);
      if (target.origin != directory.origin) invalidDav();
      final base = directory.pathSegments.where((s) => s.isNotEmpty).toList();
      final parts = checkedSegments(target).where((s) => s.isNotEmpty).toList();
      if (parts.length < base.length ||
          List.generate(
            base.length,
            (i) => parts[i] == base[i],
          ).contains(false))
        invalidDav();
      final statuses = response.descendants
          .whereType<XmlElement>()
          .where((e) => e.name.local == 'status' && e.namespaceUri == 'DAV:')
          .toList();
      if (statuses.isEmpty) invalidDav();
      for (final status in statuses) {
        final match = RegExp(
          r'^HTTP/\d\.\d ([0-9]{3})(?: .*)?$',
        ).firstMatch(status.innerText.trim());
        if (match == null) invalidDav();
        final code = int.parse(match.group(1)!);
        if (code == 401 || code == 403)
          throw const EchoFailure('authentication', 'WebDAV 访问被拒绝');
        if (code < 200 || code >= 300) invalidDav();
      }
      if (parts.length == base.length) continue;
      if (parts.length != base.length + 1) invalidDav();
      final name = parts.last;
      final match = objectNamePattern.firstMatch(name);
      if (match == null || !seen.add(name)) invalidDav();
      result.add(ObjectRef(match.group(1)!, match.group(2)!, 'objects/$name'));
    }
    return result;
  } on EchoFailure {
    rethrow;
  } on Object {
    return invalidDav();
  }
}

import 'dart:io';
import '../core/model/errors.dart';

/// Process-lifetime ownership for an application support directory.
class ProfileLease {
  static final _owners = <String, Future<void>>{};
  static final _handles = <String, RandomAccessFile>{};
  static Future<void> acquire(Directory directory) async {
    await directory.create(recursive: true);
    final path = await directory.resolveSymbolicLinks();
    final key = Platform.isWindows ? path.toLowerCase() : path;
    final existing = _owners[key];
    if (existing != null) return existing;
    final operation = _lock(key, path);
    _owners[key] = operation;
    try {
      await operation;
    } on Object {
      _owners.remove(key);
      rethrow;
    }
  }

  static Future<void> _lock(String key, String path) async {
    RandomAccessFile? handle;
    try {
      handle = await File(
        '$path${Platform.pathSeparator}.instance.lock',
      ).open(mode: FileMode.append);
      await handle.lock(FileLock.exclusive);
      // Deliberately never close at service disposal or failed bootstrap. The OS
      // releases ownership only when this process and every inflight write end.
      _handles[key] = handle;
    } on Object {
      await handle?.close();
      throw const EchoFailure(
        'unavailable',
        '此应用数据目录正在由另一实例使用，或无法取得独占访问。请关闭另一实例后重试。',
      );
    }
  }
}

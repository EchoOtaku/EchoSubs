import 'dart:io';
import 'dart:typed_data';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../core/model/errors.dart';
import 'backup_format.dart';

abstract class DocumentAccess {
  factory DocumentAccess() = PlatformDocumentAccess;
  Future<bool> save(Uint8List bytes, String suggestedName);
  Future<Uint8List?> pick();
}

class PlatformDocumentAccess implements DocumentAccess {
  PlatformDocumentAccess({TargetPlatform? platform, MethodChannel? channel})
    : _platform = platform ?? defaultTargetPlatform,
      _channel = channel ?? const MethodChannel('echosubs/document_access');
  final TargetPlatform _platform;
  final MethodChannel _channel;
  bool _busy = false;
  Future<T> _operation<T>(Future<T> Function() action) async {
    if (_busy) throw const EchoFailure('unavailable', '文件选择正在进行');
    _busy = true;
    try {
      return await action();
    } on EchoFailure {
      rethrow;
    } on PlatformException catch (e) {
      throw EchoFailure(
        e.code == 'validation' ? 'validation' : 'unavailable',
        '文件访问失败，请重新选择有权限的文件',
      );
    } on Object {
      throw const EchoFailure('unavailable', '文件读写未完成，请检查权限与可用空间');
    } finally {
      _busy = false;
    }
  }

  void _size(int length) {
    if (length <= 0 || length > maxBackupBytes)
      throw const EchoFailure('validation', '文件必须大于零且不超过 100 MiB');
  }

  @override
  Future<bool> save(Uint8List bytes, String suggestedName) => _operation(
    () async {
      _size(bytes.length);
      if (suggestedName.isEmpty ||
          suggestedName.length > 200 ||
          RegExp(r'[\x00-\x1f/\\]').hasMatch(suggestedName)) {
        throw const EchoFailure('validation', '文件名无效');
      }
      final content = Uint8List.fromList(bytes);
      if (_platform == TargetPlatform.android) {
        final saved = await _channel.invokeMethod<bool>('save', {
          'bytes': content,
          'suggestedName': suggestedName,
        });
        if (saved == null) throw const EchoFailure('unavailable', '无法确认文件保存完成');
        return saved;
      }
      if (_platform != TargetPlatform.windows)
        throw const EchoFailure('unavailable', '当前平台不支持文件选择');
      final location = await getSaveLocation(
        suggestedName: suggestedName,
        acceptedTypeGroups: [
          XTypeGroup(
            label: 'EchoSubs 导出',
            extensions: [
              suggestedName.endsWith('.json') ? 'json' : backupExtension,
            ],
          ),
        ],
      );
      if (location == null) return false;
      final file = File(location.path);
      await file.writeAsBytes(content, flush: true);
      final check = await _readFile(file);
      if (!listEquals(check, content))
        throw const EchoFailure('integrity', '文件写入不完整，请重新保存');
      return true;
    },
  );
  @override
  Future<Uint8List?> pick() => _operation(() async {
    if (_platform == TargetPlatform.android) {
      final bytes = await _channel.invokeMethod<Uint8List>('pick');
      if (bytes != null) _size(bytes.length);
      return bytes;
    }
    if (_platform != TargetPlatform.windows)
      throw const EchoFailure('unavailable', '当前平台不支持文件选择');
    final selected = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(label: 'EchoSubs 备份', extensions: [backupExtension]),
      ],
    );
    return selected == null ? null : _readFile(File(selected.path));
  });
  Future<Uint8List> _readFile(File file) async {
    _size(await file.length());
    final builder = BytesBuilder(copy: false);
    await for (final chunk in file.openRead()) {
      _size(builder.length + chunk.length);
      builder.add(chunk);
    }
    _size(builder.length);
    return builder.takeBytes();
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:echo_subs/app/services.dart';
import 'package:echo_subs/core/model/errors.dart';
import 'package:echo_subs/features/backup/backup_format.dart';
import 'package:echo_subs/features/backup/document_access.dart';
import 'package:echo_subs/features/backup/ui/backup_page.dart';
import '../support/ledger_harness.dart';

class CancelDocuments implements DocumentAccess {
  int saved = 0, picked = 0;
  @override
  Future<bool> save(Uint8List bytes, String suggestedName) async {
    saved++;
    return false;
  }

  @override
  Future<Uint8List?> pick() async {
    picked++;
    return null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const android = MethodChannel('echosubs/document_access');
  const windows = MethodChannel('plugins.flutter.io/file_selector');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() {
    messenger.setMockMethodCallHandler(android, null);
    messenger.setMockMethodCallHandler(windows, null);
  });
  test(
    'Android contract: cancellation, error, null ack, concurrent access and bounded bytes',
    () async {
      final docs = PlatformDocumentAccess(platform: TargetPlatform.android);
      final bytes = Uint8List.fromList(utf8.encode('中文测试'));
      messenger.setMockMethodCallHandler(
        android,
        (call) async => call.method == 'save' ? false : null,
      );
      expect(await docs.save(bytes, '中文.echosubsbackup'), false);
      expect(await docs.pick(), isNull);
      messenger.setMockMethodCallHandler(
        android,
        (call) async => throw PlatformException(
          code: 'unavailable',
          message: 'untrusted private detail',
        ),
      );
      await expectLater(
        docs.pick(),
        throwsA(
          isA<EchoFailure>().having(
            (e) => e.toString(),
            'safe',
            isNot(contains('untrusted')),
          ),
        ),
      );
      messenger.setMockMethodCallHandler(android, (call) async => null);
      await expectLater(
        docs.save(bytes, '中文.echosubsbackup'),
        throwsA(isA<EchoFailure>()),
      );
      final gate = Completer<Object?>();
      messenger.setMockMethodCallHandler(android, (call) => gate.future);
      final first = docs.pick();
      await expectLater(docs.pick(), throwsA(isA<EchoFailure>()));
      gate.complete(null);
      await first;
      await expectLater(
        docs.save(Uint8List(maxBackupBytes + 1), '大文件.echosubsbackup'),
        throwsA(isA<EchoFailure>()),
      );
      await expectLater(
        docs.save(bytes, '../bad'),
        throwsA(isA<EchoFailure>()),
      );
      await expectLater(
        docs.save(Uint8List(0), '空文件'),
        throwsA(isA<EchoFailure>()),
      );
    },
  );
  test(
    'Windows actual file I/O through selector contract: Chinese, cancel, revoked path and size',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'echosubs-document-test-',
      );
      final file = File('${dir.path}/中文备份.echosubsbackup');
      final bytes = Uint8List.fromList(utf8.encode('中文与 emoji 🐈'));
      final docs = PlatformDocumentAccess(platform: TargetPlatform.windows);
      messenger.setMockMethodCallHandler(windows, (call) async {
        if (call.method == 'getSavePath') {
          expect(
            (call.arguments as Map)['suggestedName'],
            '中文备份.echosubsbackup',
          );
          return file.path;
        }
        return [file.path];
      });
      expect(await docs.save(bytes, '中文备份.echosubsbackup'), true);
      expect(await file.readAsBytes(), bytes);
      expect(await docs.pick(), bytes);
      messenger.setMockMethodCallHandler(windows, (call) async => null);
      expect(await docs.save(bytes, '取消.echosubsbackup'), false);
      expect(await docs.pick(), isNull);
      messenger.setMockMethodCallHandler(
        windows,
        (call) async => call.method == 'getSavePath'
            ? '${dir.path}/missing/new.echosubsbackup'
            : ['${dir.path}/missing.echosubsbackup'],
      );
      await expectLater(
        docs.save(bytes, '失败.echosubsbackup'),
        throwsA(isA<EchoFailure>()),
      );
      await expectLater(docs.pick(), throwsA(isA<EchoFailure>()));
      final large = File('${dir.path}/oversized.echosubsbackup');
      final handle = await large.open(mode: FileMode.write);
      try {
        await handle.truncate(maxBackupBytes + 1);
      } finally {
        await handle.close();
      }
      messenger.setMockMethodCallHandler(windows, (call) async => [large.path]);
      await expectLater(
        docs.pick(),
        throwsA(isA<EchoFailure>().having((e) => e.code, 'code', 'validation')),
      );
    },
  );
  testWidgets(
    'plain export requires explicit privacy confirmation and cancelled pick preserves selection',
    (tester) async {
      final h = (await tester.runAsync(LedgerHarness.create))!;
      final services = (await tester.runAsync(() async {
        final s = AppServices(ledger: h.repo);
        await s.ready;
        return s;
      }))!;
      final docs = CancelDocuments();
      try {
        await tester.runAsync(
          () => tester.pumpWidget(
            MaterialApp(
              home: BackupPage(services: services, documents: docs),
            ),
          ),
        );
        await tester.tap(find.text('导出明文私人数据'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.textContaining('私人订阅、付款、备注'), findsOneWidget);
        expect(docs.saved, 0);
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(docs.saved, 0);
        final selected = h.repo.currentLedgerId;
        await tester.tap(find.text('选择备份并预览'));
        await tester.pumpAndSettle();
        expect(docs.picked, 1);
        expect(find.text('已取消选择，当前账本未改变'), findsOneWidget);
        expect(h.repo.currentLedgerId, selected);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(() async {
          services.dispose();
          await Future<void>.delayed(Duration.zero);
          await h.close();
        });
      }
    },
  );
}

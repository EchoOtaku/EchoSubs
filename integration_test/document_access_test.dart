import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:echo_subs/core/crypto/key_vault.dart';
import 'package:echo_subs/core/crypto/ledger_metadata.dart';
import 'package:echo_subs/core/model/ids.dart';
import 'package:echo_subs/core/model/ledger.dart';
import 'package:echo_subs/core/model/errors.dart';
import 'package:echo_subs/features/ledger/ledger_repository.dart';
import 'package:echo_subs/features/backup/backup_service.dart';
import 'package:echo_subs/features/backup/document_access.dart';
import 'package:echo_subs/storage/app_database.dart';

class _MemoryVault implements VaultStorage {
  final values = <String, String>{};
  @override
  Future<String?> read(String name) async => values[name];
  @override
  Future<void> write(String name, String value) async {
    values[name] = value;
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'real document dialogs: cancel, Chinese save, reopen, damaged backup',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Center(child: Text('EchoSubs 隔离文件测试：仅虚构数据'))),
        ),
      );
      await tester.runAsync(() async {
        Directory directory;
        if (Platform.isAndroid) {
          final support = await getApplicationSupportDirectory();
          if (!support.path.contains('/dev.echootaku.echo_subs.integration/'))
            throw StateError('Non-isolated package');
          final parent = await Directory(
            '${support.path}/task10-documents',
          ).create(recursive: true);
          directory = await parent.createTemp('fixture-');
        } else if (Platform.isWindows) {
          final root = Platform.environment['ECHOSUBS_LAN_TEST_DIR'];
          if (root == null || !root.replaceAll('\\', '/').contains('/.local/'))
            throw StateError('No isolated test directory');
          directory = await Directory(root).createTemp('fixture-');
        } else {
          throw StateError('Unsupported test platform');
        }
        final db = await AppDatabase.open(
          File('${directory.path}/fictional.sqlite'),
        );
        final storage = _MemoryVault();
        try {
          final repo = LedgerRepository(
            db,
            KeyVault(storage: storage),
            newId(),
          );
          final originalId = newId();
          final bundle = await createLedgerBundle(originalId);
          await repo.create(LedgerConfig(originalId, 'Asia/Shanghai'), bundle);
          final service = BackupService(repo), documents = DocumentAccess();
          final bytes = await service.exportEncrypted();
          debugPrint('DOC_NATIVE_SAVE_CANCEL_READY');
          expect(
            await documents.save(bytes, 'Task10-取消.echosubsbackup'),
            false,
          );
          debugPrint('DOC_NATIVE_PICK_CANCEL_READY');
          expect(await documents.pick(), isNull);
          expect(repo.currentLedgerId, originalId);
          final stamp = DateTime.now().millisecondsSinceEpoch;
          debugPrint('DOC_NATIVE_SAVE_READY');
          expect(
            await documents.save(bytes, 'Task10-中文备份-$stamp.echosubsbackup'),
            true,
          );
          debugPrint('DOC_NATIVE_PICK_READY');
          final picked = await documents.pick();
          expect(picked, bytes);
          final preview = await service.inspect(picked!, bundle.recovery);
          final restored = await service.restoreAsNew(preview);
          expect(restored, isNot(originalId));
          expect(repo.currentLedgerId, originalId);
          expect(await repo.listLedgers(), hasLength(2));
          debugPrint('DOC_NATIVE_CORRUPT_SAVE_READY');
          expect(
            await documents.save(
              Uint8List.fromList(utf8.encode('虚构损坏的备份')),
              'Task10-损坏备份-$stamp.echosubsbackup',
            ),
            true,
          );
          debugPrint('DOC_NATIVE_CORRUPT_PICK_READY');
          final corrupt = await documents.pick();
          expect(corrupt, isNotNull);
          await expectLater(
            service.inspect(corrupt!, bundle.recovery),
            throwsA(isA<EchoFailure>()),
          );
          expect(repo.currentLedgerId, originalId);
          expect(await repo.listLedgers(), hasLength(2));
          debugPrint('DOC_NATIVE_REAL_ROUNDTRIP_AND_CANCEL_OK');
        } finally {
          await db.close();
          storage.values.clear();
        }
      });
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}

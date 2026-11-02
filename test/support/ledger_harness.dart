import 'dart:io';
import 'package:echo_subs/core/crypto/key_vault.dart';
import 'package:echo_subs/core/crypto/ledger_metadata.dart';
import 'package:echo_subs/core/model/ids.dart';
import 'package:echo_subs/core/model/ledger.dart';
import 'package:echo_subs/features/ledger/ledger_repository.dart';
import 'package:echo_subs/storage/app_database.dart';

class MemoryVault implements VaultStorage {
  final values = <String, String>{};
  @override
  Future<String?> read(String name) async => values[name];
  @override
  Future<void> write(String name, String value) async {
    values[name] = value;
  }
}

class LedgerHarness {
  LedgerHarness(this.directory, this.db, this.repo, this.vault);
  final Directory directory;
  final AppDatabase db;
  final LedgerRepository repo;
  final KeyVault vault;
  static Future<LedgerHarness> create() async {
    final directory = await Directory.systemTemp.createTemp('echosubs-ui-');
    final db = await AppDatabase.open(File('${directory.path}/ledger.sqlite'));
    final vault = KeyVault(storage: MemoryVault());
    final repo = LedgerRepository(db, vault, newId());
    final id = newId();
    await repo.create(
      LedgerConfig(id, 'Asia/Shanghai'),
      await createLedgerBundle(id),
    );
    return LedgerHarness(directory, db, repo, vault);
  }

  Future<void> close() => db.close();
}

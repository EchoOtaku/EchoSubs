import 'dart:convert';
import 'dart:typed_data';
import '../core/model/errors.dart';
import '../core/model/ids.dart';
import '../features/backup/backup_service.dart';
import '../features/ledger/ledger_repository.dart';

/// Capability created only after usable storage and an existing-ledger unlock
/// failure. It does not select, replace, or require a writable old snapshot.
class StartupRecovery extends EchoFailure {
  StartupRecovery(this.repository, {required this.ownsDatabase})
    : backup = BackupService(repository),
      super('locked', '原账本无法解锁，可使用备份与原恢复密钥独立恢复');
  final LedgerRepository repository;
  final BackupService backup;
  final bool ownsDatabase;
  bool _closed = false;
  void _check() {
    if (_closed) throw const EchoFailure('cancelled', '恢复入口已关闭');
  }

  Future<LedgerId> restore(RestorePreview preview) async {
    _check();
    return backup.restoreAsNew(preview);
  }

  Future<void> select(LedgerId id) async {
    _check();
    await repository.selectLedger(id);
    final state = await repository.snapshot();
    if (state.metadata.id != id)
      throw const EchoFailure('integrity', '账本身份不匹配');
    await repository.vault.put(
      'active.ledger',
      Uint8List.fromList(utf8.encode(id)),
    );
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    if (ownsDatabase) await repository.database.close();
  }
}

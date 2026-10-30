import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../../app/services.dart';
import '../../../core/crypto/ledger_keys.dart';
import '../backup_format.dart';
import '../backup_service.dart';
import '../document_access.dart';

class BackupPage extends StatefulWidget {
  const BackupPage({super.key, required this.services, this.documents});
  final AppServices services;
  final DocumentAccess? documents;
  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  late final DocumentAccess documents = widget.documents ?? DocumentAccess();
  bool busy = false;
  String? status;
  RestorePreview? preview;
  BackupService get backup => widget.services.backup!;
  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      status = null;
    });
    try {
      await action();
    } on Object catch (e) {
      if (mounted) setState(() => status = safeError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<bool> confirm(String title, String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认'),
            ),
          ],
        ),
      ) ??
      false;
  Future<void> showRecovery(
    RecoveryCode code, {
    required bool newlyRestored,
  }) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text(newlyRestored ? '新账本恢复密钥' : '保存账本恢复密钥'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('请离线妥善保存。所有设备与恢复密钥同时丢失时，备份也无法解密。此密钥不会自动复制或写入日志。'),
                const SizedBox(height: 16),
                SelectableText(code.encoded),
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('我已保存恢复密钥'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> export({bool plain = false}) => run(() async {
    if (plain &&
        !await confirm(
          '导出明文私人信息',
          '此文件包含私人订阅、付款、备注和全部历史，任何拿到文件的人都可阅读。确认后再选择保存位置。',
        ))
      return;
    if (!mounted) return;
    final Uint8List bytes;
    if (plain) {
      bytes = await backup.exportPlain(confirmed: true);
    } else {
      final id = widget.services.ledger.currentLedgerId!;
      final recovery = await backup.recoveryFor(id);
      if (!mounted) return;
      if (recovery != null) {
        await showRecovery(recovery, newlyRestored: false);
      } else if (!await confirm(
        '本机未保存恢复密钥',
        '本机仍可导出加密备份，但必须使用这个账本原有的恢复密钥才能打开。请确认已在其他设备或离线位置保存原恢复密钥。',
      ))
        return;
      if (!mounted) return;
      if (id != widget.services.ledger.currentLedgerId) {
        setState(() => status = '账本已切换，请重新导出');
        return;
      }
      bytes = await backup.exportEncrypted();
    }
    if (!mounted) return;
    final saved = await documents.save(
      bytes,
      plain ? plainSuggestedName : backupSuggestedName,
    );
    if (mounted) setState(() => status = saved ? '文件已完整保存' : '已取消保存');
  });
  Future<void> inspect() => run(() async {
    setState(() => preview = null);
    final bytes = await documents.pick();
    if (bytes == null) {
      if (mounted) setState(() => status = '已取消选择，当前账本未改变');
      return;
    }
    if (!mounted) return;
    final input = TextEditingController();
    String? encoded;
    try {
      encoded = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('输入备份原恢复密钥'),
          content: TextField(
            controller: input,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(labelText: 'ES1- 恢复密钥'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, input.text.trim()),
              child: const Text('校验并预览'),
            ),
          ],
        ),
      );
    } finally {
      input.clear();
      input.dispose();
    }
    if (encoded == null) return;
    final result = await backup.inspect(bytes, RecoveryCode.parse(encoded));
    if (mounted) setState(() => preview = result);
  });
  Future<void> restore() => run(() async {
    final selected = preview;
    if (selected == null) return;
    final id = await widget.services.restoreBackup(selected);
    // Clear the preview before presenting a secret, preventing duplicate clicks.
    if (mounted) setState(() => preview = null);
    final recovery = await backup.recoveryFor(id);
    if (recovery != null) await showRecovery(recovery, newlyRestored: true);
    if (mounted)
      setState(() => status = '已恢复为独立新账本。同步保持关闭，当前账本未切换。请到“同步与账本”另行选择。');
  });
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('备份与恢复')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text('同步不是备份。加密备份包含全部历史与未解决冲突，同一账本沿用同一恢复密钥。文件上限 100 MiB。'),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: busy ? null : () => export(),
            child: const Text('导出加密备份'),
          ),
          TextButton(
            onPressed: busy ? null : () => export(plain: true),
            child: const Text('导出明文私人数据'),
          ),
          OutlinedButton(
            onPressed: busy ? null : inspect,
            child: const Text('选择备份并预览'),
          ),
          if (busy) const LinearProgressIndicator(),
          if (preview case final p?)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('格式 v${p.formatVersion} · ${p.batchCount} 个历史版本'),
                    Text(
                      '${p.entityCount} 个当前实体 · ${p.paymentVersionCount} 个付款版本',
                    ),
                    Text(
                      '${p.conflictCount} 个未解决冲突 · ${p.quarantinedBatchCount} 个隔离批次',
                    ),
                    const Text('恢复将生成新的账本身份、主密钥与恢复密钥。保留原账本，两个同步通道默认关闭。'),
                    FilledButton(
                      onPressed: busy ? null : restore,
                      child: const Text('确认恢复为新账本'),
                    ),
                  ],
                ),
              ),
            ),
          if (status != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(status!),
            ),
        ],
      ),
    ),
  );
}

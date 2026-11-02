import 'package:flutter/material.dart';
import '../../../app/design_system.dart';
import '../../ledger/ui/widgets.dart' show EchoActionBar;
import '../../../app/services.dart';
import '../../../core/crypto/ledger_keys.dart';
import '../../../core/model/errors.dart';
import '../sync_coordinator.dart';
import '../sync_state_store.dart';
import '../sync_status.dart';
import '../transports/webdav_transport.dart';
import 'conflicts_page.dart';
import 'pairing_page.dart';

const davDisclosure =
    '仅使用 HTTPS 和专用应用目录。将上传订阅、付款、分类、账本设置及冲突历史的认证密文。'
    '云端仍可见对象大小、数量和访问时间。首次写入会在所示账本目录创建并删除随机探针，不扫描父目录。'
    '恢复密钥不会上传；所有设备和恢复密钥都丢失时，云端密文无法恢复数据。同步不是备份。';

class SyncSettingsPage extends StatefulWidget {
  const SyncSettingsPage({super.key, required this.services});
  final AppServices services;
  @override
  State<SyncSettingsPage> createState() => _SyncSettingsPageState();
}

class _SyncSettingsPageState extends State<SyncSettingsPage> {
  List<ChannelConfig> configs = [];
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final values = await widget.services.syncRuntime.configs();
      if (mounted) setState(() => configs = values);
    } on Object catch (e) {
      if (mounted) setState(() => error = safeError(e));
    }
  }

  Future<void> open(Widget page) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => page),
    );
    await load();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.services,
    builder: (context, _) {
      final services = widget.services;
      final report = services.syncStatus.report;
      return Scaffold(
        appBar: AppBar(title: const Text('同步与账本')),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text('离线功能始终可用。仅在应用启动、前台和手动操作时同步；退出后不承诺实时同步。'),
            const SizedBox(height: 16),
            for (final kind in SyncChannelKind.values)
              _channel(
                kind,
                kind == SyncChannelKind.webdav ? report.webdav : report.lan,
              ),
            FilledButton.icon(
              onPressed: services.syncStatus.running ? null : services.syncNow,
              icon: const Icon(Icons.sync),
              label: Text(services.syncStatus.running ? '同步中…' : '立即同步 / 重试'),
            ),
            const SizedBox(height: 12),
            if (services.syncStatus.retryMessage != null)
              Text(services.syncStatus.retryMessage!),
            if (services.syncStatus.failure != null)
              Text(
                services.syncStatus.failure!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            Text(
              services.syncStatus.remindersReconciled
                  ? '提醒已核对'
                  : '提醒尚未核对：同步数据与系统提醒分别显示状态',
            ),
            TextButton(
              onPressed: () => open(ConflictsPage(services: services)),
              child: const Text('查看并解决冲突'),
            ),
            const Divider(),
            const Text(davDisclosure),
            Text('当前账本 ID：${services.ledger.currentLedgerId}'),
            OutlinedButton(
              onPressed: () => open(DavSettingsForm(services: services)),
              child: const Text('配置 HTTPS 网盘'),
            ),
            OutlinedButton(
              onPressed: () =>
                  open(DavSettingsForm(services: services, join: true)),
              child: const Text('使用恢复密钥加入已有账本'),
            ),
            OutlinedButton(
              onPressed: () => open(PairingPage(services: services)),
              child: const Text('局域网配对与设备'),
            ),
            FutureBuilder<List<String>>(
              future: services.ledger.listLedgers(),
              builder: (context, snapshot) => Column(
                children: [
                  for (final id in snapshot.data ?? <String>[])
                    ListTile(
                      title: Text(id),
                      subtitle: Text(
                        id == services.ledger.currentLedgerId ? '当前账本' : '独立账本',
                      ),
                      onTap: id == services.ledger.currentLedgerId
                          ? null
                          : () async {
                              try {
                                await services.selectLedger(id);
                                await load();
                              } on Object catch (e) {
                                if (mounted)
                                  setState(() => error = safeError(e));
                              }
                            },
                    ),
                ],
              ),
            ),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      );
    },
  );
  Widget _channel(SyncChannelKind kind, ChannelReport report) {
    final config = configs.where((c) => c.kind == kind).firstOrNull;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            EchoSwitchTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                kind == SyncChannelKind.webdav ? 'WebDAV 网盘' : '局域网直连',
              ),
              subtitle: Text(
                config == null
                    ? '尚未配置'
                    : config.enabled
                    ? '已启用'
                    : '已关闭',
              ),
              value: config?.enabled ?? false,
              onChanged: config == null
                  ? null
                  : (enabled) async {
                      try {
                        await widget.services.syncRuntime.setEnabled(
                          config,
                          enabled,
                        );
                        await load();
                      } on Object catch (e) {
                        if (mounted) setState(() => error = safeError(e));
                      }
                    },
            ),
            Text(report.succeeded ? '数据同步完成' : '尚未完成同步'),
            Text(
              '上传 ${report.uploaded} · 拉取 ${report.downloaded} · 待上传 ${report.pendingUpload}',
            ),
            Text(
              '待依赖 ${report.pendingDependencies} · 冲突 ${report.conflicts} · 隔离 ${report.quarantined}',
            ),
            Text('最近成功：${report.lastSuccess?.toLocal().toString() ?? '尚无'}'),
            for (final message in report.errors) Text(message),
            if (kind == SyncChannelKind.lan &&
                widget.services.syncRuntime.runtimeError != null)
              Text(widget.services.syncRuntime.runtimeError!),
          ],
        ),
      ),
    );
  }
}

class DavSettingsForm extends StatefulWidget {
  const DavSettingsForm({super.key, required this.services, this.join = false});
  final AppServices services;
  final bool join;
  @override
  State<DavSettingsForm> createState() => _DavSettingsFormState();
}

class _DavSettingsFormState extends State<DavSettingsForm> {
  late final String ledgerId;
  @override
  void initState() {
    super.initState();
    ledgerId = widget.services.ledger.currentLedgerId!;
  }

  final root = TextEditingController(),
      user = TextEditingController(),
      password = TextEditingController(),
      recovery = TextEditingController();
  final token = SyncCancellation();
  bool accepted = false, busy = false;
  String? error;
  @override
  void dispose() {
    token.cancel();
    root.dispose();
    user.dispose();
    password.dispose();
    recovery.dispose();
    super.dispose();
  }

  Future<void> save() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (widget.services.ledger.currentLedgerId != ledgerId) {
        throw const EchoFailure('conflict', '账本已切换，请重新打开表单');
      }
      final credentials = DavCredentials(user.text, password.text);
      if (widget.join) {
        await widget.services.syncRuntime.joinDav(
          Uri.parse(root.text.trim()),
          credentials,
          RecoveryCode.parse(recovery.text.trim()),
          token,
        );
      } else {
        await widget.services.syncRuntime.configureDav(
          Uri.parse(root.text.trim()),
          credentials,
          enabled: true,
          expectedLedgerId: ledgerId,
        );
      }
      password.clear();
      recovery.clear();
      if (mounted) Navigator.pop(context);
    } on Object catch (e) {
      if (mounted)
        setState(() {
          busy = false;
          error = safeError(e);
        });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.join ? '加入已有账本' : '配置网盘')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: EchoField(
                label: widget.join
                    ? 'HTTPS 账本目录（含账本 ID，以 / 结尾）'
                    : 'HTTPS 专用应用目录（以 / 结尾）',
                child: TextField(
                  controller: root,
                  key: const ValueKey('dav.root'),
                  decoration: const InputDecoration(),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: EchoField(
                label: '网盘用户名',
                child: TextField(
                  controller: user,
                  decoration: const InputDecoration(),
                  autocorrect: false,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: EchoField(
                label: '网盘密码 / 应用密码',
                child: TextField(
                  controller: password,
                  obscureText: true,
                  enableSuggestions: false,
                  autocorrect: false,
                  decoration: const InputDecoration(),
                ),
              ),
            ),
            if (widget.join)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: EchoField(
                  label: '原账本恢复密钥',
                  child: TextField(
                    controller: recovery,
                    obscureText: true,
                    enableSuggestions: false,
                    autocorrect: false,
                    decoration: const InputDecoration(),
                  ),
                ),
              ),
            const SizedBox(height: 24),
            const Text(davDisclosure),
            Text(
              widget.join
                  ? '仅在密钥和完整历史验证后加入；原账本仍保留。'
                  : '实际操作范围：上述应用目录 / ${widget.services.ledger.currentLedgerId} /',
            ),
            CheckboxListTile(
              value: accepted,
              onChanged: busy ? null : (v) => setState(() => accepted = v!),
              title: const Text('我已了解上传类别、专用目录与加密边界'),
            ),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    ),
    bottomNavigationBar: EchoActionBar(
      onCancel: () {
        token.cancel();
        Navigator.pop(context);
      },
      primary: FilledButton(
        key: const ValueKey('dav.save'),
        onPressed: !accepted || busy ? null : save,
        child: Text(
          busy
              ? '正在验证…'
              : widget.join
              ? '验证并加入'
              : '启用网盘',
        ),
      ),
    ),
  );
}

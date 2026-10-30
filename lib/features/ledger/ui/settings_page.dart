import 'package:flutter/material.dart';
import '../../../app/services.dart';
import 'widgets.dart';
import '../../sync/ui/sync_settings_page.dart';
import '../../reminders/ui/reminder_settings_page.dart';
import '../../backup/ui/backup_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.services});
  final AppServices services;
  @override
  Widget build(BuildContext context) => PageContent(
    children: [
      const SectionTitle('设置', subtitle: '本地账本与外观'),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('外观', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              DropdownButtonFormField<ThemeMode>(
                key: ValueKey(services.themeMode),
                initialValue: services.themeMode,
                decoration: const InputDecoration(labelText: '主题（本次会话）'),
                isExpanded: true,
                items: const [
                  DropdownMenuItem(
                    value: ThemeMode.system,
                    child: Text('跟随系统'),
                  ),
                  DropdownMenuItem(value: ThemeMode.light, child: Text('浅色')),
                  DropdownMenuItem(value: ThemeMode.dark, child: Text('深色')),
                ],
                onChanged: (v) {
                  if (v != null) services.setTheme(v);
                },
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('账本信息', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              const Text('账本 ID'),
              SelectableText(services.ledger.currentLedgerId ?? '未选择'),
              const SizedBox(height: 12),
              Text(
                '账本时区：${services.configurationNeedsConfirmation ? '配置待确认，日期提醒已暂停' : services.config?.timeZoneId ?? '未填写'}',
              ),
              const SizedBox(height: 12),
              const Text('数据保存在此设备的应用支持目录。离线可添加、编辑订阅并记录付款。'),
              const SizedBox(height: 12),
              const Text('同步通道可独立启用，未配置时保持离线。手机使用本地提醒，Windows 在应用运行时提示。'),
              TextButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => BackupPage(services: services),
                  ),
                ),
                icon: const Icon(Icons.backup_outlined),
                label: const Text('备份与恢复'),
              ),
              TextButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => ReminderSettingsPage(services: services),
                  ),
                ),
                icon: const Icon(Icons.notifications_outlined),
                label: const Text('本地提醒与权限'),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => SyncSettingsPage(services: services),
                  ),
                ),
                icon: const Icon(Icons.sync),
                label: const Text('同步与账本'),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 24),
      const Text('EchoSubs · 让订阅与付款清晰可查', textAlign: TextAlign.center),
    ],
  );
}

import 'package:flutter/material.dart';
import '../../../app/design_system.dart';
import '../../../app/services.dart';
import 'widgets.dart';
import '../../sync/ui/sync_settings_page.dart';
import '../../reminders/ui/reminder_settings_page.dart';
import '../../backup/ui/backup_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.services});
  final AppServices services;
  @override
  Widget build(BuildContext context) {
    final c = EchoColors.of(context);
    void open(Widget page) =>
        Navigator.push(context, MaterialPageRoute<void>(builder: (_) => page));
    final appearance = EchoPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('外观', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text('选择适合当前环境的显示方式。', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in const {
                ThemeMode.system: '跟随系统',
                ThemeMode.light: '浅色',
                ThemeMode.dark: '深色',
              }.entries)
                EchoChoice(
                  label: entry.value,
                  selected: services.themeMode == entry.key,
                  onPressed: () => services.setTheme(entry.key),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text('主题在本次会话中生效。', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
    final management = EchoPanel(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          _SettingsLink(
            icon: EchoSymbol.cloud,
            title: '同步与账本',
            subtitle: '网盘、局域网与设备配对',
            onTap: () => open(SyncSettingsPage(services: services)),
          ),
          Divider(color: c.border, indent: 18, endIndent: 18),
          _SettingsLink(
            icon: EchoSymbol.bell,
            title: '本地提醒与权限',
            subtitle: '检查通知状态、到期规则与待处理提醒',
            onTap: () => open(ReminderSettingsPage(services: services)),
          ),
          Divider(color: c.border, indent: 18, endIndent: 18),
          _SettingsLink(
            icon: EchoSymbol.backup,
            title: '备份与恢复',
            subtitle: '保存加密备份，或恢复为独立账本',
            onTap: () => open(BackupPage(services: services)),
          ),
        ],
      ),
    );
    return PageContent(
      maxWidth: 960,
      children: [
        const SectionTitle('设置', subtitle: '外观、同步与数据管理'),
        if (services.configurationNeedsConfirmation)
          Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: EchoNotice(
              message: '配置待确认，日期提醒已暂停',
              actionLabel: '检查账本',
              action: () => open(SyncSettingsPage(services: services)),
            ),
          ),
        LayoutBuilder(
          builder: (context, constraints) => constraints.maxWidth >= 780
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 4, child: appearance),
                    const SizedBox(width: 20),
                    Expanded(flex: 6, child: management),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    appearance,
                    const SizedBox(height: 20),
                    management,
                  ],
                ),
        ),
        const SizedBox(height: 20),
        EchoPanel(
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(top: 12),
            shape: const Border(),
            collapsedShape: const Border(),
            title: Text('账本信息', style: Theme.of(context).textTheme.titleMedium),
            subtitle: Text(
              '时区与账本标识',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '账本 ID',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: SelectableText(
                  services.ledger.currentLedgerId ?? '未选择',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '账本时区：' +
                      (services.configurationNeedsConfirmation
                          ? '配置待确认'
                          : services.config?.timeZoneId ?? '未填写'),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '数据保存在此设备。未配置同步时，仍可离线添加、编辑订阅和记录付款。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'EchoSubs · 订阅簿',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _SettingsLink extends StatelessWidget {
  const _SettingsLink({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final EchoSymbol icon;
  final String title, subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final c = EchoColors.of(context);
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: c.text,
        padding: const EdgeInsets.all(18),
        alignment: Alignment.centerLeft,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: c.accentSoft,
              borderRadius: BorderRadius.circular(9),
            ),
            child: EchoIcon(icon, color: c.accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: 12),
          EchoIcon(EchoSymbol.arrow, size: 16, color: c.muted),
        ],
      ),
    );
  }
}

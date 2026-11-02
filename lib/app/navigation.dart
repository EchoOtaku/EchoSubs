import 'package:flutter/material.dart';
import '../core/model/subscription.dart';
import '../features/ledger/ui/overview_page.dart';
import '../features/ledger/ui/subscription_list_page.dart';
import '../features/ledger/ui/subscription_editor.dart';
import '../features/ledger/ui/subscription_detail_page.dart';
import '../features/ledger/ui/calendar_page.dart';
import '../features/ledger/ui/payments_page.dart';
import '../features/ledger/ui/settings_page.dart';
import '../features/sync/ui/conflicts_page.dart';
import '../features/sync/ui/sync_settings_page.dart';
import 'design_system.dart';
import 'services.dart';

class LedgerNavigation extends StatefulWidget {
  const LedgerNavigation({super.key, required this.services});
  final AppServices services;
  @override
  State<LedgerNavigation> createState() => _LedgerNavigationState();
}

class _LedgerNavigationState extends State<LedgerNavigation> {
  int selected = 0;
  static const labels = ['总览', '订阅', '日历', '付款', '设置'];
  static const keys = [
    'overview',
    'subscriptions',
    'calendar',
    'payments',
    'settings',
  ];
  static const icons = [
    EchoSymbol.overview,
    EchoSymbol.subscriptions,
    EchoSymbol.calendar,
    EchoSymbol.payments,
    EchoSymbol.settings,
  ];
  void add() => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => SubscriptionEditor(services: widget.services),
    ),
  );
  void open(Subscription value) => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => SubscriptionDetailPage(
        services: widget.services,
        subscriptionId: value.id,
      ),
    ),
  );
  void syncSettings() => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => SyncSettingsPage(services: widget.services),
    ),
  );
  void change(int index) => setState(() => selected = index);
  void toggleTheme() => widget.services.setTheme(
    Theme.of(context).brightness == Brightness.dark
        ? ThemeMode.light
        : ThemeMode.dark,
  );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.services,
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 720;
        final services = widget.services;
        final c = EchoColors.of(context);
        final dark = Theme.of(context).brightness == Brightness.dark;
        final pages = [
          OverviewPage(services: services, onAdd: add, onOpen: open),
          SubscriptionListPage(services: services, onAdd: add, onOpen: open),
          CalendarPage(services: services, onOpen: open),
          PaymentsPage(services: services),
          SettingsPage(services: services),
        ];
        final snapshot = services.snapshot;
        Widget body;
        if (services.loading && snapshot == null) {
          body = const Center(
            child: SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                semanticsLabel: '正在读取本地账本',
              ),
            ),
          );
        } else if (snapshot == null) {
          body = Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  EchoIcon(EchoSymbol.lock, size: 32, color: c.muted),
                  const SizedBox(height: 16),
                  Text(services.error ?? '账本暂不可用'),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: services.reload,
                    child: const Text('重试读取'),
                  ),
                ],
              ),
            ),
          );
        } else {
          final conflictCount = snapshot.projection.conflicts.length;
          body = Column(
            children: [
              if (services.loading) const LinearProgressIndicator(minHeight: 2),
              if (services.error != null)
                EchoNotice(
                  message: services.error!,
                  danger: true,
                  action: services.refresh,
                  actionLabel: '重试',
                ),
              if (conflictCount > 0)
                EchoNotice(
                  message: '有 $conflictCount 项未解决冲突，受影响的内容暂不作为确定值显示。',
                  actionLabel: '处理冲突',
                  action: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => ConflictsPage(services: services),
                    ),
                  ),
                ),
              Expanded(
                child: IndexedStack(
                  key: ValueKey(snapshot.metadata.id),
                  index: selected,
                  children: pages,
                ),
              ),
            ],
          );
        }
        final themeButton = IconButton(
          key: const ValueKey('shell.theme'),
          tooltip: dark ? '切换为浅色' : '切换为深色',
          onPressed: toggleTheme,
          icon: EchoIcon(dark ? EchoSymbol.sun : EchoSymbol.moon),
        );
        return Scaffold(
          appBar: desktop
              ? null
              : AppBar(
                  title: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      EchoMark(size: 28),
                      SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          'EchoSubs',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    themeButton,
                    IconButton(
                      tooltip: '添加订阅',
                      onPressed: snapshot == null ? null : add,
                      icon: const EchoIcon(EchoSymbol.add),
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
          body: SafeArea(
            child: Row(
              children: [
                if (desktop)
                  Container(
                    key: const ValueKey('shell.sidebar'),
                    width: constraints.maxWidth >= 1200 ? 224 : 204,
                    decoration: BoxDecoration(
                      color: c.panel,
                      border: Border(right: BorderSide(color: c.border)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(22, 28, 20, 24),
                          child: Row(
                            children: [
                              const EchoMark(),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'EchoSubs',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: -.4,
                                          ),
                                    ),
                                    Text(
                                      '订阅工作台',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 8, 20, 8),
                          child: Text(
                            '账本',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ),
                        Expanded(
                          child: SingleChildScrollView(
                            child: Column(
                              children: [
                                for (var i = 0; i < labels.length; i++)
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      12,
                                      3,
                                      12,
                                      3,
                                    ),
                                    child: _NavItem(
                                      key: ValueKey('nav.' + keys[i]),
                                      label: labels[i],
                                      symbol: icons[i],
                                      selected: selected == i,
                                      onPressed: () => change(i),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: EchoPanel(
                            padding: const EdgeInsets.all(12),
                            color: c.soft,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                EchoIcon(
                                  EchoSymbol.lock,
                                  size: 18,
                                  color: c.accent,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '本地账本',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.labelLarge,
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        '离线也能记录与管理',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: Column(
                    children: [
                      if (desktop)
                        Container(
                          height: 64,
                          padding: const EdgeInsets.symmetric(horizontal: 28),
                          decoration: BoxDecoration(
                            color: c.panel,
                            border: Border(bottom: BorderSide(color: c.border)),
                          ),
                          child: Row(
                            children: [
                              Text(
                                '工作台',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 10),
                                child: EchoIcon(EchoSymbol.arrow, size: 12),
                              ),
                              Text(
                                labels[selected],
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                              const Spacer(),
                              OutlinedButton.icon(
                                onPressed: snapshot == null
                                    ? null
                                    : syncSettings,
                                icon: const EchoIcon(
                                  EchoSymbol.cloud,
                                  size: 17,
                                ),
                                label: Text(
                                  services.syncStatus.report.lan.enabled ||
                                          services
                                              .syncStatus
                                              .report
                                              .webdav
                                              .enabled
                                      ? '同步设置'
                                      : '本地模式',
                                ),
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(color: c.border),
                                  minimumSize: const Size(48, 40),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              themeButton,
                            ],
                          ),
                        ),
                      Expanded(child: body),
                    ],
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: desktop
              ? null
              : Container(
                  key: const ValueKey('shell.bottom-nav'),
                  decoration: BoxDecoration(
                    color: c.panel,
                    border: Border(top: BorderSide(color: c.border)),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                      child: Row(
                        children: [
                          for (var i = 0; i < labels.length; i++)
                            Expanded(
                              child: _NavItem(
                                key: ValueKey('nav.' + keys[i]),
                                label: labels[i],
                                symbol: icons[i],
                                selected: selected == i,
                                compact: true,
                                onPressed: () => change(i),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
        );
      },
    ),
  );
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    super.key,
    required this.label,
    required this.symbol,
    required this.selected,
    required this.onPressed,
    this.compact = false,
  });
  final String label;
  final EchoSymbol symbol;
  final bool selected, compact;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) {
    final c = EchoColors.of(context);
    final color = selected ? c.accent : c.muted;
    return Semantics(
      selected: selected,
      child: Stack(
        children: [
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: onPressed,
              style: ButtonStyle(
                foregroundColor: WidgetStatePropertyAll(color),
                backgroundColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.hovered)
                      ? c.soft
                      : selected && !compact
                      ? c.accentSoft
                      : Colors.transparent,
                ),
                minimumSize: WidgetStatePropertyAll(
                  Size(48, compact ? 64 : 48),
                ),
                padding: WidgetStatePropertyAll(
                  compact
                      ? const EdgeInsets.symmetric(horizontal: 2, vertical: 10)
                      : const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 13,
                        ),
                ),
                shape: WidgetStatePropertyAll(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                side: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.focused)
                      ? BorderSide(color: c.accent, width: 2)
                      : BorderSide.none,
                ),
              ),
              child: compact
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        EchoIcon(symbol, color: color),
                        const SizedBox(height: 5),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: color,
                          ),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        EchoIcon(symbol, color: color),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            label,
                            style: TextStyle(
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          if (selected && !compact)
            Positioned(
              left: 0,
              top: 12,
              bottom: 12,
              child: Container(
                width: 3,
                decoration: BoxDecoration(
                  color: c.accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../core/model/subscription.dart';
import '../features/ledger/ui/overview_page.dart';
import '../features/ledger/ui/subscription_list_page.dart';
import '../features/ledger/ui/subscription_editor.dart';
import '../features/ledger/ui/subscription_detail_page.dart';
import '../features/ledger/ui/calendar_page.dart';
import '../features/ledger/ui/payments_page.dart';
import '../features/ledger/ui/settings_page.dart';
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
    Icons.dashboard_outlined,
    Icons.subscriptions_outlined,
    Icons.calendar_month_outlined,
    Icons.receipt_long_outlined,
    Icons.settings_outlined,
  ];
  void add() => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => SubscriptionEditor(services: widget.services),
    ),
  );
  void open(Subscription s) => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => SubscriptionDetailPage(
        services: widget.services,
        subscriptionId: s.id,
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.services,
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 720;
        final services = widget.services;
        final pages = [
          OverviewPage(services: services, onAdd: add, onOpen: open),
          SubscriptionListPage(services: services, onAdd: add, onOpen: open),
          CalendarPage(services: services, onOpen: open),
          PaymentsPage(services: services),
          SettingsPage(services: services),
        ];
        Widget body;
        if (services.loading) {
          body = const Center(
            child: CircularProgressIndicator(semanticsLabel: '正在读取本地账本'),
          );
        } else if (services.snapshot == null) {
          body = Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline, size: 40),
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
          body = Column(
            children: [
              if (services.error != null)
                MaterialBanner(
                  content: Text(services.error!),
                  leading: const Icon(Icons.error_outline),
                  actions: [
                    TextButton(
                      onPressed: services.refresh,
                      child: const Text('重试'),
                    ),
                  ],
                ),
              if (services.snapshot!.projection.conflicts.isNotEmpty)
                MaterialBanner(
                  content: Text(
                    '有 ${services.snapshot!.projection.conflicts.length} 项未解决冲突，受影响的内容暂不作为确定值显示。',
                  ),
                  leading: const Icon(Icons.warning_amber_outlined),
                  actions: const [SizedBox.shrink()],
                ),
              Expanded(child: pages[selected]),
            ],
          );
        }
        return Scaffold(
          appBar: desktop
              ? null
              : AppBar(
                  title: const Text('EchoSubs'),
                  actions: [
                    IconButton(
                      tooltip: '添加订阅',
                      onPressed: services.snapshot == null ? null : add,
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
          body: SafeArea(
            child: Row(
              children: [
                if (desktop)
                  SizedBox(
                    width: 212,
                    child: Material(
                      color: Theme.of(context).colorScheme.surface,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(24, 28, 16, 8),
                            child: Text(
                              'EchoSubs',
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(24, 0, 16, 28),
                            child: Text(
                              '本地订阅簿',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          for (int i = 0; i < labels.length; i++)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                              child: ListTile(
                                key: ValueKey('nav.${keys[i]}'),
                                leading: Icon(icons[i]),
                                title: Text(labels[i]),
                                selected: selected == i,
                                selectedTileColor: Theme.of(
                                  context,
                                ).colorScheme.secondaryContainer,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                onTap: () => setState(() {
                                  selected = i;
                                }),
                              ),
                            ),
                          const Spacer(),
                          const Padding(
                            padding: EdgeInsets.all(24),
                            child: Row(
                              children: [
                                Icon(Icons.offline_bolt_outlined, size: 18),
                                SizedBox(width: 8),
                                Expanded(child: Text('离线可用')),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (desktop) const VerticalDivider(width: 1),
                Expanded(child: body),
              ],
            ),
          ),
          bottomNavigationBar: desktop
              ? null
              : NavigationBar(
                  selectedIndex: selected,
                  onDestinationSelected: (i) => setState(() {
                    selected = i;
                  }),
                  destinations: [
                    for (int i = 0; i < labels.length; i++)
                      NavigationDestination(
                        key: ValueKey('nav.${keys[i]}'),
                        icon: Icon(icons[i]),
                        label: labels[i],
                      ),
                  ],
                ),
        );
      },
    ),
  );
}

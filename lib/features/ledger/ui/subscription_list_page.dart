import 'package:flutter/material.dart';
import '../../../app/design_system.dart';
import '../../../app/services.dart';
import '../../../core/model/subscription.dart';
import 'widgets.dart';

class SubscriptionListPage extends StatefulWidget {
  const SubscriptionListPage({
    super.key,
    required this.services,
    required this.onAdd,
    required this.onOpen,
  });
  final AppServices services;
  final VoidCallback onAdd;
  final ValueChanged<Subscription> onOpen;
  @override
  State<SubscriptionListPage> createState() => _SubscriptionListPageState();
}

class _SubscriptionListPageState extends State<SubscriptionListPage> {
  final _search = TextEditingController();
  final _filtersScroll = ScrollController();
  String query = '';
  String? category;
  bool archived = false;
  @override
  void dispose() {
    _search.dispose();
    _filtersScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final services = widget.services;
    final c = EchoColors.of(context);
    final sortedCategories = services.categories.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final currentCategory =
        services.categories.any((value) => value.id == category)
        ? category
        : null;
    final filtered =
        services.subscriptions
            .where(
              (value) =>
                  (archived || value.status != SubscriptionStatus.archived) &&
                  (currentCategory == null ||
                      value.categoryId == currentCategory) &&
                  (value.name + ' ' + (value.provider ?? ''))
                      .toLowerCase()
                      .contains(query.toLowerCase()),
            )
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    final count = filtered.length;
    return PageContent(
      children: [
        SectionTitle(
          '订阅',
          subtitle: '管理服务、价格与使用期限',
          trailing: FilledButton.icon(
            key: const ValueKey('add.subscription'),
            onPressed: widget.onAdd,
            icon: const EchoIcon(EchoSymbol.add, size: 18),
            label: const Text('添加订阅'),
          ),
        ),
        TextField(
          key: const ValueKey('subscriptions.search'),
          controller: _search,
          decoration: InputDecoration(
            hintText: '搜索服务或提供商',
            prefixIcon: const Padding(
              padding: EdgeInsets.all(14),
              child: EchoIcon(EchoSymbol.search, size: 18),
            ),
            suffixIcon: query.isEmpty
                ? null
                : IconButton(
                    tooltip: '清空搜索',
                    icon: const EchoIcon(EchoSymbol.close, size: 16),
                    onPressed: () {
                      _search.clear();
                      setState(() => query = '');
                    },
                  ),
          ),
          onChanged: (value) => setState(() => query = value),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final filters = <Widget>[
              EchoChoice(
                label: '全部分类',
                selected: currentCategory == null,
                onPressed: () => setState(() => category = null),
              ),
              for (final value in sortedCategories)
                EchoChoice(
                  label: value.name,
                  selected: currentCategory == value.id,
                  onPressed: () => setState(() => category = value.id),
                ),
              EchoChoice(
                label: '包含归档',
                selected: archived,
                onPressed: () => setState(() => archived = !archived),
              ),
            ];
            return constraints.maxWidth >= 620
                ? Wrap(spacing: 8, runSpacing: 8, children: filters)
                : Semantics(
                    label: '分类筛选，可横向滚动',
                    child: SingleChildScrollView(
                      key: const PageStorageKey('subscriptions.filters'),
                      controller: _filtersScroll,
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (var i = 0; i < filters.length; i++)
                            Padding(
                              padding: EdgeInsets.only(
                                right: i == filters.length - 1 ? 0 : 8,
                              ),
                              child: filters[i],
                            ),
                        ],
                      ),
                    ),
                  );
          },
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            Text('服务列表', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(width: 10),
            EchoBadge('$count 项'),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) => constraints.maxWidth < 760
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.fromLTRB(72, 0, 46, 10),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 5,
                        child: Text(
                          '服务',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        flex: 3,
                        child: Text(
                          '金额与周期',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 4,
                        child: Text(
                          '权益与续费',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                    ],
                  ),
                ),
        ),
        if (services.subscriptions.isEmpty)
          EchoPanel(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                EchoIcon(EchoSymbol.subscriptions, color: c.accent, size: 28),
                const SizedBox(height: 14),
                Text('还没有订阅', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                const Text('添加第一项服务，记录价格与到期日。'),
              ],
            ),
          )
        else if (filtered.isEmpty)
          EchoPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '没有符合条件的订阅',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                const Text('尝试其他关键词，或切换分类与归档筛选。'),
              ],
            ),
          ),
        for (final value in filtered)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: SubscriptionRow(
              value: value,
              today: services.today,
              onTap: () => widget.onOpen(value),
            ),
          ),
      ],
    );
  }
}

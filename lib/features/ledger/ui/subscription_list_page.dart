import 'package:flutter/material.dart';
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
  String query = '';
  String? category;
  bool archived = false;
  @override
  Widget build(BuildContext context) {
    final services = widget.services;
    final filtered =
        services.subscriptions
            .where(
              (s) =>
                  (archived || s.status != SubscriptionStatus.archived) &&
                  (category == null || s.categoryId == category) &&
                  '${s.name} ${s.provider ?? ''}'.toLowerCase().contains(
                    query.toLowerCase(),
                  ),
            )
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    return PageContent(
      children: [
        const SectionTitle('订阅', subtitle: '管理服务、价格与使用期限'),
        TextField(
          key: const ValueKey('subscriptions.search'),
          decoration: const InputDecoration(
            labelText: '搜索服务或提供商',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (value) => setState(() {
            query = value;
          }),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilterChip(
              label: const Text('全部分类'),
              selected: category == null,
              onSelected: (_) => setState(() {
                category = null;
              }),
            ),
            for (final c in services.categories)
              FilterChip(
                label: Text(c.name),
                selected: category == c.id,
                onSelected: (_) => setState(() {
                  category = c.id;
                }),
              ),
            FilterChip(
              label: const Text('包含归档'),
              selected: archived,
              onSelected: (value) => setState(() {
                archived = value;
              }),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            key: const ValueKey('add.subscription'),
            onPressed: widget.onAdd,
            icon: const Icon(Icons.add),
            label: const Text('添加订阅'),
          ),
        ),
        const SizedBox(height: 16),
        if (services.subscriptions.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('还没有订阅，添加第一项服务吧。'),
            ),
          )
        else if (filtered.isEmpty)
          const Padding(padding: EdgeInsets.all(24), child: Text('没有符合条件的订阅')),
        for (final value in filtered)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SubscriptionRow(
              value: value,
              onTap: () => widget.onOpen(value),
            ),
          ),
      ],
    );
  }
}

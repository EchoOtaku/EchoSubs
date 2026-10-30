import 'package:flutter/material.dart';
import '../../../app/services.dart';
import '../../../core/model/money.dart';
import '../../../core/model/subscription.dart';
import '../cost_projection.dart';
import 'widgets.dart';

class OverviewPage extends StatelessWidget {
  const OverviewPage({
    super.key,
    required this.services,
    required this.onAdd,
    required this.onOpen,
  });
  final AppServices services;
  final VoidCallback onAdd;
  final ValueChanged<Subscription> onOpen;
  @override
  Widget build(BuildContext context) {
    final active = services.subscriptions
        .where((s) => s.status == SubscriptionStatus.active)
        .toList();
    final upcoming = active.where((s) => relevantDate(s) != null).toList()
      ..sort((a, b) => relevantDate(a)!.compareTo(relevantDate(b)!));
    Widget costs;
    try {
      final totals = summarizeCosts(services.subscriptions, services.payments);
      costs = LayoutBuilder(
        builder: (context, constraints) {
          final cards = [
            _CostCard(
              title: '预计支出',
              subtitle: '活跃的固定周期订阅 · 折算估计',
              monthly: totals.estimatedMonthly,
              yearly: totals.estimatedYearly,
            ),
            _CostCard(
              title: '实际支出',
              subtitle: '累计已记录付款 · 不是本月支出',
              monthly: totals.actualPaid,
            ),
          ];
          return constraints.maxWidth >= 600
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: cards[0]),
                    const SizedBox(width: 16),
                    Expanded(child: cards[1]),
                  ],
                )
              : Column(
                  children: [cards[0], const SizedBox(height: 16), cards[1]],
                );
        },
      );
    } on Object catch (e) {
      costs = Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text('费用暂时无法汇总：${safeError(e)}'),
        ),
      );
    }
    return PageContent(
      children: [
        SectionTitle(
          '总览',
          subtitle: '${services.today.toJson()} · ${active.length} 项使用中的服务',
        ),
        costs,
        const SizedBox(height: 28),
        if (services.subscriptions.isEmpty)
          EmptyLedger(onAdd: onAdd)
        else ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  '到期与续费',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                key: const ValueKey('add.subscription'),
                tooltip: '添加订阅',
                onPressed: onAdd,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (upcoming.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('暂无已填写的到期或续费日期。'),
              ),
            ),
          for (final s in upcoming.take(8))
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SubscriptionRow(
                value: s,
                today: services.today,
                onTap: () => onOpen(s),
              ),
            ),
          const SizedBox(height: 12),
          Text(
            '价格未知、按量计费和买断项目不计入周期估算。实际支出只来自付款记录。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}

class _CostCard extends StatelessWidget {
  const _CostCard({
    required this.title,
    required this.subtitle,
    required this.monthly,
    this.yearly,
  });
  final String title, subtitle;
  final Map<String, Money> monthly;
  final Map<String, Money>? yearly;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                yearly == null
                    ? Icons.receipt_long_outlined
                    : Icons.payments_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (monthly.isEmpty)
            Text(
              yearly == null ? '暂无付款记录' : '暂无可估算金额',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          for (final value in monthly.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '${moneyText(value)}${yearly == null ? '' : ' / 月'}',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          if (yearly != null)
            for (final value in yearly!.values) Text('${moneyText(value)} / 年'),
          const SizedBox(height: 12),
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    ),
  );
}

import 'package:flutter/material.dart';
import '../../../app/design_system.dart';
import '../../../app/services.dart';
import '../../../core/model/money.dart';
import '../../../core/model/subscription.dart';
import '../../sync/sync_status.dart';
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
    final c = EchoColors.of(context);
    final active = services.subscriptions
        .where((s) => s.status == SubscriptionStatus.active)
        .toList();
    final upcoming = active.where((s) => relevantDate(s) != null).toList()
      ..sort((a, b) => relevantDate(a)!.compareTo(relevantDate(b)!));
    final attention = upcoming
        .where((s) => relevantDate(s)!.compareTo(services.today) < 0)
        .length;
    final day = services.today.toJson();
    final activeCount = active.length;
    final categories = <String?, int>{
      for (final category in services.categories) category.id: 0,
      for (final category in active.map((s) => s.categoryId)) category: 0,
    };
    for (final value in active) {
      categories.update(
        value.categoryId,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    Widget costs;
    try {
      final totals = summarizeCosts(services.subscriptions, services.payments);
      costs = _CostOverview(
        estimatedMonthly: totals.estimatedMonthly,
        estimatedYearly: totals.estimatedYearly,
        actualPaid: totals.actualPaid,
      );
    } on Object catch (e) {
      final message = safeError(e);
      costs = EchoPanel(child: Text('费用暂时无法汇总：$message'));
    }
    final dueGroup = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '到期与续费',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            EchoBadge(upcoming.isEmpty ? '暂无安排' : '按日期排列'),
          ],
        ),
        const SizedBox(height: 14),
        if (services.subscriptions.isEmpty)
          EmptyLedger(onAdd: onAdd)
        else if (upcoming.isEmpty)
          EchoPanel(
            child: Row(
              children: [
                EchoIcon(EchoSymbol.calendar, color: c.accent),
                const SizedBox(width: 12),
                const Expanded(child: Text('暂无已填写的到期或续费日期。')),
              ],
            ),
          ),
        for (final value in upcoming.take(8))
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: SubscriptionRow(
              value: value,
              today: services.today,
              showDateMarker: true,
              onTap: () => onOpen(value),
            ),
          ),
        const SizedBox(height: 8),
        Text(
          '价格未知、按量计费和买断项目不计入周期估算。实际支出只来自付款记录。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
    final categoryGroup = EchoPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('分类总览', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          if (categories.isEmpty)
            Text('添加订阅时可以创建分类。', style: Theme.of(context).textTheme.bodySmall),
          for (final entry in categories.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          entry.key == null
                              ? '未分类'
                              : services.categories
                                        .where(
                                          (category) =>
                                              category.id == entry.key,
                                        )
                                        .firstOrNull
                                        ?.name ??
                                    '未知分类',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        entry.value.toString() + ' 项使用中',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  ExcludeSemantics(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: active.isEmpty ? 0 : entry.value / active.length,
                        minHeight: 4,
                        backgroundColor: c.soft,
                        color: c.accent.withValues(alpha: .65),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
    return PageContent(
      children: [
        SectionTitle(
          '总览',
          subtitle: '$day · $activeCount 项使用中的服务',
          trailing: services.subscriptions.isEmpty
              ? null
              : FilledButton.icon(
                  key: const ValueKey('add.subscription'),
                  onPressed: onAdd,
                  icon: const EchoIcon(EchoSymbol.add, size: 18),
                  label: const Text('添加订阅'),
                ),
        ),
        _SummaryStrip(
          active: activeCount,
          attention: attention,
          payments: services.payments.length,
        ),
        const SizedBox(height: 24),
        if (services.syncStatus.failure != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: EchoNotice(
              message: '同步异常：' + services.syncStatus.failure!,
              danger: true,
            ),
          ),
        for (final channel in [
          services.syncStatus.report.lan,
          services.syncStatus.report.webdav,
        ])
          if (channel.enabled && !channel.succeeded)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _SyncIssue(
                label: identical(channel, services.syncStatus.report.lan)
                    ? '局域网同步待处理'
                    : 'WebDAV 同步待处理',
                report: channel,
              ),
            ),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= 1100) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: dueGroup),
                  const SizedBox(width: 24),
                  SizedBox(
                    width: 316,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '费用概览',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                        const SizedBox(height: 12),
                        costs,
                        const SizedBox(height: 20),
                        categoryGroup,
                      ],
                    ),
                  ),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                dueGroup,
                const SizedBox(height: 28),
                costs,
                const SizedBox(height: 24),
                categoryGroup,
              ],
            );
          },
        ),
      ],
    );
  }
}

class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({
    required this.active,
    required this.attention,
    required this.payments,
  });
  final int active, attention, payments;
  @override
  Widget build(BuildContext context) {
    final c = EchoColors.of(context);
    Widget item(String label, int count, {Color? color}) => Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 5),
            Text(
              '$count',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(color: color ?? c.text),
            ),
          ],
        ),
      ),
    );
    return EchoPanel(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          item('使用中', active),
          Container(height: 46, width: 1, color: c.border),
          item('需关注', attention, color: attention > 0 ? c.warning : c.text),
          Container(height: 46, width: 1, color: c.border),
          item('付款记录', payments),
        ],
      ),
    );
  }
}

class _SyncIssue extends StatelessWidget {
  const _SyncIssue({required this.label, required this.report});
  final String label;
  final ChannelReport report;
  @override
  Widget build(BuildContext context) {
    final upload = report.pendingUpload,
        dependencies = report.pendingDependencies;
    final conflicts = report.conflicts, quarantined = report.quarantined;
    final more = report.errors.isEmpty ? '' : ' · ' + report.errors.join('；');
    return EchoNotice(
      message:
          '$label：待上传 $upload · 待补依赖 $dependencies · 冲突 $conflicts · 隔离 $quarantined$more',
    );
  }
}

class _CostOverview extends StatelessWidget {
  const _CostOverview({
    required this.estimatedMonthly,
    required this.estimatedYearly,
    required this.actualPaid,
  });
  final Map<String, Money> estimatedMonthly, estimatedYearly, actualPaid;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final forecast = _CostCard(
        title: '预计支出',
        subtitle: '活跃的固定周期订阅 · 折算估计',
        monthly: estimatedMonthly,
        yearly: estimatedYearly,
      );
      final actual = _CostCard(
        title: '实际支出',
        subtitle: '累计已记录付款',
        monthly: actualPaid,
      );
      if (constraints.maxWidth >= 620) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: forecast),
            const SizedBox(width: 16),
            Expanded(child: actual),
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [forecast, const SizedBox(height: 16), actual],
      );
    },
  );
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
  Widget build(BuildContext context) {
    final c = EchoColors.of(context);
    final forecast = yearly != null;
    final monthlyValues = monthly.values.toList()
      ..sort((a, b) => a.currency.compareTo(b.currency));
    final yearlyValues = yearly?.values.toList()
      ?..sort((a, b) => a.currency.compareTo(b.currency));
    return EchoPanel(
      color: forecast ? c.accentSoft : c.panel,
      borderColor: forecast ? c.accent.withValues(alpha: .2) : c.border,
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              EchoIcon(
                forecast ? EchoSymbol.subscriptions : EchoSymbol.payments,
                color: forecast ? c.accent : c.muted,
                size: 18,
              ),
              const SizedBox(width: 9),
              Text(title, style: Theme.of(context).textTheme.titleSmall),
            ],
          ),
          const SizedBox(height: 18),
          if (monthly.isEmpty)
            Text(
              forecast ? '暂无可估算金额' : '暂无付款记录',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          for (final value in monthlyValues)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                moneyText(value) + (forecast ? ' / 月' : ''),
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  fontSize: 27,
                  color: forecast ? c.accent : c.text,
                ),
              ),
            ),
          if (yearly != null)
            for (final value in yearlyValues!)
              Text(
                moneyText(value) + ' / 年',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          const SizedBox(height: 12),
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

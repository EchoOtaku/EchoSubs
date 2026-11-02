import 'package:flutter/material.dart';
import '../../../core/model/civil_date.dart';
import '../../../core/model/money.dart';
import '../../../core/model/subscription.dart';

String moneyText(Money? money) =>
    money == null ? '未填写' : '${money.currency} ${decimalText(money)}';
String decimalText(Money money) {
  final text = money.minorUnits.toString().padLeft(money.scale + 1, '0');
  return money.scale == 0
      ? text
      : '${text.substring(0, text.length - money.scale)}.${text.substring(text.length - money.scale)}';
}

String dateText(CivilDate? date) => date?.toJson() ?? '未填写';
String statusText(SubscriptionStatus status) => switch (status) {
  SubscriptionStatus.active => '使用中',
  SubscriptionStatus.paused => '已暂停',
  SubscriptionStatus.archived => '已归档',
};
String billingText(BillingType type) => switch (type) {
  BillingType.fixed => '固定周期',
  BillingType.metered => '按量计费',
  BillingType.lifetime => '一次性买断',
};
String cycleText(Subscription s) {
  final c = s.cycle;
  if (s.billingType != BillingType.fixed || c == null)
    return billingText(s.billingType);
  return '每 ${c.count} ${switch (c.unit) {
    CycleUnit.day => '天',
    CycleUnit.week => '周',
    CycleUnit.month => '月',
    CycleUnit.year => '年',
  }}';
}

CivilDate? relevantDate(Subscription s) {
  final dates = [
    s.entitlementEnd,
    s.nextRenewalDate,
  ].whereType<CivilDate>().toList()..sort();
  return dates.firstOrNull;
}

class PageContent extends StatelessWidget {
  const PageContent({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => ListView(
    padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 720 ? 16 : 24),
    children: [
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    ],
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.subtitle});
  final String title;
  final String? subtitle;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              subtitle!,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
      ],
    ),
  );
}

class SubscriptionRow extends StatelessWidget {
  const SubscriptionRow({
    super.key,
    required this.value,
    required this.onTap,
    this.today,
  });
  final Subscription value;
  final VoidCallback onTap;
  final CivilDate? today;
  @override
  Widget build(BuildContext context) {
    final overdue =
        relevantDate(value) != null &&
        today != null &&
        relevantDate(value)!.compareTo(today!) < 0;
    final entitlementOverdue =
        today != null &&
        value.entitlementEnd != null &&
        value.entitlementEnd!.compareTo(today!) < 0;
    final renewalOverdue =
        today != null &&
        value.nextRenewalDate != null &&
        value.nextRenewalDate!.compareTo(today!) < 0;
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          child: Icon(
            overdue ? Icons.event_busy_outlined : Icons.subscriptions_outlined,
          ),
        ),
        title: Text(
          value.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (value.provider?.isNotEmpty == true) Text(value.provider!),
              Text('${moneyText(value.price)} · ${cycleText(value)}'),
              Text(
                '${statusText(value.status)}${entitlementOverdue ? ' · 权益已过期' : ''}${renewalOverdue ? ' · 预计续费已逾期（待确认）' : ''}',
              ),
              if (value.entitlementEnd != null)
                Text('权益到期 ${dateText(value.entitlementEnd)}'),
              if (value.nextRenewalDate != null)
                Text('预计续费 ${dateText(value.nextRenewalDate)}'),
            ],
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

class EmptyLedger extends StatelessWidget {
  const EmptyLedger({super.key, required this.onAdd});
  final VoidCallback onAdd;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          Icon(
            Icons.subscriptions_outlined,
            size: 40,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text('从第一项订阅开始', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text('记录价格、权益到期与付款，让每一项服务心中有数。', textAlign: TextAlign.center),
          const SizedBox(height: 20),
          FilledButton.icon(
            key: const ValueKey('add.subscription'),
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('添加订阅'),
          ),
        ],
      ),
    ),
  );
}

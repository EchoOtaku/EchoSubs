import 'package:flutter/material.dart';
import '../../../app/design_system.dart';
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

class PageContent extends StatefulWidget {
  const PageContent({super.key, required this.children, this.maxWidth = 1160});
  final List<Widget> children;
  final double maxWidth;
  @override
  State<PageContent> createState() => _PageContentState();
}

class _PageContentState extends State<PageContent> {
  final _scroll = ScrollController();
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final gutter = constraints.maxWidth >= 1000
          ? 28.0
          : constraints.maxWidth >= 600
          ? 22.0
          : 16.0;
      return ListView(
        controller: _scroll,
        primary: false,
        padding: EdgeInsets.fromLTRB(gutter, 26, gutter, 32),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: widget.maxWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: widget.children,
              ),
            ),
          ),
        ],
      );
    },
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.subtitle, this.trailing});
  final String title;
  final String? subtitle;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final heading = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  subtitle!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        );
        if (trailing == null) return heading;
        final largeText = MediaQuery.textScalerOf(context).scale(14) > 24;
        if (constraints.maxWidth < 340 ||
            (constraints.maxWidth < 560 && largeText)) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              heading,
              const SizedBox(height: 14),
              Align(alignment: Alignment.centerLeft, child: trailing),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: heading),
            const SizedBox(width: 20),
            trailing!,
          ],
        );
      },
    ),
  );
}

class EchoActionBar extends StatelessWidget {
  const EchoActionBar({
    super.key,
    required this.primary,
    required this.onCancel,
  });
  final Widget primary;
  final VoidCallback? onCancel;
  @override
  Widget build(BuildContext context) {
    final c = EchoColors.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.panel,
          border: Border(top: BorderSide(color: c.border)),
        ),
        child: SafeArea(
          top: false,
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final cancel = TextButton(
                      onPressed: onCancel,
                      child: const Text('取消'),
                    );
                    return constraints.maxWidth < 520
                        ? Row(
                            children: [
                              cancel,
                              const SizedBox(width: 12),
                              Expanded(child: primary),
                            ],
                          )
                        : Row(
                            children: [
                              cancel,
                              const Spacer(),
                              SizedBox(width: 220, child: primary),
                            ],
                          );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ServiceAvatar extends StatelessWidget {
  const ServiceAvatar(this.name, {super.key, this.size = 42});
  final String name;
  final double size;
  @override
  Widget build(BuildContext context) {
    final c = EchoColors.of(context);
    final trimmed = name.trim();
    final initial = trimmed.isEmpty
        ? '?'
        : String.fromCharCode(trimmed.runes.first).toUpperCase();
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.soft,
          border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          initial,
          style: TextStyle(
            fontSize: size * .4,
            fontWeight: FontWeight.w700,
            color: c.muted,
          ),
        ),
      ),
    );
  }
}

class SubscriptionRow extends StatelessWidget {
  const SubscriptionRow({
    super.key,
    required this.value,
    required this.onTap,
    this.today,
    this.showDateMarker = false,
  });
  final Subscription value;
  final VoidCallback onTap;
  final CivilDate? today;
  final bool showDateMarker;
  @override
  Widget build(BuildContext context) {
    final c = EchoColors.of(context);
    final entitlementOverdue =
        today != null &&
        value.entitlementEnd != null &&
        value.entitlementEnd!.compareTo(today!) < 0;
    final renewalOverdue =
        today != null &&
        value.nextRenewalDate != null &&
        value.nextRenewalDate!.compareTo(today!) < 0;
    final end = dateText(value.entitlementEnd);
    final renewal = dateText(value.nextRenewalDate);
    final price = moneyText(value.price);
    final cycle = cycleText(value);
    final provider = value.provider;
    final sameDates =
        value.entitlementEnd != null &&
        value.entitlementEnd == value.nextRenewalDate;
    final dates = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (sameDates)
          Text(
            '权益到期 / 续费 $end',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: entitlementOverdue ? c.negative : c.muted,
            ),
          )
        else ...[
          if (value.entitlementEnd != null)
            Text(
              '权益到期 $end',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: entitlementOverdue ? c.negative : c.muted,
              ),
            ),
          if (value.nextRenewalDate != null)
            Text(
              '预计续费 $renewal',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: renewalOverdue ? c.warning : c.muted,
              ),
            ),
        ],
      ],
    );
    final identity = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value.name,
          style: Theme.of(context).textTheme.titleMedium,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (provider?.isNotEmpty == true)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              provider!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        if (!showDateMarker ||
            value.status != SubscriptionStatus.active ||
            entitlementOverdue ||
            renewalOverdue) ...[
          const SizedBox(height: 7),
          Wrap(
            spacing: 6,
            runSpacing: 5,
            children: [
              if (!showDateMarker || value.status != SubscriptionStatus.active)
                EchoBadge(statusText(value.status)),
              if (entitlementOverdue)
                EchoBadge(
                  '权益已过期',
                  color: c.negative,
                  background: c.negativeSoft,
                ),
              if (renewalOverdue)
                EchoBadge(
                  '预计续费已逾期（待确认）',
                  color: c.warning,
                  background: c.warningSoft,
                ),
            ],
          ),
        ],
      ],
    );
    final amount = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          price,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 3),
        Text(cycle, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
    return EchoPanel(
      padding: EdgeInsets.zero,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.all(16),
          foregroundColor: c.text,
          alignment: Alignment.centerLeft,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(11),
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 720;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showDateMarker && relevantDate(value) != null)
                  _DateMarker(value: value, today: today)
                else
                  ServiceAvatar(value.name),
                const SizedBox(width: 14),
                Expanded(
                  child: wide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 5, child: identity),
                            const SizedBox(width: 20),
                            Expanded(flex: 3, child: amount),
                            const SizedBox(width: 16),
                            Expanded(flex: 4, child: dates),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            identity,
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 7,
                              runSpacing: 3,
                              children: [
                                Text(
                                  price,
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(
                                        fontFeatures: const [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                ),
                                Text(
                                  '· $cycle',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                            if (value.entitlementEnd != null ||
                                value.nextRenewalDate != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 7),
                                child: dates,
                              ),
                          ],
                        ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: EchoIcon(EchoSymbol.arrow, color: c.muted, size: 16),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DateMarker extends StatelessWidget {
  const _DateMarker({required this.value, this.today});
  final Subscription value;
  final CivilDate? today;
  @override
  Widget build(BuildContext context) {
    final c = EchoColors.of(context);
    final date = relevantDate(value)!;
    final late = today != null && date.compareTo(today!) < 0;
    final month = date.month;
    final day = date.day.toString().padLeft(2, '0');
    return SizedBox(
      width: 46,
      child: Column(
        children: [
          Text('$month 月', style: Theme.of(context).textTheme.labelSmall),
          Text(
            day,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: late ? c.warning : c.accent,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 3),
          Text(
            late
                ? '待确认'
                : date == value.entitlementEnd
                ? '到期'
                : '续费',
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: late ? c.warning : c.muted),
          ),
        ],
      ),
    );
  }
}

class EmptyLedger extends StatelessWidget {
  const EmptyLedger({super.key, required this.onAdd});
  final VoidCallback onAdd;
  @override
  Widget build(BuildContext context) {
    final c = EchoColors.of(context);
    return EchoPanel(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
      child: Column(
        children: [
          const EchoMark(size: 46),
          const SizedBox(height: 20),
          Text('从第一项订阅开始', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 9),
          Text(
            '记录服务、价格和到期日，随时查看接下来的续费。',
            textAlign: TextAlign.center,
            style: TextStyle(color: c.muted, height: 1.6),
          ),
          const SizedBox(height: 18),
          const Wrap(
            spacing: 7,
            runSpacing: 7,
            alignment: WrapAlignment.center,
            children: [
              EchoBadge('影音会员'),
              EchoBadge('域名'),
              EchoBadge('服务器'),
              EchoBadge('对象存储'),
            ],
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            key: const ValueKey('add.subscription'),
            onPressed: onAdd,
            icon: const EchoIcon(EchoSymbol.add, size: 18),
            label: const Text('添加订阅'),
          ),
        ],
      ),
    );
  }
}

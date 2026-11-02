import 'package:flutter/material.dart';
import '../../../app/services.dart';
import '../../../core/model/civil_date.dart';
import '../../../core/model/subscription.dart';
import 'widgets.dart';

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key, required this.services, required this.onOpen});
  final AppServices services;
  final ValueChanged<Subscription> onOpen;
  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  late int year;
  late int month;
  CivilDate? selected;
  @override
  void initState() {
    super.initState();
    final now = widget.services.today;
    year = now.year;
    month = now.month;
  }

  void move(int delta) {
    final next = DateTime.utc(year, month + delta);
    if (next.year < 1 || next.year > 9999) return;
    setState(() {
      year = next.year;
      month = next.month;
      selected = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final events =
        <({CivilDate date, Subscription subscription, String label})>[];
    for (final s in widget.services.subscriptions.where(
      (s) => s.status == SubscriptionStatus.active,
    )) {
      if (s.entitlementEnd != null)
        events.add((date: s.entitlementEnd!, subscription: s, label: '权益到期'));
      if (s.nextRenewalDate != null && s.billingType != BillingType.lifetime)
        events.add((date: s.nextRenewalDate!, subscription: s, label: '预计续费'));
    }
    final monthly =
        events
            .where((e) => e.date.year == year && e.date.month == month)
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date));
    final visible = monthly
        .where((e) => selected == null || e.date == selected)
        .toList();
    final offset = DateTime.utc(year, month, 1).weekday - 1;
    return PageContent(
      children: [
        const SectionTitle('日历', subtitle: '查看已填写的权益到期和预计续费，不将估计当作付款'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: '上个月',
                      onPressed: () => move(-1),
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          '$year 年 $month 月',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '下个月',
                      onPressed: () => move(1),
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (final d in const ['一', '二', '三', '四', '五', '六', '日'])
                      Expanded(child: Center(child: Text(d))),
                  ],
                ),
                const SizedBox(height: 8),
                LayoutBuilder(
                  builder: (context, constraints) => Wrap(
                    children: [
                      for (
                        int index = 0;
                        index < offset + CivilDate.daysInMonth(year, month);
                        index++
                      )
                        SizedBox(
                          width: constraints.maxWidth / 7,
                          height: 64,
                          child: index < offset
                              ? null
                              : Builder(
                                  builder: (context) {
                                    final day = CivilDate(
                                      year,
                                      month,
                                      index - offset + 1,
                                    );
                                    final count = monthly
                                        .where((e) => e.date == day)
                                        .length;
                                    return Semantics(
                                      label: '${day.toJson()}，$count 项到期或续费',
                                      selected: selected == day,
                                      child: TextButton(
                                        style: TextButton.styleFrom(
                                          padding: EdgeInsets.zero,
                                          backgroundColor: selected == day
                                              ? Theme.of(
                                                  context,
                                                ).colorScheme.primaryContainer
                                              : null,
                                          minimumSize: const Size(0, 48),
                                        ),
                                        onPressed: () => setState(() {
                                          selected = selected == day
                                              ? null
                                              : day;
                                        }),
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Text('${day.day}'),
                                            if (count > 0)
                                              Text(
                                                '$count 项',
                                                style: Theme.of(
                                                  context,
                                                ).textTheme.labelSmall,
                                              ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              selected == null ? '本月事项' : selected!.toJson(),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (selected != null)
              TextButton(
                onPressed: () => setState(() {
                  selected = null;
                }),
                child: const Text('显示整月'),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (visible.isEmpty) const Text('没有已记录的到期或续费事项'),
        for (final event in visible)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              child: ListTile(
                onTap: () => widget.onOpen(event.subscription),
                leading: const Icon(Icons.event_outlined),
                title: Text(event.subscription.name),
                subtitle: Text('${event.label} · ${event.date.toJson()}'),
                trailing: const Icon(Icons.chevron_right),
              ),
            ),
          ),
      ],
    );
  }
}

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../app/design_system.dart';
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
  late int year, month;
  CivilDate? selected;
  final _horizontal = ScrollController();
  @override
  void initState() {
    super.initState();
    year = widget.services.today.year;
    month = widget.services.today.month;
  }

  @override
  void dispose() {
    _horizontal.dispose();
    super.dispose();
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
    final c = EchoColors.of(context);
    final events =
        <({CivilDate date, Subscription subscription, String label})>[];
    for (final value in widget.services.subscriptions.where(
      (s) => s.status == SubscriptionStatus.active,
    )) {
      if (value.entitlementEnd != null)
        events.add((
          date: value.entitlementEnd!,
          subscription: value,
          label: '权益到期',
        ));
      if (value.nextRenewalDate != null &&
          value.billingType != BillingType.lifetime)
        events.add((
          date: value.nextRenewalDate!,
          subscription: value,
          label: '预计续费',
        ));
    }
    final monthly =
        events
            .where(
              (event) => event.date.year == year && event.date.month == month,
            )
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date));
    final visible = monthly
        .where((event) => selected == null || event.date == selected)
        .toList();
    final offset = DateTime.utc(year, month, 1).weekday - 1;
    final days = CivilDate.daysInMonth(year, month);
    final rows = ((offset + days) / 7).ceil();
    return PageContent(
      maxWidth: 1040,
      children: [
        const SectionTitle('日历', subtitle: '查看权益到期和预计续费，点选日期筛选事项'),
        EchoPanel(
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: '上个月',
                      onPressed: () => move(-1),
                      icon: const EchoIcon(EchoSymbol.chevronLeft),
                    ),
                    Expanded(
                      child: Text(
                        '$year 年 $month 月',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: '下个月',
                      onPressed: () => move(1),
                      icon: const EchoIcon(EchoSymbol.arrow),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              LayoutBuilder(
                builder: (context, constraints) {
                  final scaler = MediaQuery.textScalerOf(context);
                  final cellWidth = math.max(
                    constraints.maxWidth / 7,
                    math.max(48.0, scaler.scale(14) * 2 + 6),
                  );
                  final cellHeight = math.max(
                    68.0,
                    scaler.scale(14) * 1.3 + scaler.scale(11.5) * 1.4 + 16,
                  );
                  final gridWidth = cellWidth * 7;
                  return ScrollConfiguration(
                    behavior: ScrollConfiguration.of(
                      context,
                    ).copyWith(scrollbars: false),
                    child: Scrollbar(
                      controller: _horizontal,
                      thumbVisibility: gridWidth > constraints.maxWidth + 1,
                      child: SingleChildScrollView(
                        controller: _horizontal,
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: gridWidth,
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  for (final day in const [
                                    '一',
                                    '二',
                                    '三',
                                    '四',
                                    '五',
                                    '六',
                                    '日',
                                  ])
                                    SizedBox(
                                      width: cellWidth,
                                      height: math.max(
                                        34.0,
                                        scaler.scale(12) * 1.5 + 8,
                                      ),
                                      child: Center(
                                        child: Text(
                                          day,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodySmall,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              for (var row = 0; row < rows; row++)
                                Row(
                                  children: [
                                    for (var col = 0; col < 7; col++)
                                      SizedBox(
                                        width: cellWidth,
                                        height: cellHeight,
                                        child:
                                            row * 7 + col < offset ||
                                                row * 7 + col >= offset + days
                                            ? null
                                            : Builder(
                                                builder: (context) {
                                                  final date = CivilDate(
                                                    year,
                                                    month,
                                                    row * 7 + col - offset + 1,
                                                  );
                                                  final count = monthly
                                                      .where(
                                                        (event) =>
                                                            event.date == date,
                                                      )
                                                      .length;
                                                  return _CalendarDay(
                                                    date: date,
                                                    count: count,
                                                    today:
                                                        date ==
                                                        widget.services.today,
                                                    selected: selected == date,
                                                    onPressed: () => setState(
                                                      () => selected =
                                                          selected == date
                                                          ? null
                                                          : date,
                                                    ),
                                                  );
                                                },
                                              ),
                                      ),
                                  ],
                                ),
                              const SizedBox(height: 8),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        SectionTitle(
          selected == null ? '本月事项' : selected!.toJson(),
          trailing: selected == null
              ? null
              : TextButton(
                  onPressed: () => setState(() => selected = null),
                  child: const Text('显示整月'),
                ),
        ),
        if (visible.isEmpty) const EchoPanel(child: Text('没有已记录的到期或续费事项')),
        for (final event in visible)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: EchoPanel(
              padding: EdgeInsets.zero,
              child: TextButton(
                onPressed: () => widget.onOpen(event.subscription),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                  foregroundColor: c.text,
                ),
                child: Row(
                  children: [
                    ServiceAvatar(event.subscription.name, size: 36),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            event.subscription.name,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            event.label + ' · ' + event.date.toJson(),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    const EchoIcon(EchoSymbol.arrow, size: 16),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _CalendarDay extends StatelessWidget {
  const _CalendarDay({
    required this.date,
    required this.count,
    required this.today,
    required this.selected,
    required this.onPressed,
  });
  final CivilDate date;
  final int count;
  final bool today, selected;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) {
    final c = EchoColors.of(context);
    final displayCount = count > 99 ? '99+' : '$count';
    final fullDate = date.toJson();
    final day = date.day;
    return Semantics(
      label: '$fullDate，$count 项到期或续费',
      selected: selected,
      child: TextButton(
        onPressed: onPressed,
        style: ButtonStyle(
          padding: const WidgetStatePropertyAll(EdgeInsets.zero),
          minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
          foregroundColor: WidgetStatePropertyAll(
            selected || today ? c.accent : c.text,
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => selected
                ? c.accentSoft
                : states.contains(WidgetState.hovered)
                ? c.soft
                : Colors.transparent,
          ),
          side: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.focused)
                ? BorderSide(color: c.accent, width: 2)
                : today
                ? BorderSide(color: c.accent)
                : BorderSide.none,
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        child: ExcludeSemantics(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$day',
                style: TextStyle(
                  fontSize: 14,
                  height: 1.2,
                  fontWeight: selected || today
                      ? FontWeight.w700
                      : FontWeight.w500,
                ),
              ),
              if (count > 0) ...[
                const SizedBox(height: 5),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                            color: c.accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          displayCount,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: c.accent, height: 1.2),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

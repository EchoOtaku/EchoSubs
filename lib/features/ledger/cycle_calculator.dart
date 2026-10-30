import '../../core/model/civil_date.dart';
import '../../core/model/errors.dart';
import '../../core/model/subscription.dart';

CivilDate occurrence(CivilDate anchor, BillingCycle cycle, int index) {
  if (index < 0) invalidModel();
  final offset = BigInt.from(cycle.count) * BigInt.from(index);
  switch (cycle.unit) {
    case CycleUnit.month:
    case CycleUnit.year:
      final months =
          BigInt.from((anchor.year - 1) * 12 + anchor.month - 1) +
          offset * BigInt.from(cycle.unit == CycleUnit.year ? 12 : 1);
      if (months > BigInt.from(9999 * 12 - 1)) invalidModel();
      final target = months.toInt();
      final year = target ~/ 12 + 1;
      final month = target % 12 + 1;
      final lastDay = CivilDate.daysInMonth(year, month);
      return CivilDate(
        year,
        month,
        anchor.day > lastDay ? lastDay : anchor.day,
      );
    case CycleUnit.day:
    case CycleUnit.week:
      final base = DateTime.utc(anchor.year, anchor.month, anchor.day);
      final days = offset * BigInt.from(cycle.unit == CycleUnit.week ? 7 : 1);
      final remaining = DateTime.utc(9999, 12, 31).difference(base).inDays;
      if (days > BigInt.from(remaining)) invalidModel();
      final target = base.add(Duration(days: days.toInt()));
      return CivilDate(target.year, target.month, target.day);
  }
}

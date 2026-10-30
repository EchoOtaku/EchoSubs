import 'errors.dart';

/// A Gregorian calendar date, with no device time zone or time of day.
class CivilDate implements Comparable<CivilDate> {
  CivilDate(this.year, this.month, this.day) {
    if (year < 1 ||
        year > 9999 ||
        month < 1 ||
        month > 12 ||
        day < 1 ||
        day > daysInMonth(year, month))
      invalidModel();
  }
  final int year;
  final int month;
  final int day;
  factory CivilDate.fromJson(String value) => parseModel(() {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) invalidModel();
    return CivilDate(
      int.parse(value.substring(0, 4)),
      int.parse(value.substring(5, 7)),
      int.parse(value.substring(8, 10)),
    );
  });
  String toJson() =>
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
  static int daysInMonth(int year, int month) {
    if (month == 2)
      return year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) ? 29 : 28;
    return [4, 6, 9, 11].contains(month) ? 30 : 31;
  }

  @override
  int compareTo(CivilDate other) {
    final years = year.compareTo(other.year);
    if (years != 0) return years;
    final months = month.compareTo(other.month);
    return months != 0 ? months : day.compareTo(other.day);
  }

  @override
  bool operator ==(Object other) =>
      other is CivilDate &&
      year == other.year &&
      month == other.month &&
      day == other.day;
  @override
  int get hashCode => Object.hash(year, month, day);
  @override
  String toString() => toJson();
}

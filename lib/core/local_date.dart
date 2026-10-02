/// A calendar date with no time or timezone. Arithmetic is done on UTC
/// midnights so daylight-saving changes can never shift a day.
class LocalDate implements Comparable<LocalDate> {
  LocalDate(this.year, this.month, this.day) {
    final check = DateTime.utc(year, month, day);
    if (check.year != year || check.month != month || check.day != day) {
      throw ArgumentError('Invalid date $year-$month-$day');
    }
  }

  factory LocalDate.fromDateTime(DateTime dt) =>
      LocalDate(dt.year, dt.month, dt.day);

  /// Parses `YYYY-MM-DD` (the stored format).
  factory LocalDate.parse(String iso) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(iso);
    if (m == null) throw FormatException('Bad date "$iso"');
    return LocalDate(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
    );
  }

  final int year;
  final int month;
  final int day;

  DateTime get _utc => DateTime.utc(year, month, day);

  /// 1 = Monday … 7 = Sunday (ISO 8601).
  int get weekday => _utc.weekday;

  LocalDate addDays(int days) {
    final d = _utc.add(Duration(days: days));
    return LocalDate(d.year, d.month, d.day);
  }

  LocalDate get startOfWeek => addDays(-(weekday - DateTime.monday));
  LocalDate get endOfWeek => startOfWeek.addDays(6);
  LocalDate get startOfMonth => LocalDate(year, month, 1);
  LocalDate get endOfMonth {
    final d = DateTime.utc(year, month + 1, 0);
    return LocalDate(d.year, d.month, d.day);
  }

  LocalDate addMonths(int months) {
    final total = year * 12 + (month - 1) + months;
    final y = total ~/ 12;
    final m = total % 12 + 1;
    final lastDay = DateTime.utc(y, m + 1, 0).day;
    return LocalDate(y, m, day > lastDay ? lastDay : day);
  }

  /// `YYYY-MM-DD`: sorts correctly as text, which SQLite range queries use.
  String toIso() =>
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';

  DateTime toDateTime() => DateTime(year, month, day);

  @override
  int compareTo(LocalDate other) => toIso().compareTo(other.toIso());

  bool isAfter(LocalDate other) => compareTo(other) > 0;
  bool isBefore(LocalDate other) => compareTo(other) < 0;

  @override
  bool operator ==(Object other) =>
      other is LocalDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => toIso();
}

enum ReportKind { daily, weekly, monthly }

/// An inclusive date range used for reports.
class ReportPeriod {
  const ReportPeriod._(this.kind, this.start, this.end);

  factory ReportPeriod.daily(LocalDate date) =>
      ReportPeriod._(ReportKind.daily, date, date);

  /// Monday through Sunday of the week that contains [date].
  factory ReportPeriod.weekly(LocalDate date) =>
      ReportPeriod._(ReportKind.weekly, date.startOfWeek, date.endOfWeek);

  /// The calendar month that contains [date].
  factory ReportPeriod.monthly(LocalDate date) =>
      ReportPeriod._(ReportKind.monthly, date.startOfMonth, date.endOfMonth);

  factory ReportPeriod.of(ReportKind kind, LocalDate anchor) => switch (kind) {
    ReportKind.daily => ReportPeriod.daily(anchor),
    ReportKind.weekly => ReportPeriod.weekly(anchor),
    ReportKind.monthly => ReportPeriod.monthly(anchor),
  };

  final ReportKind kind;
  final LocalDate start;
  final LocalDate end;

  bool contains(LocalDate d) => !d.isBefore(start) && !d.isAfter(end);

  ReportPeriod shift(int steps) => switch (kind) {
    ReportKind.daily => ReportPeriod.daily(start.addDays(steps)),
    ReportKind.weekly => ReportPeriod.weekly(start.addDays(7 * steps)),
    ReportKind.monthly => ReportPeriod.monthly(start.addMonths(steps)),
  };

  @override
  bool operator ==(Object other) =>
      other is ReportPeriod &&
      other.kind == kind &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(kind, start, end);
}

const monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June', //
  'July', 'August', 'September', 'October', 'November', 'December',
];
const _weekdayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// "Thu, 2 Oct 2026"
String formatDateLong(LocalDate d) =>
    '${_weekdayShort[d.weekday - 1]}, ${d.day} ${monthNames[d.month - 1].substring(0, 3)} ${d.year}';

/// "2 Oct"
String formatDateShort(LocalDate d) =>
    '${d.day} ${monthNames[d.month - 1].substring(0, 3)}';

String formatPeriodLabel(ReportPeriod p) => switch (p.kind) {
  ReportKind.daily => formatDateLong(p.start),
  ReportKind.weekly => '${formatDateLong(p.start)} – ${formatDateLong(p.end)}',
  ReportKind.monthly => '${monthNames[p.start.month - 1]} ${p.start.year}',
};

import 'models.dart';

/// Day / Month / Year filter on the Spending screen. Pure date maths, no UI.
enum PeriodKind { day, month, year }

class Period {
  final PeriodKind kind;
  final DateTime start; // inclusive, local midnight
  final DateTime end; // exclusive

  Period._(this.kind, this.start, this.end);

  /// The period of [kind] that contains [t].
  factory Period.of(PeriodKind kind, DateTime t) => switch (kind) {
        PeriodKind.day => Period._(kind, DateTime(t.year, t.month, t.day), DateTime(t.year, t.month, t.day + 1)),
        PeriodKind.month => Period._(kind, DateTime(t.year, t.month), DateTime(t.year, t.month + 1)),
        PeriodKind.year => Period._(kind, DateTime(t.year), DateTime(t.year + 1)),
      };

  bool contains(DateTime t) => !t.isBefore(start) && t.isBefore(end);

  Period get previous => Period.of(kind, start.subtract(const Duration(hours: 12)));
  Period get next => Period.of(kind, end.add(const Duration(hours: 12)));

  /// True once the period is over. The "next" arrow is shown only then, so the
  /// user can't step into the future.
  bool hasEnded(DateTime now) => !now.isBefore(end);

  /// Same kind, around a new date (used when switching Day/Month/Year).
  Period withKind(PeriodKind k, DateTime now) => Period.of(k, contains(now) ? now : start);

  String label(DateTime now) => switch (kind) {
        PeriodKind.day => dayLabel(start, now),
        PeriodKind.month => '${_months[start.month - 1]} ${start.year}',
        PeriodKind.year => '${start.year}',
      };
}

/// Approved items that fall in [p].
List<Item> countedIn(Iterable<Item> items, Period p) =>
    items.where((i) => i.counts && p.contains(i.spentAt)).toList();

/// Items grouped by calendar day, newest day first, newest item first within a day.
List<MapEntry<DateTime, List<Item>>> groupByDay(Iterable<Item> items) {
  final out = <DateTime, List<Item>>{};
  for (final i in items) {
    out.putIfAbsent(DateTime(i.spentAt.year, i.spentAt.month, i.spentAt.day), () => []).add(i);
  }
  for (final l in out.values) {
    l.sort((a, b) => b.spentAt.compareTo(a.spentAt));
  }
  return out.entries.toList()..sort((a, b) => b.key.compareTo(a.key));
}

/// "Today", "Yesterday", or "Wed, 25 Nov 2026".
String dayLabel(DateTime day, DateTime now) {
  final d = DateTime(day.year, day.month, day.day);
  final today = DateTime(now.year, now.month, now.day);
  if (d == today) return 'Today';
  if (d == DateTime(today.year, today.month, today.day - 1)) return 'Yesterday';
  return '${_weekdays[d.weekday - 1]}, ${d.day} ${_months[d.month - 1].substring(0, 3)} ${d.year}';
}

const _months = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December'
];
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

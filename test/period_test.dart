// Day/Month/Year filter on the Spending screen.
import 'package:expense_tracker/domain/models.dart';
import 'package:expense_tracker/domain/period.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Day / Month / Year filter', () {
    final now = DateTime(2026, 11, 27, 15);

    test('periods cover the right dates and step back and forward', () {
      final m = Period.of(PeriodKind.month, now);
      expect(m.start, DateTime(2026, 11));
      expect(m.end, DateTime(2026, 12));
      expect(m.previous.start, DateTime(2026, 10));
      expect(m.label(now), 'November 2026');
      expect(m.hasEnded(now), isFalse);
      expect(m.previous.hasEnded(now), isTrue);

      final d = Period.of(PeriodKind.day, now);
      expect(d.label(now), 'Today');
      expect(d.previous.label(now), 'Yesterday');
      expect(d.previous.previous.label(now), 'Wed, 25 Nov 2026');

      final y = Period.of(PeriodKind.year, now);
      expect(y.contains(DateTime(2026, 1, 1)), isTrue);
      expect(y.contains(DateTime(2027, 1, 1)), isFalse);
      expect(Period.of(PeriodKind.month, DateTime(2026, 1, 15)).previous.label(now), 'December 2025');
    });

    test('only approved items in the period count; items group by day, newest first', () {
      Item it(String id, DateTime at, ItemStatus s) => Item(
          id: id, captureId: 'c', name: id, amount: 10, categoryId: 'food', status: s, spentAt: at, updatedAt: at);
      final items = [
        it('a', DateTime(2026, 11, 27, 9), ItemStatus.approved),
        it('b', DateTime(2026, 11, 27, 20), ItemStatus.approved),
        it('c', DateTime(2026, 11, 26, 13), ItemStatus.approved),
        it('d', DateTime(2026, 11, 26, 14), ItemStatus.pending),
        it('e', DateTime(2026, 10, 31, 23), ItemStatus.approved),
      ];
      final nov = countedIn(items, Period.of(PeriodKind.month, now));
      expect(nov.map((i) => i.id), unorderedEquals(['a', 'b', 'c']));
      final days = groupByDay(nov);
      expect(days.map((d) => d.key), [DateTime(2026, 11, 27), DateTime(2026, 11, 26)]);
      expect(days.first.value.map((i) => i.id), ['b', 'a']);
    });
  });
}

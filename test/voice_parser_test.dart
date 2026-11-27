// Voice expense notes: spoken text -> expense lines, date and category.
import 'package:expense_tracker/domain/voice_parser.dart';
import 'package:flutter_test/flutter_test.dart';

List<(String, double, String)> lines(String s) =>
    [for (final l in parseVoiceNote(s).lines) (l.name, l.amount, l.categoryId)];

void main() {
  test('one expense, with or without "spent" and "rupees"', () {
    expect(lines('Lunch 250'), [('Lunch', 250, 'food')]);
    expect(lines('spent 250 rupees on lunch'), [('Lunch', 250, 'food')]);
    expect(lines('Paid ₹1,200 for groceries'), [('Groceries', 1200, 'groceries')]);
    expect(lines('auto 80 rs'), [('Auto', 80, 'transport')]);
  });

  test('several expenses in one sentence', () {
    expect(lines('Lunch 250 and auto 80'), [('Lunch', 250, 'food'), ('Auto', 80, 'transport')]);
    expect(lines('chai 20, samosa 30 aur medicine 150'),
        [('Chai', 20, 'food'), ('Samosa', 30, 'food'), ('Medicine', 150, 'health')]);
  });

  test('a name without an amount joins the next amount', () {
    expect(lines('lunch and dinner 500'), [('Lunch and dinner', 500, 'food')]);
  });

  test('2k, number words and "/-"', () {
    expect(lines('petrol 2k'), [('Petrol', 2000, 'transport')]);
    expect(lines('electricity bill 1.5k'), [('Electricity bill', 1500, 'bills')]);
    expect(lines('movie two hundred fifty'), [('Movie', 250, 'entertainment')]);
    expect(lines('shoes 1999/-'), [('Shoes', 1999, 'shopping')]);
  });

  test('today, yesterday and the day before', () {
    expect(parseVoiceNote('lunch 250').daysAgo, 0);
    expect(parseVoiceNote('yesterday dinner 400').daysAgo, 1);
    expect(parseVoiceNote('kal petrol 500').daysAgo, 1);
    expect(parseVoiceNote('day before yesterday movie 300').daysAgo, 2);
    expect(lines('yesterday dinner 400'), [('Dinner', 400, 'food')]);
  });

  test('unknown things go to Other; no amount means no lines', () {
    expect(lines('stationery 60'), [('Stationery', 60, 'other')]);
    expect(lines('300'), [('Expense', 300, 'other')]);
    expect(parseVoiceNote('I bought some lunch').lines, isEmpty);
  });
}

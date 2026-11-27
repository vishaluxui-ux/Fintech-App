// Bank SMS reading (N-01), app-alert/SMS duplicates, and the Day/Month/Year filter.
import 'package:expense_tracker/data/local_db.dart';
import 'package:expense_tracker/data/repository.dart';
import 'package:expense_tracker/data/settings.dart';
import 'package:expense_tracker/domain/models.dart';
import 'package:expense_tracker/domain/period.dart';
import 'package:expense_tracker/domain/sms_parser.dart';
import 'package:expense_tracker/domain/upi_parser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final t0 = DateTime(2026, 11, 27, 21, 28);
late Repository repo;

NotificationResult sms(String sender, String body) => parseBankSms(sender: sender, body: body, at: t0);

void main() {
  sqfliteFfiInit();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final settings = Settings(await SharedPreferences.getInstance());
    final db = await LocalDb.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    await db.wipe();
    repo = Repository(db, settings);
    await repo.load();
  });

  group('Bank SMS', () {
    test('only registered bank senders are read', () {
      expect(senderCode('AD-HDFCBK'), 'HDFCBK');
      expect(senderCode('VM-SBIUPI-S'), 'SBIUPI');
      expect(senderCode('+919876543210'), isNull);
      expect(senderCode('Mom'), isNull);
      expect(bankForSender('JD-ICICIT-T'), 'ICICI Bank');
      expect(bankForSender('AD-AMAZON'), isNull);
      expect(sms('+919876543210', 'Paid Rs 500 to you'), isA<Ignored>());
      expect(sms('AD-SWIGGY', 'Rs 199 debited for your order'), isA<Ignored>());
    });

    test('common bank debit wordings become payments', () {
      final a = sms('AD-HDFCBK', 'Sent Rs.1.00 From HDFC Bank A/C x1234 To RAMESH KUMAR On 27/11/26 Ref 633112345678 Not You? Call 18002586161') as UpiPayment;
      expect(a.amount, 1);
      expect(a.payee, 'RAMESH KUMAR');
      expect(a.sourceApp, 'HDFC Bank SMS');

      final b = sms('VM-SBIUPI-S', 'Dear UPI user A/C X1234 debited by 250.0 on date 27Nov26 trf to SHARMA STORES Refno 633100001. If not u? call 1800111109 -SBI');
      // SBI writes the amount without "Rs".
      expect((b as UpiPayment).amount, 250);
      expect(b.payee, 'SHARMA STORES');

      final c = sms('JD-ICICIT', 'INR 1,499.00 spent on ICICI Bank Card XX4321 on 27-Nov-26 at AMAZON. Avl Lmt: INR 50,000.00') as UpiPayment;
      expect(c.amount, 1499);
      expect(c.payee, 'AMAZON');

      final d = sms('AX-AXISBK', 'Rs 85.00 debited from A/c no. XX9876 on 27-11-26 to VPA zomato@icici (UPI Ref No 633199999).') as UpiPayment;
      expect(d.payee, 'zomato');

      final e = sms('BZ-KOTAKB', 'Your a/c XX5555 is debited for Rs.300.00 on 27-11-2026 and credited to a/c XX7777 (UPI Ref no 6331)') as UpiPayment;
      expect(e.amount, 300);
      expect(e.payee, 'Unknown payee');
    });

    test('OTPs, money in, failures and upcoming debits are skipped', () {
      expect(sms('AD-HDFCBK', 'OTP for txn of Rs 500 at AMAZON is 123456. Do not share.'), isA<Ignored>());
      expect(sms('AD-HDFCBK', 'Rs 5000 credited to your A/c XX1234 by NEFT from ACME LTD'), isA<Ignored>());
      expect(sms('AD-HDFCBK', 'Rs 200 received from ASHA on UPI'), isA<Ignored>());
      expect(sms('AD-ICICIB', 'Txn of Rs 999 at FLIPKART failed. Amount will be refunded.'), isA<Ignored>());
      expect(sms('AD-ICICIB', 'Rs 649 will be debited on 01-12-26 for NETFLIX autopay'), isA<Ignored>());
      expect(sms('AD-ICICIB', 'Your credit card bill of Rs 12,000 is due on 05-12-26'), isA<Ignored>());
    });

    test('ATM cash withdrawal SMS goes to the cash wallet', () {
      final w = sms('AD-SBIINB', 'Rs 2000 withdrawn at ATM S1BW001 from A/c XX1234 on 27Nov26. Avl Bal Rs 10,000');
      expect(w, isA<AtmWithdrawal>());
      expect((w as AtmWithdrawal).amount, 2000);
    });

    test('a payment seen as an app alert and as a bank SMS counts once', () async {
      await repo.ingestNotification(parseNotification(
          packageName: 'com.google.android.apps.nbu.paisa.user',
          title: 'Payment successful',
          text: 'Paid ₹1 to Ramesh',
          postedAt: t0));
      await repo.ingestNotification(sms('AD-HDFCBK', 'Sent Rs.1.00 From HDFC Bank A/C x1234 To RAMESH KUMAR On 27/11/26'));
      expect(repo.items, hasLength(1));
      expect(repo.captureOf(repo.items.single.captureId).sourceApp, 'Google Pay');

      // A second ₹1 an hour later is a different payment.
      await repo.ingestNotification(parseBankSms(
          sender: 'AD-HDFCBK', body: 'Sent Rs.1.00 From HDFC Bank A/C x1234 To RAMESH KUMAR', at: t0.add(const Duration(hours: 1))));
      expect(repo.items, hasLength(2));
    });

    test('an ATM withdrawal from the bank app and the bank SMS counts once', () async {
      await repo.ingestNotification(AtmWithdrawal(2000, t0, 'HDFC Bank'));
      await repo.ingestNotification(AtmWithdrawal(2000, t0.add(const Duration(minutes: 1)), 'HDFC Bank SMS'));
      expect(repo.withdrawals, hasLength(1));
    });
  });

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

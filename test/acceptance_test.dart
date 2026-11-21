// One test per Beta acceptance check in the build spec (section 6).
import 'package:expense_tracker/data/local_db.dart';
import 'package:expense_tracker/data/repository.dart';
import 'package:expense_tracker/data/settings.dart';
import 'package:expense_tracker/domain/ledger.dart' as ledger;
import 'package:expense_tracker/domain/models.dart';
import 'package:expense_tracker/domain/upi_parser.dart';
import 'package:expense_tracker/services/bill_parser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const gpay = 'com.google.android.apps.nbu.paisa.user';
final t0 = DateTime(2026, 11, 20, 13, 5);

late LocalDb db;
late Repository repo;
late Settings settings;

Future<void> fresh({Map<String, Object> prefs = const {}}) async {
  SharedPreferences.setMockInitialValues(prefs);
  settings = Settings(await SharedPreferences.getInstance());
  db = await LocalDb.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
  await db.wipe();
  repo = Repository(db, settings);
  await repo.load();
}

Future<void> pay(double amount, String payee, DateTime at, {String pkg = gpay}) => repo.ingestNotification(
    parseNotification(packageName: pkg, title: 'Payment successful', text: 'Paid ₹$amount to $payee', postedAt: at));

ParsedBill testBill({double? total = 250}) => const ParsedBill(merchant: 'Sharma Stores', total: 250, lines: [
      ParsedLine('Milk 1L', 60, 'groceries', 0.95),
      ParsedLine('Bread', 40, 'groceries', 0.9),
      ParsedLine('Face wash', 150, 'cosmetics', 0.5),
    ]);

void main() {
  sqfliteFfiInit();
  setUp(() => fresh());

  group('Capture', () {
    test('CAP-01: one UPI alert creates one pending item with amount, payee, time and source app', () async {
      await pay(249, 'Swiggy', t0);
      expect(repo.items, hasLength(1));
      final i = repo.items.single;
      final c = repo.captureOf(i.captureId);
      expect(i.status, ItemStatus.pending);
      expect(i.amount, 249);
      expect(i.payee, 'Swiggy');
      expect(i.spentAt, t0);
      expect(c.sourceApp, 'Google Pay');
    });

    test('CAP-01: parses common UPI app wordings and ignores non-payments', () {
      NotificationResult p(String pkg, String title, String text) =>
          parseNotification(packageName: pkg, title: title, text: text, postedAt: t0);

      final a = p('com.phonepe.app', 'Paid to Ramesh Kirana', '₹1,250.50 paid successfully') ;
      expect(a, isA<UpiPayment>());
      expect((a as UpiPayment).amount, 1250.5);

      final b = p('net.one97.paytm', 'Payment Successful', 'Rs.99 sent to Zomato via UPI') as UpiPayment;
      expect(b.payee, 'Zomato');
      expect(b.sourceApp, 'Paytm');

      expect(p(gpay, 'Money received', '₹500 received from Asha'), isA<Ignored>());
      expect(p(gpay, 'Payment request', 'Asha requested ₹200'), isA<Ignored>());
      expect(p('com.whatsapp', 'Paid', 'Paid ₹50 to X'), isA<Ignored>());
      expect(p(gpay, 'Offers', 'Get cashback on your next bill'), isA<Ignored>());
    });

    test('CAP-02: each line of a test bill appears as its own item', () async {
      final cap = await repo.addBill(testBill());
      final items = repo.itemsOf(cap.id);
      expect(items.map((i) => i.name), ['Milk 1L', 'Bread', 'Face wash']);
      expect(items.map((i) => i.amount), [60, 40, 150]);
      expect(items.map((i) => i.categoryId), ['groceries', 'groceries', 'cosmetics']);
      expect(items.every((i) => i.status == ItemStatus.pending), isTrue);
    });

    test('CAP-02: Edge Function JSON maps to a parsed bill', () {
      final b = parseBillJson({
        'merchant': 'Cafe',
        'total': 180,
        'items': [
          {'name': 'Coffee', 'amount': 120, 'category': 'food', 'confidence': 0.9},
          {'name': 'Cookie', 'amount': 60, 'category': 'nope', 'confidence': 0.4},
        ]
      });
      expect(b.lines, hasLength(2));
      expect(b.total, 180);
    });

    test('CAP-03: a mismatch shows a warning before approval', () async {
      final cap = await repo.addBill(const ParsedBill(merchant: 'X', total: 300, lines: [
        ParsedLine('A', 100, 'food', 0.9),
        ParsedLine('B', 150, 'food', 0.9),
      ]));
      expect(repo.mismatchFor(cap), contains('300.00'));
      // A missed line fixes it.
      await repo.addManual(name: 'C', amount: 50, categoryId: 'food', captureId: cap.id);
      expect(repo.mismatchFor(cap), isNull);
    });

    test('CAP-04: a manual item appears in the inbox as pending', () async {
      await repo.addManual(name: 'Chai', amount: 20, categoryId: 'food', cash: true);
      expect(repo.inboxCount, 1);
      expect(repo.inbox.single.value.single.name, 'Chai');
      expect(repo.inbox.single.key.source, CaptureSource.cash);
    });

    test('CAP-05: an ATM alert shows in the cash wallet with time and amount', () async {
      await repo.ingestNotification(parseNotification(
          packageName: 'com.snapwork.hdfc',
          title: 'HDFC Bank',
          text: 'Rs 2000 withdrawn at ATM HDFC0001 from a/c XX1234',
          postedAt: t0));
      expect(repo.withdrawals, hasLength(1));
      expect(repo.withdrawals.single.amount, 2000);
      expect(repo.withdrawals.single.at, t0);
      expect(repo.items, isEmpty);
    });
  });

  group('Approval', () {
    test('APR-01: items from one bill appear together', () async {
      await pay(50, 'Metro', t0);
      await repo.addBill(testBill());
      final groups = repo.inbox;
      expect(groups, hasLength(2));
      expect(groups.firstWhere((g) => g.key.source == CaptureSource.bill).value, hasLength(3));
    });

    test('APR-02: approved items count in totals; edits are kept', () async {
      await pay(249, 'Swiggy', t0);
      final id = repo.items.single.id;
      await repo.edit(id, name: 'Lunch', amount: 199, categoryId: 'food');
      expect(repo.totalApproved, 0);
      await repo.approve(id);
      expect(repo.totalApproved, 199);

      final reloaded = Repository(db, settings);
      await reloaded.load();
      final i = reloaded.items.single;
      expect([i.name, i.amount, i.categoryId, i.status], ['Lunch', 199, 'food', ItemStatus.approved]);
    });

    test('APR-03: one action approves every item in that bill', () async {
      final cap = await repo.addBill(testBill());
      await repo.approveAll(cap.id);
      expect(repo.itemsOf(cap.id).every((i) => i.status == ItemStatus.approved), isTrue);
      expect(repo.totalApproved, 250);
      expect(repo.inboxCount, 0);
    });

    test('APR-04: each flagged item shows a reason', () async {
      final cap = await repo.addBill(testBill());
      final faceWash = repo.itemsOf(cap.id).firstWhere((i) => i.name == 'Face wash');
      expect(faceWash.flagReason, contains('Low confidence'));
      expect(repo.itemsOf(cap.id).where((i) => i.name != 'Face wash').every((i) => i.flagReason == null), isTrue);

      await pay(80, 'New Cafe', t0);
      final upi = repo.items.firstWhere((i) => i.payee == 'New Cafe');
      expect(upi.flagReason, contains('New merchant'));

      // Once approved, the same merchant is known and not flagged again.
      await repo.approve(upi.id);
      await pay(90, 'New Cafe', t0.add(const Duration(days: 1)));
      expect(repo.items.last.flagReason, isNull);
    });

    test('APR-05: a deleted item leaves the totals', () async {
      final cap = await repo.addBill(testBill());
      await repo.approveAll(cap.id);
      await repo.delete(repo.itemsOf(cap.id).first.id);
      expect(repo.totalApproved, 190);
      expect(repo.itemsOf(cap.id), hasLength(2));
    });

    test('Reject: a rejected item never counts and leaves the inbox', () async {
      await pay(300, 'Shop', t0);
      await repo.reject(repo.items.single.id);
      expect(repo.totalApproved, 0);
      expect(repo.inboxCount, 0);
    });
  });

  group('Duplicates (user setting)', () {
    test('Flag mode: a repeat payment stays pending with a duplicate note', () async {
      await pay(120, 'Uber', t0);
      await pay(120, 'Uber', t0.add(const Duration(minutes: 2)), pkg: 'com.phonepe.app');
      expect(repo.inboxCount, 2);
      expect(repo.items.last.flagReason, contains('Possible duplicate'));
    });

    test('Auto-reject mode: a repeat payment is rejected and never counted', () async {
      await fresh(prefs: {'duplicate_mode': 'autoReject'});
      await pay(120, 'Uber', t0);
      await pay(120, 'Uber', t0.add(const Duration(minutes: 2)));
      expect(repo.inboxCount, 1);
      expect(repo.items.last.status, ItemStatus.rejected);
    });

    test('Payments outside the window are not duplicates', () async {
      await pay(120, 'Uber', t0);
      await pay(120, 'Uber', t0.add(const Duration(hours: 3)));
      expect(repo.items.last.flagReason, isNot(contains('duplicate')));
    });
  });

  group('Cash', () {
    test('CSH-01: outstanding equals withdrawal minus logged spends', () async {
      final w = await repo.addWithdrawal(2000, t0);
      await repo.addManual(name: 'Vegetables', amount: 300, categoryId: 'groceries', withdrawalId: w.id);
      final auto = await repo.addManual(name: 'Auto', amount: 150, categoryId: 'transport', withdrawalId: w.id);
      expect(repo.outstandingFor(w), 1550);
      await repo.delete(auto.id);
      expect(repo.outstandingFor(w), 1700);
    });

    test('CSH-02: one reminder per day, not one per withdrawal', () async {
      expect(ledger.dailyCashReminder(repo.withdrawals, repo.captures, repo.items), isNull);
      await repo.addWithdrawal(2000, t0);
      await repo.addWithdrawal(500, t0.add(const Duration(hours: 5)));
      final r = ledger.dailyCashReminder(repo.withdrawals, repo.captures, repo.items)!;
      expect(r.title, '2 withdrawals, ₹2500 not yet split');
      expect(r.body, contains('₹2000'));
      expect(r.body, contains('₹500'));
    });

    test('CSH-02: month-end review offered in the last days with cash outstanding', () async {
      await repo.addWithdrawal(1000, t0);
      expect(ledger.offerMonthEndReview(DateTime(2026, 11, 29), repo.withdrawals, repo.captures, repo.items), isTrue);
      expect(ledger.offerMonthEndReview(DateTime(2026, 11, 10), repo.withdrawals, repo.captures, repo.items), isFalse);
    });
  });

  group('Categories and dashboard', () {
    test('CAT-01: defaults include food, cosmetics and shopping; each can be changed at approval', () async {
      expect(defaultCategories.map((c) => c.id), containsAll(['food', 'cosmetics', 'shopping']));
      await pay(500, 'Myntra', t0);
      await repo.edit(repo.items.single.id, categoryId: 'shopping');
      await repo.approve(repo.items.single.id);
      expect(repo.byCategory, {'shopping': 500});
    });

    test('DSH-01: pending items stay out of the totals', () async {
      await pay(100, 'A', t0);
      await pay(200, 'B', t0.add(const Duration(hours: 1)));
      await repo.approve(repo.items.first.id);
      expect(repo.totalApproved, 100);
      expect(repo.byCategory.values.fold(0.0, (a, b) => a + b), 100);
      expect(repo.inboxCount, 1);
    });
  });

  group('Account and storage', () {
    test('ACC-02: entries are saved on the device first and queued for sync', () async {
      await repo.addManual(name: 'Chai', amount: 20, categoryId: 'food');
      final queued = await db.pending();
      expect(queued.map((q) => q.table), containsAll(['captures', 'items']));
      await db.markSynced('items', repo.items.single.id);
      expect((await db.pending()).map((q) => q.table), ['captures']);
    });

    test('ACC-02: remote rows apply without overwriting unsynced local edits', () async {
      await repo.addManual(name: 'Local', amount: 20, categoryId: 'food');
      final local = repo.items.single;
      await db.applyRemote('items', {...local.toMap(), 'name': 'Server'});
      expect((await db.items()).single.name, 'Local');
      await db.markSynced('items', local.id);
      await db.applyRemote('items', {...local.toMap(), 'name': 'Server'});
      expect((await db.items()).single.name, 'Server');
    });

    test('ACC-03: local wipe removes every item, capture and withdrawal', () async {
      await repo.addBill(testBill());
      await repo.addWithdrawal(500, t0);
      await repo.wipeLocal();
      expect([repo.items, repo.captures, repo.withdrawals].every((l) => l.isEmpty), isTrue);
      expect(await db.pending(), isEmpty);
    });

    test('Bill photo setting: photo removed after approval only when keep is off', () async {
      await fresh(prefs: {'keep_bill_photos': false});
      final cap = await repo.addBill(testBill(), imagePath: '/nonexistent/bill.jpg');
      await repo.approve(repo.itemsOf(cap.id).first.id);
      expect(repo.captureOf(cap.id).imagePath, isNotNull, reason: 'still pending items');
      await repo.approveAll(cap.id);
      expect(repo.captureOf(cap.id).imagePath, isNull);

      await fresh();
      final kept = await repo.addBill(testBill(), imagePath: '/nonexistent/bill.jpg');
      await repo.approveAll(kept.id);
      expect(repo.captureOf(kept.id).imagePath, isNotNull);
    });
  });
}

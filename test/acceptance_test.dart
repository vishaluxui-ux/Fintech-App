// One test per Beta acceptance check in the build spec (section 6).
import 'package:expense_tracker/data/local_db.dart';
import 'package:expense_tracker/data/repository.dart';
import 'package:expense_tracker/data/settings.dart';
import 'package:expense_tracker/domain/ledger.dart' as ledger;
import 'package:expense_tracker/domain/models.dart';
import 'package:expense_tracker/domain/upi_parser.dart';
import 'package:expense_tracker/services/alert_ingestor.dart';
import 'package:expense_tracker/services/alert_reader.dart';
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

    test('ACC-02: sync pushes parents before children', () async {
      final w = await repo.addWithdrawal(500, t0);
      await repo.addManual(name: 'Tea', amount: 20, categoryId: 'food', withdrawalId: w.id);
      await repo.addBill(testBill());
      final tables = (await db.pending()).map((q) => q.table).toList();
      expect(tables.lastIndexOf('withdrawals') < tables.indexOf('captures'), isTrue);
      expect(tables.lastIndexOf('captures') < tables.indexOf('items'), isTrue);
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

  group('Total mismatch: user explains why', () {
    // Items ₹500, bill says ₹400.
    Future<Capture> bill({double total = 400, double? discount}) => repo.addBill(ParsedBill(
        merchant: 'Shop', total: total, discount: discount, lines: const [
          ParsedLine('Shirt', 300, 'shopping', 0.9),
          ParsedLine('Socks', 200, 'shopping', 0.9),
        ]));
    double sum(Capture c) => repo.itemsOf(c.id).fold(0.0, (s, i) => s + i.amount);

    test('spreadReduction is proportional and exact to the paisa', () {
      expect(ledger.spreadReduction([300, 200], 100), [240, 160]);
      final r = ledger.spreadReduction([33.33, 33.33, 33.34], 10);
      expect((r.fold(0.0, (a, b) => a + b) * 100).round(), 9000);
      expect(() => ledger.spreadReduction([100], 100), throwsArgumentError);
    });

    test('Discount: spread over the lines; the mismatch clears; reason stored', () async {
      final c = await bill();
      expect(repo.mismatchFor(c), isNotNull);
      await repo.resolveDiscount(c.id, discount: 100, paidTotal: 400);
      final c2 = repo.captureOf(c.id);
      expect(repo.itemsOf(c.id).map((i) => i.amount), [240, 160]);
      expect(repo.mismatchFor(c2), isNull);
      expect(c2.adjustReason, MismatchReason.discount);
      await repo.approveAll(c.id);
      expect(repo.totalApproved, 400);
    });

    test('Discount printed on the bill is applied automatically, no prompt', () async {
      final c = await bill(discount: 100);
      expect(repo.mismatchFor(c), isNull);
      expect(c.adjustNote, 'auto');
      expect(sum(c), 400);
    });

    test('Printed discount that does not explain the gap is left for the user', () async {
      final c = await bill(discount: 30);
      expect(repo.mismatchFor(c), isNotNull);
      expect(c.adjustReason, isNull);
    });

    test('Problem while printing: lines are counted and become the total', () async {
      final c = await bill();
      await repo.resolvePrintError(c.id);
      final c2 = repo.captureOf(c.id);
      expect(c2.billTotal, 500);
      expect(repo.mismatchFor(c2), isNull);
      expect(c2.adjustReason, MismatchReason.printError);
    });

    test('Line appears twice: the chosen copy is removed', () async {
      final c = await repo.addBill(const ParsedBill(merchant: 'Cafe', total: 200, lines: [
        ParsedLine('Coffee', 100, 'food', 0.9),
        ParsedLine('Cake', 100, 'food', 0.9),
        ParsedLine('Coffee', 100, 'food', 0.9),
      ]));
      final repeats = ledger.likelyRepeatedLines(repo.itemsOf(c.id));
      expect(repeats, hasLength(1));
      await repo.resolveDuplicateLine(c.id, itemId: repeats.single);
      expect(repo.itemsOf(c.id).map((i) => i.name), ['Coffee', 'Cake']);
      expect(repo.mismatchFor(repo.captureOf(c.id)), isNull);
    });

    test('Other, paid less: difference spread over lines; reason kept', () async {
      final c = await bill();
      await repo.resolveOther(c.id, reason: 'Loyalty points', paidTotal: 450);
      final c2 = repo.captureOf(c.id);
      expect(sum(c2), 450);
      expect(c2.billTotal, 450);
      expect(c2.adjustNote, 'Loyalty points');
      expect(repo.mismatchFor(c2), isNull);
    });

    test('Other, paid more: one Adjustment line for the difference', () async {
      final c = await bill();
      await repo.resolveOther(c.id, reason: 'Tip', paidTotal: 520);
      final adj = repo.itemsOf(c.id).firstWhere((i) => i.name.startsWith('Adjustment'));
      expect(adj.amount, 20);
      expect(adj.name, 'Adjustment: Tip');
      expect(sum(c), 520);
      expect(repo.mismatchFor(repo.captureOf(c.id)), isNull);
    });

    test('Reason survives a reload from the device database', () async {
      final c = await bill();
      await repo.resolveOther(c.id, reason: 'Tip', paidTotal: 520);
      final again = Repository(db, settings);
      await again.load();
      expect(again.captureOf(c.id).adjustReason, MismatchReason.other);
      expect(again.captureOf(c.id).adjustNote, 'Tip');
    });
  });

  group('Risk reducers', () {
    test('Known merchant: third payment auto-approved with the same category, marked Auto', () async {
      await pay(100, 'Chai Point', t0);
      await repo.edit(repo.items.last.id, categoryId: 'food');
      await repo.approve(repo.items.last.id);
      await pay(120, 'Chai Point', t0.add(const Duration(days: 1)));
      expect(repo.items.last.status, ItemStatus.pending, reason: 'only one approval so far');
      await repo.edit(repo.items.last.id, categoryId: 'food');
      await repo.approve(repo.items.last.id);
      await pay(90, 'Chai Point', t0.add(const Duration(days: 2)));
      final third = repo.items.last;
      expect(third.status, ItemStatus.approved);
      expect(third.categoryId, 'food');
      expect(third.autoApproved, isTrue);
      expect(repo.totalApproved, 310);
    });

    test('Known merchant: off in settings, or categories differ -> stays pending', () async {
      await fresh(prefs: {'auto_approve_known': false});
      for (var d = 0; d < 3; d++) {
        await pay(50, 'Metro', t0.add(Duration(days: d)));
        if (d < 2) await repo.approve(repo.items.last.id);
      }
      expect(repo.items.last.status, ItemStatus.pending);

      await fresh();
      await pay(50, 'Mall', t0);
      await repo.edit(repo.items.last.id, categoryId: 'food');
      await repo.approve(repo.items.last.id);
      await pay(60, 'Mall', t0.add(const Duration(days: 1)));
      await repo.edit(repo.items.last.id, categoryId: 'shopping');
      await repo.approve(repo.items.last.id);
      await pay(70, 'Mall', t0.add(const Duration(days: 2)));
      expect(repo.items.last.status, ItemStatus.pending);
    });

    test('Auto-approved marker survives a reload', () async {
      for (var d = 0; d < 3; d++) {
        await pay(50, 'Metro', t0.add(Duration(days: d)));
        if (d < 2) await repo.approve(repo.items.last.id);
      }
      final again = Repository(db, settings);
      await again.load();
      expect(again.items.where((i) => i.autoApproved), hasLength(1));
    });

    test('Approve all unflagged leaves flagged items for review', () async {
      await repo.addManual(name: 'Tea', amount: 20, categoryId: 'food');
      await repo.addManual(name: 'Bus', amount: 30, categoryId: 'transport');
      await pay(99, 'Unknown Shop', t0); // flagged: new merchant
      final n = await repo.approveAllUnflagged();
      expect(n, 2);
      expect(repo.totalApproved, 50);
      expect(repo.inboxCount, 1);
    });

    test('Daily nudge: none when nothing waits; one combined message otherwise', () async {
      expect(ledger.dailyNudge(repo.withdrawals, repo.captures, repo.items), isNull);
      await repo.addManual(name: 'Tea', amount: 20, categoryId: 'food');
      expect(ledger.dailyNudge(repo.withdrawals, repo.captures, repo.items)!.title, '1 item to check');
      await repo.addWithdrawal(1000, t0);
      expect(ledger.dailyNudge(repo.withdrawals, repo.captures, repo.items)!.title,
          '1 item to check · ₹1000 cash not yet split');
    });

    test('Weekly summary: total, top category and change from last week', () async {
      final now = DateTime(2026, 11, 29, 19);
      Future<void> spend(double a, String cat, int daysAgo) async {
        final i = await repo.addManual(
            name: cat, amount: a, categoryId: cat, at: now.subtract(Duration(days: daysAgo)));
        await repo.approve(i.id);
      }
      await spend(300, 'food', 2);
      await spend(200, 'transport', 3);
      await spend(250, 'food', 9); // last week
      final w = ledger.weeklySummary(now, repo.items)!;
      expect(w.title, 'This week: ₹500');
      expect(w.body, 'Most on Food (₹300). 100% more than last week.');
      expect(ledger.weeklySummary(DateTime(2027, 3, 1), repo.items), isNull);
    });
  });

  group('AI reads alerts the rules miss', () {
    late List<String> calls;
    AlertIngestor ingestor(Future<NotificationResult> Function() ai) {
      calls = [];
      return AlertIngestor(repo, (pkg, title, body, at) {
        calls.add(body);
        return ai();
      });
    }

    test('Rules handle a normal alert: no AI call', () async {
      final ing = ingestor(() async => const Ignored());
      await ing.ingest(gpay, 'Payment successful', 'Paid ₹50 to Metro', t0);
      expect(calls, isEmpty);
      expect(repo.items.single.payee, 'Metro');
    });

    test('Unusual wording goes to the AI, which creates the item', () async {
      final ing = ingestor(() async => UpiPayment(240, 'Big Bazaar', t0, 'PhonePe'));
      await ing.ingest('com.phonepe.app', 'Txn alert', '₹240 to Big Bazaar done', t0);
      expect(calls, hasLength(1));
      expect(repo.items.single.payee, 'Big Bazaar');
      expect(repo.items.single.amount, 240);
    });

    test('Money received is dropped without asking the AI', () async {
      final ing = ingestor(() async => const Ignored());
      await ing.ingest(gpay, 'Money received', '₹500 received from Asha', t0);
      expect(calls, isEmpty);
      expect(repo.items, isEmpty);
    });

    test('Offline: alert waits on the device, then is read on retry', () async {
      var online = false;
      final ing = ingestor(() async {
        if (!online) throw Exception('offline');
        return UpiPayment(75, 'Kirana', t0, 'Paytm');
      });
      await ing.ingest('net.one97.paytm', 'Alert', 'Rs 75 debited for UPI txn', t0);
      expect(repo.items, isEmpty);
      expect(await db.queuedAlerts(), hasLength(1));
      online = true;
      await ing.retryQueued();
      expect(repo.items.single.payee, 'Kirana');
      expect(await db.queuedAlerts(), isEmpty);
    });

    test('Edge Function JSON maps to payment, ATM or nothing', () {
      expect(alertFromJson({'kind': 'payment', 'amount': 90, 'payee': 'Zomato'}, 'Paytm', t0), isA<UpiPayment>());
      expect(alertFromJson({'kind': 'atm', 'amount': 2000, 'payee': null}, 'HDFC Bank', t0), isA<AtmWithdrawal>());
      expect(alertFromJson({'kind': 'other', 'amount': 500, 'payee': null}, 'Paytm', t0), isA<Ignored>());
      expect(alertFromJson({'kind': 'payment', 'amount': null, 'payee': 'X'}, 'Paytm', t0), isA<Ignored>());
    });
  });

  group('Bills counted twice', () {
    test('Same bill scanned again is found (same shop and total)', () async {
      await repo.addBill(testBill(), at: t0);
      expect(ledger.findDuplicateBill(testBill(), t0.add(const Duration(hours: 1)), repo.captures, repo.items), isNotNull);
    });

    test('Same lines with the shop name read differently is still found', () async {
      await repo.addBill(testBill(), at: t0);
      const again = ParsedBill(merchant: 'SHARMA STORE', total: 250, lines: [
        ParsedLine('Milk', 60, 'groceries', 0.9),
        ParsedLine('Bread loaf', 40, 'groceries', 0.9),
        ParsedLine('Facewash', 150, 'cosmetics', 0.9),
      ]);
      expect(ledger.findDuplicateBill(again, t0, repo.captures, repo.items), isNotNull);
    });

    test('Different total, a week later, or a rejected bill is not a duplicate', () async {
      final c = await repo.addBill(testBill(), at: t0);
      expect(ledger.findDuplicateBill(const ParsedBill(merchant: 'Sharma Stores', total: 400, lines: [
        ParsedLine('Rice', 400, 'groceries', 0.9)]), t0, repo.captures, repo.items), isNull);
      expect(ledger.findDuplicateBill(testBill(), t0.add(const Duration(days: 8)), repo.captures, repo.items), isNull);
      for (final i in repo.itemsOf(c.id)) {
        await repo.reject(i.id);
      }
      expect(ledger.findDuplicateBill(testBill(), t0, repo.captures, repo.items), isNull);
    });

    test('Bill matching a UPI payment replaces it so the spend counts once', () async {
      await pay(250, 'Sharma Stores', t0);
      await repo.approve(repo.items.single.id);
      final paid = ledger.findPaymentForBill(testBill(), t0.add(const Duration(minutes: 5)), repo.captures, repo.items);
      expect(paid, isNotNull);
      final c = await repo.addBill(testBill(), at: t0, replacesPaymentId: paid!.id);
      await repo.approveAll(c.id);
      expect(repo.totalApproved, 250);
      expect(repo.items.firstWhere((i) => i.id == paid.id).status, ItemStatus.rejected);
    });

    test('A payment far from the bill time is not matched', () async {
      await pay(250, 'Sharma Stores', t0);
      expect(ledger.findPaymentForBill(testBill(), t0.add(const Duration(days: 1)), repo.captures, repo.items), isNull);
    });
  });

  group('Payment app ads and junk payees (from real beta alerts)', () {
    NotificationResult p(String pkg, String title, String text) =>
        parseNotification(packageName: pkg, title: title, text: text, postedAt: t0);
    const cred = 'com.dreamplug.androidapp';

    test('Ads are ignored by the rules and never sent to the AI', () {
      for (final a in [
        ['available for you: ₹4,64,827', 'withdraw any amount from your CRED cash account before November 30th'],
        ['EMIs from ₹1,000 to fund big purchase', 'Take a personal loan of up to ₹40 lakh & enjoy low EMIs. Tap to learn more'],
        ['win Oaklely Meta sunglasses', 'worth ₹52,300. tap before the reward expires.'],
        ['CRED money: bank charges detected', '₹40.20 charged on 24th Nov • view last 6-month trends on bank charges'],
      ]) {
        expect(p(cred, a[0], a[1]), isA<Ignored>(), reason: a[0]);
        expect(clearlyNotSpend(a[0], a[1]), isTrue, reason: a[0]);
      }
    });

    test('Ad text is never used as the payee', () {
      final r = p(cred, 'claim your reward', '₹176.39 paid successfully') as UpiPayment;
      expect(r.payee, 'Unknown payee'); // goes to the AI for the real payee
    });

    test('A real payment that mentions a reward still counts', () {
      final r = p(cred, 'payment successful', 'paid ₹314.35 to Airtel. claim your reward') as UpiPayment;
      expect(r.amount, 314.35);
      expect(r.payee, 'Airtel');
    });
  });
}

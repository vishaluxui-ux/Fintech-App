import 'models.dart';

/// Pure rules behind totals, grouping, checks and cash. No I/O here, so each
/// acceptance check can be tested directly.

/// DSH-01: only approved items count. Pending, rejected and deleted never do.
double totalApproved(Iterable<Item> items) =>
    items.where((i) => i.counts).fold(0.0, (s, i) => s + i.amount);

Map<String, double> spendByCategory(Iterable<Item> items) {
  final out = <String, double>{};
  for (final i in items.where((i) => i.counts)) {
    out[i.categoryId] = (out[i.categoryId] ?? 0) + i.amount;
  }
  return out;
}

int inboxCount(Iterable<Item> items) => items.where((i) => i.status == ItemStatus.pending).length;

/// APR-01: pending items grouped by bill or payment, newest group first.
List<MapEntry<Capture, List<Item>>> inboxGroups(Iterable<Capture> captures, Iterable<Item> items) {
  final byCapture = <String, List<Item>>{};
  for (final i in items.where((i) => i.status == ItemStatus.pending)) {
    byCapture.putIfAbsent(i.captureId, () => []).add(i);
  }
  final caps = {for (final c in captures) c.id: c};
  final groups = [
    for (final e in byCapture.entries)
      if (caps[e.key] != null) MapEntry(caps[e.key]!, e.value)
  ];
  groups.sort((a, b) => b.key.capturedAt.compareTo(a.key.capturedAt));
  return groups;
}

/// CAP-03: compare line items with the printed bill total.
/// Returns null when they match (within 1 rupee for rounding) or no total exists.
String? totalMismatch(Capture capture, Iterable<Item> items) {
  final total = capture.billTotal;
  if (total == null) return null;
  final sum = items
      .where((i) => i.captureId == capture.id && i.status != ItemStatus.deleted && i.status != ItemStatus.rejected)
      .fold(0.0, (s, i) => s + i.amount);
  if ((sum - total).abs() <= 1.0) return null;
  return 'Items add up to ₹${sum.toStringAsFixed(2)} but the bill total is ₹${total.toStringAsFixed(2)}';
}

/// Spread [reduction] across [amounts] in proportion to each, to the paisa,
/// so the result sums to exactly sum(amounts) - reduction. Any rounding
/// remainder goes to the largest line. Keeps category totals honest.
List<double> spreadReduction(List<double> amounts, double reduction) {
  final sum = amounts.fold(0.0, (s, a) => s + a);
  if (amounts.isEmpty || sum <= 0 || reduction <= 0) return amounts;
  if (reduction >= sum) throw ArgumentError('Discount is larger than the items total');
  final factor = (sum - reduction) / sum;
  final out = [for (final a in amounts) (a * factor * 100).round() / 100];
  final target = ((sum - reduction) * 100).round();
  final diff = target - out.fold(0, (s, a) => s + (a * 100).round());
  if (diff != 0) {
    var big = 0;
    for (var i = 1; i < out.length; i++) {
      if (amounts[i] > amounts[big]) big = i;
    }
    out[big] = ((out[big] * 100).round() + diff) / 100;
  }
  return out;
}

/// Figures shown at the top of the "why don't these match" sheet.
({double items, double bill, double gap}) mismatchFigures(Capture capture, Iterable<Item> items) {
  final sum = items
      .where((i) => i.captureId == capture.id && i.status != ItemStatus.deleted && i.status != ItemStatus.rejected)
      .fold(0.0, (s, i) => s + i.amount);
  final bill = capture.billTotal ?? sum;
  return (items: sum, bill: bill, gap: sum - bill);
}

/// Lines that look like a repeat (same name and amount) are offered first for "Line appears twice".
Set<String> likelyRepeatedLines(Iterable<Item> lines) {
  final seen = <String, String>{};
  final out = <String>{};
  for (final i in lines) {
    final k = '${i.name.trim().toLowerCase()}|${i.amount.toStringAsFixed(2)}';
    if (seen.containsKey(k)) out.add(i.id);
    seen[k] = i.id;
  }
  return out;
}

/// APR-04: flag reasons for a parsed or captured item.
const lowConfidence = 0.7;
String? flagFor({double? confidence, required String? payee, required Set<String> knownPayees}) {
  if (confidence != null && confidence < lowConfidence) {
    return 'Low confidence (${(confidence * 100).round()}%): check name, amount and category';
  }
  if (payee != null) {
    if (payee == 'Unknown payee') return 'Payee not found in the notification';
    if (!knownPayees.contains(payee.toLowerCase())) return 'New merchant: check the category';
  }
  return null;
}

/// Duplicate check: same amount, same payee (case-insensitive), within 10 minutes,
/// against items that are not deleted. Rejected ones count, so a second alert for a
/// rejected payment is caught too.
const duplicateWindow = Duration(minutes: 10);
Item? findDuplicate(
    {required double amount, required String? payee, required DateTime at, required Iterable<Item> existing}) {
  if (payee == null) return null;
  for (final i in existing) {
    if (i.status == ItemStatus.deleted || i.payee == null) continue;
    if ((i.amount - amount).abs() < 0.005 &&
        i.payee!.toLowerCase() == payee.toLowerCase() &&
        i.spentAt.difference(at).abs() <= duplicateWindow) {
      return i;
    }
  }
  return null;
}

/// Status and flag a new item gets when it duplicates another, per the user's setting.
({ItemStatus status, String flag}) duplicateOutcome(DuplicateMode mode, Item original) => (
      status: mode == DuplicateMode.autoReject ? ItemStatus.rejected : ItemStatus.pending,
      flag: 'Possible duplicate of ₹${original.amount.toStringAsFixed(2)} to ${original.payee} '
          'at ${_hm(original.spentAt)}',
    );

String _hm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// CSH-01: outstanding = withdrawal minus spends logged against it
/// (pending or approved; rejected/deleted are not spends).
double outstanding(Withdrawal w, Iterable<Capture> captures, Iterable<Item> items) {
  final capIds = captures.where((c) => c.withdrawalId == w.id).map((c) => c.id).toSet();
  final spent = items
      .where((i) =>
          capIds.contains(i.captureId) && (i.status == ItemStatus.pending || i.status == ItemStatus.approved))
      .fold(0.0, (s, i) => s + i.amount);
  return w.amount - spent;
}

/// CSH-02: one daily reminder listing every withdrawal that still has cash outstanding.
/// Returns null when nothing is outstanding, so no reminder is sent.
({String title, String body})? dailyCashReminder(
    Iterable<Withdrawal> ws, Iterable<Capture> captures, Iterable<Item> items) {
  final open = [
    for (final w in ws)
      if (outstanding(w, captures, items) > 0.5) (w, outstanding(w, captures, items))
  ];
  if (open.isEmpty) return null;
  final sum = open.fold(0.0, (s, e) => s + e.$2);
  final lines = open.map((e) => '₹${e.$2.toStringAsFixed(0)} from ${_d(e.$1.at)}').join(', ');
  return (
    title: open.length == 1
        ? '₹${sum.toStringAsFixed(0)} cash not yet split'
        : '${open.length} withdrawals, ₹${sum.toStringAsFixed(0)} not yet split',
    body: 'Where did it go? $lines',
  );
}

/// CSH-02 month-end review offer: last 3 days of the month with cash outstanding.
bool offerMonthEndReview(DateTime now, Iterable<Withdrawal> ws, Iterable<Capture> c, Iterable<Item> i) {
  final lastDay = DateTime(now.year, now.month + 1, 0).day;
  return now.day >= lastDay - 2 && ws.any((w) => outstanding(w, c, i) > 0.5);
}

String _d(DateTime t) => '${t.day}/${t.month}';


// ---- Retention and less-chore rules ----

/// Known merchant: the last two approved payments to this payee were
/// approved by hand (or kept) with the same category. Returns that category.
String? knownMerchantCategory(String payee, Iterable<Item> items) {
  if (payee == 'Unknown payee') return null;
  final prior = items
      .where((i) => i.status == ItemStatus.approved && i.payee?.toLowerCase() == payee.toLowerCase())
      .toList()
    ..sort((a, b) => b.spentAt.compareTo(a.spentAt));
  if (prior.length < 2) return null;
  return prior[0].categoryId == prior[1].categoryId ? prior[0].categoryId : null;
}

/// Items safe to approve in one tap: pending and not flagged.
List<Item> unflaggedPending(Iterable<Item> items) =>
    items.where((i) => i.status == ItemStatus.pending && i.flagReason == null).toList();

/// One daily nudge (CSH-02 stays one reminder a day): items waiting and/or
/// cash not yet split. Null when there is nothing to do.
({String title, String body})? dailyNudge(Iterable<Withdrawal> ws, Iterable<Capture> captures, Iterable<Item> items) {
  final pending = inboxCount(items);
  final cash = dailyCashReminder(ws, captures, items);
  if (pending == 0 && cash == null) return null;
  if (pending == 0) return cash;
  final inbox = '$pending item${pending == 1 ? '' : 's'} to check';
  if (cash == null) return (title: inbox, body: 'Takes a few seconds. Pending items are not in your totals yet.');
  return (title: '$inbox · ${cash.title}', body: cash.body);
}

/// Weekly summary for the 7 days before [now], compared with the 7 before that.
({String title, String body})? weeklySummary(DateTime now, Iterable<Item> items) {
  final start = now.subtract(const Duration(days: 7));
  final prevStart = now.subtract(const Duration(days: 14));
  final week = items.where((i) => i.counts && i.spentAt.isAfter(start) && !i.spentAt.isAfter(now));
  final prev = items.where((i) => i.counts && i.spentAt.isAfter(prevStart) && !i.spentAt.isAfter(start));
  final total = totalApproved(week);
  if (total == 0) return null;
  final byCat = spendByCategory(week).entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  final top = byCat.first;
  final prevTotal = totalApproved(prev);
  String change = '';
  if (prevTotal > 0) {
    final pct = ((total - prevTotal) / prevTotal * 100).round();
    change = pct == 0 ? ' Same as last week.' : ' ${pct.abs()}% ${pct > 0 ? 'more' : 'less'} than last week.';
  }
  return (
    title: 'This week: ₹${total.toStringAsFixed(0)}',
    body: 'Most on ${categoryById(top.key).name} (₹${top.value.toStringAsFixed(0)}).$change',
  );
}


// ---- Bills counted twice ----

String _norm(String? s) => (s ?? '').toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

/// A bill already scanned: same total (within ₹1) and the same shop or the
/// same line amounts, scanned within 7 days. Rejected/deleted bills don't count.
Capture? findDuplicateBill(ParsedBill bill, DateTime at, Iterable<Capture> captures, Iterable<Item> items) {
  final lineSum = bill.lines.fold<double>(0.0, (s, l) => s + l.amount);
  final total = bill.total ?? lineSum;
  final amounts = (bill.lines.map((l) => (l.amount * 100).round()).toList()..sort()).join(',');
  for (final c in captures) {
    if (c.source != CaptureSource.bill || c.capturedAt.difference(at).abs() > const Duration(days: 7)) continue;
    final lines = items
        .where((i) => i.captureId == c.id && i.status != ItemStatus.deleted && i.status != ItemStatus.rejected)
        .toList();
    if (lines.isEmpty) continue;
    final cTotal = c.billTotal ?? lines.fold<double>(0.0, (s, i) => s + i.amount);
    if ((cTotal - total).abs() > 1.0) continue;
    final sameShop = _norm(c.sourceApp).isNotEmpty && _norm(c.sourceApp) == _norm(bill.merchant);
    final cAmounts = (lines.map((i) => (i.amount * 100).round()).toList()..sort()).join(',');
    if (sameShop || cAmounts == amounts) return c;
  }
  return null;
}

/// A UPI payment that is probably this bill: same amount (within ₹1), within
/// 12 hours, still counting or pending. Scanning the bill would count it twice.
Item? findPaymentForBill(ParsedBill bill, DateTime at, Iterable<Capture> captures, Iterable<Item> items) {
  final total = bill.total ?? bill.lines.fold<double>(0.0, (s, l) => s + l.amount);
  final upi = {for (final c in captures) if (c.source == CaptureSource.upiNotification) c.id};
  for (final i in items) {
    if (!upi.contains(i.captureId)) continue;
    if (i.status != ItemStatus.pending && i.status != ItemStatus.approved) continue;
    if ((i.amount - total).abs() <= 1.0 && i.spentAt.difference(at).abs() <= const Duration(hours: 12)) return i;
  }
  return null;
}

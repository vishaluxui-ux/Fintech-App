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

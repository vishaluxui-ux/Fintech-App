import 'dart:io';

import 'package:flutter/foundation.dart';

import '../domain/ledger.dart' as ledger;
import '../domain/models.dart';
import '../domain/upi_parser.dart';
import 'local_db.dart';
import 'settings.dart';

/// Single source of truth for the UI. Holds everything in memory, writes
/// through to [LocalDb] first (ACC-02), and applies the ledger rules.
class Repository extends ChangeNotifier {
  final LocalDb _db;
  final Settings settings;
  final void Function()? onLocalChange; // nudges sync

  List<Capture> captures = [];
  List<Item> items = [];
  List<Withdrawal> withdrawals = [];

  Repository(this._db, this.settings, {this.onLocalChange});

  Future<void> load() async {
    captures = await _db.captures();
    items = await _db.items();
    withdrawals = await _db.withdrawals();
    notifyListeners();
  }

  // ---- read model ----
  double get totalApproved => ledger.totalApproved(items);
  Map<String, double> get byCategory => ledger.spendByCategory(items);
  int get inboxCount => ledger.inboxCount(items);
  List<MapEntry<Capture, List<Item>>> get inbox => ledger.inboxGroups(captures, items);
  Capture captureOf(String id) => captures.firstWhere((c) => c.id == id);
  List<Item> itemsOf(String captureId) =>
      items.where((i) => i.captureId == captureId && i.status != ItemStatus.deleted).toList();
  String? mismatchFor(Capture c) => ledger.totalMismatch(c, items);
  double outstandingFor(Withdrawal w) => ledger.outstanding(w, captures, items);
  List<Item> get approved => items.where((i) => i.counts).toList()..sort((a, b) => b.spentAt.compareTo(a.spentAt));

  Set<String> get _knownPayees => items
      .where((i) => i.status == ItemStatus.approved && i.payee != null)
      .map((i) => i.payee!.toLowerCase())
      .toSet();

  // ---- capture ----

  /// CAP-01 / CAP-05: one notification -> one pending item or one withdrawal.
  Future<void> ingestNotification(NotificationResult r) async {
    switch (r) {
      case UpiPayment p:
        await _addPayment(p);
      case AtmWithdrawal a:
        await addWithdrawal(a.amount, a.at, sourceApp: a.sourceApp);
      case Ignored():
        return;
    }
  }

  Future<void> _addPayment(UpiPayment p) async {
    final cap = Capture(id: newId(), source: CaptureSource.upiNotification, sourceApp: p.sourceApp, capturedAt: p.at);
    var status = ItemStatus.pending;
    var flag = ledger.flagFor(payee: p.payee, knownPayees: _knownPayees);
    final dup = ledger.findDuplicate(amount: p.amount, payee: p.payee, at: p.at, existing: items);
    if (dup != null) {
      final o = ledger.duplicateOutcome(settings.duplicateMode, dup);
      status = o.status;
      flag = o.flag;
    }
    final item = Item(
      id: newId(),
      captureId: cap.id,
      name: p.payee,
      amount: p.amount,
      categoryId: _guessCategory(p.payee),
      status: status,
      spentAt: p.at,
      payee: p.payee,
      flagReason: flag,
      updatedAt: DateTime.now(),
    );
    await _saveCapture(cap, [item]);
  }

  /// Reuse the category the user last approved for this payee.
  String _guessCategory(String payee) {
    final prior = items.where((i) => i.status == ItemStatus.approved && i.payee?.toLowerCase() == payee.toLowerCase());
    return prior.isEmpty ? 'other' : prior.reduce((a, b) => a.updatedAt.isAfter(b.updatedAt) ? a : b).categoryId;
  }

  /// CAP-02 / CAP-03: one bill -> one capture with an item per line.
  Future<Capture> addBill(ParsedBill bill, {String? imagePath, DateTime? at}) async {
    final now = at ?? DateTime.now();
    final cap = Capture(
        id: newId(),
        source: CaptureSource.bill,
        sourceApp: bill.merchant,
        capturedAt: now,
        billTotal: bill.total,
        imagePath: imagePath);
    final lines = [
      for (final l in bill.lines)
        Item(
          id: newId(),
          captureId: cap.id,
          name: l.name,
          amount: l.amount,
          categoryId: categoryById(l.categoryId).id,
          status: ItemStatus.pending,
          spentAt: now,
          payee: bill.merchant,
          flagReason: ledger.flagFor(confidence: l.confidence, payee: null, knownPayees: const {}),
          updatedAt: DateTime.now(),
        )
    ];
    await _saveCapture(cap, lines);
    return cap;
  }

  /// CAP-04: manual entry. With [withdrawalId] it is a cash spend split from
  /// that withdrawal (CSH-01); [captureId] adds a missed line to an existing bill.
  Future<Item> addManual({
    required String name,
    required double amount,
    required String categoryId,
    String? withdrawalId,
    String? captureId,
    bool cash = false,
    DateTime? at,
  }) async {
    final when = at ?? DateTime.now();
    Capture? cap;
    if (captureId == null) {
      cap = Capture(
          id: newId(),
          source: (cash || withdrawalId != null) ? CaptureSource.cash : CaptureSource.manual,
          capturedAt: when,
          withdrawalId: withdrawalId);
    }
    final item = Item(
      id: newId(),
      captureId: captureId ?? cap!.id,
      name: name,
      amount: amount,
      categoryId: categoryId,
      status: ItemStatus.pending,
      spentAt: when,
      updatedAt: DateTime.now(),
    );
    await _saveCapture(cap, [item]);
    return item;
  }

  Future<Withdrawal> addWithdrawal(double amount, DateTime at, {String? sourceApp}) async {
    final w = Withdrawal(id: newId(), amount: amount, at: at, sourceApp: sourceApp);
    await _db.putWithdrawal(w);
    withdrawals = [...withdrawals, w];
    _changed();
    return w;
  }

  // ---- approval ----

  /// APR-02: edits are kept; editing clears a flag the user has now reviewed.
  Future<void> edit(String itemId, {String? name, double? amount, String? categoryId}) =>
      _update(itemId, (i) => i.copyWith(name: name, amount: amount, categoryId: categoryId));

  Future<void> approve(String itemId) =>
      _update(itemId, (i) => i.copyWith(status: ItemStatus.approved, clearFlag: true));

  /// APR-03: one action approves every pending item in the bill.
  Future<void> approveAll(String captureId) async {
    for (final i in items.where((i) => i.captureId == captureId && i.status == ItemStatus.pending).toList()) {
      await approve(i.id);
    }
  }

  /// Rejected: kept for duplicate checks and parsing feedback, never counted.
  Future<void> reject(String itemId) => _update(itemId, (i) => i.copyWith(status: ItemStatus.rejected));

  /// APR-05: leaves every total.
  Future<void> delete(String itemId) => _update(itemId, (i) => i.copyWith(status: ItemStatus.deleted));

  Future<void> _update(String id, Item Function(Item) f) async {
    final idx = items.indexWhere((i) => i.id == id);
    if (idx < 0) return;
    final next = f(items[idx]);
    await _db.putItem(next);
    items = [...items]..[idx] = next;
    await _maybeDropPhoto(next.captureId);
    _changed();
  }

  /// Bill photo retention setting: once nothing on the bill is pending, drop the photo.
  Future<void> _maybeDropPhoto(String captureId) async {
    if (settings.keepBillPhotos) return;
    final idx = captures.indexWhere((c) => c.id == captureId);
    if (idx < 0 || captures[idx].imagePath == null) return;
    if (items.any((i) => i.captureId == captureId && i.status == ItemStatus.pending)) return;
    final path = captures[idx].imagePath!;
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
    final next = captures[idx].copyWith(clearImage: true);
    await _db.putCapture(next);
    captures = [...captures]..[idx] = next;
  }

  Future<void> _saveCapture(Capture? cap, List<Item> newItems) async {
    if (cap != null) {
      await _db.putCapture(cap);
      captures = [...captures, cap];
    }
    for (final i in newItems) {
      await _db.putItem(i);
    }
    items = [...items, ...newItems];
    _changed();
  }

  void _changed() {
    notifyListeners();
    onLocalChange?.call();
  }

  Future<void> wipeLocal() async {
    await _db.wipe();
    captures = [];
    items = [];
    withdrawals = [];
    notifyListeners();
  }
}

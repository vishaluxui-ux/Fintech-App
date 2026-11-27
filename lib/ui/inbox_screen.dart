import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../data/repository.dart';
import '../domain/ledger.dart' as ledger;
import '../domain/models.dart';
import '../domain/period.dart';
import '../services/refresh_service.dart';
import '../services/bill_parser.dart';
import 'bill_screen.dart';
import 'item_editor.dart';
import 'mismatch_sheet.dart';
import 'theme.dart';

/// APR-01: pending items grouped by bill or payment.
class InboxScreen extends StatelessWidget {
  const InboxScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<Repository>();
    final groups = repo.inbox;
    final unflagged = ledger.unflaggedPending(repo.items).length;
    return Scaffold(
      appBar: AppBar(title: const Text('Inbox'), actions: [
        IconButton(
          onPressed: () => _refresh(context),
          icon: const Icon(Icons.refresh),
          tooltip: 'Check for new payments',
        ),
        if (unflagged > 0)
          TextButton.icon(
            onPressed: () async {
              final n = await repo.approveAllUnflagged();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('Approved $n item${n == 1 ? '' : 's'}. Flagged ones still need a look.')));
              }
            },
            icon: const Icon(Icons.done_all),
            label: Text('Approve $unflagged'),
          ),
      ]),
      floatingActionButton: _AddMenu(),
      body: RefreshIndicator(
        onRefresh: () => _refresh(context),
        child: groups.isEmpty
            ? ListView(children: const [
                Padding(
                  padding: EdgeInsets.all(32),
                  child: Text('Nothing to check. New UPI payments and scanned bills land here.\n\n'
                      'Pull down or tap ↻ to check for new payments.',
                      textAlign: TextAlign.center),
                ),
              ])
            : ListView.builder(
                padding: const EdgeInsets.only(bottom: 96),
                itemCount: groups.length,
                itemBuilder: (_, i) {
                  final at = groups[i].key.capturedAt;
                  final newDay = i == 0 || !_sameDay(groups[i - 1].key.capturedAt, at);
                  final card = _GroupCard(capture: groups[i].key, items: groups[i].value);
                  if (!newDay) return card;
                  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: Text(dayLabel(at, DateTime.now()),
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(color: Theme.of(context).colorScheme.primary)),
                    ),
                    card,
                  ]);
                },
              ),
      ),
    );
  }

  static bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  static Future<void> _refresh(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final r = await context.read<RefreshService>().refresh();
    messenger.showSnackBar(SnackBar(content: Text(r.message)));
  }
}

class _GroupCard extends StatelessWidget {
  final Capture capture;
  final List<Item> items;
  const _GroupCard({required this.capture, required this.items});

  String get _title => switch (capture.source) {
        CaptureSource.bill => capture.sourceApp ?? 'Bill',
        CaptureSource.upiNotification => 'UPI · ${capture.sourceApp ?? ''}',
        CaptureSource.cash => 'Cash',
        CaptureSource.manual => 'Added by you',
      };

  @override
  Widget build(BuildContext context) {
    final repo = context.read<Repository>();
    final mismatch = repo.mismatchFor(capture);
    final cs = Theme.of(context).colorScheme;
    final single = items.length == 1 && capture.source != CaptureSource.bill;

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ListTile(
          title: Text(_title),
          subtitle: Text(when(capture.capturedAt)),
          trailing: capture.source == CaptureSource.bill ? const Icon(Icons.chevron_right) : null,
          onTap: capture.source == CaptureSource.bill
              ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => BillScreen(captureId: capture.id)))
              : null,
        ),
        if (mismatch != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Icon(Icons.warning_amber, color: cs.error, size: 18),
              const SizedBox(width: 6),
              Expanded(child: Text(mismatch, style: TextStyle(color: cs.error))),
            ]),
          ),
        for (final i in items) ItemTile(item: i),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            if (single) ...[
              TextButton(onPressed: () => repo.reject(items.first.id), child: const Text('Reject')),
              FilledButton(onPressed: () => repo.approve(items.first.id), child: const Text('Approve')),
            ] else
              FilledButton(
                onPressed: () => confirmApproveAll(context, capture, items.length),
                child: Text('Approve all ${items.length}'),
              ),
          ]),
        ),
      ]),
    );
  }
}

/// APR-03 with the CAP-03 warning shown before approval.
Future<void> confirmApproveAll(BuildContext context, Capture capture, int count) async {
  final repo = context.read<Repository>();
  final mismatch = repo.mismatchFor(capture);
  if (mismatch != null) {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Totals do not match'),
        content: Text('$mismatch. Tell us why and we\'ll fix the amounts, or approve as it is.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Approve as is')),
          FilledButton(onPressed: () => Navigator.pop(c, false), child: const Text('Fix the bill')),
        ],
      ),
    );
    if (ok == null || !context.mounted) return;
    if (!ok) {
      final fixed = await showMismatchSheet(context, capture.id);
      if (!fixed || repo.mismatchFor(repo.captureOf(capture.id)) != null) return;
    }
  }
  await repo.approveAll(capture.id);
}

/// One inbox line: tap to edit, swipe actions in the editor.
class ItemTile extends StatelessWidget {
  final Item item;
  const ItemTile({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      title: Text(item.name),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(categoryById(item.categoryId).name),
        if (item.flagReason != null)
          Row(children: [
            Icon(Icons.flag_outlined, size: 14, color: cs.tertiary),
            const SizedBox(width: 4),
            Expanded(child: Text(item.flagReason!, style: TextStyle(color: cs.tertiary))),
          ]),
      ]),
      trailing: Text(inr(item.amount), style: Theme.of(context).textTheme.titleSmall),
      onTap: () => showItemEditor(context, item: item),
    );
  }
}

class _AddMenu extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      onPressed: () => showModalBottomSheet(
        context: context,
        builder: (c) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Scan a bill'),
                onTap: () {
                  Navigator.pop(c);
                  scanBill(context, ImageSource.camera);
                }),
            ListTile(
                leading: const Icon(Icons.image_outlined),
                title: const Text('Bill photo or screenshot'),
                onTap: () {
                  Navigator.pop(c);
                  scanBill(context, ImageSource.gallery);
                }),
            ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Add manually'),
                onTap: () {
                  Navigator.pop(c);
                  showItemEditor(context);
                }),
          ]),
        ),
      ),
      icon: const Icon(Icons.add),
      label: const Text('Add'),
    );
  }
}

/// CAP-02: pick or take a photo, send it for parsing, add the lines as pending.
Future<void> scanBill(BuildContext context, ImageSource source) async {
  final picked = await ImagePicker().pickImage(source: source, maxWidth: 2000, imageQuality: 85);
  if (picked == null || !context.mounted) return;
  await scanBillFile(context, picked.path);
}

/// Reads a bill photo or payment screenshot at [path] (picked, taken, or shared into the app).
Future<void> scanBillFile(BuildContext context, String path) async {
  final repo = context.read<Repository>();
  final parser = context.read<BillParser>();
  final nav = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(const SnackBar(content: Text('Reading the bill…')));
  try {
    final bill = await parser.parse(File(path));
    if (bill.lines.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('No items found. Try a clearer photo, or add them manually.')));
      return;
    }
    messenger.hideCurrentSnackBar();
    final now = DateTime.now();
    final settings = repo.settings;

    // Same bill scanned before?
    final dup = ledger.findDuplicateBill(bill, now, repo.captures, repo.items);
    if (dup != null) {
      final what = '${dup.sourceApp ?? 'a bill'} from ${when(dup.capturedAt)}';
      if (settings.duplicateMode == DuplicateMode.autoReject) {
        var addAnyway = false;
        await messenger
            .showSnackBar(SnackBar(
              content: Text('Skipped: you already scanned this bill ($what).'),
              action: SnackBarAction(label: 'Add anyway', onPressed: () => addAnyway = true),
              duration: const Duration(seconds: 6),
            ))
            .closed;
        if (!addAnyway) return;
      } else {
        if (!context.mounted) return;
        final add = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Already scanned?'),
            content: Text('This looks like $what. Adding it again will count it twice.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Add anyway')),
              FilledButton(onPressed: () => Navigator.pop(c, false), child: const Text("Don't add")),
            ],
          ),
        );
        if (add != true) return;
      }
    }

    // Already logged as a UPI payment?
    String? replaces;
    final paid = ledger.findPaymentForBill(bill, now, repo.captures, repo.items);
    if (paid != null && context.mounted) {
      final useBill = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Paid by UPI?'),
          content: Text('This bill matches your ${inr(paid.amount)} payment to ${paid.payee ?? paid.name} '
              'at ${when(paid.spentAt)}. Use the bill\'s item list instead, so it counts once?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep both')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Use bill items')),
          ],
        ),
      );
      if (useBill == null) return;
      if (useBill) replaces = paid.id;
    }

    final cap = await repo.addBill(bill, imagePath: path, at: now, replacesPaymentId: replaces);
    messenger.hideCurrentSnackBar();
    nav.push(MaterialPageRoute(builder: (_) => BillScreen(captureId: cap.id)));
  } catch (e) {
    messenger.showSnackBar(const SnackBar(content: Text('Could not read the bill. Check your connection and try again.')));
  }
}

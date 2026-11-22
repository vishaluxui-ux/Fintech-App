import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../data/repository.dart';
import '../domain/ledger.dart' as ledger;
import '../domain/models.dart';
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
      body: groups.isEmpty
          ? const Center(
              child: Padding(
              padding: EdgeInsets.all(32),
              child: Text('Nothing to check. New UPI payments and scanned bills land here.', textAlign: TextAlign.center),
            ))
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 96),
              itemCount: groups.length,
              itemBuilder: (_, i) => _GroupCard(capture: groups[i].key, items: groups[i].value),
            ),
    );
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
    final cap = await repo.addBill(bill, imagePath: path);
    messenger.hideCurrentSnackBar();
    nav.push(MaterialPageRoute(builder: (_) => BillScreen(captureId: cap.id)));
  } catch (e) {
    messenger.showSnackBar(const SnackBar(content: Text('Could not read the bill. Check your connection and try again.')));
  }
}

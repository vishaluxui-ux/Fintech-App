import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/repository.dart';
import '../domain/models.dart';
import 'inbox_screen.dart';
import 'item_editor.dart';
import 'mismatch_sheet.dart';
import 'theme.dart';

/// Review one bill: photo, every line, total check, add a missed line, approve all.
class BillScreen extends StatelessWidget {
  final String captureId;
  const BillScreen({super.key, required this.captureId});

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<Repository>();
    final cap = repo.captureOf(captureId);
    final items = repo.itemsOf(captureId).where((i) => i.status != ItemStatus.rejected).toList();
    final pending = items.where((i) => i.status == ItemStatus.pending).length;
    final mismatch = repo.mismatchFor(cap);
    final sum = items.fold(0.0, (s, i) => s + i.amount);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(cap.sourceApp ?? 'Bill')),
      body: ListView(padding: const EdgeInsets.only(bottom: 96), children: [
        if (cap.imagePath != null && File(cap.imagePath!).existsSync())
          Padding(
            padding: const EdgeInsets.all(12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(File(cap.imagePath!), height: 180, fit: BoxFit.cover),
            ),
          ),
        ListTile(
          title: const Text('Items total'),
          trailing: Text(inr(sum), style: Theme.of(context).textTheme.titleMedium),
          subtitle: cap.billTotal == null ? const Text('No total found on the bill') : Text('Bill says ${inr(cap.billTotal!)}'),
        ),
        if (mismatch != null)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: cs.errorContainer, borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              Expanded(child: Text(mismatch, style: TextStyle(color: cs.onErrorContainer))),
              TextButton(onPressed: () => showMismatchSheet(context, captureId), child: const Text('Fix')),
            ]),
          ),
        if (cap.adjustReason != null)
          ListTile(
            dense: true,
            leading: const Icon(Icons.check_circle_outline),
            title: Text(switch (cap.adjustReason!) {
              MismatchReason.discount => cap.adjustNote == 'auto' ? 'Discount applied from the bill' : 'Discount applied',
              MismatchReason.printError => 'Printed total ignored: items counted',
              MismatchReason.duplicateLine => 'Repeated line removed',
              MismatchReason.other => 'Adjusted: ${cap.adjustNote ?? ''}',
            }),
          ),
        const Divider(),
        for (final i in items)
          i.status == ItemStatus.pending
              ? ItemTile(item: i)
              : ListTile(
                  dense: true,
                  title: Text(i.name),
                  subtitle: Text('${categoryById(i.categoryId).name} · approved'),
                  trailing: Text(inr(i.amount)),
                ),
        TextButton.icon(
          onPressed: () => showItemEditor(context, captureId: captureId),
          icon: const Icon(Icons.add),
          label: const Text('Add a missed line'),
        ),
      ]),
      bottomNavigationBar: pending == 0
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton(
                  onPressed: () async {
                    await confirmApproveAll(context, cap, pending);
                    if (context.mounted && repo.itemsOf(captureId).every((i) => i.status != ItemStatus.pending)) {
                      Navigator.pop(context);
                    }
                  },
                  child: Text('Approve all $pending'),
                ),
              ),
            ),
    );
  }
}

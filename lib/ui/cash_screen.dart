import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/repository.dart';
import '../domain/ledger.dart' as ledger;
import '../domain/models.dart';
import 'item_editor.dart';
import 'theme.dart';

/// CAP-05 / CSH-01 / CSH-02: withdrawals as unallocated cash, split into spends.
class CashScreen extends StatelessWidget {
  const CashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<Repository>();
    final ws = [...repo.withdrawals]..sort((a, b) => b.at.compareTo(a.at));
    final totalOut = ws.fold(0.0, (s, w) => s + repo.outstandingFor(w).clamp(0, double.infinity));
    final monthEnd = ledger.offerMonthEndReview(DateTime.now(), repo.withdrawals, repo.captures, repo.items);

    return Scaffold(
      appBar: AppBar(title: const Text('Cash')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addWithdrawal(context),
        icon: const Icon(Icons.atm),
        label: const Text('Add withdrawal'),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 96), children: [
        Text('Not yet split', style: Theme.of(context).textTheme.labelLarge),
        Text(inr(totalOut), style: Theme.of(context).textTheme.headlineMedium),
        if (monthEnd)
          Card(
            child: ListTile(
              leading: const Icon(Icons.event_note_outlined),
              title: const Text('Month-end review'),
              subtitle: const Text('Split what is left before the month closes.'),
            ),
          ),
        const SizedBox(height: 8),
        if (ws.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text('ATM withdrawals from your bank or UPI app alerts show up here. You can also add one yourself.'),
          ),
        for (final w in ws) _WithdrawalCard(w: w),
      ]),
    );
  }

  Future<void> _addWithdrawal(BuildContext context) async {
    final c = TextEditingController();
    final amount = await showDialog<double>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('ATM withdrawal'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Amount', prefixText: '₹ '),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, double.tryParse(c.text.trim())), child: const Text('Add')),
        ],
      ),
    );
    if (amount != null && amount > 0 && context.mounted) {
      await context.read<Repository>().addWithdrawal(amount, DateTime.now());
    }
  }
}

class _WithdrawalCard extends StatelessWidget {
  final Withdrawal w;
  const _WithdrawalCard({required this.w});

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<Repository>();
    final out = repo.outstandingFor(w);
    final spends = repo.captures
        .where((c) => c.withdrawalId == w.id)
        .expand((c) => repo.itemsOf(c.id))
        .where((i) => i.status == ItemStatus.pending || i.status == ItemStatus.approved)
        .toList();
    return Card(
      child: ExpansionTile(
        title: Text('${inr(w.amount, whole: true)} withdrawn'),
        subtitle: Text('${when(w.at)}${w.sourceApp != null ? ' · ${w.sourceApp}' : ''}\n'
            '${inr(out)} outstanding'),
        children: [
          for (final i in spends)
            ListTile(
              dense: true,
              title: Text(i.name),
              subtitle: Text('${categoryById(i.categoryId).name}${i.status == ItemStatus.pending ? ' · in inbox' : ''}'),
              trailing: Text(inr(i.amount)),
            ),
          if (out > 0)
            TextButton.icon(
              onPressed: () => showItemEditor(context, withdrawalId: w.id),
              icon: const Icon(Icons.call_split),
              label: const Text('Split into a spend'),
            ),
        ],
      ),
    );
  }
}

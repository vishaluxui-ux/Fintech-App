import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/repository.dart';
import '../domain/models.dart';
import 'theme.dart';

/// DSH-01: total approved spend, spend by category, inbox count.
class DashboardScreen extends StatelessWidget {
  final VoidCallback onOpenInbox;
  const DashboardScreen({super.key, required this.onOpenInbox});

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<Repository>();
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final cats = repo.byCategory.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final total = repo.totalApproved;

    return Scaffold(
      appBar: AppBar(title: const Text('Spending')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Approved spend', style: t.labelLarge),
        Text(inr(total), key: const Key('total'), style: t.displaySmall),
        const SizedBox(height: 12),
        if (repo.inboxCount > 0)
          Card(
            color: cs.secondaryContainer,
            child: ListTile(
              leading: const Icon(Icons.inbox_outlined),
              title: Text('${repo.inboxCount} item${repo.inboxCount == 1 ? '' : 's'} to check'),
              subtitle: const Text('Pending items are not in your totals yet'),
              trailing: const Icon(Icons.chevron_right),
              onTap: onOpenInbox,
            ),
          ),
        const SizedBox(height: 16),
        Text('By category', style: t.titleMedium),
        const SizedBox(height: 8),
        if (cats.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text('Approve items in your inbox to see where your money goes.'),
          ),
        for (final e in cats)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(categoryById(e.key).name)),
                Text(inr(e.value, whole: true), style: t.titleSmall),
              ]),
              const SizedBox(height: 4),
              LinearProgressIndicator(value: total == 0 ? 0 : e.value / total, minHeight: 8,
                  borderRadius: BorderRadius.circular(4)),
            ]),
          ),
      ]),
    );
  }
}

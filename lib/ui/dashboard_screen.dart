import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/repository.dart';
import '../domain/ledger.dart' as ledger;
import '../domain/models.dart';
import '../domain/period.dart';
import '../services/refresh_service.dart';
import 'item_editor.dart';
import 'pie_chart.dart';
import 'theme.dart';

/// DSH-01: approved spend for a day, month or year, by category (pie) and by date.
/// Pending items never count.
class DashboardScreen extends StatefulWidget {
  final VoidCallback onOpenInbox;
  const DashboardScreen({super.key, required this.onOpenInbox});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  Period _period = Period.of(PeriodKind.month, DateTime.now());
  String? _category; // filters the Transactions tab

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final messenger = ScaffoldMessenger.of(context);
    final r = await context.read<RefreshService>().refresh();
    messenger.showSnackBar(SnackBar(content: Text(r.message)));
  }

  void _openCategory(String id) => setState(() {
        _category = id;
        _tabs.animateTo(1);
      });

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<Repository>();
    final now = DateTime.now();
    final inPeriod = countedIn(repo.items, _period);
    final total = ledger.totalApproved(inPeriod);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Spending'),
        actions: [
          IconButton(
              onPressed: _refresh, icon: const Icon(Icons.refresh), tooltip: 'Check for new payments'),
        ],
        bottom: TabBar(controller: _tabs, tabs: const [Tab(text: 'Categories'), Tab(text: 'Transactions')]),
      ),
      body: Column(children: [
        _PeriodBar(
          period: _period,
          now: now,
          onChanged: (p) => setState(() => _period = p),
        ),
        _TotalRow(total: total, inboxCount: repo.inboxCount, onOpenInbox: widget.onOpenInbox),
        Expanded(
          child: TabBarView(controller: _tabs, children: [
            RefreshIndicator(
              onRefresh: _refresh,
              child: _CategoriesTab(items: inPeriod, total: total, period: _period, now: now, onOpen: _openCategory),
            ),
            RefreshIndicator(
              onRefresh: _refresh,
              child: _TransactionsTab(
                items: _category == null ? inPeriod : inPeriod.where((i) => i.categoryId == _category).toList(),
                category: _category,
                onClearCategory: () => setState(() => _category = null),
                now: now,
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// Day / Month / Year switch, with arrows to step back and forward.
class _PeriodBar extends StatelessWidget {
  final Period period;
  final DateTime now;
  final ValueChanged<Period> onChanged;
  const _PeriodBar({required this.period, required this.now, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(children: [
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<PeriodKind>(
            segments: const [
              ButtonSegment(value: PeriodKind.day, label: Text('Day')),
              ButtonSegment(value: PeriodKind.month, label: Text('Month')),
              ButtonSegment(value: PeriodKind.year, label: Text('Year')),
            ],
            selected: {period.kind},
            showSelectedIcon: false,
            onSelectionChanged: (s) => onChanged(period.withKind(s.first, now)),
          ),
        ),
        const SizedBox(height: 4),
        Row(children: [
          IconButton(
            onPressed: () => onChanged(period.previous),
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Previous',
          ),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _pickDate(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(period.label(now), textAlign: TextAlign.center, style: t.titleMedium),
              ),
            ),
          ),
          IconButton(
            onPressed: period.hasEnded(now) ? () => onChanged(period.next) : null,
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Next',
          ),
        ]),
      ]),
    );
  }

  Future<void> _pickDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: period.contains(now) ? now : period.start,
      firstDate: DateTime(2020),
      lastDate: now,
      helpText: 'Jump to a date',
    );
    if (picked != null) onChanged(Period.of(period.kind, picked));
  }
}

class _TotalRow extends StatelessWidget {
  final double total;
  final int inboxCount;
  final VoidCallback onOpenInbox;
  const _TotalRow({required this.total, required this.inboxCount, required this.onOpenInbox});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Approved spend', style: t.labelLarge, textAlign: TextAlign.center),
        Text(inr(total), key: const Key('total'), style: t.headlineMedium, textAlign: TextAlign.center),
        if (inboxCount > 0) ...[
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            color: cs.secondaryContainer,
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.inbox_outlined),
              title: Text('$inboxCount item${inboxCount == 1 ? '' : 's'} to check'),
              subtitle: const Text('Pending items are not in your totals yet'),
              trailing: const Icon(Icons.chevron_right),
              onTap: onOpenInbox,
            ),
          ),
        ],
      ]),
    );
  }
}

/// Pie chart of the period's spend plus a list of categories with amount and share.
class _CategoriesTab extends StatelessWidget {
  final List<Item> items;
  final double total;
  final Period period;
  final DateTime now;
  final ValueChanged<String> onOpen;
  const _CategoriesTab(
      {required this.items, required this.total, required this.period, required this.now, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cats = ledger.spendByCategory(items).entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    if (cats.isEmpty) {
      return ListView(padding: const EdgeInsets.all(32), children: [
        Text('No approved spend in ${period.label(now)}.\nApprove items in your inbox to see where your money goes.',
            textAlign: TextAlign.center),
      ]);
    }
    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
      Center(
        child: SpendPie(
          slices: [for (final e in cats) PieSlice(e.key, e.value, categoryColor(e.key))],
          centerTop: period.label(now),
          centerBottom: inr(total, whole: true),
          onTap: onOpen,
        ),
      ),
      const SizedBox(height: 16),
      for (final e in cats)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(radius: 8, backgroundColor: categoryColor(e.key)),
          minLeadingWidth: 16,
          title: Text(categoryById(e.key).name),
          subtitle: Text('${(e.value / total * 100).round()}% · '
              '${items.where((i) => i.categoryId == e.key).length} item${items.where((i) => i.categoryId == e.key).length == 1 ? '' : 's'}'),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(inr(e.value, whole: true), style: t.titleSmall),
            const Icon(Icons.chevron_right),
          ]),
          onTap: () => onOpen(e.key),
        ),
    ]);
  }
}

/// Approved items with a separator for each date, showing that day's total.
class _TransactionsTab extends StatelessWidget {
  final List<Item> items;
  final String? category;
  final VoidCallback onClearCategory;
  final DateTime now;
  const _TransactionsTab(
      {required this.items, required this.category, required this.onClearCategory, required this.now});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final days = groupByDay(items);
    return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
      if (category != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: InputChip(
              avatar: CircleAvatar(backgroundColor: categoryColor(category!)),
              label: Text(categoryById(category!).name),
              onDeleted: onClearCategory,
              deleteButtonTooltipMessage: 'Show all categories',
            ),
          ),
        ),
      if (days.isEmpty)
        const Padding(
          padding: EdgeInsets.all(32),
          child: Text('Nothing approved in this period.', textAlign: TextAlign.center),
        ),
      for (final d in days) ...[
        Container(
          color: cs.surfaceContainerHighest,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          margin: const EdgeInsets.only(top: 8),
          child: Row(children: [
            Expanded(child: Text(dayLabel(d.key, now), style: t.labelLarge)),
            Text(inr(ledger.totalApproved(d.value), whole: true), style: t.labelLarge),
          ]),
        ),
        for (final i in d.value) _ItemRow(item: i),
      ],
    ]);
  }
}

class _ItemRow extends StatelessWidget {
  final Item item;
  const _ItemRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final time = TimeOfDay.fromDateTime(item.spentAt).format(context);
    return ListTile(
      dense: true,
      leading: CircleAvatar(radius: 6, backgroundColor: categoryColor(item.categoryId)),
      minLeadingWidth: 12,
      title: Text(item.name),
      subtitle: Text('${categoryById(item.categoryId).name} · $time'),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (item.autoApproved)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Tooltip(
              message: 'Approved automatically: you approved this merchant before',
              child: Chip(
                  label: const Text('Auto'),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  side: BorderSide(color: cs.outlineVariant)),
            ),
          ),
        Text(inr(item.amount), style: t.titleSmall),
      ]),
      onTap: () => showItemEditor(context, item: item),
    );
  }
}

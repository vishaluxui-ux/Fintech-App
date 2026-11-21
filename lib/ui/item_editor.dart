import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/repository.dart';
import '../domain/models.dart';

/// Edit + approve / reject / delete an item (APR-02, APR-05), or add a new one
/// (CAP-04). [captureId] adds a missed line to a bill; [withdrawalId] logs a cash spend.
Future<void> showItemEditor(BuildContext context, {Item? item, String? captureId, String? withdrawalId}) =>
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _Editor(item: item, captureId: captureId, withdrawalId: withdrawalId),
    );

class _Editor extends StatefulWidget {
  final Item? item;
  final String? captureId;
  final String? withdrawalId;
  const _Editor({this.item, this.captureId, this.withdrawalId});
  @override
  State<_Editor> createState() => _EditorState();
}

class _EditorState extends State<_Editor> {
  late final _name = TextEditingController(text: widget.item?.name ?? '');
  late final _amount = TextEditingController(text: widget.item?.amount.toStringAsFixed(2) ?? '');
  late String _cat = widget.item?.categoryId ?? 'food';
  bool _cash = false;
  String? _err;

  bool get _isNew => widget.item == null;

  ({String name, double amount})? _read() {
    final a = double.tryParse(_amount.text.replaceAll(',', '').trim());
    if (_name.text.trim().isEmpty) {
      setState(() => _err = 'Enter a name');
      return null;
    }
    if (a == null || a <= 0) {
      setState(() => _err = 'Enter an amount above 0');
      return null;
    }
    return (name: _name.text.trim(), amount: a);
  }

  Future<void> _save({bool approve = false}) async {
    final v = _read();
    if (v == null) return;
    final repo = context.read<Repository>();
    if (_isNew) {
      final i = await repo.addManual(
          name: v.name,
          amount: v.amount,
          categoryId: _cat,
          captureId: widget.captureId,
          withdrawalId: widget.withdrawalId,
          cash: _cash);
      if (approve) await repo.approve(i.id);
    } else {
      await repo.edit(widget.item!.id, name: v.name, amount: v.amount, categoryId: _cat);
      if (approve) await repo.approve(widget.item!.id);
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _act(Future<void> Function(String) f) async {
    await f(widget.item!.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<Repository>();
    final title = _isNew
        ? (widget.withdrawalId != null ? 'Log a cash spend' : (widget.captureId != null ? 'Add a missed line' : 'Add an item'))
        : 'Check item';
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        if (widget.item?.flagReason != null) ...[
          const SizedBox(height: 8),
          Text(widget.item!.flagReason!, style: TextStyle(color: Theme.of(context).colorScheme.tertiary)),
        ],
        const SizedBox(height: 16),
        TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name'), textCapitalization: TextCapitalization.sentences),
        const SizedBox(height: 12),
        TextField(
          controller: _amount,
          decoration: const InputDecoration(labelText: 'Amount', prefixText: '₹ '),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _cat,
          decoration: const InputDecoration(labelText: 'Category'),
          items: [for (final c in defaultCategories) DropdownMenuItem(value: c.id, child: Text(c.name))],
          onChanged: (v) => setState(() => _cat = v!),
        ),
        if (_isNew && widget.captureId == null && widget.withdrawalId == null)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _cash,
            onChanged: (v) => setState(() => _cash = v!),
            title: const Text('Paid in cash'),
          ),
        if (_err != null) Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(_err!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ),
        const SizedBox(height: 16),
        Row(children: [
          if (!_isNew) ...[
            IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline), onPressed: () => _act(repo.delete)),
            TextButton(onPressed: () => _act(repo.reject), child: const Text('Reject')),
          ],
          const Spacer(),
          OutlinedButton(onPressed: () => _save(), child: Text(_isNew ? 'Add to inbox' : 'Save')),
          const SizedBox(width: 8),
          FilledButton(onPressed: () => _save(approve: true), child: Text(_isNew ? 'Add & approve' : 'Approve')),
        ]),
      ]),
    );
  }
}

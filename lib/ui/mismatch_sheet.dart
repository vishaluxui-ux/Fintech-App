import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/repository.dart';
import '../domain/ledger.dart' as ledger;
import '../domain/models.dart';
import 'theme.dart';

/// Asks why a bill's lines don't add up to its total, then fixes the lines
/// so the counted amount is what the user actually paid.
/// Returns true when the mismatch was resolved.
Future<bool> showMismatchSheet(BuildContext context, String captureId) async =>
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _MismatchSheet(captureId: captureId),
    ) ??
    false;

class _MismatchSheet extends StatefulWidget {
  final String captureId;
  const _MismatchSheet({required this.captureId});
  @override
  State<_MismatchSheet> createState() => _MismatchSheetState();
}

class _MismatchSheetState extends State<_MismatchSheet> {
  MismatchReason? _reason;
  final _discount = TextEditingController();
  final _paid = TextEditingController();
  final _note = TextEditingController();
  String? _repeatId;
  String? _err;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final repo = context.read<Repository>();
    final f = ledger.mismatchFigures(repo.captureOf(widget.captureId), repo.items);
    _paid.text = f.bill.toStringAsFixed(2);
    if (f.gap > 0) {
      _discount.text = f.gap.toStringAsFixed(2);
      _reason = MismatchReason.discount; // items cost more than the bill: most often a discount
    }
    final repeats = ledger.likelyRepeatedLines(repo.itemsOf(widget.captureId).where(_open));
    if (repeats.isNotEmpty) {
      _repeatId = repeats.first;
      _reason = MismatchReason.duplicateLine;
    }
  }

  bool _open(Item i) => i.status != ItemStatus.rejected && i.status != ItemStatus.deleted;

  double? _num(TextEditingController c) => double.tryParse(c.text.replaceAll(',', '').trim());

  Future<void> _apply() async {
    final repo = context.read<Repository>();
    final f = ledger.mismatchFigures(repo.captureOf(widget.captureId), repo.items);
    setState(() => _err = null);
    try {
      switch (_reason) {
        case MismatchReason.discount:
          final d = _num(_discount), paid = _num(_paid);
          if (d == null || d <= 0) return setState(() => _err = 'Enter the discount amount');
          if (paid == null || paid <= 0) return setState(() => _err = 'Enter the amount you paid');
          if (d >= f.items) return setState(() => _err = 'The discount is more than the items total');
          if ((f.items - d - paid).abs() > 1.0) {
            return setState(() => _err =
                'Items ${inr(f.items)} minus discount ${inr(d)} is ${inr(f.items - d)}, not ${inr(paid)}. Check both numbers.');
          }
          setState(() => _busy = true);
          await repo.resolveDiscount(widget.captureId, discount: d, paidTotal: paid);
        case MismatchReason.printError:
          setState(() => _busy = true);
          await repo.resolvePrintError(widget.captureId);
        case MismatchReason.duplicateLine:
          if (_repeatId == null) return setState(() => _err = 'Tap the line that appears twice');
          setState(() => _busy = true);
          await repo.resolveDuplicateLine(widget.captureId, itemId: _repeatId!);
        case MismatchReason.other:
          final paid = _num(_paid);
          if (_note.text.trim().isEmpty) return setState(() => _err = 'Tell us what happened');
          if (paid == null || paid <= 0) return setState(() => _err = 'Enter the actual bill total');
          setState(() => _busy = true);
          await repo.resolveOther(widget.captureId, reason: _note.text.trim(), paidTotal: paid);
        case null:
          return setState(() => _err = 'Pick a reason');
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _busy = false;
        _err = 'Could not apply that. Check the numbers.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<Repository>();
    final f = ledger.mismatchFigures(repo.captureOf(widget.captureId), repo.items);
    final lines = repo.itemsOf(widget.captureId).where(_open).toList();
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    Widget option(MismatchReason r, String label, String hint) => RadioListTile<MismatchReason>(
          value: r,
          title: Text(label),
          subtitle: Text(hint),
          contentPadding: EdgeInsets.zero,
        );

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Why don\'t these match?', style: t.titleLarge),
          const SizedBox(height: 8),
          Text('Items ${inr(f.items)} · Bill ${inr(f.bill)} · '
              '${f.gap > 0 ? '${inr(f.gap)} less on the bill' : '${inr(-f.gap)} more on the bill'}',
              style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          RadioGroup<MismatchReason>(
            groupValue: _reason,
            onChanged: (v) => setState(() {
              _reason = v;
              _err = null;
            }),
            child: Column(children: [
              option(MismatchReason.discount, 'Discount', 'A discount or coupon came off the total'),
              if (_reason == MismatchReason.discount) ...[
                _field(_discount, 'Discount amount'),
                _field(_paid, 'Amount you paid'),
              ],
              option(MismatchReason.printError, 'Problem while printing',
                  'The items are right; count ${inr(f.items)}'),
              option(MismatchReason.duplicateLine, 'A line appears twice', 'Remove the extra copy'),
              if (_reason == MismatchReason.duplicateLine)
                RadioGroup<String>(
                  groupValue: _repeatId,
                  onChanged: (v) => setState(() => _repeatId = v),
                  child: Column(children: [
                    for (final i in lines)
                      RadioListTile<String>(
                        dense: true,
                        value: i.id,
                        title: Text(i.name),
                        secondary: Text(inr(i.amount)),
                      ),
                  ]),
                ),
              option(MismatchReason.other, 'Other', 'Tell us what happened'),
              if (_reason == MismatchReason.other) ...[
                _field(_note, 'What happened', number: false),
                _field(_paid, 'Actual bill total'),
              ],
            ]),
          ),
          if (_err != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_err!, style: TextStyle(color: cs.error)),
            ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _busy ? null : _apply, child: const Text('Fix the bill')),
        ]),
      ),
    );
  }

  Widget _field(TextEditingController c, String label, {bool number = true}) => Padding(
        padding: const EdgeInsets.only(left: 16, bottom: 12),
        child: TextField(
          controller: c,
          keyboardType: number ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: label, prefixText: number ? '₹ ' : null),
        ),
      );
}

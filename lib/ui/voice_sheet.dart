import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/repository.dart';
import '../domain/models.dart';
import '../domain/voice_parser.dart';
import '../services/voice_service.dart';
import 'item_editor.dart';
import 'theme.dart';

/// Say an expense: listen, show what was understood, let the user fix it, then save.
Future<void> startVoiceNote(BuildContext context) async {
  final voice = context.read<VoiceService>();
  final messenger = ScaffoldMessenger.of(context);
  String? heard;
  try {
    heard = await voice.listen();
  } on VoiceUnavailable {
    messenger.showSnackBar(const SnackBar(
        content: Text('Voice input isn\'t available on this phone. Install or update the Google app, or add manually.')));
    return;
  } catch (_) {
    messenger.showSnackBar(const SnackBar(content: Text('Couldn\'t start voice input. Try again.')));
    return;
  }
  if (heard == null || heard.trim().isEmpty) {
    messenger.showSnackBar(const SnackBar(content: Text('Didn\'t catch that. Tap the mic and try again.')));
    return;
  }
  if (!context.mounted) return;
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _VoiceSheet(heard: heard!),
  );
}

class _Line {
  final TextEditingController name;
  final TextEditingController amount;
  String category;
  _Line(VoiceLine l)
      : name = TextEditingController(text: l.name),
        amount = TextEditingController(text: _fmt(l.amount)),
        category = l.categoryId;
  static String _fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
}

class _VoiceSheet extends StatefulWidget {
  final String heard;
  const _VoiceSheet({required this.heard});
  @override
  State<_VoiceSheet> createState() => _VoiceSheetState();
}

class _VoiceSheetState extends State<_VoiceSheet> {
  late String _heard = widget.heard;
  late List<_Line> _lines;
  late int _daysAgo;
  String? _err;

  @override
  void initState() {
    super.initState();
    _apply(_heard);
  }

  void _apply(String text) {
    final note = parseVoiceNote(text);
    _heard = text;
    _lines = [for (final l in note.lines) _Line(l)];
    _daysAgo = note.daysAgo;
    _err = null;
  }

  Future<void> _again() async {
    final text = await context.read<VoiceService>().listen().catchError((_) => null);
    if (text == null || text.trim().isEmpty || !mounted) return;
    setState(() => _apply(text));
  }

  Future<void> _save({required bool approve}) async {
    final rows = <({String name, double amount, String cat})>[];
    for (final l in _lines) {
      final a = double.tryParse(l.amount.text.replaceAll(',', '').trim());
      if (l.name.text.trim().isEmpty || a == null || a <= 0) {
        setState(() => _err = 'Each line needs a name and an amount above 0');
        return;
      }
      rows.add((name: l.name.text.trim(), amount: a, cat: l.category));
    }
    if (rows.isEmpty) return;
    final repo = context.read<Repository>();
    final messenger = ScaffoldMessenger.of(context);
    final now = DateTime.now();
    final at = DateTime(now.year, now.month, now.day - _daysAgo, now.hour, now.minute);
    // One note = one group in the inbox, so "Approve all" covers it.
    String? captureId;
    for (final r in rows) {
      final i = await repo.addManual(name: r.name, amount: r.amount, categoryId: r.cat, at: at, captureId: captureId);
      captureId ??= i.captureId;
      if (approve) await repo.approve(i.id);
    }
    if (!mounted) return;
    Navigator.pop(context);
    final total = rows.fold(0.0, (s, r) => s + r.amount);
    messenger.showSnackBar(SnackBar(
        content: Text(approve
            ? 'Added ${inr(total, whole: true)} to your spending'
            : '${rows.length} item${rows.length == 1 ? '' : 's'} added to your inbox')));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(Icons.mic, color: cs.primary),
            const SizedBox(width: 8),
            Expanded(child: Text('You said', style: t.titleMedium)),
            TextButton.icon(onPressed: _again, icon: const Icon(Icons.refresh), label: const Text('Say again')),
          ]),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(8)),
            child: Text('"$_heard"', style: t.bodyLarge?.copyWith(fontStyle: FontStyle.italic)),
          ),
          const SizedBox(height: 16),
          if (_lines.isEmpty) ...[
            Text('No amount found. Try saying it like "Lunch 250" or "Auto 80 and chai 20".',
                style: t.bodyMedium?.copyWith(color: cs.error)),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  showItemEditor(context);
                },
                child: const Text('Type instead'),
              ),
              FilledButton.icon(onPressed: _again, icon: const Icon(Icons.mic), label: const Text('Try again')),
            ]),
          ] else ...[
            Wrap(spacing: 8, children: [
              for (final d in const [(0, 'Today'), (1, 'Yesterday'), (2, '2 days ago')])
                ChoiceChip(
                  label: Text(d.$2),
                  selected: _daysAgo == d.$1,
                  onSelected: (_) => setState(() => _daysAgo = d.$1),
                ),
            ]),
            const SizedBox(height: 8),
            for (final (k, l) in _lines.indexed) _LineEditor(
              key: ObjectKey(l),
              line: l,
              onChanged: () => setState(() {}),
              onRemove: _lines.length == 1 ? null : () => setState(() => _lines.removeAt(k)),
            ),
            if (_err != null) Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(_err!, style: TextStyle(color: cs.error)),
            ),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(onPressed: () => _save(approve: false), child: const Text('Add to inbox')),
              const SizedBox(width: 8),
              FilledButton(onPressed: () => _save(approve: true), child: const Text('Add & approve')),
            ]),
          ],
        ]),
      ),
    );
  }
}

class _LineEditor extends StatelessWidget {
  final _Line line;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;
  const _LineEditor({super.key, required this.line, required this.onChanged, this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          flex: 5,
          child: Column(children: [
            TextField(
              controller: line.name,
              decoration: const InputDecoration(labelText: 'What', isDense: true),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: line.category,
              isDense: true,
              decoration: const InputDecoration(labelText: 'Category', isDense: true),
              items: [
                for (final c in defaultCategories)
                  DropdownMenuItem(
                    value: c.id,
                    child: Row(children: [
                      CircleAvatar(radius: 5, backgroundColor: categoryColor(c.id)),
                      const SizedBox(width: 8),
                      Text(c.name),
                    ]),
                  ),
              ],
              onChanged: (v) {
                line.category = v ?? line.category;
                onChanged();
              },
            ),
          ]),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 3,
          child: TextField(
            controller: line.amount,
            decoration: const InputDecoration(labelText: 'Amount', prefixText: '₹', isDense: true),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
        ),
        if (onRemove != null)
          IconButton(onPressed: onRemove, icon: const Icon(Icons.close), tooltip: 'Remove this line'),
      ]),
    );
  }
}

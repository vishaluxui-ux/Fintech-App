import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/notification_bridge.dart';
import '../services/refresh_service.dart';
import 'theme.dart';

/// Shows which apps posted notifications recently and whether Spend Inbox reads them.
/// Nothing here is stored or sent; it is held in memory by the listener.
class AlertCheckScreen extends StatefulWidget {
  const AlertCheckScreen({super.key});
  @override
  State<AlertCheckScreen> createState() => _AlertCheckScreenState();
}

class _AlertCheckScreenState extends State<AlertCheckScreen> {
  List<Map> _seen = [];
  bool? _access;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Refresh button: check for new payments (alerts and bank SMS), then reload this list.
  Future<void> _refresh() async {
    final messenger = ScaffoldMessenger.of(context);
    final r = await context.read<RefreshService>().refresh();
    await _load();
    messenger.showSnackBar(SnackBar(content: Text(r.message)));
  }

  Future<void> _load() async {
    final b = context.read<NotificationBridge>();
    final access = await b.hasAccess().catchError((_) => false);
    final seen = await b.recentSeen().catchError((_) => <Map>[]);
    if (mounted) setState(() {
      _access = access;
      _seen = seen;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Check payment alerts'), actions: [
        IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh), tooltip: 'Check for new payments'),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          child: ListTile(
            leading: Icon(_access == true ? Icons.check_circle : Icons.error_outline,
                color: _access == true ? Colors.green : cs.error),
            title: Text(_access == true ? 'Notification access is on' : 'Notification access is off'),
            subtitle: const Text('Make a small payment, come back here and tap refresh.'),
          ),
        ),
        const SizedBox(height: 16),
        Text('Seen since the app last started', style: t.titleMedium),
        const SizedBox(height: 4),
        Text('App names only. Kept in memory on this phone; never saved or sent.', style: t.bodySmall),
        const SizedBox(height: 8),
        if (_seen.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text('No notifications seen yet. If you just paid and nothing shows here, '
                'the payment app did not post a notification, or access was turned on after it arrived.'),
          ),
        for (final n in _seen)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(n['supported'] == true ? Icons.check : Icons.block,
                color: n['supported'] == true ? Colors.green : cs.outline),
            title: Text('${n['label']}'),
            subtitle: Text([
              when(DateTime.fromMillisecondsSinceEpoch(n['postedAt'] as int)),
              n['supported'] == true ? 'read by Spend Inbox' : 'ignored (not a supported payment app)',
              if ((n['title'] as String?)?.isNotEmpty == true) '"${n['title']}"',
            ].join(' · ')),
          ),
      ]),
    );
  }
}

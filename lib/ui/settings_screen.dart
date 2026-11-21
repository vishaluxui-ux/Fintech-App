import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/repository.dart';
import '../data/settings.dart';
import '../domain/models.dart';
import '../services/auth_service.dart';
import '../services/notification_bridge.dart';
import '../services/reminder_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with WidgetsBindingObserver {
  bool? _access;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    final bridge = context.read<NotificationBridge>();
    final a = await bridge.hasAccess().catchError((_) => false);
    if (mounted) setState(() => _access = a);
    if (a) bridge.drain();
  }

  /// Explain exactly what is read before sending the user to the system setting.
  Future<void> _enableNotifications() async {
    final go = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Read UPI payment alerts'),
        content: const Text(
            'Spend Inbox reads notifications only from UPI and banking apps (Google Pay, PhonePe, Paytm, BHIM and your bank) '
            'to pick up the amount, payee and time of a payment or ATM withdrawal.\n\n'
            'Notifications from every other app are ignored and never stored. We do not read SMS.\n\n'
            'On the next screen, turn on Spend Inbox.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Not now')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Continue')),
        ],
      ),
    );
    if (go == true && mounted) {
      final bridge = context.read<NotificationBridge>();
      context.read<Settings>().notificationExplainerSeen = true;
      await context.read<ReminderService>().requestPermission();
      await bridge.openSettings();
    }
  }

  Future<void> _deleteAccount() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text('This permanently deletes your account and every item, bill and cash entry, '
            'on this phone and on our servers. It cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(c).colorScheme.error),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete everything'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final repo = context.read<Repository>();
    final settings = context.read<Settings>();
    final auth = context.read<AuthService>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await auth.deleteAccount();
      await repo.wipeLocal();
      await settings.clear();
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Could not delete the account. Connect to the internet and try again.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Settings>();
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(children: [
        const _Header('Capture'),
        ListTile(
          leading: const Icon(Icons.notifications_outlined),
          title: const Text('UPI payment alerts'),
          subtitle: Text(_access == true ? 'On: payments are picked up automatically' : 'Off: tap to turn on'),
          trailing: _access == true ? const Icon(Icons.check_circle, color: Colors.green) : const Icon(Icons.chevron_right),
          onTap: _access == true ? () => context.read<NotificationBridge>().openSettings() : _enableNotifications,
        ),
        const _Header('Duplicate payments'),
        RadioGroup<DuplicateMode>(
          groupValue: s.duplicateMode,
          onChanged: (v) => s.duplicateMode = v!,
          child: const Column(children: [
            RadioListTile(
              value: DuplicateMode.flag,
              title: Text('Flag for me to check'),
              subtitle: Text('Likely duplicates stay in the inbox with a note'),
            ),
            RadioListTile(
              value: DuplicateMode.autoReject,
              title: Text('Reject automatically'),
              subtitle: Text('Likely duplicates are rejected and never counted'),
            ),
          ]),
        ),
        const _Header('Bill photos'),
        SwitchListTile(
          value: s.keepBillPhotos,
          onChanged: (v) => s.keepBillPhotos = v,
          title: const Text('Keep photos after approval'),
          subtitle: Text(s.keepBillPhotos
              ? 'Photos stay on this phone so you can look at them again'
              : 'Photos are deleted once a bill is approved; only the item list is kept'),
        ),
        const _Header('Account'),
        ListTile(
          leading: const Icon(Icons.logout),
          title: const Text('Sign out'),
          onTap: () => context.read<AuthService>().signOut(),
        ),
        ListTile(
          leading: Icon(Icons.delete_forever_outlined, color: Theme.of(context).colorScheme.error),
          title: Text('Delete account and data', style: TextStyle(color: Theme.of(context).colorScheme.error)),
          onTap: _deleteAccount,
        ),
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('Bill photos are sent to Anthropic\'s Claude to read the items. They are not used to train models.',
              style: TextStyle(fontSize: 12)),
        ),
      ]),
    );
  }
}

class _Header extends StatelessWidget {
  final String text;
  const _Header(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Text(text, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );
}

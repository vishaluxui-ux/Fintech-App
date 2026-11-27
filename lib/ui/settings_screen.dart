import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/repository.dart';
import '../data/settings.dart';
import '../domain/models.dart';
import '../services/auth_service.dart';
import '../services/notification_bridge.dart';
import '../services/refresh_service.dart';
import '../services/reminder_service.dart';
import '../services/sms_service.dart';
import 'alert_check_screen.dart';

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
    _checkSms();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) {
      _check();
      _checkSms();
    }
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
            'Notifications from every other app are ignored and never stored.\n\n'
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

  bool? _smsGranted;

  Future<void> _checkSms() async {
    final g = await context.read<SmsService>().granted().catchError((_) => false);
    if (mounted) setState(() => _smsGranted = g);
  }

  /// Bank SMS is opt-in: explain exactly what is read, then ask Android for permission.
  Future<void> _toggleSms(bool on) async {
    final settings = context.read<Settings>();
    if (!on) {
      settings.readBankSms = false;
      return;
    }
    final go = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Read bank SMS'),
        content: const Text(
            'Catches payments that your UPI app doesn\'t notify you about, by reading the debit SMS your bank sends.\n\n'
            '• Only SMS from bank senders (like AD-HDFCBK) are read. Personal messages and OTPs are skipped.\n'
            '• SMS are read on this phone only. The text is never saved or sent to our servers or our AI.\n'
            '• Only the amount, payee and time of a spend are kept, in your inbox for you to approve.\n'
            '• The first check looks at the last ${SmsService.firstReadDays} days.\n\n'
            'You can turn this off any time.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Not now')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Allow')),
        ],
      ),
    );
    if (go != true || !mounted) return;
    final sms = context.read<SmsService>();
    final refresher = context.read<RefreshService>();
    final messenger = ScaffoldMessenger.of(context);
    final granted = await sms.request().catchError((_) => false);
    if (!mounted) return;
    setState(() => _smsGranted = granted);
    if (!granted) {
      messenger.showSnackBar(const SnackBar(
          content: Text('SMS permission was not given. You can allow it in Android Settings > Apps > Spend Inbox > Permissions.')));
      return;
    }
    settings.readBankSms = true;
    final r = await refresher.refresh();
    messenger.showSnackBar(SnackBar(content: Text(r.message)));
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
        SwitchListTile(
          secondary: const Icon(Icons.sms_outlined),
          value: s.readBankSms && _smsGranted == true,
          onChanged: _toggleSms,
          title: const Text('Bank SMS'),
          subtitle: Text(s.readBankSms && _smsGranted == false
              ? 'Permission was removed. Turn on again to allow it.'
              : 'Read debit SMS from your bank, on this phone only. Catches payments with no app alert.'),
        ),
        ListTile(
          leading: const Icon(Icons.refresh),
          title: const Text('Check for new payments now'),
          subtitle: const Text('Reads new payment alerts and bank SMS, then syncs'),
          onTap: () async {
            final messenger = ScaffoldMessenger.of(context);
            final r = await context.read<RefreshService>().refresh();
            messenger.showSnackBar(SnackBar(content: Text(r.message)));
          },
        ),
        ListTile(
          leading: const Icon(Icons.manage_search),
          title: const Text('Check payment alerts'),
          subtitle: const Text('See which apps sent notifications and whether they were read'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AlertCheckScreen())),
        ),
        const _Header('Less checking'),
        SwitchListTile(
          value: s.autoApproveKnown,
          onChanged: (v) => s.autoApproveKnown = v,
          title: const Text('Auto-approve known merchants'),
          subtitle: const Text('After you approve a merchant twice with the same category, '
              'new payments to it are approved for you. They show "Auto" so you can change them.'),
        ),
        SwitchListTile(
          value: s.weeklySummary,
          onChanged: (v) => s.weeklySummary = v,
          title: const Text('Weekly summary'),
          subtitle: const Text('Sunday evening: what you spent and how it compares with last week'),
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
          child: Text('Bill photos, and payment alerts the app can\'t read by itself, are sent to Anthropic\'s Claude '
              'to read them. They are not used to train models. Bank SMS are read on this phone only and never sent.',
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

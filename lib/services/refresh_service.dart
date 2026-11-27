import '../data/repository.dart';
import '../data/settings.dart';
import 'notification_bridge.dart';
import 'sms_service.dart';
import 'sync_service.dart';

/// What one refresh found.
class RefreshResult {
  final int newItems;
  final int newWithdrawals;
  final bool smsOn;
  const RefreshResult(this.newItems, this.newWithdrawals, this.smsOn);

  String get message {
    final parts = [
      if (newItems > 0) '$newItems new payment${newItems == 1 ? '' : 's'} in your inbox',
      if (newWithdrawals > 0) '$newWithdrawals ATM withdrawal${newWithdrawals == 1 ? '' : 's'}',
    ];
    if (parts.isNotEmpty) return 'Found ${parts.join(' and ')}';
    return smsOn ? 'Up to date. No new payments in alerts or bank SMS.' : 'Up to date. No new payment alerts.';
  }
}

/// The "check for new payments" action: payment app alerts, bank SMS (if on),
/// alerts waiting for the AI, then a sync with the server.
class RefreshService {
  final Repository repo;
  final Settings settings;
  final NotificationBridge bridge;
  final SmsService sms;
  final SyncService? sync;
  bool _running = false;

  RefreshService(this.repo, this.settings, this.bridge, this.sms, this.sync);

  Future<RefreshResult> refresh() async {
    final itemsBefore = repo.items.length;
    final wBefore = repo.withdrawals.length;
    if (!_running) {
      _running = true;
      try {
        await bridge.drain().catchError((_) {});
        await sms.readNew(repo, settings).catchError((_) => 0);
        await sync?.sync();
      } finally {
        _running = false;
      }
    }
    return RefreshResult(repo.items.length - itemsBefore, repo.withdrawals.length - wBefore, settings.readBankSms);
  }
}

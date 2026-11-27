import '../data/repository.dart';
import 'notification_bridge.dart';
import 'sync_service.dart';

/// What one refresh found.
class RefreshResult {
  final int newItems;
  final int newWithdrawals;
  const RefreshResult(this.newItems, this.newWithdrawals);

  String get message {
    final parts = [
      if (newItems > 0) '$newItems new payment${newItems == 1 ? '' : 's'} in your inbox',
      if (newWithdrawals > 0) '$newWithdrawals ATM withdrawal${newWithdrawals == 1 ? '' : 's'}',
    ];
    if (parts.isNotEmpty) return 'Found ${parts.join(' and ')}';
    return 'Up to date. No new payment alerts.';
  }
}

/// The "check for new payments" action: payment app alerts, alerts waiting
/// for the AI, then a sync with the server.
class RefreshService {
  final Repository repo;
  final NotificationBridge bridge;
  final SyncService? sync;
  bool _running = false;

  RefreshService(this.repo, this.bridge, this.sync);

  Future<RefreshResult> refresh() async {
    final itemsBefore = repo.items.length;
    final wBefore = repo.withdrawals.length;
    if (!_running) {
      _running = true;
      try {
        await bridge.drain().catchError((_) {});
        await sync?.sync();
      } finally {
        _running = false;
      }
    }
    return RefreshResult(repo.items.length - itemsBefore, repo.withdrawals.length - wBefore);
  }
}

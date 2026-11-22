import '../data/repository.dart';
import '../domain/upi_parser.dart';

/// Reads one notification. The built-in rules go first (free, offline).
/// When they can't settle an alert from a supported app that mentions money,
/// the AI reads it. If the AI can't be reached, the alert waits on the device
/// and is retried on the next drain, so nothing is lost offline.
class AlertIngestor {
  final Repository repo;

  /// Returns the AI's reading, or throws when it can't be reached.
  final Future<NotificationResult> Function(String pkg, String title, String body, DateTime at) aiRead;

  AlertIngestor(this.repo, this.aiRead);

  Future<void> ingest(String pkg, String title, String body, DateTime at) async {
    final r = parseNotification(packageName: pkg, title: title, text: body, postedAt: at);
    if (!_needsAi(pkg, title, body, r)) return repo.ingestNotification(r);
    try {
      final ai = await aiRead(pkg, title, body, at);
      // Keep the rules' reading if the AI found nothing better.
      await repo.ingestNotification(ai is Ignored && r is UpiPayment ? r : ai);
    } catch (_) {
      await repo.db.queueAlert(pkg, title, body, at);
    }
  }

  bool _needsAi(String pkg, String title, String body, NotificationResult r) {
    if (!supportedApps.containsKey(pkg)) return false;
    if (parseAmount('$title $body') == null || clearlyNotSpend(title, body)) return false;
    return r is Ignored || (r is UpiPayment && r.payee == 'Unknown payee');
  }

  /// Retry alerts that waited for the AI. Stops at the first failure (still offline).
  Future<void> retryQueued() async {
    for (final q in await repo.db.queuedAlerts()) {
      final pkg = q['package'] as String, title = q['title'] as String, body = q['body'] as String;
      final at = DateTime.fromMillisecondsSinceEpoch(q['posted_at'] as int);
      try {
        final ai = await aiRead(pkg, title, body, at);
        await repo.ingestNotification(ai);
        await repo.db.dropQueuedAlert(q['id'] as int);
      } catch (_) {
        return;
      }
    }
  }
}

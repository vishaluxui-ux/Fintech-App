import 'package:flutter/services.dart';

import 'alert_ingestor.dart';

/// Talks to the native NotificationListenerService (android/.../UpiNotificationListener.kt)
/// and to the share target (a screenshot shared from a UPI app).
class NotificationBridge {
  static const _method = MethodChannel('spendinbox/notifications');
  static const _events = EventChannel('spendinbox/notifications/events');

  final AlertIngestor ingestor;
  NotificationBridge(this.ingestor);

  Future<bool> hasAccess() async => await _method.invokeMethod<bool>('hasAccess') ?? false;
  Future<void> openSettings() => _method.invokeMethod('openSettings');

  /// Diagnostics: notifications the listener saw recently (newest first).
  Future<List<Map>> recentSeen() async => await _method.invokeListMethod<Map>('recentSeen') ?? const [];

  /// Path of an image shared into the app, if any (consumed once).
  Future<String?> takeSharedImage() => _method.invokeMethod<String>('takeSharedImage');

  void start() {
    drain();
    _events.receiveBroadcastStream().listen((_) => drain(), onError: (_) {});
  }

  bool _draining = false;
  Future<void> drain() async {
    if (_draining) return;
    _draining = true;
    try {
      await ingestor.retryQueued();
      final list = await _method.invokeListMethod<Map>('drain') ?? const [];
      for (final n in list) {
        await ingestor.ingest(
          n['package'] as String,
          (n['title'] as String?) ?? '',
          (n['text'] as String?) ?? '',
          DateTime.fromMillisecondsSinceEpoch(n['postedAt'] as int),
        );
      }
    } finally {
      _draining = false;
    }
  }
}

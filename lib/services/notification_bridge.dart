import 'package:flutter/services.dart';

import '../data/repository.dart';
import '../domain/upi_parser.dart';

/// Talks to the native NotificationListenerService (android/.../UpiNotificationListener.kt).
/// The service stores notifications from supported apps in a queue on the device;
/// we drain it on start and whenever a new one arrives.
class NotificationBridge {
  static const _method = MethodChannel('spendinbox/notifications');
  static const _events = EventChannel('spendinbox/notifications/events');

  final Repository repo;
  NotificationBridge(this.repo);

  Future<bool> hasAccess() async => await _method.invokeMethod<bool>('hasAccess') ?? false;
  Future<void> openSettings() => _method.invokeMethod('openSettings');

  void start() {
    drain();
    _events.receiveBroadcastStream().listen((_) => drain(), onError: (_) {});
  }

  Future<void> drain() async {
    final list = await _method.invokeListMethod<Map>('drain') ?? const [];
    for (final n in list) {
      await repo.ingestNotification(parseNotification(
        packageName: n['package'] as String,
        title: (n['title'] as String?) ?? '',
        text: (n['text'] as String?) ?? '',
        postedAt: DateTime.fromMillisecondsSinceEpoch(n['postedAt'] as int),
      ));
    }
  }
}

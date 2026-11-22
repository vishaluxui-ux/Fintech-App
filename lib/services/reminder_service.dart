import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../data/repository.dart';
import '../domain/ledger.dart' as ledger;

/// Two scheduled notifications, each with a fixed id so it replaces itself:
/// - daily at 8 pm, only when items or cash are waiting (CSH-02: one a day);
/// - weekly on Sunday at 7 pm, a spending summary (can be turned off).
/// Content is recomputed whenever the data changes.
class ReminderService {
  static const _dailyId = 1001;
  static const _weeklyId = 1002;
  final _plugin = FlutterLocalNotificationsPlugin();
  final Repository repo;
  ReminderService(this.repo);

  Future<void> init() async {
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
    await _plugin.initialize(
        settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')));
    repo.addListener(reschedule);
    repo.settings.addListener(reschedule);
    await reschedule();
  }

  static const _details = NotificationDetails(
      android: AndroidNotificationDetails('nudges', 'Reminders and summaries',
          channelDescription: 'One daily reminder when something is waiting, and a weekly summary'));

  Future<void> reschedule() async {
    final now = tz.TZDateTime.now(tz.local);

    final daily = ledger.dailyNudge(repo.withdrawals, repo.captures, repo.items);
    if (daily == null) {
      await _plugin.cancel(id: _dailyId);
    } else {
      var at = tz.TZDateTime(tz.local, now.year, now.month, now.day, 20);
      if (!at.isAfter(now)) at = at.add(const Duration(days: 1));
      await _plugin.zonedSchedule(
        id: _dailyId, title: daily.title, body: daily.body, scheduledDate: at,
        notificationDetails: _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }

    var sunday = tz.TZDateTime(tz.local, now.year, now.month, now.day, 19)
        .add(Duration(days: (DateTime.sunday - now.weekday) % 7));
    if (!sunday.isAfter(now)) sunday = sunday.add(const Duration(days: 7));
    final weekly = repo.settings.weeklySummary ? ledger.weeklySummary(sunday, repo.items) : null;
    if (weekly == null) {
      await _plugin.cancel(id: _weeklyId);
    } else {
      await _plugin.zonedSchedule(
        id: _weeklyId, title: weekly.title, body: weekly.body, scheduledDate: sunday,
        notificationDetails: _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }

  Future<void> requestPermission() async => _plugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.requestNotificationsPermission();
}

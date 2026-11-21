import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../data/repository.dart';
import '../domain/ledger.dart' as ledger;

/// CSH-02: a single daily reminder (fixed id, so it replaces itself) that lists
/// every withdrawal with cash outstanding. Cancelled when nothing is outstanding.
class ReminderService {
  static const _id = 1001;
  final _plugin = FlutterLocalNotificationsPlugin();
  final Repository repo;
  ReminderService(this.repo);

  Future<void> init() async {
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
    await _plugin.initialize(
        settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')));
    repo.addListener(reschedule);
    await reschedule();
  }

  Future<void> reschedule() async {
    final r = ledger.dailyCashReminder(repo.withdrawals, repo.captures, repo.items);
    if (r == null) {
      await _plugin.cancel(id: _id);
      return;
    }
    final now = tz.TZDateTime.now(tz.local);
    var at = tz.TZDateTime(tz.local, now.year, now.month, now.day, 20);
    if (!at.isAfter(now)) at = at.add(const Duration(days: 1));
    await _plugin.zonedSchedule(
      id: _id,
      title: r.title,
      body: r.body,
      scheduledDate: at,
      notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails('cash', 'Cash reminders',
              channelDescription: 'One daily reminder to split ATM cash')),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  Future<void> requestPermission() async => _plugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.requestNotificationsPermission();
}

import 'package:flutter/services.dart';

import '../data/repository.dart';
import '../data/settings.dart';
import '../domain/sms_parser.dart';
import '../domain/upi_parser.dart';

/// Opt-in bank SMS reading (N-01). The native side returns only SMS from DLT
/// sender headers (like "AD-HDFCBK"); personal SMS never reach Dart. Parsing is
/// on the phone; SMS text is never stored or sent.
class SmsService {
  static const _method = MethodChannel('spendinbox/sms');

  /// How far back the first read goes when the user turns the feature on.
  static const firstReadDays = 30;

  Future<bool> granted() async => await _method.invokeMethod<bool>('granted') ?? false;

  /// Shows Android's permission prompt. True when the user allows it.
  Future<bool> request() async => await _method.invokeMethod<bool>('request') ?? false;

  /// Reads bank SMS that arrived since the last read and adds the spends.
  /// Returns how many SMS described a spend (duplicates of app alerts are skipped by the repository).
  Future<int> readNew(Repository repo, Settings settings) async {
    if (!settings.readBankSms || !await granted()) return 0;
    final since = settings.lastSmsRead ?? DateTime.now().subtract(const Duration(days: firstReadDays));
    final rows = await _method.invokeListMethod<Map>('read', {'since': since.millisecondsSinceEpoch}) ?? const [];
    var newest = since;
    var found = 0;
    // Oldest first, so duplicate checks see payments in the order they happened.
    final sorted = [...rows]..sort((a, b) => (a['date'] as int).compareTo(b['date'] as int));
    for (final r in sorted) {
      final at = DateTime.fromMillisecondsSinceEpoch(r['date'] as int);
      if (at.isAfter(newest)) newest = at;
      final result = parseBankSms(sender: r['address'] as String, body: r['body'] as String, at: at);
      if (result is! Ignored) found++;
      await repo.ingestNotification(result);
    }
    settings.lastSmsRead = newest;
    return found;
  }
}

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/upi_parser.dart';

/// Calls the `parse-alert` Edge Function (Claude Haiku) for an alert the rules couldn't read.
class AlertReader {
  final SupabaseClient client;
  AlertReader(this.client);

  Future<NotificationResult> read(String pkg, String title, String body, DateTime at) async {
    final app = supportedApps[pkg] ?? pkg;
    final res = await client.functions.invoke('parse-alert', body: {'app': app, 'title': title, 'text': body});
    if (res.status != 200) throw Exception('alert reader ${res.status}');
    return alertFromJson(res.data as Map<String, dynamic>, app, at);
  }
}

NotificationResult alertFromJson(Map<String, dynamic> j, String app, DateTime at) {
  final amount = (j['amount'] as num?)?.toDouble();
  if (amount == null || amount <= 0) return const Ignored();
  switch (j['kind']) {
    case 'payment':
      final payee = (j['payee'] as String?)?.trim();
      return UpiPayment(amount, (payee == null || payee.isEmpty) ? 'Unknown payee' : payee, at, app);
    case 'atm':
      return AtmWithdrawal(amount, at, app);
    default:
      return const Ignored();
  }
}

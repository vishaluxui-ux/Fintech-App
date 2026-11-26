/// Parses UPI payment and ATM withdrawal notifications (CAP-01, CAP-05).
/// Works on the notification title + text only. No SMS, no accessibility.
library;

/// Package names of apps we read. Everything else is ignored.
const supportedApps = <String, String>{
  'com.google.android.apps.nbu.paisa.user': 'Google Pay',
  'com.phonepe.app': 'PhonePe',
  'net.one97.paytm': 'Paytm',
  'in.org.npci.upiapp': 'BHIM',
  'in.amazon.mShop.android.shopping': 'Amazon Pay',
  'com.dreamplug.androidapp': 'CRED',
  'com.csam.icici.bank.imobile': 'iMobile Pay',
  'com.snapwork.hdfc': 'HDFC Bank',
  'com.sbi.lotusintouch': 'YONO SBI',
  'com.axis.mobile': 'Axis Mobile',
};

sealed class NotificationResult {
  const NotificationResult();
}

class UpiPayment extends NotificationResult {
  final double amount;
  final String payee;
  final DateTime at;
  final String sourceApp;
  const UpiPayment(this.amount, this.payee, this.at, this.sourceApp);
}

class AtmWithdrawal extends NotificationResult {
  final double amount;
  final DateTime at;
  final String sourceApp;
  const AtmWithdrawal(this.amount, this.at, this.sourceApp);
}

class Ignored extends NotificationResult {
  const Ignored();
}

final _amount = RegExp(r'(?:₹|rs\.?|inr)\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)', caseSensitive: false);
final _received = RegExp(r'\b(received|credited|refund|cashback|request(?:ed)?|collect|failed|declined|reminder|due)\b',
    caseSensitive: false);
final _paid = RegExp(r'\b(paid|sent|debited|payment (?:of|to)|transferred|successful(?:ly)?)\b', caseSensitive: false);
final _atm = RegExp(r'\b(atm|cash withdrawal|withdrawn|withdrawal)\b', caseSensitive: false);
final _payeePatterns = <RegExp>[
  RegExp(r'\b(?:paid|sent|transferred)\s+(?:₹|rs\.?|inr)?\s*[0-9.,]*\s*to\s+(.+?)(?:\s+(?:on|via|using|from|ref|upi)\b|[.,]|$)',
      caseSensitive: false),
  RegExp(r'\bto\s+(.+?)(?:\s+(?:on|via|using|from|ref|upi)\b|[.,]|$)', caseSensitive: false),
  RegExp(r'\bat\s+(.+?)(?:\s+(?:on|via|using|ref)\b|[.,]|$)', caseSensitive: false),
];

// Marketing from payment apps: offers, loans, prizes, tips. Never a spend.
final _promo = RegExp(
    r'\b(win|won|offer|offers|loan|emi|emis|lakh|pre-?approved|eligible|available for you|reward expires|'
    r'tap to|tap before|learn more|trends|limit increase|credit score|invest|sip|gold)\b',
    caseSensitive: false);

// A "payee" that is really ad or button text.
final _junkPayee = RegExp(r'\b(claim|reward|rewards|tap|offer|view|check|know more|unlock|cashback)\b',
    caseSensitive: false);

/// True when the alert is clearly not a spend (money in, a request, a failure,
/// or marketing). These are dropped without asking the AI.
bool clearlyNotSpend(String title, String text) {
  final all = '$title $text';
  return _received.hasMatch(all) || (_promo.hasMatch(all) && !_paid.hasMatch(all));
}

double? parseAmount(String text) {
  final m = _amount.firstMatch(text);
  if (m == null) return null;
  return double.tryParse(m.group(1)!.replaceAll(',', ''));
}

NotificationResult parseNotification({
  required String packageName,
  required String title,
  required String text,
  required DateTime postedAt,
}) {
  final app = supportedApps[packageName];
  if (app == null) return const Ignored();
  final body = '$title $text'.trim();
  final amount = parseAmount(body);
  if (amount == null || amount <= 0) return const Ignored();

  if (_atm.hasMatch(body) && !_received.hasMatch(body)) {
    return AtmWithdrawal(amount, postedAt, app);
  }
  if (clearlyNotSpend(title, text) || !_paid.hasMatch(body)) return const Ignored();

  String payee = 'Unknown payee';
  for (final p in _payeePatterns) {
    final m = p.firstMatch(text.isNotEmpty ? text : title) ?? p.firstMatch(body);
    if (m != null) {
      final candidate = m.group(1)!.trim();
      if (candidate.isNotEmpty && parseAmount(candidate) == null && !_junkPayee.hasMatch(candidate)) {
        payee = candidate;
        break;
      }
    }
  }
  return UpiPayment(amount, payee, postedAt, app);
}

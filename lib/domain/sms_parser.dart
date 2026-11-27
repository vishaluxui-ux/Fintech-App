/// Reads bank transaction SMS (opt-in, N-01). Runs on the phone only: SMS text
/// is never stored or sent anywhere, only the payment it describes.
///
/// Only messages from registered bank senders are looked at. In India those use
/// a DLT header such as "AD-HDFCBK" or "VM-SBIUPI-S". Personal SMS (from phone
/// numbers) and every other sender are dropped before parsing.
library;

import 'upi_parser.dart';

/// Six-letter sender codes of banks and payment banks -> name shown in the app.
const bankSenders = <String, String>{
  'HDFCBK': 'HDFC Bank',
  'HDFCBN': 'HDFC Bank',
  'SBIUPI': 'SBI',
  'SBIINB': 'SBI',
  'SBIPSG': 'SBI',
  'ATMSBI': 'SBI',
  'CBSSBI': 'SBI',
  'ICICIB': 'ICICI Bank',
  'ICICIT': 'ICICI Bank',
  'AXISBK': 'Axis Bank',
  'AXISMR': 'Axis Bank',
  'KOTAKB': 'Kotak Bank',
  'PNBSMS': 'PNB',
  'BOBTXN': 'Bank of Baroda',
  'BOBSMS': 'Bank of Baroda',
  'CANBNK': 'Canara Bank',
  'UNIONB': 'Union Bank',
  'IDFCFB': 'IDFC First Bank',
  'YESBNK': 'Yes Bank',
  'INDUSB': 'IndusInd Bank',
  'IOBCHN': 'Indian Overseas Bank',
  'CENTBK': 'Central Bank',
  'BOIIND': 'Bank of India',
  'FEDBNK': 'Federal Bank',
  'AUBANK': 'AU Bank',
  'PAYTMB': 'Paytm Payments Bank',
  'AIRBNK': 'Airtel Payments Bank',
  'JIOPBS': 'Jio Payments Bank',
  'IPBMSG': 'India Post Payments Bank',
};

/// "AD-HDFCBK", "VM-SBIUPI-S", "JD-ICICIT-T" -> "HDFCBK". Null for phone numbers
/// and anything that is not a DLT header.
String? senderCode(String address) {
  final m = RegExp(r'^[A-Z]{2}-([A-Z0-9]{6})(?:-[A-Z])?$').firstMatch(address.trim().toUpperCase());
  return m?.group(1);
}

/// Bank name for a sender, or null when the sender is not a known bank.
String? bankForSender(String address) => bankSenders[senderCode(address)];

final _debit = RegExp(r'\b(debited|spent|sent|paid|withdrawn|purchase|txn of|transaction of|used for)\b',
    caseSensitive: false);
// Not a completed spend: one-time codes, money in, failures, reversals, upcoming debits, bills due.
final _notSpend = RegExp(
    r'\b(otp|one time password|verification code|credited to your|received|refund(?:ed)?|reversed|reversal|'
    r'failed|declined|unsuccessful|will be debited|to be debited|due on|due date|is due|requested|request|'
    r'mandate|autopay set|e-?mandate registered|cashback)\b',
    caseSensitive: false);
final _atm = RegExp(r'\b(atm|cash withdrawal|withdrawn at|withdrawal at)\b', caseSensitive: false);
final _payee = <RegExp>[
  RegExp(r'\bto\s+VPA\s+([^\s(]+)', caseSensitive: false),
  RegExp(r'\b(?:to|at|towards)\s+([A-Za-z][A-Za-z0-9&.\- ]{1,40}?)(?=\s+(?:on|ref|upi|via|not|avl|avail|from|for|txn|\d)|[.(,]|$)',
      caseSensitive: false),
];
final _notAPayee = RegExp(r'^(a/?c|ac|acct|account|your|card|bank|upi|imps|neft|you|xx|\*)', caseSensitive: false);

/// One bank SMS -> a payment, an ATM withdrawal, or Ignored.
/// [sourceApp] on the result is the bank name plus " SMS" so the app can tell SMS from app alerts.
NotificationResult parseBankSms({required String sender, required String body, required DateTime at}) {
  final bank = bankForSender(sender);
  if (bank == null) return const Ignored();
  final text = body.replaceAll(RegExp(r'\s+'), ' ').trim();
  final amount = parseAmount(text) ?? _bareDebitAmount(text);
  if (amount == null || amount <= 0) return const Ignored();
  if (_notSpend.hasMatch(text)) return const Ignored();
  final source = '$bank SMS';

  if (_atm.hasMatch(text) && RegExp(r'withdraw|atm', caseSensitive: false).hasMatch(text)) {
    return AtmWithdrawal(amount, at, source);
  }
  if (!_debit.hasMatch(text)) return const Ignored();
  return UpiPayment(amount, _payeeOf(text), at, source);
}

// SBI and some others write "debited by 250.0" with no "Rs".
final _bareDebit = RegExp(r'\bdebited (?:by|for|with)\s+([0-9][0-9,]*(?:\.[0-9]{1,2})?)\b', caseSensitive: false);
double? _bareDebitAmount(String text) {
  final m = _bareDebit.firstMatch(text);
  return m == null ? null : double.tryParse(m.group(1)!.replaceAll(',', ''));
}

String _payeeOf(String text) {
  for (final p in _payee) {
    for (final m in p.allMatches(text)) {
      var c = m.group(1)!.trim();
      if (c.contains('@')) c = c.split('@').first; // VPA: keep the name part
      c = c.replaceAll(RegExp(r'[.\-]+$'), '').trim();
      if (c.length < 2 || _notAPayee.hasMatch(c) || parseAmount(c) != null || RegExp(r'^\d').hasMatch(c)) continue;
      return c;
    }
  }
  return 'Unknown payee';
}

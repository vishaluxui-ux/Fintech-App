import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models.dart';

/// User choices: duplicate handling and bill photo retention.
class Settings extends ChangeNotifier {
  final SharedPreferences _p;
  Settings(this._p);

  DuplicateMode get duplicateMode =>
      DuplicateMode.values.byName(_p.getString('duplicate_mode') ?? DuplicateMode.flag.name);
  set duplicateMode(DuplicateMode m) {
    _p.setString('duplicate_mode', m.name);
    notifyListeners();
  }

  /// When false, the bill photo is removed once every item on it is approved
  /// and only the extracted lines remain.
  bool get keepBillPhotos => _p.getBool('keep_bill_photos') ?? true;
  set keepBillPhotos(bool v) {
    _p.setBool('keep_bill_photos', v);
    notifyListeners();
  }

  /// Approve payments to a merchant you've approved twice with the same category.
  bool get autoApproveKnown => _p.getBool('auto_approve_known') ?? true;
  set autoApproveKnown(bool v) {
    _p.setBool('auto_approve_known', v);
    notifyListeners();
  }

  bool get weeklySummary => _p.getBool('weekly_summary') ?? true;
  set weeklySummary(bool v) {
    _p.setBool('weekly_summary', v);
    notifyListeners();
  }

  /// Bank SMS reading (opt-in). Off until the user turns it on and grants permission.
  bool get readBankSms => _p.getBool('read_bank_sms') ?? false;
  set readBankSms(bool v) {
    _p.setBool('read_bank_sms', v);
    notifyListeners();
  }

  /// Time of the newest bank SMS already read, so each SMS is read once.
  DateTime? get lastSmsRead {
    final ms = _p.getInt('last_sms_read');
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  set lastSmsRead(DateTime? t) =>
      t == null ? _p.remove('last_sms_read') : _p.setInt('last_sms_read', t.millisecondsSinceEpoch);

  bool get notificationExplainerSeen => _p.getBool('notif_explainer_seen') ?? false;
  set notificationExplainerSeen(bool v) => _p.setBool('notif_explainer_seen', v);

  Future<void> clear() async {
    await _p.clear();
    notifyListeners();
  }
}

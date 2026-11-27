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

  bool get notificationExplainerSeen => _p.getBool('notif_explainer_seen') ?? false;
  set notificationExplainerSeen(bool v) => _p.setBool('notif_explainer_seen', v);

  Future<void> clear() async {
    await _p.clear();
    notifyListeners();
  }
}

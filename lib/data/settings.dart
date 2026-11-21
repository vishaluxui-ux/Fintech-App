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

  bool get notificationExplainerSeen => _p.getBool('notif_explainer_seen') ?? false;
  set notificationExplainerSeen(bool v) => _p.setBool('notif_explainer_seen', v);

  Future<void> clear() async {
    await _p.clear();
    notifyListeners();
  }
}

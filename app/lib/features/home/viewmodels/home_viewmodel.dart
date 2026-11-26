import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'package:brr/features/auth/models/user_profile.dart';
import 'package:brr/features/auth/viewmodels/auth_viewmodel.dart';

/// ViewModel ของหน้า Home — ครอบ session user จาก AuthViewModel
/// ให้ view อ่านผ่านตัวเอง ไม่ยืม VM ของ feature อื่นตรงๆ;
/// state/logic เฉพาะ home ที่เพิ่มภายหลังอยู่ที่นี่
class HomeViewModel extends ChangeNotifier {
  HomeViewModel(AuthViewModel auth) : _auth = auth {
    _auth.addListener(notifyListeners);
  }

  /// หยิบ AuthViewModel จาก Provider ที่ root — view ไม่ต้อง
  /// เห็น VM ข้าม feature (pattern เดียวกับ forContext ทั้งแอป)
  factory HomeViewModel.forContext(BuildContext context) =>
      HomeViewModel(context.read<AuthViewModel>());

  final AuthViewModel _auth;

  UserProfile? get user => _auth.user;
  bool get isOffline => _auth.isOffline;
  bool get isOfficer => _auth.user?.isOfficer ?? false;

  @override
  void dispose() {
    _auth.removeListener(notifyListeners);
    super.dispose();
  }
}

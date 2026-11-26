import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'package:brr/core/services/api_client.dart';
import 'package:brr/features/auth/models/user_profile.dart';
import 'package:brr/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:brr/features/map/viewmodels/failed_edits_viewmodel.dart';

/// ViewModel ของหน้าเมนู — ครอบ session user + signOut จาก
/// AuthViewModel และเป็นทางเดียวที่ tile ใช้รีเฟรชจำนวนงาน
/// ค้าง (เดิม view ยิง static ด้วย context เอง)
class MenuViewModel extends ChangeNotifier {
  MenuViewModel(AuthViewModel auth, ApiClient? api)
    : _auth = auth,
      _api = api {
    _auth.addListener(notifyListeners);
  }

  /// หยิบ AuthViewModel + ApiClient จาก Provider ที่ root —
  /// view ไม่ต้องเห็นชั้น data เอง (MVVM)
  factory MenuViewModel.forContext(BuildContext context) => MenuViewModel(
    context.read<AuthViewModel>(),
    context.read<ApiClient>(),
  );

  final AuthViewModel _auth;
  final ApiClient? _api;

  UserProfile? get user => _auth.user;
  bool get isOfficer => _auth.user?.isOfficer ?? false;

  void signOut() => _auth.signOut();

  /// รีเฟรชจำนวนการแก้ไขค้างเข้า badge — VM ส่ง api ให้ชั้น
  /// VM ของ map แทนที่จะให้ view เห็น ApiClient
  Future<int> refreshFailedCount() =>
      FailedEditsViewModel.failedCountFor(_api);

  @override
  void dispose() {
    _auth.removeListener(notifyListeners);
    super.dispose();
  }
}

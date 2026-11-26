import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:brr/core/config/app_info.dart';
import 'package:brr/features/settings/data/settings_service.dart';

/// ViewModel หน้าตั้งค่า — view ไม่เห็น service/url_launcher ตรง
class SettingsViewModel extends ChangeNotifier {
  SettingsViewModel([SettingsService? service])
    : _service = service ?? SettingsService();

  final SettingsService _service;

  /// เวอร์ชั่นแอปที่ติดตั้งอยู่ — sync กับ pubspec ผ่าน [AppInfo]
  String get version => AppInfo.version;

  bool _backingUp = false;
  bool get backingUp => _backingUp;

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  /// เปิดหน้าแอปบน Play Store — ลอง market:// (เด้งเข้าแอปสโตร์
  /// ตรง) ก่อน fallback เป็น https ใน browser; คืน false ถ้าเปิด
  /// ไม่ได้ทั้งคู่ให้ UI แจ้ง
  Future<bool> openPlayStore() async {
    try {
      if (await launchUrl(
        Uri.parse(AppInfo.playStoreMarketUri),
        mode: LaunchMode.externalApplication,
      )) {
        return true;
      }
      return await launchUrl(
        Uri.parse(AppInfo.playStoreUrl),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      return false;
    }
  }

  /// สำรองข้อมูลในเครื่องออกไฟล์ — คืน path โฟลเดอร์ backup;
  /// throw ให้ UI แจ้งเหตุผล
  Future<String> backup() async {
    if (_backingUp) throw Exception('กำลังสำรองข้อมูลอยู่');
    _backingUp = true;
    _safeNotify();
    try {
      return await _service.exportBackup();
    } finally {
      _backingUp = false;
      _safeNotify();
    }
  }
}

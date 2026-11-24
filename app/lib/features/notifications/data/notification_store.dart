import 'package:flutter/foundation.dart';

/// จำนวนแจ้งเตือนที่ยังไม่อ่าน — home badge ฟังตัวนี้
/// (global เหมือน failedEditsCount: อายุเท่าแอป ไม่ต้อง dispose)
/// TODO: wire เข้า GET /notifications ของ backend เมื่อมี
final ValueNotifier<int> unreadNotifications = ValueNotifier(0);

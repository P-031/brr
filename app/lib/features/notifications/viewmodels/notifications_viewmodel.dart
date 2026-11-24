import 'package:flutter/foundation.dart';

import 'package:brr/features/notifications/data/notification_store.dart';
import 'package:brr/features/notifications/models/notification_item.dart';

/// ViewModel หน้าแจ้งเตือน — view/home ไม่เห็น store ตรง;
/// badge ยังไม่อ่านฟังผ่าน [unreadListenable]
///
/// TODO: เมื่อ backend มี GET /notifications ให้เพิ่ม service
/// + forContext ตาม pattern ParcelStatusViewModel แล้ว fetch
/// ใน [load]
class NotificationsViewModel extends ChangeNotifier {
  NotificationsViewModel() {
    load();
  }

  /// badge จำนวนยังไม่อ่าน — home listen ตัวนี้ (ชั้น data
  /// ซ่อนหลัง VM ตาม MVVM; static เพราะ home ไม่ได้ถือ VM)
  static ValueListenable<int> get unreadListenable => unreadNotifications;

  final List<NotificationItem> _items = [];
  List<NotificationItem> get items => _items;

  int get unreadCount => _items.where((n) => n.unread).length;

  /// โหลดรายการแจ้งเตือน — ยังไม่มี endpoint เลยเป็น list ว่าง;
  /// เมื่อ backend พร้อม fetch แล้ว assign _items + notifyListeners
  Future<void> load() async {
    _syncBadge();
  }

  /// อัปเดต badge กลางให้ตรง items ปัจจุบัน — VM เป็นเจ้าของ
  /// การเขียน store (global) ไม่ใช่ view
  void _syncBadge() {
    unreadNotifications.value = unreadCount;
  }
}

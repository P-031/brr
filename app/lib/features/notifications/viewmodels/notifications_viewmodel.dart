import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'package:brr/core/services/api_client.dart';
import 'package:brr/core/utils/thai_date.dart';
import 'package:brr/features/map/data/parcel_service.dart';
import 'package:brr/features/map/viewmodels/failed_edits_viewmodel.dart';
import 'package:brr/features/notifications/data/notification_store.dart';
import 'package:brr/features/notifications/models/notification_item.dart';

/// ViewModel หน้าแจ้งเตือน — view/home ไม่เห็น service ตรง;
/// badge ยังไม่อ่านฟังผ่าน [unreadListenable]
class NotificationsViewModel extends ChangeNotifier {
  NotificationsViewModel(ParcelService? service, {this._api})
    : _service = service {
    load();
  }

  /// สร้างจาก session api — view ส่งแค่นี้ ไม่ต้องเห็น ParcelService
  /// (api null = ออฟไลน์ → list ว่าง + error)
  NotificationsViewModel.forApi(ApiClient? api)
    : this(api == null ? null : ParcelService(api), api: api);

  /// หยิบ ApiClient จาก Provider ที่ root (pattern เดียวกับ
  /// ParcelStatusViewModel.forContext)
  factory NotificationsViewModel.forContext(BuildContext context) =>
      NotificationsViewModel.forApi(context.read<ApiClient>());

  final ParcelService? _service;
  final ApiClient? _api;

  /// รีเฟรชจำนวนงานค้างเข้า badge — VM ส่ง api ให้ชั้น VM
  /// ของ map แทนที่จะให้ view ยิง static ด้วย context เอง
  Future<int> refreshFailedCount() =>
      FailedEditsViewModel.failedCountFor(_api);

  /// badge จำนวนยังไม่อ่าน — home listen ตัวนี้ (ชั้น data
  /// ซ่อนหลัง VM ตาม MVVM; static เพราะ home ไม่ได้ถือ VM)
  static ValueListenable<int> get unreadListenable => unreadNotifications;

  /// ล้าง badge — เรียกตอน logout เพราะจำนวนเป็นของผู้ใช้คนก่อน
  /// (คนถัดไปบนเครื่องเดียวกันไม่ควรเห็นเลขค้าง)
  static void clearBadge() => unreadNotifications.value = 0;

  /// ดึงจำนวนยังไม่อ่านล่าสุดมาอัปเดต badge — เรียกเบาๆ จาก
  /// จุดที่ไม่ได้เปิดหน้าแจ้งเตือน (login/resume/เน็ตกลับ) ไม่งั้น
  /// badge จะว่างจนกว่าผู้ใช้เปิดหน้าครั้งแรก; พลาดเงียบไว้
  static Future<void> refreshBadge(ApiClient? api) async {
    if (api == null) return;
    try {
      final r = await ParcelService(api).fetchNotifications();
      unreadNotifications.value = r.unread;
    } catch (_) {}
  }

  final List<NotificationItem> _items = [];
  List<NotificationItem> get items => _items;

  bool _loading = true;
  bool get loading => _loading;

  /// พลาดตอนโหลด — view แสดงข้อความแทน list ว่าง ไม่โยนทิ้ง
  String? _error;
  String? get error => _error;

  bool _disposed = false;

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// โหลดรายการจาก `GET /notifications` — สำเร็จแล้วยิง
  /// `POST /notifications/read` เคลียร์ badge (การเปิดหน้านี้ =
  /// ผู้ใช้อ่านแล้ว); items เก็บ flag unread ของตอนโหลดไว้ตกแต่ง
  Future<void> load() async {
    final service = _service;
    if (service == null) {
      _loading = false;
      _error = 'ออฟไลน์อยู่';
      _syncBadge(0);
      return;
    }
    try {
      final (unread: serverUnread, items: raw) = await service
          .fetchNotifications();
      _items
        ..clear()
        ..addAll(raw.map(_parse));
      _loading = false;
      _error = null;
      _syncBadge(serverUnread);
      _safeNotify();
      // เคลียร์ฝั่ง server หลังแสดง list แล้ว — badge เป็นศูนย์
      // ทันทีไม่ว่าผล (ผู้ใช้เห็นรายการครบแล้ว)
      unreadNotifications.value = 0;
      await service.markNotificationsRead();
    } catch (e) {
      _loading = false;
      _error = '$e'.replaceFirst('Exception: ', '');
      _safeNotify();
    }
  }

  NotificationItem _parse(Map<String, dynamic> j) => NotificationItem(
    title: '${j['title'] ?? ''}',
    body: '${j['body'] ?? ''}',
    time: _fmtTime(j['createdAt']),
    unread: j['read'] != true,
  );

  String _fmtTime(Object? iso) {
    final d = DateTime.tryParse('$iso')?.toLocal();
    return d == null ? '' : formatThaiDateTime(d);
  }

  /// อัปเดต badge กลาง — VM เป็นเจ้าของการเขียน store (global)
  /// ไม่ใช่ view
  void _syncBadge(int count) {
    unreadNotifications.value = count;
  }
}

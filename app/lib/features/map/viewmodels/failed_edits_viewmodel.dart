import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'package:brr/core/services/api_client.dart';
import 'package:brr/features/map/data/parcel_local_store.dart';
import 'package:brr/features/map/data/parcel_service.dart';

/// ViewModel ของหน้า "การแก้ไขที่ส่งไม่สำเร็จ" — รายการ PATCH ที่
/// server ปฏิเสธตอน flush คิว offline (version stale เกิน retry /
/// 4xx-5xx อื่น) เก็บไว้ในเครื่องให้ผู้ใช้ตัดสินใจ ไม่หายเงียบ
class FailedEditsViewModel extends ChangeNotifier {
  FailedEditsViewModel(ParcelService? service) : _service = service {
    load();
  }

  /// สร้างจาก session api — view ส่งแค่ context ไม่เห็น ParcelService
  FailedEditsViewModel.forApi(ApiClient? api)
    : this(api == null ? null : ParcelService(api));

  factory FailedEditsViewModel.forContext(BuildContext context) =>
      FailedEditsViewModel.forApi(context.read<ApiClient>());

  /// จำนวนรายการแบบ live — badge/แจ้งเตือน listen ตัวนี้ได้ทันที
  /// ที่ store บันทึกรายการใหม่ ไม่ต้องรอเปิดเมนู
  static ValueListenable<int> get countListenable => failedEditsCount;

  /// จำนวนรายการสำหรับ badge ที่เมนู — static เพราะเมนูไม่ได้ถือ
  /// VM ตัวเต็ม (อ่าน prefs ตรงๆ เบามาก)
  static Future<int> failedCountFor(BuildContext context) async {
    final n = (await ParcelService(
      context.read<ApiClient>(),
    ).loadFailedEdits()).length;
    failedEditsCount.value = n;
    return n;
  }

  final ParcelService? _service;

  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;
  bool _disposed = false;

  /// plotId ที่กำลัง retry/discard — ปิดปุ่มใบนั้นกันกดซ้ำ
  String? _busyId;

  List<Map<String, dynamic>> get items => _items;
  bool get loading => _loading;
  String? get busyId => _busyId;

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> load() async {
    final service = _service;
    if (service == null) {
      _items = const [];
      _loading = false;
      _safeNotify();
      return;
    }
    try {
      _items = await service.loadFailedEdits();
    } catch (_) {
      _items = const [];
    }
    _loading = false;
    _safeNotify();
  }

  /// key เทียบ entry ตัวเดียวกัน — plotId+queuedAt ตาม _sameFailedEdit
  /// ฝั่ง service (ใช้ปิดปุ่มต่อใบ)
  static String keyOf(Map<String, dynamic> e) =>
      '${e['plotId']}|${e['queuedAt']}';

  /// ส่งเข้าคิวใหม่แล้ว flush — คืน error text เมื่อล้มเหลว
  /// (รายการยังอยู่ให้ลองอีกครั้งถ้า server ปฏิเสธซ้ำ)
  Future<String?> retry(Map<String, dynamic> entry) async {
    final service = _service;
    if (service == null) return 'ออฟไลน์อยู่ — ส่งใหม่ไม่ได้';
    _busyId = keyOf(entry);
    _safeNotify();
    try {
      await service.retryFailedEdit(entry);
      await load();
      return null;
    } catch (e) {
      return '$e'.replaceFirst('Exception: ', '');
    } finally {
      _busyId = null;
      _safeNotify();
    }
  }

  /// ทิ้งรายการเดียว — ผู้ใช้ยืนยันไม่เอาค่าที่เคยแก้แล้ว
  Future<void> discard(Map<String, dynamic> entry) async {
    final service = _service;
    if (service == null) return;
    _busyId = keyOf(entry);
    _safeNotify();
    try {
      await service.discardFailedEdit(entry);
      await load();
    } finally {
      _busyId = null;
      _safeNotify();
    }
  }

  /// ทิ้งทั้งหมด — ปุ่ม "ล้างรายการ"
  Future<void> discardAll() async {
    await _service?.discardAllFailedEdits();
    await load();
  }
}

import 'package:flutter/foundation.dart';

import 'package:brr/features/map/data/parcel_service.dart';
import 'package:brr/features/map/models/parcel.dart';

/// ViewModel ของ flow "ข้อมูลแปลง" ทั้งหมด — info sheet, หน้ารายละเอียด
/// และ 3 หน้าแก้ไข/คำขอใต้เมนู ⋮ แชร์ instance เดียวกัน ดังนั้น
/// detail future ถูกสร้างครั้งเดียวและ PATCH สำเร็จ → refetch แล้ว
/// notify ให้ทุกหน้าที่ subscribe อัปเดตอัตโนมัติ
///
/// View ไม่เห็น ParcelService เลย — ทุก network call ผ่าน VM นี้
class ParcelDetailViewModel extends ChangeNotifier {
  ParcelDetailViewModel({required this.parcel, required ParcelService service})
    : _service = service;

  final Parcel parcel;
  final ParcelService _service;

  Future<Map<String, dynamic>?>? _detail;

  /// `/plots/:id` — cache future เดียวกันให้ sheet/detail/edit ใช้ร่วม
  /// (แปลง draft ไม่มีบน server → resolve null ทันที)
  Future<Map<String, dynamic>?> get detail => _detail ??= parcel.isDraft
      ? Future<Map<String, dynamic>?>.value(null)
      : _service.fetchParcelDetail(parcel.id);

  /// ตัวเลือกฟอร์มจาก `GET /meta/options` — โหลดใหม่ทุกครั้งที่หน้า
  /// เปิด (cache ไว้ฝั่ง caller ตามความเหมาะสม)
  Future<FormOptions> loadOptions() => _service.fetchOptions();

  /// PATCH รูท/ลำดับ แล้ว refetch detail — listener (sheet/detail
  /// view) เห็นค่าใหม่ทันทีโดยไม่ต้อง reopen
  Future<void> updateRouteSeq({String? rootNo, String? sequenceNo}) async {
    await _service.updateParcelMeta(
      parcel.id,
      rootNo: rootNo,
      sequenceNo: sequenceNo,
    );
    _detail = _service.fetchParcelDetail(parcel.id);
    notifyListeners();
  }

  /// ส่งคำขออัปเดตแปลง — `kind` = 'status' (คำขอ1) / 'edit' (คำขอ2),
  /// `value` = ตัวเลือกจาก /meta/options — endpoint รอ backend
  /// (docs/API_CONTRACT.md) เมื่อมีใช้ได้ทันที
  Future<void> submitRequest({required String kind, required String value}) =>
      _service.submitPlotRequest(parcel.id, kind: kind, value: value);
}

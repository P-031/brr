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
  ParcelDetailViewModel({required this.parcel, required this._service});

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

  /// รายชื่อชาวไร่สำหรับ picker "ชาวไร่คนใหม่" ในคำขอแก้ไขชาวไร
  Future<List<FarmerRef>> loadFarmers() => _service.fetchFarmers();

  /// จำนวนกิจกรรมที่บันทึกในเครื่องของแปลงนี้ — หน้าบันทึกกิจกรรม
  /// ใช้ตั้งชื่อ "ครั้งที่ N"
  Future<int> activityDraftCount() => _service.activityDraftCount(parcel.id);

  /// บันทึกกิจกรรมลงเครื่อง — photos = path ไฟล์ที่ถ่าย;
  /// `detailPending` = บันทึกเฉพาะรูปรอกรอกรายละเอียด
  Future<void> saveActivityDraft({
    required List<String> photoPaths,
    bool detailPending = false,
    String? plantedAt,
    String? caneGroup,
  }) => _service.saveActivityDraft(
    plotId: parcel.id,
    photoPaths: photoPaths,
    detailPending: detailPending,
    plantedAt: plantedAt,
    caneGroup: caneGroup,
  );

  /// จุดเสี่ยงภัยพิบัติของแปลง — เก็บในเครื่องรอ endpoint
  Future<Map<String, dynamic>?> riskPoint() => _service.riskPointFor(parcel.id);

  Future<void> saveRiskPoint({
    required String type,
    String? name,
    int? severity,
    String? note,
  }) => _service.saveRiskPoint(
    plotId: parcel.id,
    type: type,
    name: name,
    severity: severity,
    note: note,
  );

  /// PATCH รูท/ลำดับ แล้ว refetch detail — listener (sheet/detail
  /// view) เห็นค่าใหม่ทันทีโดยไม่ต้อง reopen
  Future<void> updateRouteSeq({String? rootNo, String? sequenceNo}) async {
    final current = await detail;
    final rawVersion = current?['version'];
    final version = rawVersion is int ? rawVersion : null;
    if (version == null) {
      throw Exception('ยังโหลดข้อมูลแปลงไม่ครบ ลองใหม่อีกครั้ง');
    }
    await _service.updateParcelMeta(
      parcel.id,
      version: version,
      rootNo: rootNo,
      sequenceNo: sequenceNo,
    );
    _detail = _service.fetchParcelDetail(parcel.id);
    notifyListeners();
  }

  /// ส่งคำขออัปเดตแปลง — `kind` = 'status' (คำขอ1) / 'edit' (คำขอ2)
  /// / 'group' (กลุ่มบำรุง/ตัด); `value` = ตัวเลือกเดียวจาก
  /// /meta/options, `fields` = payload หลายฟิลด์ — endpoint รอ
  /// backend (docs/API_CONTRACT.md) เมื่อมีใช้ได้ทันที
  Future<String> submitRequest({
    required String kind,
    String? value,
    Map<String, String?>? fields,
  }) => _service.submitPlotRequest(
    parcel.id,
    kind: kind,
    value: value,
    fields: fields,
  );
}

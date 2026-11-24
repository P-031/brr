import 'dart:async';

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
  ParcelDetailViewModel({required this.parcel, required this._service}) {
    // warm options cache ทิ้งไว้เบื้องหลัง — sheet ย่อย (จุดเสี่ยง/
    // โครงการ/คำขอ) ที่เปิดจาก flow นี้จะมี options พร้อมทันที
    // (service cache แชร์กัน ยิงซ้ำไม่เสียหาย); พลาดเงียบเดี๋ยว
    // sheet ลองเองอีกทีตอนเปิด
    unawaited(
      _service.fetchOptions().catchError((_) => const FormOptions()),
    );
  }

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

  /// กิจกรรมที่บันทึกไว้ในเครื่องของแปลง — ใหม่สุดก่อน
  /// (หน้า "นำส่งกิจกรรมที่บันทึกไว้ในเครื่อง")
  Future<List<Map<String, dynamic>>> activityDrafts() =>
      _service.activitiesFor(parcel.id);

  /// ลบกิจกรรมในเครื่อง (+ รูปที่ persist ไว้ตามรายการ)
  Future<void> removeActivityDraft(String id) =>
      _service.removeActivityDraft(id);

  /// นำส่งกิจกรรมร่างขึ้นระบบ — คืน true เมื่อออฟไลน์แล้วถูก
  /// คิวไว้ส่งอัตโนมัติ (UI แสดง "บันทึกไว้ส่งเมื่อออนไลน์" แทน
  /// error); พลาดอื่น throw เพื่อให้ UI แจ้งเหตุผล
  Future<bool> submitActivity(Map<String, dynamic> activity) async {
    try {
      await _service.submitActivity(parcel.id, activity);
      return false;
    } on ActivityQueued {
      return true;
    }
  }

  /// จำนวนกิจกรรมใหม่ที่ยังไม่ได้เปิดดู — badge บนปุ่มเมนู
  Future<int> unseenActivityCount() => _service.unseenActivityCount(parcel.id);

  /// ทำเครื่องหมายว่าดูกิจกรรมครบแล้ว — badge หาย
  Future<void> markActivitiesSeen() => _service.markActivitiesSeen(parcel.id);

  /// การยืนยันแปลงข้ามปีล่าสุดของแปลง — เก็บในเครื่องรอ endpoint
  Future<Map<String, dynamic>?> parcelConfirm() =>
      _service.parcelConfirmFor(parcel.id);

  /// รายการปีการผลิตสำหรับ dropdown "ปีการผลิตเป้าหมาย" —
  /// ใช้ `/plots/years` ชุดเดียวกับหน้าดาวน์โหลด
  Future<List<String>> loadYears() async => [
    for (final y in (await _service.fetchYearIndex()).years.keys) ?y,
  ];

  Future<void> saveParcelConfirm({
    String? targetYear,
    String? status,
    String? note,
    List<String> photoPaths = const [],
    String? recordedBy,
  }) => _service.saveParcelConfirm(
    plotId: parcel.id,
    targetYear: targetYear,
    status: status,
    note: note,
    photoPaths: photoPaths,
    recordedBy: recordedBy,
  );

  /// บันทึกกิจกรรมลงเครื่อง — photos = path ไฟล์ที่ถ่าย;
  /// `detailPending` = บันทึกเฉพาะรูปรอกรอกรายละเอียด
  Future<void> saveActivityDraft({
    required List<String> photoPaths,
    bool detailPending = false,
    String? plantedAt,
    String? caneGroup,
    String? herbicideUsed,
    String? fertilizerRate,
    String? npkN,
    String? npkP,
    String? npkK,
    bool? mpiApplied,
    List<Map<String, dynamic>>? fertilizerRounds,
    String? organicFertilizerType,
    String? organicRate,
    String? organicDate,
    String? dolomiteRate,
    String? dolomiteDate,
    bool? weedPresent,
    bool? subsoiled,
    String? subsoilDepth,
    bool? diseasePresent,
    String? diseaseType,
    String? diseaseSpread,
    bool? diseaseManaged,
    bool? pestPresent,
    String? pestType,
    String? pestSpread,
    String? pestDamage,
    bool? pestManaged,
    bool? hilled,
    String? germinationPercent,
    String? harvestGroupFarmerId,
    String? harvestGroupFarmer,
    String? lossReason,
    String? lossAreaRai,
    String? yieldEstimate,
    String? totalTons,
    String? cutVarietyDeduction,
    String? cutLossKgPerRai,
    String? cutLossTons,
    String? cutLossReason,
    String? actualHarvestTons,
    bool? seedCane,
    String? seedCaneNote,
    String? suggestion,
    String? activityId,
    String? recordedBy,
    String? recordedByRole,
  }) => _service.saveActivityDraft(
    plotId: parcel.id,
    photoPaths: photoPaths,
    detailPending: detailPending,
    plantedAt: plantedAt,
    caneGroup: caneGroup,
    herbicideUsed: herbicideUsed,
    fertilizerRate: fertilizerRate,
    npkN: npkN,
    npkP: npkP,
    npkK: npkK,
    mpiApplied: mpiApplied,
    fertilizerRounds: fertilizerRounds,
    organicFertilizerType: organicFertilizerType,
    organicRate: organicRate,
    organicDate: organicDate,
    dolomiteRate: dolomiteRate,
    dolomiteDate: dolomiteDate,
    weedPresent: weedPresent,
    subsoiled: subsoiled,
    subsoilDepth: subsoilDepth,
    diseasePresent: diseasePresent,
    diseaseType: diseaseType,
    diseaseSpread: diseaseSpread,
    diseaseManaged: diseaseManaged,
    pestPresent: pestPresent,
    pestType: pestType,
    pestSpread: pestSpread,
    pestDamage: pestDamage,
    pestManaged: pestManaged,
    hilled: hilled,
    germinationPercent: germinationPercent,
    harvestGroupFarmerId: harvestGroupFarmerId,
    harvestGroupFarmer: harvestGroupFarmer,
    lossReason: lossReason,
    lossAreaRai: lossAreaRai,
    yieldEstimate: yieldEstimate,
    totalTons: totalTons,
    cutVarietyDeduction: cutVarietyDeduction,
    cutLossKgPerRai: cutLossKgPerRai,
    cutLossTons: cutLossTons,
    cutLossReason: cutLossReason,
    actualHarvestTons: actualHarvestTons,
    seedCane: seedCane,
    seedCaneNote: seedCaneNote,
    suggestion: suggestion,
    activityId: activityId,
    recordedBy: recordedBy,
    recordedByRole: recordedByRole,
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

  /// โครงการส่งเสริมที่เลือกไว้ของแปลง — เก็บในเครื่องรอ endpoint
  Future<Map<String, dynamic>?> plotProject() =>
      _service.plotProjectFor(parcel.id);

  Future<void> savePlotProject({
    required List<String> items,
    Map<String, String> choices = const {},
    required bool passed,
  }) => _service.savePlotProject(
    plotId: parcel.id,
    items: items,
    choices: choices,
    passed: passed,
  );

  /// สถานะแปลงตัดที่บันทึกไว้ในเครื่อง — เก็บในเครื่องรอ endpoint
  Future<Map<String, dynamic>?> cutStatus() => _service.cutStatusFor(parcel.id);

  Future<void> saveCutStatus({
    required String status,
    String? statusCode,
    String? startDate,
    String? endDate,
    String? estimateTons,
    String? cutCaneTons,
  }) => _service.saveCutStatus(
    plotId: parcel.id,
    status: status,
    statusCode: statusCode,
    startDate: startDate,
    endDate: endDate,
    estimateTons: estimateTons,
    cutCaneTons: cutCaneTons,
  );

  /// PATCH รูท/ลำดับ แล้ว refetch detail — listener (sheet/detail
  /// view) เห็นค่าใหม่ทันทีโดยไม่ต้อง reopen
  /// คืน true เมื่อออฟไลน์ → บันทึกเข้าคิวในเครื่อง ส่งเองเมื่อเน็ตกลับ
  Future<bool> updateRouteSeq({String? rootNo, String? sequenceNo}) async {
    final current = await detail;
    final rawVersion = current?['version'];
    final version = rawVersion is int ? rawVersion : null;
    if (version == null) {
      throw Exception('ยังโหลดข้อมูลแปลงไม่ครบ ลองใหม่อีกครั้ง');
    }
    try {
      await _service.updateParcelMeta(
        parcel.id,
        version: version,
        rootNo: rootNo,
        sequenceNo: sequenceNo,
      );
    } on PendingEditQueued {
      return true;
    }
    _detail = _service.fetchParcelDetail(parcel.id);
    notifyListeners();
    return false;
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

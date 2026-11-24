import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'package:brr/core/config/api_config.dart';
import 'package:brr/core/config/api_endpoints.dart';
import 'package:brr/features/map/data/parcel_local_store.dart';
import 'package:brr/features/map/models/parcel.dart';
import 'package:brr/features/parcel_status/models/plot_request.dart';
import 'package:brr/features/plot_activities/models/plot_list_item.dart';
import 'package:brr/core/services/api_client.dart';
import 'package:brr/core/utils/json_safe.dart';

/// รหัสแปลงที่แอปเป็นคนตั้ง — ส่งซ้ำรหัสเดิมจะไม่สร้างแปลงใบที่สอง
String newPlotId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// ข้อความ error จาก body ของ backend — ตอบเป็น
/// `{error: "...", details: [{path, message}]}` (zod) หรือ
/// `{error: "..."}` ธรรมดา ถ้า parse ไม่ได้คืน status code
String _errorDetail(http.Response res) {
  try {
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final error = '${body['error'] ?? ''}';
    final rawDetails = body['details'];
    final details = [
      if (rawDetails is List)
        for (final d in rawDetails)
          if (d is Map) '${d['path']}: ${d['message']}',
    ];
    if (details.isNotEmpty) return '$error (${details.join(', ')})';
    if (error.isNotEmpty) return error;
  } catch (_) {}
  return 'HTTP ${res.statusCode}';
}

/// Data layer for land parcels — ชั้น network (backend API) ทั้งหมด
/// Local persistence (ร่าง/กิจกรรม/จุดเสี่ยง/คิวออฟไลน์/รูปถ่าย) อยู่ใน
/// [ParcelLocalStore] — service นี้ delegate API เดิมไปที่ store
/// เพื่อให้ view/VM ไม่ต้องเปลี่ยน
///
/// When [ApiConfig.enabled] is on, boundaries come from the backend
/// (`GET /plots/map`, Bearer token via [ApiClient]).
/// Otherwise it serves mock parcels around Buriram.
class ParcelService {
  ParcelService([ApiClient? api]) : _api = api;

  final ApiClient? _api;
  final ParcelLocalStore _local = ParcelLocalStore();

  /// Bounding box covering Thailand — the backend clips to the
  /// caller's own parcels anyway.
  /// กรอบดาวน์โหลดเต็ม (ทั้งประเทศ) — fetch ครบแล้วครอบคลุมทุก viewport
  static const fullBox = 'west=97&south=5&east=106&north=21&limit=50000';

  /// suffix กัน id ร่างชนเมื่อบันทึก 2 ครั้งใน microsecond เดียวกัน
  static int _draftSeq = 0;

  // ================================================================
  // Local persistence — delegate ไป ParcelLocalStore (signature เดิม)
  // ================================================================

  /// ข้อมูลแปลงที่ดาวน์โหลดครั้งล่าสุด — ใช้เมื่อเครือข่ายล่ม.
  /// คืน null ถ้าไม่เคยดาวน์โหลดสำเร็จ.
  Future<ParcelPage?> loadCachedParcels() async {
    final body = await _local.readParcelCache();
    if (body == null) return null;
    try {
      final page = await compute(_parseParcelList, body);
      return (
        items: [...page.items, ...await _drafts()],
        truncated: page.truncated,
      );
    } catch (_) {
      return null;
    }
  }

  /// แปลงฉบับร่างที่บันทึกลงเครื่องทั้งหมด — ใช้โดยหน้า
  /// "ข้อมูลฉบับร่าง" และ merge เข้าชุดแปลงตอนโหลดแผนที่
  /// อ่านร่างทั้งหมด — prune ร่าง confirmed เก่าเกินกำหนดก่อนเสมอ
  /// (เรียกจาก service เพราะ prune เขียน prefs ผ่าน write queue
  /// เดียวกัน; ใส่ใน loadDrafts ที่ถูกเรียกข้างใน _serialized
  /// จะ deadlock — queue รอตัวเอง)
  Future<List<Parcel>> _drafts() async {
    try {
      await _local.pruneConfirmedDrafts();
    } catch (_) {}
    return _local.loadDrafts();
  }

  Future<List<Parcel>> fetchDrafts() => _drafts();

  /// รหัสที่ใช้ยิง POST จริงของร่างนี้ — จำไว้ในเครื่อง เพื่อกดยืนยันซ้ำแล้วไม่สร้างแปลงใบที่สอง
  /// (gen รหัสที่นี่ แต่เขียนลง prefs ผ่าน write queue ของ local
  /// store เดียวกันกับ saveDraft — ไม่เขียน prefs ตรงๆ เอง)
  Future<String> ensureClientId(Parcel draft) =>
      _local.ensureClientId(draft, newPlotId());

  /// ยืนยันร่างสำเร็จ — ไม่ลบ แต่ stamp `status = 'confirmed'` ไว้
  /// ให้หน้าฉบับร่างกรอง "ยืนยันแล้ว/ยังไม่ยืนยัน" ได้
  Future<void> markDraftConfirmed(String id) => _local.markDraftConfirmed(id);

  /// Removes a stored draft by id (e.g. after it's pushed to the backend).
  Future<void> removeDraft(String id) => _local.removeDraft(id);

  /// บันทึกกิจกรรมลงเครื่อง — `detailPending` = บันทึกเฉพาะรูปไว้ก่อน
  /// รอกรอกรายละเอียด ("นำส่งกิจกรรมในเครื่อง" จะหยิบ list นี้ต่อ)
  Future<void> saveActivityDraft({
    required String plotId,
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
  }) => _local.saveActivityDraft(
    plotId: plotId,
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

  /// จำนวนกิจกรรมในเครื่องของแปลง — ใช้ตั้งชื่อ "ครั้งที่ N"
  Future<int> activityDraftCount(String plotId) =>
      _local.activityDraftCount(plotId);

  /// กิจกรรมที่บันทึกไว้ในเครื่องของแปลง — ใหม่สุดขึ้นก่อน
  Future<List<Map<String, dynamic>>> activitiesFor(String plotId) =>
      _local.activitiesFor(plotId);

  /// จำนวนกิจกรรมใหม่ที่ยังไม่เคยเปิดดู — ใช้เป็น badge บนปุ่มเมนู
  Future<int> unseenActivityCount(String plotId) =>
      _local.unseenActivityCount(plotId);

  /// ทำเครื่องหมายว่าดูกิจกรรมของแปลงครบแล้ว — badge หาย
  Future<void> markActivitiesSeen(String plotId) =>
      _local.markActivitiesSeen(plotId);

  /// ล้างสถานะ "ดูแล้ว" ทั้งหมด — เรียกตอน logout เพราะเป็นข้อมูล
  /// ตามผู้ใช้ (อีกคน login เครื่องเดียวกันไม่ควรเห็น badge ตามของเก่า)
  /// ร่าง/คิวส่งไม่แตะ — งานค้างของผู้ใช้ต้องอยู่ครบ
  static Future<void> clearActivitySeen() =>
      ParcelLocalStore.clearActivitySeen();

  /// ลบกิจกรรมในเครื่อง + ลบรูปที่ persist ไว้ตามรายการด้วย
  Future<void> removeActivityDraft(String id) => _local.removeActivityDraft(id);

  /// นำส่งกิจกรรมที่บันทึกในเครื่องขึ้นระบบ —
  /// `POST /plots/:id/activities` body = `{id: uuid(serverId),`
  /// ฟิลด์กิจกรรมทั้งชุด, photoCount}` (backend schema:
  /// `{id, plantedAt?, detailPending?, photoCount 1-3}` —
  /// field นอก schema ถูก strip เงียบๆ; รูปยังอยู่เครื่อง)
  /// สำเร็จ → mark 'sent', transport fail → mark 'queued' +
  /// throw [ActivityQueued], server ปฏิเสธ → mark 'failed' + throw
  /// ให้ UI แจ้งเหตุผล
  Future<void> submitActivity(
    String plotId,
    Map<String, dynamic> activity,
  ) async {
    if (!ApiConfig.enabled || _api == null) {
      throw Exception('ออฟไลน์อยู่ — นำส่งไม่ได้');
    }
    final actId = '${activity['id']}';
    // uuid ต้องคงเดิมข้าม retry — backend dedup ด้วย id ถ้า
    // เปลี่ยนทุกครั้งจะสร้างกิจกรรมซ้ำใน DB; null = ร่างถูกลบ
    // ไปแล้ว ห้ามยิง (ไม่งั้นเกิดกิจกรรมเรือนแม่ใน DB)
    final serverId = await _local.ensureActivityServerId(actId);
    if (serverId == null) {
      throw Exception('ร่างกิจกรรมถูกลบไปแล้ว');
    }
    // photoCount นับเฉพาะไฟล์ที่ยังอยู่จริง — path ที่ไฟล์โดนลบ
    // ไปแล้วไม่นับ (backend รับ 0 ได้ตาม contract ล่าสุด)
    final actPhotos = activity['photos'];
    final livePhotos = actPhotos is List
        ? [
            for (final p in actPhotos)
              if (File('$p').existsSync()) p,
          ]
        : const <Object?>[];
    final body = <String, dynamic>{
      'id': serverId,
      for (final e in activity.entries)
        if (!const {
          'id',
          'serverId',
          'submitStatus',
          'plotId',
          'photos',
        }.contains(e.key))
          e.key: e.value,
      'photoCount': livePhotos.length,
    };
    final http.Response res;
    try {
      res = await _api.postJson(ApiEndpoints.plotActivities(plotId), body);
    } on TransportException {
      // เน็ตหลุด/timeout — คิวไว้ส่งอัตโนมัติตอนเน็ตกลับ
      // (flushQueuedActivities) ไม่นับเป็น "ส่งไม่สำเร็จ"
      // ที่ต้องให้ผู้ใช้ตัดสินใจเหมือน server ปฏิเสธ
      try {
        await _local.setActivitySubmitStatus(actId, 'queued');
      } catch (_) {}
      throw const ActivityQueued();
    } catch (_) {
      try {
        await _local.setActivitySubmitStatus(actId, 'failed');
      } catch (_) {}
      throw Exception('เชื่อมต่อเซิร์ฟเวอร์ไม่ได้ — ลองใหม่เมื่อออนไลน์');
    }
    if (res.statusCode == 200 || res.statusCode == 201) {
      // server รับแล้ว = สำเร็จ — เขียนสถานะลงเครื่องพลาด (ดิสก์เต็ม)
      // ห้ามรายงาน fail ไม่งั้นผู้ใช้กดส่งซ้ำ → กิจกรรมซ้ำในระบบ
      try {
        await _local.setActivitySubmitStatus(actId, 'sent');
      } catch (_) {}
      return;
    }
    try {
      await _local.setActivitySubmitStatus(actId, 'failed');
    } catch (_) {}
    throw Exception('นำส่งไม่สำเร็จ: ${_errorDetail(res)}');
  }

  /// ส่งกิจกรรมที่คิวไว้ตอนออฟไลน์ขึ้นระบบอัตโนมัติ — เรียกเมื่อ
  /// connectivity กลับมา; รายการที่เน็ตยังไม่นิ่งค้างเป็น 'queued'
  /// ต่อรอรอบถัดไป, server ปฏิเสธ → 'failed' ให้ผู้ใช้ตัดสินใจ
  Future<void> flushQueuedActivities() async {
    if (!ApiConfig.enabled || _api == null) return;
    for (final a in await _local.queuedActivities()) {
      try {
        await submitActivity('${a['plotId']}', a);
      } on ActivityQueued {
        // ยังส่งไม่ได้ — ปล่อยค้างในคิวรอรอบถัดไป
      } catch (_) {
        // server ปฏิเสธ → submitActivity mark 'failed' ให้แล้ว
      }
    }
  }

  /// จุดเสี่ยงล่าสุดของแปลง (เก็บทับรายการเดิมต่อ plotId)
  Future<Map<String, dynamic>?> riskPointFor(String plotId) =>
      _local.riskPointFor(plotId);

  /// ประเภทจุดเสี่ยงล่าสุดของทุกแปลง — plotId → type แผนที่ใช้ทาสี
  /// polygon ตามสถานะนี้
  Future<Map<String, String>> riskPointTypes() async => {
    for (final r in await _local.loadRiskPoints())
      '${r['plotId']}': '${r['type'] ?? ''}',
  };

  /// บันทึก/อัปเดตจุดเสี่ยงของแปลง — type จาก backend riskLevels,
  /// severity 1-5, name/note พิมพ์เอง
  Future<void> saveRiskPoint({
    required String plotId,
    required String type,
    String? name,
    int? severity,
    String? note,
  }) => _local.saveRiskPoint(
    plotId: plotId,
    type: type,
    name: name,
    severity: severity,
    note: note,
  );

  /// โครงการที่เลือกไว้ของแปลง — {items: [ชื่อ], passed: bool}
  Future<Map<String, dynamic>?> plotProjectFor(String plotId) =>
      _local.plotProjectFor(plotId);

  /// บันทึกรายการโครงการที่ติ๊ก — passed = ครบเกณฑ์บังคับแล้ว
  /// choices = ตัวเลือกย่อยต่อเกณฑ์ {ชื่อเกณฑ์: ชนิด} (เช่น ชนิดปุ๋ยอินทรีย์)
  Future<void> savePlotProject({
    required String plotId,
    required List<String> items,
    Map<String, String> choices = const {},
    required bool passed,
  }) => _local.savePlotProject(
    plotId: plotId,
    items: items,
    choices: choices,
    passed: passed,
  );

  /// การยืนยันข้ามปีล่าสุดของแปลง (เก็บทับรายการเดิมต่อ plotId)
  Future<Map<String, dynamic>?> parcelConfirmFor(String plotId) =>
      _local.parcelConfirmFor(plotId);

  /// บันทึกยืนยันแปลงข้ามปี — รูป copy เข้า documents เหมือน
  /// รูปกิจกรรม/รูปแปลง กัน temp cache ถูกระบบล้าง
  Future<void> saveParcelConfirm({
    required String plotId,
    String? targetYear,
    String? status,
    String? note,
    List<String> photoPaths = const [],
    String? recordedBy,
  }) => _local.saveParcelConfirm(
    plotId: plotId,
    targetYear: targetYear,
    status: status,
    note: note,
    photoPaths: photoPaths,
    recordedBy: recordedBy,
  );

  /// สถานะตัดล่าสุดของแปลง — {status, startDate, endDate,
  /// estimateTons, cutCaneTons, updatedAt}
  Future<Map<String, dynamic>?> cutStatusFor(String plotId) =>
      _local.cutStatusFor(plotId);

  /// บันทึก/อัปเดตสถานะแปลงตัด — status = ชื่อตัวเลือกที่แสดง,
  /// statusCode = รหัสสถานะจาก backend (กัน label เปลี่ยน)
  Future<void> saveCutStatus({
    required String plotId,
    required String status,
    String? statusCode,
    String? startDate,
    String? endDate,
    String? estimateTons,
    String? cutCaneTons,
  }) => _local.saveCutStatus(
    plotId: plotId,
    status: status,
    statusCode: statusCode,
    startDate: startDate,
    endDate: endDate,
    estimateTons: estimateTons,
    cutCaneTons: cutCaneTons,
  );

  /// จำนวน PATCH ที่ค้างในคิวรอส่ง — ใช้แสดง badge/สถานะ
  Future<int> pendingEditCount() async =>
      (await _local.loadPendingEdits()).length;

  // ================================================================
  // Network — backend API
  // ================================================================

  /// เบา — รายการปีการผลิต + จำนวน สำหรับหน้าเลือกดาวน์โหลด.
  /// `GET /plots/years` รวดเดียว (GROUP BY ฝั่ง server) + drafts
  /// ในเครื่อง. ข้อมูลหนัก (ขอบแปลง) ดึงตอนกดดาวน์โหลดผ่าน [fetchParcels].
  Future<({Map<String?, int> years, List<Parcel> drafts})>
  fetchYearIndex() async {
    final drafts = await _drafts();
    if (ApiConfig.enabled && _api != null) {
      final res = await _api.get(ApiEndpoints.plotsYears);
      if (res.statusCode != 200) {
        throw Exception('โหลดรายการปีไม่สำเร็จ (${res.statusCode})');
      }
      // backend อาจส่ง {items:[...]} หรือ list ตรง — ทนทั้งสองรูปแบบ
      final body = jsonDecode(res.body);
      final items = body is List
          ? body
          : body is Map<String, dynamic>
          ? body['items'] is List
                ? body['items'] as List
                : const []
          : const [];
      return (
        years: {
          for (final j in items)
            if (j is Map)
              j['year']?.toString():
                  num.tryParse('${j['count']}')?.toInt() ?? 0,
        },
        drafts: drafts,
      );
    }
    final years = <String?, int>{};
    for (final p in _mockParcels) {
      years.update(p.productionYear, (v) => v + 1, ifAbsent: () => 1);
    }
    return (years: years, drafts: drafts);
  }

  Future<ParcelPage> fetchParcels({
    String? box,

    /// เลือกเฉพาะปีการผลิต — null = ทุกปี, null ใน set = รวมแปลงไม่มีปี.
    Set<String?>? years,
    void Function(int received, int? total)? onProgress,

    /// เรียกตอนรับ bytes ครบแล้วกำลัง gunzip+parse ใน isolate —
    /// ช่วงนี้ UI ต้องโชว์สถานะ "กำลังเตรียมข้อมูล" ไม่งั้นดูเหมือนค้าง
    void Function()? onProcessing,
  }) async {
    // เลือกปีว่างเปล่า = เอาเฉพาะ draft ในเครื่อง (ถ้าส่ง years ว่าง
    // ไป backend จะตีความเป็น "ทุกปี")
    if (years != null && years.isEmpty) {
      return (items: await _drafts(), truncated: false);
    }
    if (ApiConfig.enabled && _api != null) {
      // เลือกเฉพาะ "ไม่มีปี" → join ได้ '' — ส่งแค่ nullYear=1
      // ไม่ให้ backend รับ years= ว่างไปตีเป็นปีสตริงว่าง
      final yearQuery = years == null
          ? ''
          : () {
              final ys = years.whereType<String>().toList();
              return '${ys.isNotEmpty ? '&years=${Uri.encodeQueryComponent(ys.join(","))}' : ''}'
                  '${years.contains(null) ? '&nullYear=1' : ''}';
            }();
      final res = await _api.getStreamed(
        '${ApiEndpoints.plotsMap}?${box ?? fullBox}$yearQuery',
        onProgress: onProgress,
        onProcessing: onProcessing,
      );
      if (res.statusCode != 200) {
        throw Exception('โหลดข้อมูลพื้นที่ไม่สำเร็จ (${res.statusCode})');
      }
      // เขียน cache ก่อน parse — ถ้าคราวหน้าเน็ตล่มยังมีข้อมูลเปิดได้
      unawaited(_local.writeParcelCache(res.body));
      // parse ใน isolate — payload หลายพันแปลง jsonDecode+map บน
      // main isolate จะค้างจอ โดยเฉพาะเครื่องสเปคต่ำ
      onProcessing?.call();
      final page = await compute(_parseParcelList, res.body);
      return (
        items: [...page.items, ...await _drafts()],
        truncated: page.truncated,
      );
    }
    // Mock — used only when the backend is disabled.
    return (items: [..._mockParcels, ...await _drafts()], truncated: false);
  }

  /// รายการแปลงแบบเพจ (`GET /plots`) — ใช้หน้ากิจกรรมแปลง
  /// cursor = nextCursor จากหน้าก่อน; filter ตรงกับพารามิเตอร์ backend
  Future<PlotPage> fetchPlots({
    int limit = 30,
    String? cursor,
    Set<String?>? years,
    Set<String>? zones,
    Set<String>? caneTypes,
    Set<bool>? planted,
    Set<String>? groupKinds,
    String? search,
  }) async {
    if (!ApiConfig.enabled || _api == null) {
      const PlotPage empty = (items: [], nextCursor: null, total: 0);
      return empty;
    }
    final p = StringBuffer('limit=$limit');
    if (cursor != null) {
      p.write('&cursor=${Uri.encodeQueryComponent(cursor)}');
    }
    if (years != null && years.isNotEmpty) {
      // เลือกเฉพาะ "ไม่มีปี" → join ได้ '' — อย่าส่ง years= เปล่า
      // ให้ backend ตีเป็นค่าปีว่าง ส่งแค่ nullYear=1 พอ
      final ys = years.whereType<String>().toList();
      if (ys.isNotEmpty) {
        p.write('&years=${Uri.encodeQueryComponent(ys.join(","))}');
      }
      if (years.contains(null)) p.write('&nullYear=1');
    }
    if (zones != null && zones.isNotEmpty) {
      p.write('&zone=${Uri.encodeQueryComponent(zones.join(","))}');
    }
    if (caneTypes != null && caneTypes.isNotEmpty) {
      p.write('&caneType=${Uri.encodeQueryComponent(caneTypes.join(","))}');
    }
    // เลือกครบทั้งสองสถานะ = เหมือนไม่กรอง ไม่ส่งพารามิเตอร์
    if (planted != null && planted.length == 1) {
      p.write('&planted=${planted.first ? "1" : "0"}');
    }
    if (groupKinds != null && groupKinds.length == 1) {
      p.write('&groupKind=${groupKinds.first}');
    }
    if (search != null && search.isNotEmpty) {
      p.write('&search=${Uri.encodeQueryComponent(search)}');
    }
    final res = await _api.get('${ApiEndpoints.plots}?$p');
    if (res.statusCode != 200) {
      throw Exception('โหลดรายการแปลงไม่สำเร็จ (${res.statusCode})');
    }
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    // item เสียตัวเดียวข้ามไป — ไม่ให้ล้มทั้งเพจ
    final parsed = <PlotListItem>[];
    for (final x in j['items'] is List ? j['items'] as List : const []) {
      try {
        parsed.add(PlotListItem.fromJson(x as Map<String, dynamic>));
      } catch (_) {}
    }
    return (
      items: parsed,
      nextCursor: j['nextCursor']?.toString(),
      total: toIntOrNull(j['total']) ?? 0,
    );
  }

  /// รายละเอียดแปลงทีละตัว (`GET /plots/:id`) — ใช้ตอนแตะแปลงบน
  /// แผนที่ meta ครบอยู่ที่นี่ ไม่ต้องฝังมากับ bulk payload ของ map
  /// คืน null เมื่อโหลดไม่ได้ (ออฟไลน์/ไม่พบ) — UI fallback ใช้ข้อมูล
  /// ที่มีใน Parcel อยู่แล้ว
  Future<Map<String, dynamic>?> fetchParcelDetail(String id) async {
    if (!ApiConfig.enabled || _api == null) return null;
    try {
      final res = await _api.get(ApiEndpoints.plot(id));
      if (res.statusCode == 200) {
        // เน็ตใช้ได้แล้ว — ล้างคิว PATCH ที่ค้างไว้เผื่อมี
        unawaited(flushPendingEdits());
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  /// Creates a new parcel — POST /plots when the backend is on.
  /// [productionYear]/[officerName] are collected now and forwarded
  /// once the backend schema supports them.
  Future<Parcel> createParcel({
    required String name,
    String variety = '',
    String? productionYear,
    String? officerName,
    String? project,
    String? farmerName,
    String? farmerId,
    String? caneGroup,
    String? zone,
    String? province,
    String? district,
    String? subdistrict,
    String? village,
    String? rootNo,
    String? sequenceNo,
    String? prevPlotNo,
    String? caneType,
    String? caneVariety,
    String? ownership,
    String? terrain,
    String? hasLoss,
    String? lossRai,
    String? targetYield,
    String? note,
    List<String> photos = const [],
    bool draft = false,
    required List<LatLng> points,
    required String id,
    Map<String, Object?>? survey,
  }) async {
    // Draft = save on device only, never posts to the backend.
    if (!draft && ApiConfig.enabled && _api != null) {
      // late — อ่านเฉพาะเมื่อ draft ยัง false (try สำเร็จ);
      // catch ตั้ง draft=true → ไม่ถูกอ่านข้างล่าง
      late http.Response res;
      try {
        res = await _api.postJson(ApiEndpoints.plots, {
          'id': id,
          'name': name,
          'variety': variety,
          // Officer saves the plot for the picked farmer; farmers
          // omit it and the backend uses their own account.
          'farmerId': ?farmerId,
          'productionYear': ?productionYear,
          'officerName': ?officerName,
          'project': ?project,
          'caneGroup': ?caneGroup,
          'zone': ?zone,
          'province': ?province,
          'district': ?district,
          'subdistrict': ?subdistrict,
          'village': ?village,
          'rootNo': ?rootNo,
          'sequenceNo': ?sequenceNo,
          'prevPlotNo': ?prevPlotNo,
          'caneType': ?caneType,
          'caneVariety': ?caneVariety,
          'ownership': ?ownership,
          'terrain': ?terrain,
          'hasLoss': ?hasLoss,
          'lossRai': ?double.tryParse(lossRai ?? ''),
          'targetYield': ?double.tryParse(targetYield ?? ''),
          'note': ?note,
          'survey': ?survey,
          if (survey == null)
            'points': [
              for (final p in points)
                {'latitude': p.latitude, 'longitude': p.longitude},
            ],
        });
      } on TransportException {
        // เน็ตหลุด/timeout กลางส่ง — ฟอร์มกับขอบที่กรอกมาต้องไม่
        // หาย: fallback เซฟเป็นร่างในเครื่อง (user ยืนยันส่งใหม่
        // จากหน้าร่างได้) — server ตอบกลับมาแล้ว (4xx/5xx) ยัง
        // throw เหมือนเดิมเพราะเป็น rejection ไม่ใช่ transport
        draft = true;
      }
      if (!draft) {
        if (res.statusCode >= 300) {
          throw Exception('บันทึกแปลงไม่สำเร็จ: ${_errorDetail(res)}');
        }
        return Parcel.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
      }
    }
    // รูปจาก image_picker อยู่ใน temp cache — ระบบล้างได้ทุกเมื่อ
    // draft เก็บแค่ path เลยต้อง copy ไป documents ของแอปก่อน
    final storedPhotos = [for (final p in photos) await _local.persistPhoto(p)];
    final local = Parcel(
      // microseconds + counter — บันทึก 2 ครั้งใน ms เดียวกันไม่ชน id
      // (id ชน = SharedPreferences ทับกัน ร่างหาย)
      id: 'local-${DateTime.now().microsecondsSinceEpoch}-${_draftSeq++}',
      name: name,
      points: points,
      productionYear: productionYear,
      owner: farmerName,
      variety: variety.isEmpty ? null : variety,
      isDraft: draft,
      savedAt: draft ? DateTime.now() : null,
      // เก็บ payload ฟอร์มครบไว้ใน meta — หน้าฉบับร่างใช้แสดง +
      // replay เป็น POST จริงตอน "ยืนยัน" / prefill ตอน "แก้ไข"
      meta: {
        'clientId': id,
        'productionYear': ?productionYear,
        'officerName': ?officerName,
        'project': ?project,
        'farmerName': ?farmerName,
        'farmerId': ?farmerId,
        'caneGroup': ?caneGroup,
        'zone': ?zone,
        'province': ?province,
        'district': ?district,
        'subdistrict': ?subdistrict,
        'village': ?village,
        'rootNo': ?rootNo,
        'sequenceNo': ?sequenceNo,
        'prevPlotNo': ?prevPlotNo,
        'caneType': ?caneType,
        'caneVariety': ?caneVariety,
        'ownership': ?ownership,
        'terrain': ?terrain,
        'hasLoss': ?hasLoss,
        'lossRai': ?lossRai,
        'targetYield': ?targetYield,
        'note': ?note,
        'survey': ?survey,
        // path รูปถ่ายตอนบันทึก — หน้าร่างใช้แสดง + ฟอร์ม prefill
        if (storedPhotos.isNotEmpty) 'photos': storedPhotos,
      },
    );
    if (draft) await _local.saveDraft(local);
    return local;
  }

  /// อัปเดต meta ของแปลง — PATCH /plots/:id คืน detail ล่าสุด
  /// (ใช้หน้า "แก้ไข รูท & ลำดับ" เป็นหลัก)
  Future<Map<String, dynamic>?> updateParcelMeta(
    String id, {
    required int version,
    String? rootNo,
    String? sequenceNo,
    String? caneType,
    String? productionYear,
    String? officerName,
    String? project,
    String? caneGroup,
    String? zone,
    String? prevPlotNo,
    String? caneVariety,
    String? ownership,
    String? terrain,
    String? hasLoss,
    String? lossRai,
    String? targetYield,
    String? note,
  }) async {
    if (!ApiConfig.enabled || _api == null) return null;
    // ส่งคิวที่ค้างก่อน — รักษาลำดับการแก้ไขต่อแปลง
    // (transport error ภายใน flush ถูกกลืน — คิวค้างต่อ)
    await flushPendingEdits();
    final body = <String, Object?>{
      'version': version,
      'rootNo': ?rootNo,
      'sequenceNo': ?sequenceNo,
      'caneType': ?caneType,
      'productionYear': ?productionYear,
      'officerName': ?officerName,
      'project': ?project,
      'caneGroup': ?caneGroup,
      'zone': ?zone,
      'prevPlotNo': ?prevPlotNo,
      'caneVariety': ?caneVariety,
      'ownership': ?ownership,
      'terrain': ?terrain,
      'hasLoss': ?hasLoss,
      'lossRai': ?double.tryParse(lossRai ?? ''),
      'targetYield': ?double.tryParse(targetYield ?? ''),
      'note': ?note,
    };
    final http.Response res;
    try {
      // _send throw เฉพาะข้อผิดพลาดชั้น transport (timeout/socket)
      // — error จาก server กลับมาเป็น Response ปกติ ไม่เข้า catch
      res = await _api.patchJson(ApiEndpoints.plot(id), body);
    } catch (_) {
      // เน็ตขาด: เก็บไว้ในคิวส่งใหม่เมื่อออนไลน์ ข้อมูลไม่หาย
      await _queuePendingEdit(id, body);
      throw const PendingEditQueued();
    }
    if (res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    throw Exception('บันทึกไม่สำเร็จ: ${_errorDetail(res)}');
  }

  /// โยนเมื่อ PATCH ถูกเก็บเข้าคิวเพราะออฟไลน์ — caller แสดง
  /// "บันทึกไว้ในเครื่อง" แทน error

  // ---- คิว PATCH ที่ค้างเพราะออฟไลน์ — retry เมื่อเน็ตกลับ ----

  /// เก็บ PATCH ไว้ส่งภายหลัง — แปลงเดียวกัน merge เป็น entry เดียว
  /// โดยรวมฟิลด์ของทุกรอบที่คิวไว้ (ค่าใหม่ชนะต่อฟิลด์) — ถ้าทับ
  /// ทั้ง body การแก้คนละฟิลด์ 2 รอบจะเหลือแค่รอบสุดท้าย
  Future<void> _queuePendingEdit(String id, Map<String, Object?> body) =>
      _local.updatePendingEdits((items) async {
        final prev = items
            .where((e) => e['plotId'] == id)
            .map((e) => e['body'])
            .whereType<Map>()
            .fold<Map<String, Object?>>(
              {},
              (acc, b) => acc..addAll(Map<String, Object?>.from(b)),
            );
        items.removeWhere((e) => e['plotId'] == id);
        items.add({
          'plotId': id,
          'body': {...prev, ...body},
          'queuedAt': DateTime.now().toIso8601String(),
        });
      });

  /// ลองส่งคิวค้างทั้งหมดตามลำดับ — หยุดเมื่อเจอ transport error
  /// (ยังออฟไลน์อยู่ คิวที่เหลือค้างไว้รอรอบหน้า); 4xx/5xx จาก
  /// server = รายการนั้นใช้ไม่ได้แล้ว ตัดทิ้งไม่ให้ติดค้างนิรันดร์
  /// แต่บันทึกไว้ใน failed list ไม่ให้ข้อมูลที่ผู้ใช้แก้หายเงียบๆ
  Future<void> flushPendingEdits() async {
    // PATCH ต่อเนื่องใช้เวลานานได้ (30s timeout × N รายการ) — ยิง
    // network นอก _serialized write lock เดี๋ยว save อื่น (ร่าง/
    // รูป/จุดเสี่ยง) ค้างตามคิว; กัน flush ซ้อนด้วย flag — snapshot
    // เดียวกันส่งซ้ำ = PATCH เดิม idempotent แต่เสียเวลาเปล่า
    if (!ApiConfig.enabled || _api == null) return;
    // เรียกซ้อนตอนกำลัง flush (เช่น retryFailedEdit/auto-flush
    // จาก PATCH ที่ล้มพร้อมกัน) — entry ใหม่เข้าคิวหลัง snapshot
    // ไปแล้ว ถ้า return เงียบจะไม่ได้ส่งจนกว่าจะมี trigger รอบ
    // หน้า (อาจไม่มีเลย) → ทำเครื่องหมายวนรอบใหม่แทน
    if (_flushing) {
      _flushAgain = true;
      return;
    }
    _flushing = true;
    try {
      do {
        _flushAgain = false;
        await _flushPending();
      } while (_flushAgain);
    } finally {
      _flushing = false;
    }
  }

  bool _flushing = false;
  bool _flushAgain = false;

  Future<void> _flushPending() async {
    final api = _api;
    if (api == null) return;
    // snapshot คิวออกมาก่อน — entry ที่เข้ามาระหว่างยิงจะไม่โดนจับ
    // (queuedAt ใหม่เสมอ removeWhere ไม่ชน)
    final snapshot = await _local.loadPendingEdits();
    final failed = <Map<String, dynamic>>[];
    final sentKeys = <String>{}, droppedKeys = <String>{};
    String keyOf(Map<String, dynamic> e) => '${e['plotId']}|${e['queuedAt']}';
    for (final e in snapshot) {
      final key = keyOf(e);
      // entry เสีย (body ไม่ใช่ Map) — ส่งต่อไม่ได้ตลอดกาล ตัดทิ้ง
      // ไม่งั้นตัวเสียตัวเดียวขวางคิวตัวหลังทั้งหมด (catch→break)
      final rawBody = e['body'];
      if (rawBody is! Map) {
        droppedKeys.add(key);
        continue;
      }
      final plotId = '${e['plotId']}';
      final body = Map<String, Object?>.from(rawBody);
      http.Response res;
      try {
        res = await api.patchJson(ApiEndpoints.plot(plotId), body);
      } catch (_) {
        // transport error — ยังออฟไลน์ เก็บตัวนี้+ที่เหลือไว้แล้วหยุด
        break;
      }
      // version ที่คิวไว้ตั้งแต่ตอนแก้อาจ stale — server ตอบ 409
      // VERSION_CONFLICT พร้อมรายละเอียดปัจจุบันใน `current`
      // ดึง version สดแล้วส่งซ้ำครั้งเดียว แทนที่จะทิ้งการแก้ไข
      // ที่ผู้ใช้ตั้งใจไว้ (แก้ไข offline ชนะตามลำดับคิว)
      if (res.statusCode == 409) {
        try {
          final j = jsonDecode(res.body);
          final cur = j is Map ? j['current'] : null;
          final fresh = cur is Map ? cur['version'] : null;
          if (j is Map && j['code'] == 'VERSION_CONFLICT' && fresh is int) {
            body['version'] = fresh;
            res = await api.patchJson(ApiEndpoints.plot(plotId), body);
          }
        } catch (_) {
          // เน็ตหลุดระหว่าง retry — คิวไว้เหมือน transport error
          break;
        }
      }
      if (res.statusCode == 200) {
        sentKeys.add(key);
        continue;
      }
      // 401/403 = session ยังไม่พร้อม (token ค้าง/หมดอายุ) ไม่ใช่
      // การปฏิเสธจริง — คิงไว้ส่งรอบหน้าเหมือน transport error
      if (res.statusCode == 401 || res.statusCode == 403) break;
      // server ปฏิเสธจริงๆ (หลัง retry แล้วยังไม่ผ่าน / 4xx-5xx
      // อื่น) — ตัดออกจากคิวแต่จดไว้ใน failed list พร้อมสาเหตุ
      failed.add({
        'plotId': plotId,
        'body': body,
        'status': res.statusCode,
        'queuedAt': e['queuedAt'],
      });
      droppedKeys.add(key);
    }
    // apply การลบใน write lock — เฉพาะ entry ที่ snapshot เห็น
    // (plotId|queuedAt ตรง); entry ใหม่ที่ merge/เพิ่มระหว่าง
    // ยิงจะรอดและถูกส่งรอบหน้า
    if (sentKeys.isNotEmpty || droppedKeys.isNotEmpty) {
      await _local.updatePendingEdits((items) async {
        items.removeWhere((e) {
          final k = keyOf(e);
          return sentKeys.contains(k) || droppedKeys.contains(k);
        });
      });
    }
    // เขียน failed หลังจบ transform — recordFailedEdit ใช้ write
    // queue เดียวกัน เรียกซ้อนข้างใน updatePendingEdits จะ deadlock
    for (final f in failed) {
      try {
        await _local.recordFailedEdit(f);
      } catch (_) {}
    }
  }

  /// การแก้ไขที่ server ปฏิเสธตอนส่งคิว — expose ให้ layer บน
  /// แจ้งผู้ใช้ได้ (เช่น badge ในหน้าเมนู) ไม่ให้หายเงียบ
  Future<List<Map<String, dynamic>>> loadFailedEdits() =>
      _local.loadFailedEdits();

  /// ส่งรายการที่โดนปฏิเสธเข้าคิวใหม่ — ค่าที่ผู้ใช้แก้ยังอยู่
  /// ครบใน body; flush จะ retry ด้วย version สดเองถ้ายัง stale
  /// (เดิม version ค้างเก่า → 409 → ระบบดึง current ลองอีกครั้ง)
  Future<void> retryFailedEdit(Map<String, dynamic> entry) async {
    final plotId = '${entry['plotId']}';
    final body = entry['body'];
    if (plotId.isEmpty || body is! Map) {
      throw Exception('ข้อมูลรายการเสีย ส่งใหม่ไม่ได้');
    }
    await _queuePendingEdit(plotId, Map<String, Object?>.from(body));
    await _local.updateFailedEdits((items) async {
      items.removeWhere((e) => _sameFailedEdit(e, entry));
    });
    await flushPendingEdits();
  }

  /// ทิ้งรายการเดียว — ผู้ใช้ยืนยันแล้วว่าไม่เอาค่าที่เคยแก้
  Future<void> discardFailedEdit(Map<String, dynamic> entry) =>
      _local.updateFailedEdits((items) async {
        items.removeWhere((e) => _sameFailedEdit(e, entry));
      });

  /// ทิ้งทั้งหมด — ปุ่ม "ล้างรายการ" ในหน้าแจ้งเตือน
  Future<void> discardAllFailedEdits() => _local.clearFailedEdits();

  /// เทียบ entry ด้วย plotId+queuedAt — body อาจถูก merge/แก้
  /// ตอน retry เลยเทียบทั้ง object ไม่ได้
  static bool _sameFailedEdit(Map<String, dynamic> a, Map b) =>
      '${a['plotId']}' == '${b['plotId']}' &&
      '${a['queuedAt']}' == '${b['queuedAt']}';

  /// ส่งคำขออัปเดตแปลง (เมนู ⋮ → คำขอ1/2/กลุ่ม) —
  /// `POST /plots/:id/requests` body = {kind, value?, ...fields}
  /// (backend เก็บ payload ดิบ — field เสริมเข้า payload ตรงๆ)
  /// คืน status ที่ backend บันทึกจริง (เช่น "รออนุมัติ") ให้ UI แจ้งผู้ใช้
  Future<String> submitPlotRequest(
    String id, {
    required String kind,
    String? value,
    Map<String, String?>? fields,
  }) async {
    if (!ApiConfig.enabled || _api == null) {
      throw Exception('ออฟไลน์อยู่ — ส่งคำขอไม่ได้');
    }
    final res = await _api.postJson('${ApiEndpoints.plot(id)}/requests', {
      'kind': kind,
      'value': ?value,
      if (fields != null)
        for (final e in fields.entries)
          if (e.value != null) e.key: e.value,
    });
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception('ส่งคำขอไม่สำเร็จ: ${_errorDetail(res)}');
    }
    try {
      final status = jsonDecode(res.body)['status'];
      if (status is String && status.isNotEmpty) return status;
    } catch (_) {}
    return 'รออนุมัติ';
  }

  /// ดาวน์โหลด/อัปเดตข้อมูลจุดเสี่ยงภัยพิบัติล่าสุด — GET /risk-points
  /// แล้ว merge เข้า local store ตาม plotId
  Future<int> downloadRiskPoints() async {
    if (!ApiConfig.enabled || _api == null) {
      throw Exception('ออฟไลน์อยู่ — ดาวน์โหลดไม่ได้');
    }
    final res = await _api.get(ApiEndpoints.riskPoints);
    if (res.statusCode != 200) {
      throw Exception('ดาวน์โหลดไม่สำเร็จ: ${_errorDetail(res)}');
    }
    final body = jsonDecode(res.body);
    final list = body is List
        ? body
        : body is Map
        ? body['items'] is List
              ? body['items'] as List
              : const []
        : const [];
    // upsert ทีละแปลงภายใต้ write queue เดียว — merge นอก queue
    // จะทับจุดที่ผู้ใช้เพิ่งบันทึกระหว่างโหลดกับเขียนหายเงียบ
    return _local.updateRiskPoints((items) async {
      var merged = 0;
      for (final x in list) {
        if (x is! Map) continue;
        final item = Map<String, dynamic>.from(x);
        final plotId = '${item['plotId'] ?? ''}';
        if (plotId.isEmpty) continue;
        items.removeWhere((r) => r['plotId'] == plotId);
        items.add(item);
        merged++;
      }
      return merged;
    });
  }

  /// Extension officers for the caretaker dropdown.
  /// Backend-ready: will list officer accounts once an endpoint
  /// exists; until then returns a placeholder list.
  Future<List<String>> fetchOfficers() async {
    if (ApiConfig.enabled && _api != null) {
      try {
        final res = await _api.get(ApiEndpoints.officers);
        if (res.statusCode == 200) {
          final body = jsonDecode(res.body);
          final items = body is List
              ? body
              : body is Map
              ? body['items'] is List
                    ? body['items'] as List
                    : const []
              : const [];
          // item ที่ไม่มี displayName ข้ามไป ไม่ล้มทั้ง list
          return [
            for (final j in items)
              if (j is Map && '${j['displayName'] ?? ''}'.isNotEmpty)
                '${j['displayName']}',
          ];
        }
        throw Exception('GET /officers → ${res.statusCode}');
      } catch (e) {
        debugPrint('fetchOfficers failed: $e');
        rethrow;
      }
    }
    return const [];
  }

  /// Farmers under this officer's care (farmerCare links) — used in
  /// the save form so an officer can pick the plot owner.
  Future<List<FarmerRef>> fetchFarmers() async {
    if (ApiConfig.enabled && _api != null) {
      try {
        final res = await _api.get(ApiEndpoints.farmers);
        if (res.statusCode == 200) {
          final body = jsonDecode(res.body);
          final items = body is List
              ? body
              : body is Map
              ? body['items'] is List
                    ? body['items'] as List
                    : const []
              : const [];
          return [
            for (final j in items)
              if (j is Map)
                FarmerRef(
                  id: '${j['id']}',
                  name: '${j['displayName'] ?? j['username']}',
                ),
          ];
        }
        throw Exception('GET /farmers → ${res.statusCode}');
      } catch (e) {
        debugPrint('fetchFarmers failed: $e');
        rethrow;
      }
    }
    return const [];
  }

  /// All picker option lists for the save form — master data served
  /// by the backend (`GET /meta/options`).
  /// master options เปลี่ยนน้อยมาก — cache future เดียวกันทั้งเซสชัน
  /// (endpoint ดึง prevPlots หลักหมื่นแถว ยิงซ้ำทุก sheet ช้า ~4 วิ);
  /// ล้มเหลวล้าง cache ให้ retry รอบหน้าได้
  Future<FormOptions>? _optionsCache;

  Future<FormOptions> fetchOptions() {
    return _optionsCache ??= _loadOptions().catchError((e) {
      _optionsCache = null;
      throw e;
    });
  }

  /// stale-while-revalidate — มี cache ในเครื่อง → คืนของเก่าทันที
  /// แล้วยิง remote อัปเดต memory+disk เบื้องหลัง (options ของจริง
  /// แทบไม่เปลี่ยน ผู้ใช้ไม่ต้องรอ endpoint หนักทุก sheet)
  Future<FormOptions> _loadOptions() async {
    if (!ApiConfig.enabled || _api == null) return const FormOptions();
    final disk = await _local.readMetaOptions();
    if (disk != null) {
      try {
        final cached = FormOptions.fromJson(
          jsonDecode(disk) as Map<String, dynamic>,
        );
        unawaited(_refreshOptions());
        return cached;
      } catch (_) {
        // json cache เสีย — ทิ้งแล้วรอ remote ตามปกติ
      }
    }
    return _fetchOptionsRemote();
  }

  /// ยิง remote แล้วแทนที่ memory cache — เรียกเบื้องหลังตอน stale
  /// hit; พลาดเงียบได้ (ของเก่ายังใช้ต่อได้)
  Future<void> _refreshOptions() async {
    try {
      _optionsCache = Future.value(await _fetchOptionsRemote());
    } catch (_) {}
  }

  Future<FormOptions> _fetchOptionsRemote() async {
    if (ApiConfig.enabled && _api != null) {
      try {
        final res = await _api.get(ApiEndpoints.metaOptions);
        if (res.statusCode == 200) {
          unawaited(_local.writeMetaOptions(res.body));
          return FormOptions.fromJson(
            jsonDecode(res.body) as Map<String, dynamic>,
          );
        }
        throw Exception('GET /meta/options → ${res.statusCode}');
      } catch (e) {
        debugPrint('fetchOptions failed: $e');
        rethrow;
      }
    }
    return const FormOptions();
  }

  /// คำขอแปลงทั้งหมดที่ผู้ใช้มองเห็น — `GET /plot-requests`
  /// (หน้าสถานะแปลง); ออฟไลน์คืน list ว่าง ไม่โยน
  /// ตาม nextCursor จนหมด (backend ตัดหน้าละ ≤500)
  Future<List<PlotRequestEntry>> fetchPlotRequests() async {
    if (!ApiConfig.enabled || _api == null) return const [];
    final out = <PlotRequestEntry>[];
    String? cursor;
    // เพดานรอบกันหน้าเพี้ยนวนไม่จบ — คำขอจริงไม่น่าเกินหลักพัน
    for (var round = 0; round < 20; round++) {
      final res = await _api.get(
        cursor == null
            ? ApiEndpoints.plotRequests
            : '${ApiEndpoints.plotRequests}?cursor=${Uri.encodeQueryComponent(cursor)}',
      );
      if (res.statusCode != 200) {
        throw Exception('โหลดรายการคำขอไม่สำเร็จ: ${_errorDetail(res)}');
      }
      final body = jsonDecode(res.body);
      final items = body is List
          ? body
          : body is Map
          ? body['items'] is List
                ? body['items'] as List
                : const []
          : const [];
      // item เสียตัวเดียวข้ามไป — ไม่ล้มทั้งหน้าคำขอ
      for (final j in items) {
        if (j is Map) {
          try {
            out.add(PlotRequestEntry.fromJson(Map<String, dynamic>.from(j)));
          } catch (_) {}
        }
      }
      final next = body is Map ? body['nextCursor']?.toString() : null;
      if (next == null || next.isEmpty) break;
      cursor = next;
    }
    return out;
  }
}

/// หน้ารายการแปลง (list) — nextCursor สำหรับ "โหลดเพิ่ม"
/// null = หมดแล้ว; total = จำนวนรวมทั้งหมดตามฟิลเตอร์
typedef PlotPage = ({List<PlotListItem> items, String? nextCursor, int total});

/// Decode /plots/map payload ใน background isolate — compute() ส่ง
/// เฉพาะ String ข้ามได้ แล้วคืน Parcel[] กลับมา
ParcelPage _parseParcelList(String body) {
  final j = jsonDecode(body) as Map<String, dynamic>;
  final items = j['items'] is List ? j['items'] as List : const [];
  // item เสียตัวเดียวไม่ให้ล้มทั้งหมื่นแปลง — ข้ามแล้วไปต่อ
  final parsed = <Parcel>[];
  for (final x in items) {
    try {
      parsed.add(Parcel.fromJson(x as Map<String, dynamic>));
    } catch (_) {}
  }
  return (items: parsed, truncated: j['truncated'] == true);
}

/// โยนเมื่อ PATCH ถูกเก็บเข้าคิวเพราะออฟไลน์ — caller แสดง
/// "บันทึกไว้ในเครื่อง" แทน error; ระบบส่งต่อเองเมื่อเน็ตกลับ
class PendingEditQueued implements Exception {
  const PendingEditQueued();
}

/// โยนเมื่อนำส่งกิจกรรมไม่ได้เพราะออฟไลน์/timeout — กิจกรรมถูก
/// mark 'queued' ไว้ส่งอัตโนมัติเมื่อเน็ตกลับ caller แสดง
/// "บันทึกไว้ส่งเมื่อออนไลน์" แทน error
class ActivityQueued implements Exception {
  const ActivityQueued();

  @override
  String toString() => 'ออฟไลน์อยู่ — บันทึกไว้ส่งอัตโนมัติเมื่อออนไลน์';
}

final _mockParcels = <Parcel>[
  Parcel(
    id: 'p1',
    name: 'แปลงอ้อย A (ตัวอย่าง)',
    points: [
      LatLng(14.9960, 103.1100),
      LatLng(14.9980, 103.1100),
      LatLng(14.9980, 103.1125),
      LatLng(14.9960, 103.1125),
    ],
  ),
  Parcel(
    id: 'p2',
    name: 'แปลงอ้อย B (ตัวอย่าง)',
    points: [
      LatLng(14.9930, 103.1130),
      LatLng(14.9945, 103.1128),
      LatLng(14.9950, 103.1150),
      LatLng(14.9932, 103.1152),
    ],
  ),
];

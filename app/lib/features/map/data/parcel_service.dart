import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:brr/core/config/api_config.dart';
import 'package:brr/core/config/api_endpoints.dart';
import 'package:brr/features/map/models/parcel.dart';
import 'package:brr/features/parcel_status/models/plot_request.dart';
import 'package:brr/features/plot_activities/models/plot_list_item.dart';
import 'package:brr/core/services/api_client.dart';

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
    final details = [
      for (final d in body['details'] as List? ?? const [])
        '${(d as Map<String, dynamic>)['path']}: ${d['message']}',
    ];
    if (details.isNotEmpty) return '$error (${details.join(', ')})';
    if (error.isNotEmpty) return error;
  } catch (_) {}
  return 'HTTP ${res.statusCode}';
}

/// Data layer for land parcels.
///
/// When [ApiConfig.enabled] is on, boundaries come from the backend
/// (`GET /plots/map`, Bearer token via [ApiClient]).
/// Otherwise it serves mock parcels around Buriram.
class ParcelService {
  ParcelService([ApiClient? api]) : _api = api;

  final ApiClient? _api;

  /// Bounding box covering Thailand — the backend clips to the
  /// caller's own parcels anyway.
  /// กรอบดาวน์โหลดเต็ม (ทั้งประเทศ) — fetch ครบแล้วครอบคลุมทุก viewport
  static const fullBox = 'west=97&south=5&east=106&north=21&limit=50000';

  /// SharedPreferences key holding device-only draft parcels.
  static const _draftsKey = 'draft_parcels';

  /// ไฟล์ cache payload ดาวน์โหลดล่าสุด — fallback ตอนเน็ตล่ม.
  static const _cacheName = 'parcels_cache.json';

  Future<File> _cacheFile() async =>
      File('${(await getApplicationDocumentsDirectory()).path}/$_cacheName');

  /// ข้อมูลแปลงที่ดาวน์โหลดครั้งล่าสุด — ใช้เมื่อเครือข่ายล่ม.
  /// คืน null ถ้าไม่เคยดาวน์โหลดสำเร็จ.
  Future<ParcelPage?> loadCachedParcels() async {
    try {
      final f = await _cacheFile();
      if (!await f.exists()) return null;
      final page = await compute(_parseParcelList, await f.readAsString());
      return (
        items: [...page.items, ...await _loadDrafts()],
        truncated: page.truncated,
      );
    } catch (_) {
      return null;
    }
  }

  /// แปลงฉบับร่างที่บันทึกลงเครื่องทั้งหมด — ใช้โดยหน้า
  /// "ข้อมูลฉบับร่าง" และ merge เข้าชุดแปลงตอนโหลดแผนที่
  Future<List<Parcel>> fetchDrafts() => _loadDrafts();

  Future<List<Parcel>> _loadDrafts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_draftsKey);
    if (raw == null) return [];
    try {
      return [
        for (final j in jsonDecode(raw) as List)
          Parcel.fromJson(j as Map<String, dynamic>),
      ];
    } catch (_) {
      return [];
    }
  }

  /// รหัสที่ใช้ยิง POST จริงของร่างนี้ — จำไว้ในเครื่อง เพื่อกดยืนยันซ้ำแล้วไม่สร้างแปลงใบที่สอง
  Future<String> ensureClientId(Parcel draft) async {
    final raw = draft.meta?['clientId'];
    if (raw is String && raw.isNotEmpty) return raw;
    final id = newPlotId();
    final prefs = await SharedPreferences.getInstance();
    final drafts = await _loadDrafts();
    final i = drafts.indexWhere((d) => d.id == draft.id);
    if (i >= 0) {
      final d = drafts[i];
      drafts[i] = Parcel(
        id: d.id,
        name: d.name,
        variety: d.variety,
        owner: d.owner,
        productionYear: d.productionYear,
        meta: {...?d.meta, 'clientId': id},
        status: d.status,
        points: d.points,
        isDraft: d.isDraft,
        savedAt: d.savedAt,
        centerOverride: d.centerOverride,
      );
      await prefs.setString(
        _draftsKey,
        jsonEncode([for (final item in drafts) item.toJson()]),
      );
    }
    return id;
  }

  Future<void> _saveDraft(Parcel p) async {
    final prefs = await SharedPreferences.getInstance();
    final drafts = await _loadDrafts();
    drafts.add(p);
    await prefs.setString(
      _draftsKey,
      jsonEncode([for (final d in drafts) d.toJson()]),
    );
  }

  /// ยืนยันร่างสำเร็จ — ไม่ลบ แต่ stamp `status = 'confirmed'` ไว้
  /// ให้หน้าฉบับร่างกรอง "ยืนยันแล้ว/ยังไม่ยืนยัน" ได้
  Future<void> markDraftConfirmed(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final drafts = await _loadDrafts();
    final i = drafts.indexWhere((d) => d.id == id);
    if (i < 0) return;
    final d = drafts[i];
    drafts[i] = Parcel(
      id: d.id,
      name: d.name,
      variety: d.variety,
      owner: d.owner,
      productionYear: d.productionYear,
      meta: d.meta,
      status: 'confirmed',
      points: d.points,
      isDraft: d.isDraft,
      savedAt: d.savedAt,
      centerOverride: d.centerOverride,
    );
    await prefs.setString(
      _draftsKey,
      jsonEncode([for (final d in drafts) d.toJson()]),
    );
  }

  // ---- กิจกรรมแปลง — บันทึกลงเครื่องก่อน รอ endpoint นำส่ง backend ----

  static const _activityKey = 'activity_drafts_v1';

  Future<List<Map<String, dynamic>>> _loadActivities() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_activityKey);
    if (raw == null) return [];
    try {
      return [
        for (final j in jsonDecode(raw) as List)
          Map<String, dynamic>.from(j as Map),
      ];
    } catch (_) {
      return [];
    }
  }

  /// บันทึกกิจกรรมลงเครื่อง — `detailPending` = บันทึกเฉพาะรูปไว้ก่อน
  /// รอกรอกรายละเอียด ("นำส่งกิจกรรมในเครื่อง" จะหยิบ list นี้ต่อ)
  Future<void> saveActivityDraft({
    required String plotId,
    required List<String> photoPaths,
    bool detailPending = false,
    String? plantedAt,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final items = await _loadActivities();
    items.add({
      'id': 'act-${DateTime.now().millisecondsSinceEpoch}',
      'plotId': plotId,
      'photos': photoPaths,
      'detailPending': detailPending,
      'plantedAt': ?plantedAt,
      'createdAt': DateTime.now().toIso8601String(),
    });
    await prefs.setString(_activityKey, jsonEncode(items));
  }

  /// จำนวนกิจกรรมในเครื่องของแปลง — ใช้ตั้งชื่อ "ครั้งที่ N"
  Future<int> activityDraftCount(String plotId) async =>
      (await _loadActivities()).where((a) => a['plotId'] == plotId).length;

  // ---- จุดเสี่ยงภัยพิบัติ — เก็บลงเครื่องก่อน รอ endpoint backend ----

  static const _riskKey = 'risk_points_v1';

  Future<List<Map<String, dynamic>>> _loadRiskPoints() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_riskKey);
    if (raw == null) return [];
    try {
      return [
        for (final j in jsonDecode(raw) as List)
          Map<String, dynamic>.from(j as Map),
      ];
    } catch (_) {
      return [];
    }
  }

  /// จุดเสี่ยงล่าสุดของแปลง (เก็บทับรายการเดิมต่อ plotId)
  Future<Map<String, dynamic>?> riskPointFor(String plotId) async {
    for (final r in await _loadRiskPoints()) {
      if (r['plotId'] == plotId) return r;
    }
    return null;
  }

  /// บันทึก/อัปเดตจุดเสี่ยงของแปลง — type จาก backend riskLevels,
  /// severity 1-5, name/note พิมพ์เอง
  Future<void> saveRiskPoint({
    required String plotId,
    required String type,
    String? name,
    int? severity,
    String? note,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final items = await _loadRiskPoints();
    items.removeWhere((r) => r['plotId'] == plotId);
    items.add({
      'plotId': plotId,
      'type': type,
      'name': ?name,
      'severity': ?severity,
      'note': ?note,
      'updatedAt': DateTime.now().toIso8601String(),
    });
    await prefs.setString(_riskKey, jsonEncode(items));
  }

  /// Removes a stored draft by id (e.g. after it's pushed to the backend).
  Future<void> removeDraft(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final drafts = await _loadDrafts();
    drafts.removeWhere((d) => d.id == id);
    await prefs.setString(
      _draftsKey,
      jsonEncode([for (final d in drafts) d.toJson()]),
    );
  }

  /// เบา — รายการปีการผลิต + จำนวน สำหรับหน้าเลือกดาวน์โหลด.
  /// `GET /plots/years` รวดเดียว (GROUP BY ฝั่ง server) + drafts
  /// ในเครื่อง. ข้อมูลหนัก (ขอบแปลง) ดึงตอนกดดาวน์โหลดผ่าน [fetchParcels].
  Future<({Map<String?, int> years, List<Parcel> drafts})>
  fetchYearIndex() async {
    final drafts = await _loadDrafts();
    if (ApiConfig.enabled && _api != null) {
      final res = await _api.get(ApiEndpoints.plotsYears);
      if (res.statusCode != 200) {
        throw Exception('โหลดรายการปีไม่สำเร็จ (${res.statusCode})');
      }
      final items = jsonDecode(res.body)['items'] as List;
      return (
        years: {
          for (final j in items)
            (j as Map<String, dynamic>)['year'] as String?:
                (j['count'] as num).toInt(),
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
      return (items: await _loadDrafts(), truncated: false);
    }
    if (ApiConfig.enabled && _api != null) {
      final yearQuery = years == null
          ? ''
          : '&years=${Uri.encodeQueryComponent(years.whereType<String>().join(","))}'
                '${years.contains(null) ? '&nullYear=1' : ''}';
      final res = await _api.getStreamed(
        '${ApiEndpoints.plotsMap}?${box ?? fullBox}$yearQuery',
        onProgress: onProgress,
        onProcessing: onProcessing,
      );
      if (res.statusCode != 200) {
        throw Exception('โหลดข้อมูลพื้นที่ไม่สำเร็จ (${res.statusCode})');
      }
      // เขียน cache ก่อน parse — ถ้าคราวหน้าเน็ตล่มยังมีข้อมูลเปิดได้
      unawaited(() async {
        try {
          await (await _cacheFile()).writeAsString(res.body);
        } catch (_) {}
      }());
      // parse ใน isolate — payload หลายพันแปลง jsonDecode+map บน
      // main isolate จะค้างจอ โดยเฉพาะเครื่องสเปคต่ำ
      onProcessing?.call();
      final page = await compute(_parseParcelList, res.body);
      return (
        items: [...page.items, ...await _loadDrafts()],
        truncated: page.truncated,
      );
    }
    // Mock — used only when the backend is disabled.
    return (items: [..._mockParcels, ...await _loadDrafts()], truncated: false);
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
      p.write(
        '&years=${Uri.encodeQueryComponent(years.whereType<String>().join(","))}',
      );
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
    return (
      items: [
        for (final x in j['items'] as List)
          PlotListItem.fromJson(x as Map<String, dynamic>),
      ],
      nextCursor: j['nextCursor'] as String?,
      total: (j['total'] as num?)?.toInt() ?? 0,
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
      final res = await _api.postJson(
        ApiEndpoints.plots,
        {
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
        },
      );
      if (res.statusCode >= 300) {
        throw Exception('บันทึกแปลงไม่สำเร็จ: ${_errorDetail(res)}');
      }
      return Parcel.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
    }
    final local = Parcel(
      id: 'local-${DateTime.now().millisecondsSinceEpoch}',
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
        if (photos.isNotEmpty) 'photos': photos,
      },
    );
    if (draft) await _saveDraft(local);
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
    final res = await _api.patchJson(ApiEndpoints.plot(id), {
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
    });
    if (res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    throw Exception('บันทึกไม่สำเร็จ: ${_errorDetail(res)}');
  }

  /// ส่งคำขออัปเดตแปลง (เมนู ⋮ → คำขอ1/2/กลุ่ม) —
  /// `POST /plots/:id/requests` body = {kind, value?, ...fields}
  /// TODO(backend): endpoint ยังไม่มี — shape ตาม
  /// docs/API_CONTRACT.md; ตอนนี้ call แล้วจะเจอ 404 โชว์บน UI
  /// ซื่อสัตย์ เมื่อ backend เขียนเสร็จใช้ได้ทันที ไม่ต้องแก้แอป
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
  /// แล้วเก็บ payload ลงเครื่อง (ออฟไลน์ใช้ต่อได้) คืนจำนวนจุดที่ได้
  /// TODO(backend): endpoint ยังไม่มี — ตอนนี้จะเจอ 404 โชว์ซื่อสัตย์
  Future<int> downloadRiskPoints() async {
    if (!ApiConfig.enabled || _api == null) {
      throw Exception('ออฟไลน์อยู่ — ดาวน์โหลดไม่ได้');
    }
    final res = await _api.get(ApiEndpoints.riskPoints);
    if (res.statusCode != 200) {
      throw Exception('ดาวน์โหลดไม่สำเร็จ: ${_errorDetail(res)}');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('risk_points', res.body);
    final items = jsonDecode(res.body);
    if (items is List) return items.length;
    final list = (items as Map<String, dynamic>)['items'];
    return list is List ? list.length : 0;
  }

  /// Extension officers for the caretaker dropdown.
  /// Backend-ready: will list officer accounts once an endpoint
  /// exists; until then returns a placeholder list.
  Future<List<String>> fetchOfficers() async {
    if (ApiConfig.enabled && _api != null) {
      try {
        final res = await _api.get(ApiEndpoints.officers);
        if (res.statusCode == 200) {
          final items = jsonDecode(res.body)['items'] as List;
          return [
            for (final j in items)
              (j as Map<String, dynamic>)['displayName'] as String,
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
          final items = jsonDecode(res.body)['items'] as List;
          return [
            for (final j in items)
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
  Future<FormOptions> fetchOptions() async {
    if (ApiConfig.enabled && _api != null) {
      try {
        final res = await _api.get(ApiEndpoints.metaOptions);
        if (res.statusCode == 200) {
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
  Future<List<PlotRequestEntry>> fetchPlotRequests() async {
    if (!ApiConfig.enabled || _api == null) return const [];
    final res = await _api.get(ApiEndpoints.plotRequests);
    if (res.statusCode != 200) {
      throw Exception('โหลดรายการคำขอไม่สำเร็จ: ${_errorDetail(res)}');
    }
    final items = jsonDecode(res.body)['items'] as List? ?? const [];
    return [
      for (final j in items)
        PlotRequestEntry.fromJson(j as Map<String, dynamic>),
    ];
  }
}

/// หน้าข้อมูลแปลง + ธง truncated จาก backend — viewport fetch ที่ตัด
/// ข้อมูลไม่ครบต้องไม่ถูกจำว่า "ครอบคลุมกรอบนั้น"
typedef ParcelPage = ({List<Parcel> items, bool truncated});

/// หน้ารายการแปลง (list) — nextCursor สำหรับ "โหลดเพิ่ม"
/// null = หมดแล้ว; total = จำนวนรวมทั้งหมดตามฟิลเตอร์
typedef PlotPage = ({
  List<PlotListItem> items,
  String? nextCursor,
  int total,
});

/// Decode /plots/map payload ใน background isolate — compute() ส่ง
/// เฉพาะ String ข้ามได้ แล้วคืน Parcel[] กลับมา
ParcelPage _parseParcelList(String body) {
  final j = jsonDecode(body) as Map<String, dynamic>;
  final items = j['items'] as List;
  return (
    items: [
      for (final x in items) Parcel.fromJson(x as Map<String, dynamic>),
    ],
    truncated: j['truncated'] == true,
  );
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

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:brr/core/config/api_config.dart';
import 'package:brr/core/config/api_endpoints.dart';
import 'package:brr/features/map/models/parcel.dart';
import 'package:brr/features/plot_activities/models/plot_list_item.dart';
import 'package:brr/core/services/api_client.dart';

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

  Future<void> _saveDraft(Parcel p) async {
    final prefs = await SharedPreferences.getInstance();
    final drafts = await _loadDrafts();
    drafts.add(p);
    await prefs.setString(
      _draftsKey,
      jsonEncode([for (final d in drafts) d.toJson()]),
    );
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
  }) async {
    // Draft = save on device only, never posts to the backend.
    if (!draft && ApiConfig.enabled && _api != null) {
      final res = await _api.postJson(
        ApiEndpoints.plots,
        {
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
          'points': [
            for (final p in points)
              {'latitude': p.latitude, 'longitude': p.longitude},
          ],
        },
      );
      if (res.statusCode >= 300) {
        throw Exception('บันทึกแปลงไม่สำเร็จ (${res.statusCode})');
      }
      return Parcel.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
    }
    final local = Parcel(
      id: 'local-${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      points: points,
      productionYear: productionYear,
      isDraft: draft,
    );
    if (draft) await _saveDraft(local);
    return local;
  }

  /// อัปเดต meta ของแปลง — PATCH /plots/:id คืน detail ล่าสุด
  /// (ใช้หน้า "แก้ไข รูท & ลำดับ" เป็นหลัก)
  Future<Map<String, dynamic>?> updateParcelMeta(
    String id, {
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
    throw Exception('บันทึกไม่สำเร็จ (${res.statusCode})');
  }

  /// ส่งคำขออัปเดตแปลง (เมนู ⋮ → คำขอ1/2) — `POST /plots/:id/requests`
  /// TODO(backend): endpoint ยังไม่มี — shape ตาม
  /// docs/API_CONTRACT.md; ตอนนี้ call แล้วจะเจอ 404 โชว์บน UI
  /// ซื่อสัตย์ เมื่อ backend เขียนเสร็จใช้ได้ทันที ไม่ต้องแก้แอป
  Future<void> submitPlotRequest(
    String id, {
    required String kind,
    required String value,
  }) async {
    if (!ApiConfig.enabled || _api == null) {
      throw Exception('ออฟไลน์อยู่ — ส่งคำขอไม่ได้');
    }
    final res = await _api.postJson('${ApiEndpoints.plot(id)}/requests', {
      'kind': kind,
      'value': value,
    });
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception('ส่งคำขอไม่สำเร็จ (${res.statusCode})');
    }
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

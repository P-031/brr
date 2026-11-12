import 'dart:convert';

import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:brr/core/config/api_config.dart';
import 'package:brr/features/map/models/parcel.dart';
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
  static const _box = 'west=97&south=5&east=106&north=21';

  /// SharedPreferences key holding device-only draft parcels.
  static const _draftsKey = 'draft_parcels';

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

  Future<List<Parcel>> fetchParcels() async {
    if (ApiConfig.enabled && _api != null) {
      final res = await _api.get('/plots/map?$_box');
      if (res.statusCode != 200) {
        throw Exception('โหลดข้อมูลพื้นที่ไม่สำเร็จ (${res.statusCode})');
      }
      final items = jsonDecode(res.body)['items'] as List;
      return [
        ...items.map((j) => Parcel.fromJson(j as Map<String, dynamic>)),
        ...await _loadDrafts(),
      ];
    }
    // Mock — used only when the backend is disabled.
    return [..._mockParcels, ...await _loadDrafts()];
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
        '/plots',
        {
          'name': name,
          'variety': variety,
          // TODO: send productionYear/officerName/project/farmerName/
          // caneGroup/location fields/rootNo/sequenceNo when the
          // schema supports them.
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
      isDraft: draft,
    );
    if (draft) await _saveDraft(local);
    return local;
  }

  /// Extension officers for the caretaker dropdown.
  /// Backend-ready: will list officer accounts once an endpoint
  /// exists; until then returns a placeholder list.
  Future<List<String>> fetchOfficers() async {
    if (ApiConfig.enabled && _api != null) {
      try {
        final res = await _api.get('/accounts?role=officer');
        if (res.statusCode == 200) {
          final items = jsonDecode(res.body)['items'] as List;
          return [
            for (final j in items)
              (j as Map<String, dynamic>)['displayName'] as String,
          ];
        }
      } catch (_) {}
    }
    return const [];
  }

  /// Farmers for the dropdown — same backend-ready pattern as
  /// [fetchOfficers].
  Future<List<String>> fetchFarmers() async {
    if (ApiConfig.enabled && _api != null) {
      try {
        final res = await _api.get('/accounts?role=farmer');
        if (res.statusCode == 200) {
          final items = jsonDecode(res.body)['items'] as List;
          return [
            for (final j in items)
              (j as Map<String, dynamic>)['displayName'] as String,
          ];
        }
      } catch (_) {}
    }
    return const [];
  }

  /// Sugarcane collectives (กลุ่มบำรุง) — placeholder until a backend
  /// endpoint exists.
  Future<List<String>> fetchCaneGroups() async {
    if (ApiConfig.enabled && _api != null) {
      try {
        final res = await _api.get('/cane-groups');
        if (res.statusCode == 200) {
          final items = jsonDecode(res.body)['items'] as List;
          return [for (final j in items) '${j['name']}'];
        }
      } catch (_) {}
    }
    return const [];
  }
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

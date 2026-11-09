import 'dart:convert';

import 'package:latlong2/latlong.dart';

import '../config/api_config.dart';
import '../models/parcel.dart';
import 'api_client.dart';

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

  Future<List<Parcel>> fetchParcels() async {
    if (ApiConfig.enabled && _api != null) {
      final res = await _api.get('/plots/map?$_box');
      if (res.statusCode != 200) {
        throw Exception('โหลดข้อมูลพื้นที่ไม่สำเร็จ (${res.statusCode})');
      }
      final items = jsonDecode(res.body)['items'] as List;
      return items
          .map((j) => Parcel.fromJson(j as Map<String, dynamic>))
          .toList();
    }
    // Mock — used only when the backend is disabled.
    return _mockParcels;
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

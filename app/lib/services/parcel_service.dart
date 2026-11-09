import 'dart:convert';

import 'package:latlong2/latlong.dart';

import '../config/api_config.dart';
import '../models/parcel.dart';
import 'api_client.dart';

/// Data layer for land parcels.
///
/// When [ApiConfig.enabled] is on, coordinates come from the backend
/// (`GET /api/v1/parcels`, Bearer token via [ApiClient]).
/// Until then it serves mock parcels around Buriram so the map screen
/// can be built and tested.
class ParcelService {
  ParcelService([ApiClient? api]) : _api = api;

  final ApiClient? _api;

  Future<List<Parcel>> fetchParcels() async {
    if (ApiConfig.enabled && _api != null) {
      final res = await _api.get('/api/v1/parcels');
      if (res.statusCode != 200) {
        throw Exception('โหลดข้อมูลพื้นที่ไม่สำเร็จ (${res.statusCode})');
      }
      return (jsonDecode(res.body) as List)
          .map((j) => Parcel.fromJson(j as Map<String, dynamic>))
          .toList();
    }
    // Mock — remove once the backend is live.
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

import 'package:latlong2/latlong.dart';

/// แปลง `outline`/`points` จาก backend เป็นรายการพิกัด — รับได้หลาย
/// shape เพราะ endpoint ต่างกันส่งคนละรูปแบบ:
/// - `/plots/map` + `/plots/:id` → `[{latitude, longitude}, ...]`
/// - `/plots` (list) → GeoJSON `{type:'Polygon', coordinates:[[[lng,lat]...]]}`
///   (MultiPolygon ใช้ชิ้นแรก) — ไม่รองรับทั้งสองจะทำแปลงหลุดเงียบๆ
/// - พิกัดเสีย/field ผิดชนิด → ข้ามตัวนั้น ไม่ล้มทั้งแปลง
List<LatLng> outlineLatLngs(Object? raw) {
  final points = <LatLng>[];

  void addMap(Object? c) {
    if (c is Map && c['latitude'] is num && c['longitude'] is num) {
      points.add(
        LatLng(
          (c['latitude'] as num).toDouble(),
          (c['longitude'] as num).toDouble(),
        ),
      );
    }
  }

  void addPair(Object? c) {
    // GeoJSON เรียง [longitude, latitude]
    if (c is List && c.length >= 2 && c[0] is num && c[1] is num) {
      points.add(LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()));
    }
  }

  if (raw is List) {
    for (final c in raw) {
      addMap(c);
      addPair(c);
    }
    return points;
  }

  if (raw is Map) {
    // Feature wrapper → แกะ geometry ออกมาจัดการต่อ
    if (raw['type'] == 'Feature' && raw['geometry'] is Map) {
      return outlineLatLngs(raw['geometry']);
    }
    final coords = raw['coordinates'];
    if (raw['type'] == 'Polygon' && coords is List) {
      // coordinates[0] = วงนอก (holes ไม่เอา — thumbnail/polygon เดียวพอ)
      if (coords.isNotEmpty && coords.first is List) {
        for (final c in coords.first as List) {
          addPair(c);
        }
      }
    } else if (raw['type'] == 'MultiPolygon' && coords is List) {
      final firstPoly = coords.isNotEmpty ? coords.first : null;
      if (firstPoly is List &&
          firstPoly.isNotEmpty &&
          firstPoly.first is List) {
        for (final c in firstPoly.first as List) {
          addPair(c);
        }
      }
    }
  }
  return points;
}

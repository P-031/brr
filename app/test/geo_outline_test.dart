import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:brr/features/map/models/geo_outline.dart';

/// เทียบ LatLng ทีละฟิลด์ — latlong2 ไม่ได้ override ==
void expectPoint(LatLng p, double lat, double lng) {
  expect(p.latitude, closeTo(lat, 1e-9));
  expect(p.longitude, closeTo(lng, 1e-9));
}

void main() {
  group('outlineLatLngs', () {
    test('list of {latitude, longitude} maps — shape จาก /plots/map', () {
      final pts = outlineLatLngs([
        {'latitude': 14.0, 'longitude': 100.5},
        {'latitude': 14.1, 'longitude': 100.6},
      ]);
      expect(pts.length, 2);
      expectPoint(pts[0], 14.0, 100.5);
      expectPoint(pts[1], 14.1, 100.6);
    });

    test('GeoJSON Polygon — คู่พิกัดเรียง [lng, lat] ต้องสลับ', () {
      final pts = outlineLatLngs({
        'type': 'Polygon',
        'coordinates': [
          [
            [100.5, 14.0],
            [100.6, 14.1],
            [100.7, 14.2],
          ],
        ],
      });
      expect(pts.length, 3);
      expectPoint(pts.first, 14.0, 100.5);
      expectPoint(pts.last, 14.2, 100.7);
    });

    test('Feature wrapper — แกะ geometry ออกมา parse ต่อ', () {
      final pts = outlineLatLngs({
        'type': 'Feature',
        'properties': {},
        'geometry': {
          'type': 'Polygon',
          'coordinates': [
            [
              [100.5, 14.0],
              [100.6, 14.1],
            ],
          ],
        },
      });
      expect(pts.length, 2);
      expectPoint(pts[0], 14.0, 100.5);
      expectPoint(pts[1], 14.1, 100.6);
    });

    test('MultiPolygon — ใช้ชิ้นแรก', () {
      final pts = outlineLatLngs({
        'type': 'MultiPolygon',
        'coordinates': [
          [
            [
              [100.5, 14.0],
              [100.6, 14.1],
            ],
          ],
          [
            [
              [200.5, 24.0],
              [200.6, 24.1],
            ],
          ],
        ],
      });
      expect(pts.length, 2);
      expectPoint(pts[0], 14.0, 100.5);
      expectPoint(pts[1], 14.1, 100.6);
    });

    test('list of [lng, lat] pairs — pair shape ตรงๆ ก็รับ', () {
      final pts = outlineLatLngs([
        [100.5, 14.0],
        [100.6, 14.1],
      ]);
      expect(pts.length, 2);
      expectPoint(pts[0], 14.0, 100.5);
      expectPoint(pts[1], 14.1, 100.6);
    });

    test('entry เสียข้ามตัวนั้น — ไม่ล้มทั้งแปลง', () {
      final pts = outlineLatLngs([
        {'latitude': 14.0, 'longitude': 100.5},
        {'latitude': 'bad', 'longitude': 100.6},
        'garbage',
        {'latitude': 14.1},
        42,
        {'latitude': 14.2, 'longitude': 100.7},
      ]);
      expect(pts.length, 2);
      expectPoint(pts[0], 14.0, 100.5);
      expectPoint(pts[1], 14.2, 100.7);
    });

    test('null/ว่าง/ชนิดผิด → list ว่าง', () {
      expect(outlineLatLngs(null), isEmpty);
      expect(outlineLatLngs([]), isEmpty);
      expect(outlineLatLngs('text'), isEmpty);
      expect(outlineLatLngs({'type': 'Point', 'coordinates': []}), isEmpty);
      expect(outlineLatLngs({'type': 'Polygon', 'coordinates': null}), isEmpty);
    });

    test('Polygon ที่มี hole — เอาเฉพาะวงนอก', () {
      final pts = outlineLatLngs({
        'type': 'Polygon',
        'coordinates': [
          // วงนอก
          [
            [100.5, 14.0],
            [100.6, 14.1],
          ],
          // hole — ต้องไม่ถูกรวม
          [
            [100.55, 14.05],
            [100.56, 14.06],
          ],
        ],
      });
      expect(pts.length, 2);
    });
  });
}

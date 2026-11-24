import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:brr/features/map/models/parcel.dart';

Map<String, dynamic> baseJson() => {
  'id': 123,
  'name': 'แปลงทดสอบ #42',
  'outline': [
    {'latitude': 14.0, 'longitude': 100.0},
    {'latitude': 14.001, 'longitude': 100.0},
    {'latitude': 14.001, 'longitude': 100.001},
  ],
};

void main() {
  group('Parcel.fromJson', () {
    test('parses outline points and id/name from non-string values', () {
      final p = Parcel.fromJson(baseJson());
      expect(p.id, '123');
      expect(p.name, 'แปลงทดสอบ #42');
      expect(p.points.length, 3);
      expect(p.points.first.latitude, 14.0);
    });

    test('falls back to points key when outline is absent', () {
      final j = baseJson()
        ..remove('outline')
        ..['points'] = [
          {'latitude': 15.0, 'longitude': 101.0},
        ];
      final p = Parcel.fromJson(j);
      expect(p.points.length, 1);
      expect(p.points.first.longitude, 101.0);
    });

    test('skips malformed coordinate entries instead of failing', () {
      final j = baseJson()
        ..['outline'] = [
          {'latitude': 14.0, 'longitude': 100.0},
          'garbage',
          {'latitude': 'not-a-num', 'longitude': 100.0},
          {'latitude': 14.1}, // missing longitude
          {'latitude': 14.2, 'longitude': 100.2},
        ];
      final p = Parcel.fromJson(j);
      expect(p.points.length, 2);
    });

    test('tolerates wrong types for farmer/meta/center', () {
      final j = baseJson()
        ..['farmer'] = 'should-be-map'
        ..['meta'] = ['not', 'a', 'map']
        ..['center'] = 7;
      final p = Parcel.fromJson(j);
      expect(p.owner, isNull);
      expect(p.meta, isNull);
      expect(p.centerOverride, isNull);
    });

    test('empty productionYear normalizes to null', () {
      final j = baseJson()..['meta'] = {'productionYear': ''};
      expect(Parcel.fromJson(j).productionYear, isNull);

      j['meta'] = {'productionYear': '2567'};
      expect(Parcel.fromJson(j).productionYear, '2567');
    });

    test('owner comes from farmer.displayName', () {
      final j = baseJson()..['farmer'] = {'displayName': 'นายทดสอบ'};
      expect(Parcel.fromJson(j).owner, 'นายทดสอบ');
    });

    test('centerOverride only when both coords are numeric', () {
      var j = baseJson()..['center'] = {'latitude': 14.5, 'longitude': 100.5};
      expect(Parcel.fromJson(j).centerOverride!.latitude, 14.5);

      j = baseJson()..['center'] = {'latitude': 'x', 'longitude': 100.5};
      expect(Parcel.fromJson(j).centerOverride, isNull);
    });

    test('isDraft only true for literal true', () {
      expect(Parcel.fromJson(baseJson()).isDraft, isFalse);
      expect(
        Parcel.fromJson(baseJson()..['isDraft'] = 'true').isDraft,
        isFalse,
      );
      expect(Parcel.fromJson(baseJson()..['isDraft'] = true).isDraft, isTrue);
    });
  });

  group('Parcel helpers', () {
    test('landNo strips trailing #NNN, plotCode extracts it', () {
      final p = Parcel(id: '1', name: 'แปลงเหนือ #123', points: const []);
      expect(p.landNo, 'แปลงเหนือ');
      expect(p.plotCode, '123');
    });

    test('name without code returns null plotCode', () {
      const p = Parcel(id: '1', name: 'แปลงกลาง', points: []);
      expect(p.plotCode, isNull);
      expect(p.landNo, 'แปลงกลาง');
    });

    test('center averages points when no override', () {
      const p = Parcel(
        id: '1',
        name: 'x',
        points: [LatLng(14.0, 100.0), LatLng(14.2, 100.4)],
      );
      expect(p.center.latitude, closeTo(14.1, 1e-9));
      expect(p.center.longitude, closeTo(100.2, 1e-9));
    });

    test('formatThaiArea carries ตร.วา over the งาน boundary', () {
      // 99.6 ตร.วา → round เป็น 100 → carry ขึ้น 1 งาน
      expect(Parcel.formatThaiArea(99.6 * 4), '0 ไร่ 1 งาน 0 ตร.วา');
      expect(Parcel.formatThaiArea(1600), '1 ไร่ 0 งาน 0 ตร.วา');
    });

    test('intersectsBox rejects parcels fully outside the frame', () {
      const p = Parcel(
        id: '1',
        name: 'x',
        points: [LatLng(14.0, 100.0), LatLng(14.1, 100.1)],
      );
      expect(p.intersectsBox(100.2, 14.2, 100.3, 14.3), isFalse);
      expect(p.intersectsBox(99.9, 13.9, 100.15, 14.15), isTrue);
    });
  });
}

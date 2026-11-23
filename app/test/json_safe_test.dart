import 'package:flutter_test/flutter_test.dart';

import 'package:brr/core/utils/json_safe.dart';

void main() {
  group('toDoubleOrNull', () {
    test('num ผ่านตรง / string ตัวเลข parse ได้', () {
      expect(toDoubleOrNull(3.5), 3.5);
      expect(toDoubleOrNull(7), 7.0);
      expect(toDoubleOrNull('12.25'), 12.25);
    });

    test('ค่าที่ parse ไม่ได้คืน null ไม่ throw', () {
      expect(toDoubleOrNull('abc'), isNull);
      expect(toDoubleOrNull(null), isNull);
      expect(toDoubleOrNull([1, 2]), isNull);
      expect(toDoubleOrNull({'a': 1}), isNull);
    });
  });

  group('toIntOrNull', () {
    test('num/string ตัวเลข parse ได้', () {
      expect(toIntOrNull(4), 4);
      expect(toIntOrNull(4.7), 4);
      expect(toIntOrNull('42'), 42);
    });

    test('ค่าที่ parse ไม่ได้คืน null', () {
      expect(toIntOrNull('x'), isNull);
      expect(toIntOrNull(null), isNull);
    });
  });

  group('asStringMap', () {
    test('Map ผ่าน / ชนิดอื่นคืน null', () {
      final m = <String, dynamic>{'a': 1};
      expect(asStringMap(m), same(m));
      expect(asStringMap(<int, int>{1: 2}), isNull);
      expect(asStringMap('str'), isNull);
      expect(asStringMap(null), isNull);
    });
  });
}

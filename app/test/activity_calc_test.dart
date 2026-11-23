import 'package:flutter_test/flutter_test.dart';

import 'package:brr/features/map/models/activity_calc.dart';

void main() {
  group('rateOf', () {
    test('empty/null/garbage parses to 0', () {
      expect(rateOf(null), 0);
      expect(rateOf(''), 0);
      expect(rateOf('abc'), 0);
    });

    test('parses plain and decimal numbers', () {
      expect(rateOf('12'), 12);
      expect(rateOf('2.5'), 2.5);
    });
  });

  group('totalTons', () {
    test('yield per rai times area', () {
      expect(totalTons('12', 5), 60);
      expect(totalTons('0', 5), 0);
    });

    test('missing yield means zero tons', () {
      expect(totalTons(null, 10), 0);
      expect(totalTons('abc', 10), 0);
    });
  });

  group('actualTons', () {
    test('subtracts variety and cut losses', () {
      // 12 ตัน/ไร่ × 5 ไร่ = 60 − 3 − 2 = 55
      expect(actualTons('12', 5, cutVarietyTons: '3', cutLossTons: '2'), 55);
    });

    test('blank deductions count as zero', () {
      expect(actualTons('12', 5), 60);
      expect(actualTons('12', 5, cutVarietyTons: '', cutLossTons: 'x'), 60);
    });
  });

  group('totalFertilizerRate', () {
    test('base rate plus every round', () {
      expect(totalFertilizerRate('50', ['10', '20', '30']), 110);
    });

    test('empty base and unparseable rounds are zero', () {
      expect(totalFertilizerRate(null, const []), 0);
      expect(totalFertilizerRate('', [null, 'x', '5']), 5);
    });
  });
}

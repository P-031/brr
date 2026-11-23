import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';

import 'package:brr/core/widgets/digit_formatter.dart';

String fmt(String input, {bool decimal = false}) =>
    DigitFormatter(decimal: decimal)
        .formatEditUpdate(TextEditingValue.empty, TextEditingValue(text: input))
        .text;

void main() {
  group('DigitFormatter', () {
    test('keeps ASCII digits', () {
      expect(fmt('12345'), '12345');
    });

    test('converts Thai digits ๐-๙ to ASCII', () {
      expect(fmt('๐๑๒๓๔๕๖๗๘๙'), '0123456789');
      // ตัวอักษรไทยที่ไม่ใช่แถวตัวเลข Kedmanee ถูกตัดทิ้ง
      expect(fmt('ไร่ละ๑๒'), '12');
    });

    test('maps Kedmanee digit-row letters to digits', () {
      // ปุ่มตำแหน่งเดียวกับเลขบนแป้นไทย — ผู้ใช้ลืมเปลี่ยนภาษา
      expect(fmt('ภถุ'), '456'); // 4 5 6
      expect(fmt('ๅ/-ภถุึคตจ'), '1234567890');
    });

    test('strips letters and symbols', () {
      expect(fmt('abc12.5xyz'), '125');
      expect(fmt('1,2,3'), '123');
      // '-' อยู่แถวตัวเลข Kedmanee (ปุ่ม 3) → แปลงเป็นเลขไม่ใช่ตัด
      expect(fmt('1-2-3'), '13233');
    });

    test('allows one decimal point when decimal: true', () {
      expect(fmt('1.25', decimal: true), '1.25');
      expect(fmt('1.2.5', decimal: true), '1.25'); // จุดแรกอยู่ จุดสองตัด
      expect(fmt('..', decimal: true), '.');
    });

    test('strips dots when decimal: false', () {
      expect(fmt('1.25'), '125');
    });

    test('keeps newValue when text survives the filter unchanged', () {
      const v = TextEditingValue(
        text: '123',
        selection: TextSelection.collapsed(offset: 1),
      );
      final out = const DigitFormatter().formatEditUpdate(
        TextEditingValue.empty,
        v,
      );
      expect(identical(out, v), isTrue);
    });
  });
}

import 'package:flutter/services.dart';

/// แปลงเลขไทย ๐-๙ เป็นอารบิกแล้วตัดตัวอื่นทิ้ง ทำให้ช่องตัวเลข
/// พิมพ์ได้ไม่ว่าแป้นจะอยู่โหมดไหน — ใช้ร่วมกันทุกช่องตัวเลขในแอป
class DigitFormatter extends TextInputFormatter {
  const DigitFormatter({this.decimal = false});

  /// true = อนุญาตจุดทศนิยม 1 จุด (ไร่สูญเสีย/เป้าผลผลิต/อัตราปุ๋ย)
  final bool decimal;

  static const _thai = '๐๑๒๓๔๕๖๗๘๙';

  /// แป้นไทย Kedmanee — อักขระที่แถวตัวเลขพิมพ์ออกมาโดยไม่กด Shift
  /// จับคู่กับเลขตาม "ตำแหน่งปุ่ม" (กดปุ่ม 4 ได้ ภ = ตั้งใจพิมพ์ 4)
  static const _kedmanee = {
    'ๅ': '1',
    '/': '2',
    '-': '3',
    'ภ': '4',
    'ถ': '5',
    'ุ': '6',
    'ึ': '7',
    'ค': '8',
    'ต': '9',
    'จ': '0',
  };

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final sb = StringBuffer();
    var hasDot = false;
    for (final r in newValue.text.runes) {
      final ch = String.fromCharCode(r);
      final ti = _thai.indexOf(ch);
      if (ti >= 0) {
        sb.write(ti);
        continue;
      }
      final kd = _kedmanee[ch];
      if (kd != null) {
        sb.write(kd);
        continue;
      }
      if (r >= 0x30 && r <= 0x39) {
        sb.write(ch);
        continue;
      }
      if (decimal && !hasDot && ch == '.') {
        hasDot = true;
        sb.write('.');
      }
    }
    final text = sb.toString();
    // ข้อความผ่าน filter แล้วเหมือนเดิม (เช่น พิมพ์เลขอารบิกกลาง
    // ประโยค) → คืน newValue เลย cursor ไม่ดีดไปท้ายทุกครั้ง
    if (text == newValue.text) return newValue;
    // มีตัวที่ถูกตัด/แปลง — วาง cursor หลังตัวสุดท้ายที่ผ่าน filter
    // ก่อนจุด cursor เดิม (run substring เดิมผ่าน formatter เดียวกัน)
    final cursorEnd = newValue.selection.end.clamp(0, newValue.text.length);
    final keptLen = formatEditUpdate(
      oldValue,
      TextEditingValue(text: newValue.text.substring(0, cursorEnd)),
    ).text.length;
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: keptLen.clamp(0, text.length)),
    );
  }
}

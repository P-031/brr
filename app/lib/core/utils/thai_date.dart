/// ชื่อเดือนไทย + formatter วันที่แชร์ทั้งแอป — เดิมแต่ละ view
/// ประกาศ const ซ้ำกันเอง (ฝาแฝด 4 จุด) แก้ทีเดียวที่นี่
library;

/// ชื่อเดือนแบบย่อ — index 0 = มกราคม
const thaiMonthsShort = [
  'ม.ค.',
  'ก.พ.',
  'มี.ค.',
  'เม.ย.',
  'พ.ค.',
  'มิ.ย.',
  'ก.ค.',
  'ส.ค.',
  'ก.ย.',
  'ต.ค.',
  'พ.ย.',
  'ธ.ค.',
];

/// ชื่อเดือนแบบเต็ม — index 0 = มกราคม
const thaiMonths = [
  'มกราคม',
  'กุมภาพันธ์',
  'มีนาคม',
  'เมษายน',
  'พฤษภาคม',
  'มิถุนายน',
  'กรกฎาคม',
  'สิงหาคม',
  'กันยายน',
  'ตุลาคม',
  'พฤศจิกายน',
  'ธันวาคม',
];

/// "12 ม.ค. 2568" — ปีพุทธศักราช (+543)
String formatThaiDate(DateTime d) =>
    '${d.day} ${thaiMonthsShort[d.month - 1]} ${d.year + 543}';

/// "12 ม.ค. 2568 08:30 น." — วันที่ + เวลา 24 ชม.
String formatThaiDateTime(DateTime t) {
  final hm =
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  return '${formatThaiDate(t)} $hm น.';
}

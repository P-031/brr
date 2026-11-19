import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax/iconsax.dart';

import 'package:brr/core/theme/app_theme.dart';

/// เลือกวันที่แบบปฏิทิน แสดงปีเป็น พ.ศ. — เด้งกลางจอ
/// (showDatePicker ของ Flutter โชว์ ค.ศ. แม้ locale ไทย เลยทำเอง
/// หน้าตาเลียนแบบ Material picker: หัว "เลือกวันที่" + วันที่ใหญ่ +
/// dropdown เดือน/ปี + ตารางวัน + ปุ่ม ยกเลิก/ตกลง)
/// คืน DateTime ค.ศ. ที่เลือก หรือ null ถ้ายกเลิก
Future<DateTime?> showThaiDatePicker(
  BuildContext context, {
  DateTime? initialDate,
  DateTime? firstDate,
  DateTime? lastDate,
}) => showDialog<DateTime>(
  context: context,
  builder: (_) => _ThaiDatePickerDialog(
    initial: initialDate ?? DateTime.now(),
    first: firstDate ?? DateTime(2000),
    last: lastDate ?? DateTime.now().add(const Duration(days: 365)),
  ),
);

const _thaiMonths = [
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

const _thaiMonthsShort = [
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

/// วันในสัปดาห์ — index 0 = อาทิตย์ (weekday 7 → 0)
const _thaiDayNames = ['อา.', 'จ.', 'อ.', 'พ.', 'พฤ.', 'ศ.', 'ส.'];
const _thaiWeekdays = ['อา', 'จ', 'อ', 'พ', 'พฤ', 'ศ', 'ส'];

class _ThaiDatePickerDialog extends StatefulWidget {
  const _ThaiDatePickerDialog({
    required this.initial,
    required this.first,
    required this.last,
  });

  final DateTime initial;
  final DateTime first;
  final DateTime last;

  @override
  State<_ThaiDatePickerDialog> createState() => _ThaiDatePickerDialogState();
}

class _ThaiDatePickerDialogState extends State<_ThaiDatePickerDialog> {
  late DateTime _selected;
  late DateTime _visible; // วันที่ 1 ของเดือนที่แสดง

  @override
  void initState() {
    super.initState();
    _selected = widget.initial;
    _visible = DateTime(widget.initial.year, widget.initial.month);
  }

  bool _inRange(DateTime d) =>
      !d.isBefore(
        DateTime(widget.first.year, widget.first.month, widget.first.day),
      ) &&
      !d.isAfter(
        DateTime(widget.last.year, widget.last.month, widget.last.day),
      );

  void _shiftMonth(int delta) {
    var m = _visible.month + delta;
    var y = _visible.year;
    if (m < 1) {
      m = 12;
      y--;
    } else if (m > 12) {
      m = 1;
      y++;
    }
    if (DateTime(
          y,
          m,
        ).isBefore(DateTime(widget.first.year, widget.first.month)) ||
        DateTime(y, m).isAfter(DateTime(widget.last.year, widget.last.month))) {
      return;
    }
    setState(() => _visible = DateTime(y, m));
  }

  /// แตะหัวเดือน/ปี → popup เลือกเดือนกับปี พ.ศ. กระโดดได้เร็ว
  Future<void> _pickMonthYear() async {
    final picked = await showDialog<DateTime>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 420, maxWidth: 340),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'เลือกเดือนและปี',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (var y = widget.last.year; y >= widget.first.year; y--)
                      ExpansionTile(
                        title: Text(
                          '${y + 543}',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: y == _visible.year
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: y == _visible.year
                                ? AppColors.green
                                : Colors.black87,
                          ),
                        ),
                        initiallyExpanded: y == _visible.year,
                        children: [
                          for (var m = 1; m <= 12; m++)
                            ListTile(
                              dense: true,
                              title: Text(
                                _thaiMonths[m - 1],
                                style: TextStyle(
                                  fontSize: 17,
                                  color:
                                      y == _visible.year && m == _visible.month
                                      ? AppColors.green
                                      : Colors.black87,
                                  fontWeight:
                                      y == _visible.year && m == _visible.month
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                              onTap: () =>
                                  Navigator.of(ctx).pop(DateTime(y, m)),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) setState(() => _visible = picked);
  }

  /// ดินสอ → popup พิมพ์วันที่เอง วว/ดด/ปปปป (ใส่ / อัตโนมัติ)
  /// รับ พ.ศ. (>=2400 ลบ 543) และ ค.ศ.
  Future<void> _editByText() async {
    final ctrl = TextEditingController(
      text:
          '${_selected.day.toString().padLeft(2, '0')}/'
          '${_selected.month.toString().padLeft(2, '0')}/'
          '${_selected.year + 543}',
    );
    final parsed = await showDialog<DateTime>(
      context: context,
      builder: (ctx) {
        void trySubmit() {
          final parts = ctrl.text.trim().split('/');
          if (parts.length != 3) return;
          final d = int.tryParse(parts[0]);
          final m = int.tryParse(parts[1]);
          var y = int.tryParse(parts[2]);
          if (d == null || m == null || y == null) return;
          if (y >= 2400) y -= 543;
          final dt = DateTime(y, m, d);
          if (dt.year != y || dt.month != m || dt.day != d || !_inRange(dt)) {
            return;
          }
          Navigator.of(ctx).pop(dt);
        }

        return AlertDialog(
          title: const Text(
            'กรอกวันที่',
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
          ),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: TextInputType.datetime,
            inputFormatters: [ThaiDateSlashFormatter()],
            onSubmitted: (_) => trySubmit(),
            style: const TextStyle(fontSize: 19),
            decoration: InputDecoration(
              hintText: 'วว/ดด/ปปปป (พ.ศ.)',
              hintStyle: const TextStyle(fontSize: 17),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('ยกเลิก', style: TextStyle(fontSize: 17)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.green),
              onPressed: trySubmit,
              child: const Text('ตกลง', style: TextStyle(fontSize: 17)),
            ),
          ],
        );
      },
    );
    if (parsed != null) {
      setState(() {
        _selected = parsed;
        _visible = DateTime(parsed.year, parsed.month);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final daysInMonth = DateUtils.getDaysInMonth(_visible.year, _visible.month);
    final leading = DateTime(_visible.year, _visible.month, 1).weekday % 7;
    final cells = leading + daysInMonth;

    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ---- หัว: "เลือกวันที่" + วันที่เลือกใหญ่ ----
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'เลือกวันที่',
                    style: TextStyle(fontSize: 14, color: Colors.black45),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${_thaiDayNames[_selected.weekday % 7]} '
                          '${_selected.day} '
                          '${_thaiMonthsShort[_selected.month - 1]} '
                          '${_selected.year + 543}',
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: _editByText,
                        icon: const Icon(
                          Iconsax.edit_2,
                          size: 26,
                          color: Colors.black45,
                        ),
                      ),
                      TextButton(
                        onPressed: () => setState(() {
                          // clamp เข้ากรอบ first/last — ไม่งั้น "วันนี้"
                          // เลือกวันนอกช่วงที่อนุญาตได้แล้วตกลงคืนค่าเพี้ยน
                          var t = DateTime.now();
                          if (!_inRange(t)) {
                            t = t.isBefore(widget.first)
                                ? widget.first
                                : widget.last;
                          }
                          _selected = t;
                          _visible = DateTime(t.year, t.month);
                        }),
                        child: const Text(
                          'วันนี้',
                          style: TextStyle(
                            fontSize: 18,
                            color: AppColors.green,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // ---- แถวเดือน/ปี + ลูกศรเลื่อนเดือน ----
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: _pickMonthYear,
                    icon: const Icon(
                      Iconsax.arrow_down_1,
                      size: 20,
                      color: Colors.black87,
                    ),
                    label: Text(
                      '${_thaiMonths[_visible.month - 1]} '
                      '${_visible.year + 543}',
                      style: const TextStyle(
                        fontSize: 19,
                        color: Colors.black87,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => _shiftMonth(-1),
                    icon: const Icon(
                      Iconsax.arrow_left_2,
                      size: 28,
                      color: Colors.black54,
                    ),
                  ),
                  IconButton(
                    onPressed: () => _shiftMonth(1),
                    icon: const Icon(
                      Iconsax.arrow_right_2,
                      size: 28,
                      color: Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
            // ---- หัวคอลัมน์วัน ----
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  for (final w in _thaiWeekdays)
                    Expanded(
                      child: Center(
                        child: Text(
                          w,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.black45,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            // ---- ตารางวัน ----
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  mainAxisSpacing: 4,
                  crossAxisSpacing: 4,
                ),
                itemCount: cells,
                itemBuilder: (_, i) {
                  final day = i - leading + 1;
                  if (day < 1) return const SizedBox.shrink();
                  final d = DateTime(_visible.year, _visible.month, day);
                  final enabled = _inRange(d);
                  final on =
                      d.year == _selected.year &&
                      d.month == _selected.month &&
                      d.day == _selected.day;
                  return InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: enabled ? () => setState(() => _selected = d) : null,
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: on ? AppColors.green : null,
                      ),
                      child: Text(
                        '$day',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: on ? FontWeight.bold : FontWeight.normal,
                          color: !enabled
                              ? Colors.black26
                              : on
                              ? Colors.white
                              : Colors.black87,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            // ---- ปุ่มล่าง: ยกเลิก / ตกลง ----
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text(
                      'ยกเลิก',
                      style: TextStyle(fontSize: 18, color: Colors.black54),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(_selected),
                    child: const Text(
                      'ตกลง',
                      style: TextStyle(
                        fontSize: 18,
                        color: AppColors.green,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// พิมพ์ตัวเลขติดกัน → ใส่ / ให้อัตโนมัติเป็น วว/ดด/ปปปป
/// (เก็บเฉพาะตัวเลข สูงสุด 8 หลัก) — ใช้ร่วมกันทุกช่องวันที่
class ThaiDateSlashFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final d = digits.length > 8 ? digits.substring(0, 8) : digits;
    final buf = StringBuffer();
    for (var i = 0; i < d.length; i++) {
      if (i == 2 || i == 4) buf.write('/');
      buf.write(d[i]);
    }
    final text = buf.toString();
    // cursor อยู่กลางข้อความ (แก้/ลบเลขข้างใน) — วาง cursor หลัง
    // ตำแหน่งเลขตัวเดิมก่อน cursor ไม่ใช่ดีดไปท้ายทุกครั้ง
    final digitsBefore = newValue.text
        .substring(0, newValue.selection.end.clamp(0, newValue.text.length))
        .replaceAll(RegExp(r'\D'), '')
        .length
        .clamp(0, 8);
    var cursor = digitsBefore;
    if (digitsBefore > 2) cursor++; // เลย / ตัวแรก
    if (digitsBefore > 4) cursor++; // เลย / ตัวสอง
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: cursor.clamp(0, text.length)),
    );
  }
}

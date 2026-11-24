import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import 'package:brr/core/theme/app_theme.dart';
import 'package:brr/core/widgets/digit_formatter.dart';
import 'package:brr/core/widgets/option_popup.dart';
import 'package:brr/core/widgets/thai_date_picker.dart';
import 'package:brr/features/map/widgets/unit_field.dart';

/// รอบการใส่ปุ๋ยหนึ่งรอบ — ค่าที่กรอกจาก [ FertRoundDialog ]
/// `npk` = ข้อความสูตรปุ๋ยที่แสดง (ชื่อสินค้า หรือ N-P-K)
class FertRound {
  FertRound({this.date, this.rate, this.npk, this.n, this.p, this.k});

  final DateTime? date;
  final String? rate;
  final String? npk;
  final String? n;
  final String? p;
  final String? k;
}

/// Dialog กรอกรอบใส่ปุ๋ย — วันที่ใส่ / อัตรา / สูตรปุ๋ย (เลือกจาก
/// `/meta/options → fertilizerFormulas` + "อื่น ๆ") + ช่อง N-P-K
/// เลือกสูตรที่มีรูปแบบ 15-5-30 ในชื่อจะเติม N/P/K ให้อัตโนมัติ
class FertRoundDialog extends StatefulWidget {
  const FertRoundDialog({
    super.key,
    required this.roundNo,
    required this.formulas,
  });

  final int roundNo;

  /// รายการสูตรปุ๋ยจาก backend — ว่างได้ถ้า /meta/options ยังไม่ส่ง
  final List<String> formulas;

  @override
  State<FertRoundDialog> createState() => _FertRoundDialogState();
}

class _FertRoundDialogState extends State<FertRoundDialog> {
  static const _other = 'อื่น ๆ';
  static final _npkRe = RegExp(r'(\d+)\s*-\s*(\d+)\s*-\s*(\d+)');

  final _rateCtrl = TextEditingController();
  final _nCtrl = TextEditingController();
  final _pCtrl = TextEditingController();
  final _kCtrl = TextEditingController();
  DateTime? _date;
  String? _formula;

  @override
  void dispose() {
    _rateCtrl.dispose();
    _nCtrl.dispose();
    _pCtrl.dispose();
    _kCtrl.dispose();
    super.dispose();
  }

  String _fmtThai(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/'
      '${d.year + 543}';

  Future<void> _pickDate() async {
    final picked = await showThaiDatePicker(
      context,
      initialDate: _date ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  Future<void> _pickFormula() async {
    final labels = [...widget.formulas, _other];
    final idx = await showOptionPopup(
      context,
      title: 'เลือกสูตรปุ๋ย',
      labels: labels,
      selectedIndex: _formula == null ? null : labels.indexOf(_formula!),
    );
    if (idx == null || !mounted) return;
    setState(() {
      _formula = labels[idx];
      // ชื่อสูตรที่มี N-P-K ในตัว เช่น "สูตร 15-5-30" → เติมช่องให้เลย
      final m = _npkRe.firstMatch(_formula!);
      if (m != null) {
        _nCtrl.text = m.group(1)!;
        _pCtrl.text = m.group(2)!;
        _kCtrl.text = m.group(3)!;
      }
    });
  }

  void _save() {
    String? nn(TextEditingController c) {
      final t = c.text.trim();
      return t.isEmpty ? null : t;
    }

    // ข้อความสูตรปุ๋ยที่แสดง: ชื่อสินค้าที่เลือก หรือ N-P-K จากช่อง
    // (ตัวเลือก "อื่น ๆ" → แสดงเป็นค่า N-P-K ที่กรอก)
    final npkCombo = [
      _nCtrl.text.trim(),
      _pCtrl.text.trim(),
      _kCtrl.text.trim(),
    ].join('-');
    String? npk;
    if (_formula == _other) {
      npk = npkCombo == '--' ? null : npkCombo;
    } else {
      npk = _formula ?? (npkCombo == '--' ? null : npkCombo);
    }
    Navigator.of(context).pop(
      FertRound(
        date: _date,
        rate: nn(_rateCtrl),
        npk: npk,
        n: nn(_nCtrl),
        p: nn(_pCtrl),
        k: nn(_kCtrl),
      ),
    );
  }

  /// ช่องแบบ dropdown ของ dialog — แตะแล้วเปิด picker
  Widget _pickerField(
    String hint,
    String? value,
    VoidCallback onTap, {
    IconData icon = Iconsax.arrow_circle_down,
  }) => InkWell(
    borderRadius: BorderRadius.circular(10),
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: value == null ? Colors.grey.shade300 : AppColors.green,
          width: value == null ? 1 : 1.5,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              value ?? hint,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 17,
                color: value == null ? Colors.black45 : Colors.black87,
              ),
            ),
          ),
          Icon(icon, size: 28, color: Colors.black87),
        ],
      ),
    ),
  );

  Widget _npkBox(String label, TextEditingController c) =>
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: c,
        builder: (_, v, _) => TextField(
          textAlign: TextAlign.start,
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: const [DigitFormatter(decimal: true)],
          style: const TextStyle(fontSize: 19),
          decoration: InputDecoration(
            labelText: label,
            labelStyle: const TextStyle(fontSize: 17),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: v.text.trim().isNotEmpty
                    ? AppColors.green
                    : Colors.grey.shade400,
                width: v.text.trim().isNotEmpty ? 1.5 : 1,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 13,
            ),
          ),
        ),
      );

  /// label อยู่บนช่อง (สไตล์เดียวกับฟอร์มหลัก)
  static const _dlgLabel = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: Colors.black87,
  );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      title: Text(
        'เพิ่มปุ๋ยครั้งที่ ${widget.roundNo}',
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
      ),
      content: SingleChildScrollView(
        child: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('วันที่ใส่', style: _dlgLabel),
              const SizedBox(height: 6),
              _pickerField(
                'เลือกวันที่',
                _date == null ? null : _fmtThai(_date!),
                _pickDate,
                icon: Icons.calendar_today,
              ),
              const SizedBox(height: 12),
              const Text('อัตรา(กก./ไร่)', style: _dlgLabel),
              const SizedBox(height: 6),
              UnitField(controller: _rateCtrl, unit: 'กก./ไร่'),
              const SizedBox(height: 12),
              const Text('สูตรปุ๋ย', style: _dlgLabel),
              const SizedBox(height: 6),
              _pickerField('เลือก', _formula, _pickFormula),
              const SizedBox(height: 14),
              const Text(
                'สูตรปุ๋ย NPK',
                style: TextStyle(fontSize: 17, color: Colors.black87),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _npkBox('N', _nCtrl)),
                  const SizedBox(width: 8),
                  Expanded(child: _npkBox('P', _pCtrl)),
                  const SizedBox(width: 8),
                  Expanded(child: _npkBox('K', _kCtrl)),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(
            'ยกเลิก',
            style: TextStyle(fontSize: 17, color: Colors.black54),
          ),
        ),
        TextButton(
          onPressed: _save,
          child: const Text(
            'บันทึก',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: AppColors.green,
            ),
          ),
        ),
      ],
    );
  }
}

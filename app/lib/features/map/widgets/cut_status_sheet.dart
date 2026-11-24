import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import 'package:brr/core/utils/thai_date.dart';
import 'package:brr/core/theme/app_theme.dart';
import 'package:brr/core/widgets/digit_formatter.dart';
import 'package:brr/core/widgets/thai_date_picker.dart';
import 'package:brr/features/map/models/parcel.dart';
import 'package:brr/features/map/viewmodels/parcel_detail_viewmodel.dart';

/// สี badge ต่อรหัสสถานะ — เรื่องการแสดงผลอยู่ฝั่งแอป;
/// code/ชื่อสถานะมาจาก backend (/meta/options → cutStatuses)
/// code ที่ไม่รู้จักใช้สีเทา
const _statusColors = {
  'N': Color(0xFF757575),
  'Y': Color(0xFFF57C00),
  'F': Color(0xFF2E7D32),
  'S': Color(0xFF1565C0),
};

/// Sheet "อัปเดตสถานะแปลงตัด" — เปิดจากการ์ดฟ้าใน info sheet:
/// เลือกสถานะ + วันที่เริ่ม/เสร็จ + ตัน — เก็บลงเครื่องรอ endpoint
/// pop คืน true เมื่อบันทึกสำเร็จ ให้ parent refresh badge การ์ด
Future<bool?> showCutStatusSheet(
  BuildContext context, {
  required ParcelDetailViewModel vm,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => Padding(
      // ดันเนื้อหาขึ้นเหนือคีย์บอร์ดตอนพิมพ์
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: _CutStatusSheet(vm: vm),
    ),
  );
}

class _CutStatusSheet extends StatefulWidget {
  const _CutStatusSheet({required this.vm});

  final ParcelDetailViewModel vm;

  @override
  State<_CutStatusSheet> createState() => _CutStatusSheetState();
}

class _CutStatusSheetState extends State<_CutStatusSheet> {
  /// ตัวเลือกสถานะจาก `/meta/options → cutStatuses` — ไม่ hardcode;
  /// ว่างเมื่อ backend ยังไม่ส่ง (แสดงข้อความแทน list)
  List<OptionItem> _items = const [];
  bool _loaded = false;
  String? _status;
  String? _statusCode;
  DateTime? _startDate;
  DateTime? _endDate;
  late final TextEditingController _estimateCtrl;
  final _cutCaneCtrl = TextEditingController(text: '0');
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // ประมาณตัน — prefill จาก targetYield ของแปลงถ้ามี
    _estimateCtrl = TextEditingController(
      text: '${widget.vm.parcel.meta?['targetYield'] ?? ''}',
    );
    _load();
  }

  /// โหลดตัวเลือกสถานะจาก backend + เติมค่าที่เคยบันทึกในเครื่อง
  /// — โหลดพังก็โชว์สถานะว่างแทนค้าง
  Future<void> _load() async {
    List<OptionItem> items = const [];
    Map<String, dynamic>? saved;
    try {
      items = (await widget.vm.loadOptions()).cutStatuses;
    } catch (_) {}
    try {
      saved = await widget.vm.cutStatus();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _items = items;
      _loaded = true;
      if (saved != null) {
        // จับคู่ด้วย code ก่อน ไม่เจอค่อยเทียบชื่อ — กัน backend
        // เปลี่ยน label แล้วค่าเก่าหลุด
        final code = '${saved['statusCode'] ?? ''}';
        final name = '${saved['status'] ?? ''}';
        for (final it in _items) {
          if ((code.isNotEmpty && it.code == code) ||
              (name.isNotEmpty && it.name == name)) {
            _status = it.name;
            _statusCode = it.code;
            break;
          }
        }
        _startDate = DateTime.tryParse('${saved['startDate']}');
        _endDate = DateTime.tryParse('${saved['endDate']}');
        final cut = '${saved['cutCaneTons'] ?? ''}';
        if (cut.isNotEmpty) _cutCaneCtrl.text = cut;
        final est = '${saved['estimateTons'] ?? ''}';
        if (est.isNotEmpty && _estimateCtrl.text.isEmpty) {
          _estimateCtrl.text = est;
        }
      }
    });
  }

  @override
  void dispose() {
    _estimateCtrl.dispose();
    _cutCaneCtrl.dispose();
    super.dispose();
  }

  String _fmt(DateTime d) => formatThaiDate(d);

  String? _iso(DateTime? d) => d == null
      ? null
      : '${d.year.toString().padLeft(4, '0')}-'
            '${d.month.toString().padLeft(2, '0')}-'
            '${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickDate(bool isStart) async {
    final current = isStart ? _startDate : _endDate;
    final picked = await showThaiDatePicker(
      context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && mounted) {
      setState(() => isStart ? _startDate = picked : _endDate = picked);
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_status == null) {
      // มีตัวเลือกจากระบบ → บังคับเลือกสถานะ; ไม่มีตัวเลือก →
      // อนุญาตบันทึกถ้ากรอกข้อมูลอื่นไว้แล้ว (วันที่/ตัน)
      final hasData =
          _startDate != null ||
          _endDate != null ||
          _estimateCtrl.text.trim().isNotEmpty ||
          (_cutCaneCtrl.text.trim().isNotEmpty &&
              _cutCaneCtrl.text.trim() != '0');
      if (_items.isNotEmpty || !hasData) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _items.isNotEmpty
                  ? 'กรุณาเลือกสถานะแปลง'
                  : 'กรุณากรอกข้อมูลอย่างน้อย 1 อย่าง',
            ),
          ),
        );
        return;
      }
    }
    setState(() => _saving = true);
    try {
      await widget.vm.saveCutStatus(
        status: _status ?? '',
        statusCode: _statusCode,
        startDate: _iso(_startDate),
        endDate: _iso(_endDate),
        estimateTons: _estimateCtrl.text.trim().isEmpty
            ? null
            : _estimateCtrl.text.trim(),
        cutCaneTons: _cutCaneCtrl.text.trim().isEmpty
            ? null
            : _cutCaneCtrl.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'.replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// แถวตัวเลือกสถานะ — วงกลม radio + badge รหัสสี + ชื่อ
  Widget _statusRow(int i) {
    final item = _items[i];
    final color = _statusColors[item.code] ?? Colors.grey.shade600;
    final selected = _status == item.name;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() {
          _status = item.name;
          _statusCode = item.code;
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.08) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? color : Colors.grey.shade300,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Center(
            child: Text(item.name, style: const TextStyle(fontSize: 16.5)),
          ),
        ),
      ),
    );
  }

  /// ช่องเลือกวันที่ — กรอบเทา + ไอคอนปฏิทิน เหมือนการ์ดกิจกรรม
  Widget _dateField(String hint, DateTime? value, bool isStart) => InkWell(
    borderRadius: BorderRadius.circular(10),
    onTap: () => _pickDate(isStart),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: value == null ? Colors.grey.shade300 : AppColors.green,
          width: value == null ? 1 : 1.5,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Iconsax.calendar_1,
            size: 22,
            color: value == null ? Colors.black38 : AppColors.green,
          ),
          const SizedBox(width: 10),
          Text(
            value == null ? hint : _fmt(value),
            style: TextStyle(
              fontSize: 16.5,
              color: value == null ? Colors.black38 : Colors.black87,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _label(String s) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      s,
      style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final p = widget.vm.parcel;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // หัว sheet — ไอคอน + ชื่อ + รหัสแปลง + ปุ่มปิด
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.sky.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Iconsax.row_vertical,
                  size: 22,
                  color: AppColors.sky,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'อัปเดตสถานะแปลงตัด',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.navy,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'แปลง: ${p.landNo}'
                      '${p.plotCode != null ? ' #${p.plotCode}' : ''}',
                      style: const TextStyle(
                        fontSize: 15.5,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Iconsax.close_circle, size: 28),
                color: Colors.black45,
              ),
            ],
          ),
          const SizedBox(height: 18),
          _label('สถานะแปลง'),
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Text(
              'เลือกสถานะแปลงได้ 1 รายการ',
              style: TextStyle(fontSize: 14, color: Colors.black45),
            ),
          ),
          if (!_loaded)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_items.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'ไม่มีข้อมูลสถานะแปลงจากระบบ',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: Colors.black45),
              ),
            )
          else
            for (var i = 0; i < _items.length; i++) _statusRow(i),
          const SizedBox(height: 16),
          _label('วันที่เริ่มตัด'),
          _dateField('เลือกวันที่เริ่มตัด', _startDate, true),
          const SizedBox(height: 14),
          _label('วันที่ตัดเสร็จ'),
          _dateField('เลือกวันที่ตัดเสร็จ', _endDate, false),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('ประมาณตัน'),
                    TextField(
                      textAlign: TextAlign.start,
                      controller: _estimateCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: const [DigitFormatter(decimal: true)],
                      style: const TextStyle(fontSize: 16.5),
                      decoration: InputDecoration(
                        isDense: true,
                        filled: true,
                        fillColor: Colors.grey.shade100,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 13,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: AppColors.green,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('เข้าหีบ (ตัน)'),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 13,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      // รอข้อมูลหีบจาก backend — โชว์ค่าเริ่มต้น
                      child: const Text(
                        '0.00 (0.0%)',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16.5, color: Colors.black54),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _label('ตัดพันธุ์อ้อย (ตัน)'),
          TextField(
            textAlign: TextAlign.start,
            controller: _cutCaneCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: const [DigitFormatter(decimal: true)],
            style: const TextStyle(fontSize: 16.5),
            decoration: InputDecoration(
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(
                  color: AppColors.green,
                  width: 1.5,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 13,
              ),
            ),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: BorderSide(color: Colors.grey.shade400),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(
                    'ยกเลิก',
                    style: TextStyle(fontSize: 17, color: Colors.black87),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.green,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Iconsax.save_2, size: 22),
                  label: Text(
                    _saving ? 'กำลังบันทึก…' : 'บันทึก',
                    style: const TextStyle(
                      fontSize: 17.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

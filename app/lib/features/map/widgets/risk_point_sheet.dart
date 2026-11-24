import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import 'package:brr/core/theme/app_theme.dart';
import 'package:brr/features/map/models/parcel.dart';
import 'package:brr/features/map/viewmodels/parcel_detail_viewmodel.dart';
import 'package:brr/core/utils/json_safe.dart';

/// (icon, พื้น, ขอบ/ตัวหนังสือ) ต่อประเภทจุดเสี่ยง — 3 สีต่างชัด
/// ตามโจทย์: น้ำท่วม=แดง, แห้งแล้ง=ส้ม, น้ำท่วม-แล้ง 50-50=เหลือง
/// backend ส่ง สูง/ปานกลาง/ต่ำ — map: สูง=น้ำท่วม กลาง=แล้ง ต่ำ=50-50
/// ชื่อใหม่จาก backend ที่ยังไม่รู้จักได้ชุดเทา generic
///
/// label จาก backend → ชื่อชนิดภัยที่แสดงบน chip จริง
String riskDisplayName(String name) {
  if (name.contains('สูง')) return 'น้ำท่วม';
  if (name.contains('กลาง')) return 'แห้งแล้ง';
  if (name.contains('ต่ำ')) return '50-50';
  return name;
}

(IconData, Color, Color) riskChipStyle(String name) {
  if (name.contains('ต่ำ')) {
    return (
      Icons.brightness_6,
      const Color(0xFFFFEB3B),
      const Color(0xFF7A5C00),
    );
  }
  if (name.contains('สูง')) {
    return (Icons.tsunami, const Color(0xFFFFCDD2), const Color(0xFFC62828));
  }
  if (name.contains('กลาง')) {
    return (Icons.wb_sunny, const Color(0xFFFFCC80), const Color(0xFFBF4D00));
  }
  if (name.contains('50')) {
    return (
      Icons.brightness_6,
      const Color(0xFFFFEB3B),
      const Color(0xFF7A5C00),
    );
  }
  if (name.contains('น้ำ')) {
    return (Icons.tsunami, const Color(0xFFFFCDD2), const Color(0xFFC62828));
  }
  if (name.contains('แล้ง')) {
    return (Icons.wb_sunny, const Color(0xFFFFCC80), const Color(0xFFBF4D00));
  }
  return (Iconsax.warning_2, const Color(0xFFE0E0E0), const Color(0xFF616161));
}

/// Sheet "กำหนดเป็นจุดเสี่ยงภัยพิบัติ" — เปิดจากการ์ดจุดเสี่ยงใน
/// info sheet: เลือกประเภท + ชื่อจุดเสี่ยง + ระดับ 1-5 + หมายเหตุ
/// pop คืน type ที่บันทึก (String) ให้ parent อัปเดตการ์ด preview
/// [initialType] = ประเภทที่เลือกมาจาก chip บนการ์ด preview
Future<String?> showRiskPointSheet(
  BuildContext context, {
  required ParcelDetailViewModel vm,
  String? initialType,
}) {
  return showModalBottomSheet<String>(
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
      child: _RiskPointSheet(vm: vm, initialType: initialType),
    ),
  );
}

class _RiskPointSheet extends StatefulWidget {
  const _RiskPointSheet({required this.vm, this.initialType});

  final ParcelDetailViewModel vm;
  final String? initialType;

  @override
  State<_RiskPointSheet> createState() => _RiskPointSheetState();
}

class _RiskPointSheetState extends State<_RiskPointSheet> {
  final _nameCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  // cache ไว้ตั้งแต่ init — ส่งใหม่เข้า FutureBuilder ทุก build จะ
  // ยิง /meta/options ซ้ำทุกครั้งที่ setState (กด chip/พิมพ์ช่อง)
  late final Future<FormOptions> _options = widget.vm.loadOptions();
  String? _type;
  int _severity = 3;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // ประเภทที่เลือกจาก chip การ์ด preview มีสิทธิ์ก่อนค่าเดิม
    _type = widget.initialType;
    // เติมค่าจากจุดเสี่ยงที่เคยบันทึกในเครื่อง
    widget.vm.riskPoint().then((r) {
      if (r == null || !mounted) return;
      setState(() {
        _type ??= '${r['type'] ?? ''}'.isEmpty ? null : '${r['type']}';
        _nameCtrl.text = '${r['name'] ?? ''}';
        _noteCtrl.text = '${r['note'] ?? ''}';
        _severity = toIntOrNull(r['severity']) ?? 3;
      });
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _needType() => showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Iconsax.warning_2, size: 56, color: Color(0xFFE65100)),
          const SizedBox(height: 14),
          const Text(
            'กรุณาเลือกประเภทจุดเสี่ยง',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.green),
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('ตกลง', style: TextStyle(fontSize: 16)),
            ),
          ),
        ],
      ),
    ),
  );

  Future<void> _save() async {
    if (_saving) return;
    if (_type == null) {
      _needType();
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.vm.saveRiskPoint(
        type: _type!,
        name: _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim(),
        severity: _severity,
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(_type);
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

  Widget _typeChip(String label) {
    final (icon, bg, fg) = riskChipStyle(label);
    final selected = _type == label;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _type = selected ? null : label),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: selected ? bg : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? fg : Colors.grey.shade300,
              width: selected ? 2.2 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 24, color: selected ? fg : Colors.black87),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.bold,
                    color: selected ? fg : Colors.black87,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// (พื้น, ขอบ/ตัวหนังสือ) ของปุ่มที่ถูกเลือก — สไตล์เดียวกับ
  /// chip ประเภทจุดเสี่ยง: ยังไม่เลือกประเภท = เทาปกติ
  (Color, Color) get _selColors => _type == null
      ? (const Color(0xFFEEEEEE), const Color(0xFF616161))
      : (riskChipStyle(_type!).$2, riskChipStyle(_type!).$3);

  Widget _severityBtn(int n) {
    final selected = _severity == n;
    final (bg, fg) = _selColors;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _severity = n),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            color: selected ? bg : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? fg : Colors.grey.shade300,
              width: selected ? 2.2 : 1,
            ),
          ),
          child: Text(
            '$n',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: selected ? fg : Colors.black87,
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _fieldDeco(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(fontSize: 16.5, color: Colors.black38),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: Colors.grey.shade300),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: _selColors.$2, width: 1.5),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
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
          // หัว sheet — ชื่อ + ข้อมูลแปลง + ปุ่มปิด
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'กำหนดเป็นจุดเสี่ยงภัยพิบัติ',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A237E),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'แปลง ${p.landNo}'
                      '${p.plotCode != null ? ' #${p.plotCode}' : ''}',
                      style: const TextStyle(
                        fontSize: 16.5,
                        color: Colors.black54,
                      ),
                    ),
                    Text(
                      '(${p.areaThai})',
                      style: const TextStyle(
                        fontSize: 16.5,
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
          const Divider(height: 26),
          const Text(
            'เลือกประเภทจุดเสี่ยง:',
            style: TextStyle(fontSize: 17.5, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          // ตัวเลือกประเภทจาก backend riskLevels
          FutureBuilder<FormOptions>(
            future: _options,
            builder: (context, snap) {
              // แสดงเป็นชื่อชนิดภัย + กลับลำดับ — น้ำท่วม(สูง)มาก่อน 50-50(ต่ำ)ท้าย
              final levels = [
                for (final l in snap.data?.riskLevels ?? const <String>[])
                  riskDisplayName(l),
              ].reversed.toList();
              if (levels.isEmpty) {
                return const Text(
                  'โหลดตัวเลือกไม่สำเร็จ',
                  style: TextStyle(fontSize: 15, color: Colors.black45),
                );
              }
              return Row(
                children: [
                  for (var i = 0; i < levels.length; i++) ...[
                    _typeChip(levels[i]),
                    if (i < levels.length - 1) const SizedBox(width: 10),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          const Text(
            'ชื่อจุดเสี่ยงภัย:',
            style: TextStyle(fontSize: 17.5, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          TextField(
            textAlign: TextAlign.start,
            controller: _nameCtrl,
            style: const TextStyle(fontSize: 17),
            decoration: _fieldDeco('เช่น น้ำท่วม - แปลง ...'),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'ระดับความรุนแรง (1 - 5):',
                  style: TextStyle(fontSize: 17.5, fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                'ระดับ $_severity',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _selColors.$2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (var i = 1; i <= 5; i++) ...[
                _severityBtn(i),
                if (i < 5) const SizedBox(width: 10),
              ],
            ],
          ),
          const SizedBox(height: 18),
          const Text(
            'หมายเหตุ / รายละเอียดเพิ่มเติม:',
            style: TextStyle(fontSize: 17.5, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          TextField(
            textAlign: TextAlign.start,
            controller: _noteCtrl,
            maxLines: 3,
            style: const TextStyle(fontSize: 17),
            decoration: _fieldDeco(
              'เช่น น้ำหลากจากคลองธรรมชาติช่วงฝนตกหนัก...',
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
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _selColors.$1,
                    foregroundColor: _selColors.$2,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: BorderSide(color: _selColors.$2, width: 2.2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: _saving ? null : _save,
                  child: Text(
                    _saving ? 'กำลังบันทึก…' : 'บันทึกจุดเสี่ยงภัย',
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

import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import 'package:brr/core/theme/app_theme.dart';
import 'package:brr/features/map/models/parcel.dart';
import 'package:brr/features/map/viewmodels/parcel_detail_viewmodel.dart';

const _lightGreen = Color(0xFFEAF4EA);

/// Sheet "ข้อมูลโครงการส่งเสริมแปลง" — เปิดจากการ์ดม่วงใน info sheet:
/// ติ๊กเลือกเกณฑ์ 6 ข้อ + แจ้งเตือนเมื่อเกณฑ์บังคับยังไม่ครบ
/// pop คืน true เมื่อบันทึกสำเร็จ ให้ parent refresh การ์ด
Future<bool?> showPlotProjectSheet(
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
    builder: (_) => _PlotProjectSheet(vm: vm),
  );
}

class _PlotProjectSheet extends StatefulWidget {
  const _PlotProjectSheet({required this.vm});

  final ParcelDetailViewModel vm;

  @override
  State<_PlotProjectSheet> createState() => _PlotProjectSheetState();
}

class _PlotProjectSheetState extends State<_PlotProjectSheet> {
  /// เกณฑ์จาก `/meta/options → projectCriteria` — ไม่ hardcode;
  /// ว่างเมื่อ backend ยังไม่ส่ง (แสดงข้อความแทน list)
  List<CriteriaItem> _items = const [];
  bool _loaded = false;
  final _selected = <int>{};
  bool _saving = false;

  /// ชื่อเกณฑ์บังคับ (required) ทั้งหมดตามลำดับ
  List<String> get _requiredNames => [
    for (final it in _items)
      if (it.required) it.name,
  ];

  /// ชื่อเกณฑ์บังคับที่ยังไม่ได้ติ๊ก
  List<String> get _missingRequired => [
    for (var i = 0; i < _items.length; i++)
      if (_items[i].required && !_selected.contains(i)) _items[i].name,
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// โหลดเกณฑ์จาก backend + เติมค่าที่เคยบันทึกในเครื่อง
  /// (จับคู่กลับเป็นดัชนีตามชื่อ) — โหลดพังก็โชว์สถานะว่างแทนค้าง
  Future<void> _load() async {
    List<CriteriaItem> items = const [];
    Map<String, dynamic>? saved;
    try {
      items = (await widget.vm.loadOptions()).projectCriteria;
    } catch (_) {}
    try {
      saved = await widget.vm.plotProject();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _items = items;
      _loaded = true;
      if (saved != null) {
        final names = {
          for (final s in saved['items'] as List? ?? const []) '$s',
        };
        for (var i = 0; i < _items.length; i++) {
          if (names.contains(_items[i].name)) _selected.add(i);
        }
      }
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.vm.savePlotProject(
        items: [for (final i in _selected.toList()..sort()) _items[i].name],
        passed: _missingRequired.isEmpty,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _itemRow(int i) {
    final (name: name, required: required) = _items[i];
    final selected = _selected.contains(i);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () =>
            setState(() => selected ? _selected.remove(i) : _selected.add(i)),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? _lightGreen : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? AppColors.green : Colors.grey.shade300,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 26,
                height: 26,
                child: Checkbox(
                  value: selected,
                  onChanged: (_) => setState(
                    () => selected ? _selected.remove(i) : _selected.add(i),
                  ),
                  activeColor: AppColors.green,
                  side: BorderSide(color: Colors.grey.shade400, width: 1.5),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${i + 1}. $name',
                  style: const TextStyle(fontSize: 16.5),
                ),
              ),
              if (required)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade300),
                  ),
                  child: Text(
                    'จำเป็น',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.red.shade700,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.vm.parcel;
    final missing = _missingRequired;
    // ประเภทอ้อยของแปลงสำหรับหัวข้อเงื่อนไข — ไม่มีใน meta ใช้คำกลาง
    final caneType = '${p.meta?['caneType'] ?? ''}';
    final condLabel = caneType.isEmpty ? 'แปลงนี้' : 'แปลง$caneType';
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // หัว sheet — ไอคอนดาว + ชื่อ + ข้อมูลแปลง + ปุ่มปิด
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CircleAvatar(
                radius: 20,
                backgroundColor: _lightGreen,
                child: Icon(Iconsax.star_1, color: AppColors.green, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ข้อมูลโครงการส่งเสริมแปลง',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.navy,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'แปลง: ${p.landNo}'
                      '${p.plotCode != null ? ' #${p.plotCode}' : ''}'
                      ' (${p.areaThai})',
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
          const SizedBox(height: 14),
          // กล่องเงื่อนไข — เขียวอ่อนชุดเดียวกับกล่อง info ของแอป
          // ชื่อประเภทอ้อย + เกณฑ์บังคับมาจาก meta/backend ไม่ hardcode
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _lightGreen,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Iconsax.info_circle,
                  size: 20,
                  color: AppColors.green,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _requiredNames.isEmpty
                        ? 'เงื่อนไขสำหรับ $condLabel'
                        : 'เงื่อนไขสำหรับ $condLabel\n'
                              'ต้องมีโครงการ: ${_requiredNames.join(', ')} '
                              'จึงจะมีสิทธิ์เข้าโครงการ Brr Model',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.green,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // แถวนับจำนวน + ปุ่มลัดเลือก/ล้าง
          Row(
            children: [
              Expanded(
                child: Text(
                  'เลือกโครงการ (${_selected.length}/${_items.length})',
                  style: const TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (_requiredNames.isNotEmpty)
                TextButton(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: AppColors.navy,
                  ),
                  onPressed: () => setState(() {
                    _selected
                      ..clear()
                      ..addAll([
                        for (var i = 0; i < _items.length; i++)
                          if (_items[i].required) i,
                      ]);
                  }),
                  child: Text(
                    'เลือกเกณฑ์บังคับ (${_requiredNames.length} โครงการ)',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              TextButton(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: AppColors.green,
                ),
                onPressed: () => setState(
                  () =>
                      _selected.addAll(List.generate(_items.length, (i) => i)),
                ),
                child: const Text(
                  'เลือกทั้งหมด',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: Colors.black54,
                ),
                onPressed: () => setState(_selected.clear),
                child: const Text(
                  'ล้าง',
                  style: TextStyle(
                    fontSize: 14,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (!_loaded)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
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
                'ไม่มีข้อมูลเกณฑ์โครงการจากระบบ',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: Colors.black45),
              ),
            )
          else
            for (var i = 0; i < _items.length; i++) _itemRow(i),
          const SizedBox(height: 14),
          // กล่องเตือนส้ม — โชว์เฉพาะตอนเกณฑ์บังคับยังไม่ครบ
          if (missing.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF6E8),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE65100)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Iconsax.warning_2,
                    size: 20,
                    color: Color(0xFFE65100),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'ยังไม่ผ่านเกณฑ์โครงการ Brr Model\n'
                      'ยังขาดโครงการ: ${missing.join(', ')}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFE65100),
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
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
                  onPressed: _saving || _items.isEmpty ? null : _save,
                  icon: const Icon(Iconsax.save_2, size: 22),
                  label: Text(
                    _saving ? 'กำลังบันทึก…' : 'บันทึกข้อมูลโครงการ',
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

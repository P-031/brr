import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import 'package:brr/core/theme/app_theme.dart';
import 'package:brr/core/widgets/option_popup.dart';
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
  FormOptions? _opts;
  bool _loaded = false;
  final _selected = <int>{};

  /// ตัวเลือกย่อยที่เลือกไว้ต่อเกณฑ์ (ชื่อเกณฑ์ → ชนิดที่เลือก)
  /// เช่น ใส่ปุ๋ยอินทรีย์ → กากน้ำตาล
  final _choices = <String, String>{};
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
    FormOptions? opts;
    Map<String, dynamic>? saved;
    try {
      opts = await widget.vm.loadOptions();
    } catch (_) {}
    try {
      saved = await widget.vm.plotProject();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _opts = opts;
      _items = opts?.projectCriteria ?? const [];
      _loaded = true;
      if (saved != null) {
        final savedItems = saved['items'];
        final names = {
          if (savedItems is List)
            for (final s in savedItems) '$s',
        };
        for (var i = 0; i < _items.length; i++) {
          if (names.contains(_items[i].name)) _selected.add(i);
        }
        // ตัวเลือกย่อยที่เคยบันทึก — {ชื่อเกณฑ์: ชนิด}
        final savedChoices = saved['choices'];
        if (savedChoices is Map) {
          for (final e in savedChoices.entries) {
            _choices['${e.key}'] = '${e.value}';
          }
        }
      }
    });
  }

  /// ตัวเลือกย่อยของเกณฑ์ — จาก `options` ที่ backend ส่งมากับ
  /// เกณฑ์ก่อน; ไม่มีค่อย fallback ตามชื่อเกณฑ์กับ list ที่
  /// /meta/options มีอยู่แล้ว (ปุ๋ยอินทรีย์ → organicFertilizerTypes)
  List<String> _optionsFor(CriteriaItem it) {
    if (it.options.isNotEmpty) return it.options;
    if (it.name.contains('ปุ๋ยอินทรีย์')) {
      return _opts?.organicFertilizerTypes ?? const [];
    }
    return const [];
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final chosen = [for (final i in _selected.toList()..sort()) _items[i]];
      await widget.vm.savePlotProject(
        items: [for (final it in chosen) it.name],
        // เก็บตัวเลือกย่อยเฉพาะเกณฑ์ที่ติ๊กไว้
        choices: {
          for (final it in chosen)
            if (_choices[it.name] != null) it.name: _choices[it.name]!,
        },
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

  /// dropdown เลือกชนิดย่อยของเกณฑ์ — สไตล์เดียวกับช่องเลือก
  /// ทั่วแอป (กรอบทอง + ลูกศร Iconsax + showOptionPopup)
  Widget _optionDropdown(CriteriaItem it, List<String> options) {
    final current = _choices[it.name];
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        final idx = await showOptionPopup(
          context,
          title: it.name,
          labels: options,
          selectedIndex: current == null ? null : options.indexOf(current),
        );
        if (idx != null && mounted) {
          setState(() => _choices[it.name] = options[idx]);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: current == null ? AppColors.gold : AppColors.green,
            width: current == null ? 1 : 1.5,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                current ?? 'เลือกชนิด…',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15.5,
                  color: current == null ? Colors.black45 : Colors.black87,
                ),
              ),
            ),
            const Icon(
              Iconsax.arrow_circle_down,
              size: 26,
              color: Colors.black87,
            ),
          ],
        ),
      ),
    );
  }

  Widget _itemRow(int i) {
    final it = _items[i];
    final (name: name, required: required) = (
      name: it.name,
      required: it.required,
    );
    final selected = _selected.contains(i);
    void toggle() => setState(() {
      if (selected) {
        _selected.remove(i);
        _choices.remove(it.name);
      } else {
        _selected.add(i);
      }
    });
    final options = _optionsFor(it);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: toggle,
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
                      onChanged: (_) => toggle(),
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
          if (selected && options.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 38),
              child: _optionDropdown(it, options),
            ),
        ],
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

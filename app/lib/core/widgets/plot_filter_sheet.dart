import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import 'package:brr/core/theme/app_theme.dart';
import 'package:brr/core/utils/fuzzy_search.dart';

/// ผลกลับจาก filter sheet — เซตว่าง = ไม่กรอง (ทั้งหมด)
/// cutGroups/maintainGroups = ชื่อกลุ่มจริง (ไม่ใช่ kind)
typedef PlotFilterResult = ({
  Set<String?> years,
  Set<String> zones,
  Set<String> caneTypes,
  Set<bool> planted,
  Set<String> cutGroups,
  Set<String> maintainGroups,
});

/// ชีตเลือกตัวกรองแปลง — multi-select ทุกช่อง กด "ใช้ตัวกรอง" ทีเดียว
/// (สไตล์เดียวกับ filter หน้ากิจกรรมแปลง); ตัวเลือกทั้งหมดผู้เรียกส่ง
/// เข้ามา (map ดึงจาก meta ของแปลง, activities จาก backend)
Future<PlotFilterResult?> showPlotFilterSheet(
  BuildContext context, {
  required List<String> yearOptions,
  required List<String> zoneOptions,
  required List<String> caneTypeOptions,
  required List<String> cutGroupOptions,
  required List<String> maintainGroupOptions,
  required Set<String?> years,
  required Set<String> zones,
  required Set<String> caneTypes,
  required Set<bool> planted,
  required Set<String> cutGroups,
  required Set<String> maintainGroups,
}) {
  return showModalBottomSheet<PlotFilterResult>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => SafeArea(
        // จำกัดชีต ~78% จอ — ไม่ยืดเต็มหน้าจอ/ชนรูกล้อง;
        // หัวชีตกับปุ่มใช้ตัวกรองตรึงบน-ล่าง การ์ดเลื่อนใน list
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.78,
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    // ปุ่มย้อนกลับ — วงกลมขาวสไตล์ปุ่มลอยบนแผนที่
                    // ปิดชีตโดยไม่ apply
                    GestureDetector(
                      onTap: () => Navigator.of(ctx).pop(),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.black12),
                          boxShadow: const [
                            BoxShadow(color: Colors.black12, blurRadius: 4),
                          ],
                        ),
                        child: const Icon(
                          Iconsax.arrow_left,
                          size: 22,
                          color: AppColors.green,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Icon(Iconsax.setting_4, color: AppColors.green),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'ตัวกรองแปลง',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => setS(() {
                        years.clear();
                        zones.clear();
                        caneTypes.clear();
                        planted.clear();
                        cutGroups.clear();
                        maintainGroups.clear();
                      }),
                      child: const Text(
                        'ล้างทั้งหมด',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    children: [
                      // null = "ไม่มีปีการผลิต"
                      _filterField<String?>(
                        context,
                        label: 'ปีการผลิต',
                        icon: Icons.calendar_today,
                        selected: years,
                        options: {
                          null: 'ไม่มีปีการผลิต',
                          for (final y in yearOptions) y: y,
                        },
                        onChanged: (_) => setS(() {}),
                      ),
                      const SizedBox(height: 12),
                      _filterField<String>(
                        context,
                        label: 'เขต',
                        icon: Iconsax.location,
                        selected: zones,
                        options: {for (final z in zoneOptions) z: z},
                        onChanged: (_) => setS(() {}),
                      ),
                      const SizedBox(height: 12),
                      _filterField<String>(
                        context,
                        label: 'ประเภทปลูก',
                        icon: Iconsax.hierarchy,
                        selected: caneTypes,
                        options: {for (final t in caneTypeOptions) t: t},
                        onChanged: (_) => setS(() {}),
                      ),
                      const SizedBox(height: 12),
                      _filterField<bool>(
                        context,
                        label: 'แปลงที่ปลูก',
                        icon: Iconsax.tree,
                        selected: planted,
                        options: const {true: 'ปลูกแล้ว', false: 'ยังไม่ปลูก'},
                        onChanged: (_) => setS(() {}),
                      ),
                      const SizedBox(height: 12),
                      _filterField<String>(
                        context,
                        label: 'กลุ่มตัด',
                        icon: Iconsax.people,
                        selected: cutGroups,
                        options: {for (final g in cutGroupOptions) g: g},
                        onChanged: (_) => setS(() {}),
                      ),
                      const SizedBox(height: 12),
                      _filterField<String>(
                        context,
                        label: 'กลุ่มบำรุง',
                        icon: Iconsax.people,
                        selected: maintainGroups,
                        options: {for (final g in maintainGroupOptions) g: g},
                        onChanged: (_) => setS(() {}),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop((
                    years: years,
                    zones: zones,
                    caneTypes: caneTypes,
                    planted: planted,
                    cutGroups: cutGroups,
                    maintainGroups: maintainGroups,
                  )),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.green,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text(
                    'ใช้ตัวกรอง',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// ช่องเลือกฟิลเตอร์ — การ์ดขาว + กล่องเทาแสดงค่า (สไตล์เดียวกับ
/// หน้ากิจกรรมแปลง); แตะแล้วเด้ง multi-pick dialog
Widget _filterField<T>(
  BuildContext context, {
  required String label,
  required IconData icon,
  required Set<T> selected,
  required Map<T, String> options,
  required ValueChanged<Set<T>> onChanged,
}) {
  final display = selected.isEmpty
      ? 'ทั้งหมด'
      : selected.length == 1
      ? (options[selected.first] ?? 'ทั้งหมด')
      : 'เลือกแล้ว ${selected.length}';
  final active = selected.isNotEmpty;
  return InkWell(
    borderRadius: BorderRadius.circular(12),
    onTap: () => _pickMulti<T>(
      context,
      label: label,
      selected: selected,
      options: options,
      onChanged: onChanged,
    ),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: active ? AppColors.green : Colors.black26,
          width: active ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 22, color: AppColors.green),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.black12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    display,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 17,
                      color: active ? null : Colors.black45,
                    ),
                  ),
                ),
                Icon(
                  Iconsax.arrow_circle_down,
                  size: 28,
                  color: active ? AppColors.green : Colors.black87,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// ตัวเลือกเด้งเป็น popup กลางจอ — เลือกได้หลายค่า (toggle)
/// "ทั้งหมด" = ล้าง selection; กด "เสร็จ" หรือแตะพื้นหลังเพื่อปิด
void _pickMulti<T>(
  BuildContext context, {
  required String label,
  required Set<T> selected,
  required Map<T, String> options,
  required ValueChanged<Set<T>> onChanged,
}) {
  showDialog(
    context: context,
    builder: (ctx) {
      // query อยู่นอก StatefulBuilder — ไม่งั้นโดน reset ทุก rebuild
      var query = '';
      return StatefulBuilder(
        builder: (ctx, setSheet) {
          // ตรงก่อน — ไม่เจอค่อยหาคำใกล้เคียง (helper กลาง)
          final filtered = fuzzySearch(options.entries, query, (e) => e.value);
          void toggle(T key) {
            setSheet(() {
              if (selected.contains(key)) {
                selected.remove(key);
              } else {
                selected.add(key);
              }
            });
            onChanged(selected);
          }

          Widget tile(String text, bool on, VoidCallback onTap) => Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onTap,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: on ? const Color(0xFFE8F5E9) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: on ? AppColors.green : const Color(0xFFDDDDDD),
                    width: on ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        text,
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: on ? FontWeight.w700 : FontWeight.w400,
                          color: on ? AppColors.green : Colors.black87,
                        ),
                      ),
                    ),
                    if (on)
                      const Icon(
                        Iconsax.tick_circle,
                        color: AppColors.green,
                        size: 24,
                      ),
                  ],
                ),
              ),
            ),
          );
          return Dialog(
            backgroundColor: Colors.white,
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 24,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 8, 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            label,
                            style: const TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: const Text(
                            'เสร็จ',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
                    child: TextField(
                      textAlign: TextAlign.start,
                      style: const TextStyle(fontSize: 18),
                      onChanged: (q) => setSheet(() => query = q),
                      decoration: InputDecoration(
                        hintText: 'ค้นหา',
                        hintStyle: const TextStyle(fontSize: 17),
                        prefixIcon: const Icon(Iconsax.search_normal),
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.only(top: 12),
                      children: [
                        tile('ทั้งหมด', selected.isEmpty, () {
                          setSheet(() => selected.clear());
                          onChanged(selected);
                        }),
                        for (final e in filtered)
                          tile(
                            e.value,
                            selected.contains(e.key),
                            () => toggle(e.key),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

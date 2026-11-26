import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import 'package:brr/core/theme/app_theme.dart';
import 'package:brr/core/utils/fuzzy_search.dart';

/// popup เลือกตัวเลือกกลางจอ — ใช้แทน dropdown menu ทั้งแอป
/// คืน index ที่เลือก หรือ null ถ้ากดพื้นหลัง/ยกเลิก
/// [searchHint] มีค่า = เพิ่มช่องค้นหากรองตัวเลือก (list ยาว เช่น
/// รายชื่อชาวไร่)
Future<int?> showOptionPopup(
  BuildContext context, {
  String? title,
  required List<String> labels,
  int? selectedIndex,
  String? searchHint,
}) => showDialog<int>(
  context: context,
  builder: (ctx) {
    // query/controller ต้องอยู่นอก StatefulBuilder — ไม่งั้นโดน
    // reset ทุก rebuild; ใช้ controller เพื่อให้ปุ่ม X ล้างข้อความได้
    var query = '';
    final searchCtrl = TextEditingController();
    return StatefulBuilder(
      builder: (ctx, setDialogState) {
        // ตรงก่อน — ไม่เจอค่อยหาคำใกล้เคียง (fuzzySearch)
        final direct = [
          for (var i = 0; i < labels.length; i++)
            if (query.isNotEmpty &&
                labels[i].toLowerCase().contains(query.toLowerCase()))
              i,
        ];
        final filtered = fuzzySearch(
          List<int>.generate(labels.length, (i) => i),
          query,
          (i) => labels[i],
        );
        // ผลมาจากคำใกล้เคียง = query ไม่ว่างแต่ไม่มีตัวตรงเลย
        final showingSimilar = query.isNotEmpty && direct.isEmpty;
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
                if (title != null) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                ],
                if (searchHint != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
                    child: TextField(
                      controller: searchCtrl,
                      textAlign: TextAlign.start,
                      style: const TextStyle(fontSize: 18),
                      // ไม่ autofocus — เปิดมาเห็น list เต็มก่อน
                      // เหมือนช่องค้นหาในแผนที่
                      autofocus: false,
                      onChanged: (q) => setDialogState(() => query = q),
                      // กดค้นบนคีย์บอร์ด = ยืนยันค้น ปิดคีย์บอร์ด
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => FocusScope.of(ctx).unfocus(),
                      decoration: InputDecoration(
                        hintText: searchHint,
                        hintStyle: const TextStyle(fontSize: 17),
                        // แตะแว่นขยาย = ยืนยันค้น/ปิดคีย์บอร์ด เหมือน
                        // ช่องค้นหาในแผนที่
                        prefixIcon: GestureDetector(
                          onTap: () => FocusScope.of(ctx).unfocus(),
                          behavior: HitTestBehavior.opaque,
                          child: const Icon(
                            Iconsax.search_normal,
                            size: 28,
                          ),
                        ),
                        // ปุ่ม X ล้างข้อความ — โผล่เฉพาะตอนมี query
                        suffixIcon: query.isEmpty
                            ? null
                            : GestureDetector(
                                onTap: () {
                                  searchCtrl.clear();
                                  setDialogState(() => query = '');
                                },
                                behavior: HitTestBehavior.opaque,
                                child: const Icon(
                                  Iconsax.close_circle,
                                  size: 28,
                                  color: Colors.black54,
                                ),
                              ),
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                if (showingSimilar && filtered.isNotEmpty)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'ไม่พบตรง — คำใกล้เคียง:',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.black45,
                        ),
                      ),
                    ),
                  ),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.all(12),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, fi) {
                      final i = filtered[fi];
                      final selected = i == selectedIndex;
                      return InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => Navigator.of(ctx).pop(i),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: selected
                                ? AppColors.green.withValues(alpha: 0.08)
                                : null,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: selected
                                  ? AppColors.green
                                  : Colors.black12,
                              width: selected ? 1.5 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  labels[i],
                                  style: TextStyle(
                                    fontSize: 19,
                                    fontWeight: selected
                                        ? FontWeight.w700
                                        : FontWeight.w400,
                                    color: selected
                                        ? AppColors.green
                                        : Colors.black87,
                                  ),
                                ),
                              ),
                              if (selected)
                                const Icon(
                                  Iconsax.tick_circle,
                                  color: AppColors.green,
                                  size: 24,
                                ),
                            ],
                          ),
                        ),
                      );
                    },
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

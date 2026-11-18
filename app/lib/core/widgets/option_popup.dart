import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import 'package:brr/core/theme/app_theme.dart';

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
    // query ต้องอยู่นอก StatefulBuilder — ไม่งั้นโดน reset ทุก rebuild
    var query = '';
    return StatefulBuilder(
      builder: (ctx, setDialogState) {
        final filtered = <int>[
        for (var i = 0; i < labels.length; i++)
          if (query.isEmpty || labels[i].contains(query)) i,
      ];
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
                        fontSize: 20,
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
                    autofocus: true,
                    onChanged: (q) => setDialogState(() => query = q),
                    decoration: InputDecoration(
                      hintText: searchHint,
                      prefixIcon: const Icon(Iconsax.search_normal),
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
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
                                  fontSize: 17,
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
                                size: 22,
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

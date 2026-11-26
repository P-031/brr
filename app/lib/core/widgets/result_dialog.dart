import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import 'package:brr/core/theme/app_theme.dart';

/// dialog แจ้งผลกลางจอ — success=ติ๊กเขียว / ไม่สำเร็จ=เตือนส้ม
/// ใช้แทน snackbar จุดที่อยากให้ผู้ใช้เห็นชัด (บันทึกสำเร็จ/ล้มเหลว)
/// [message] ใส่รายละเอียดเพิ่มใต้หัวข้อได้ (เช่น เหตุที่พัง)
Future<void> showResultDialog(
  BuildContext context, {
  required bool success,
  required String title,
  String? message,
}) => showDialog<void>(
  context: context,
  builder: (ctx) => AlertDialog(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          success ? Iconsax.tick_circle : Iconsax.warning_2,
          size: 56,
          color: success ? AppColors.green : const Color(0xFFE65100),
        ),
        const SizedBox(height: 14),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
        ),
        if (message != null && message.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            message,
            style: const TextStyle(fontSize: 16, color: Colors.black54),
          ),
        ],
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('ตกลง', style: TextStyle(fontSize: 16)),
          ),
        ),
      ],
    ),
  ),
);

import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import 'package:brr/core/theme/app_theme.dart';

/// dialog ยืนยันออกหน้าฟอร์มโดยไม่บันทึก — คืน true เมื่อผู้ใช้
/// ยืนยัน "ออก" (ใช้คู่ PopScope กันข้อมูลที่กรอกหายเพราะกดย้อนพลาด)
Future<bool> confirmDiscardChanges(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Iconsax.warning_2, size: 56, color: Color(0xFFE65100)),
          const SizedBox(height: 14),
          const Text(
            'ออกโดยไม่บันทึก?',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'ข้อมูลที่กรอกไว้จะหายไป',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.black54),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('กรอกต่อ'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.green,
                  ),
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('ออก'),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
  return ok == true;
}

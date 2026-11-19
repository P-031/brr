import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:image_picker/image_picker.dart';

import 'package:brr/core/theme/app_theme.dart';

/// Bottom sheet เลือกแหล่งรูป — ถ่ายรูป / เลือกจากแกลเลอรี
/// ใช้ร่วมกันทุกหน้าที่รับรูป (แอปหลักรองรับรูปจากเครื่องด้วย
/// ไม่บังคับถ่ายสดอย่างเดียว)
Future<ImageSource?> showImageSourceSheet(BuildContext context) =>
    showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Iconsax.camera, color: AppColors.green),
              title: const Text('ถ่ายรูป'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Iconsax.gallery, color: AppColors.green),
              title: const Text('เลือกจากแกลเลอรี'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

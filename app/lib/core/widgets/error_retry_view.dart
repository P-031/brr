import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

/// จอ error กลางหน้า + ปุ่มลองใหม่ใหญ่ — แชร์ทุกจอที่โหลดข้อมูล
/// ไม่ได้ (ดาวน์โหลด/แผนที่/สถานะแปลง/อนุมัติ) ให้หน้าตาเหมือน
/// กันเป๊ะ; [fallback] = ปุ่มรอง (เช่น ใช้ข้อมูลในเครื่อง) ใส่ได้
class ErrorRetryView extends StatelessWidget {
  const ErrorRetryView(
    this.title, {
    super.key,
    required this.onRetry,
    this.fallback,
  });

  final String title;
  final VoidCallback onRetry;

  /// widget เสริมใต้ปุ่มลองใหม่ (ปุ่มรอง) — null = ไม่มี
  final Widget? fallback;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Iconsax.warning_2, color: Colors.red, size: 56),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
          ),
          onPressed: onRetry,
          icon: const Icon(Icons.autorenew, size: 30),
          label: const Text(
            'ลองใหม่',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ),
        ?fallback,
      ],
    ),
  );
}

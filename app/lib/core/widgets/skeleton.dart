import 'package:flutter/material.dart';

/// กระดูก skeleton แชร์ทุกหน้า — ครอบ layout เทาที่วาดเลียนแบบ
/// หน้าจริงด้วย [SkeletonPulse] แล้ววาง [SkelBox]/[SkelLine]/
/// [SkelCircle] ตรงตำแหน่งของจริง
class SkeletonPulse extends StatefulWidget {
  const SkeletonPulse({super.key, required this.child});

  final Widget child;

  @override
  State<SkeletonPulse> createState() => _SkeletonPulseState();
}

class _SkeletonPulseState extends State<SkeletonPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (_, _) =>
        Opacity(opacity: 0.55 + 0.35 * _c.value, child: widget.child),
  );
}

/// กล่องเทามุมมน — ใช้แทนรูป/การ์ด/ปุ่มที่ยังโหลดไม่เสร็จ
class SkelBox extends StatelessWidget {
  const SkelBox({
    super.key,
    this.width,
    this.height = 14,
    this.radius = 6,
    this.color,
  });

  final double? width;
  final double height;
  final double radius;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: color ?? Colors.grey.shade300,
      borderRadius: BorderRadius.circular(radius),
    ),
  );
}

/// เส้นเทาบาง — ใช้แทนบรรทัดข้อความ
class SkelLine extends StatelessWidget {
  const SkelLine({super.key, this.width, this.height = 13});

  final double? width;
  final double height;

  @override
  Widget build(BuildContext context) =>
      SkelBox(width: width, height: height, radius: height / 2);
}

/// วงกลมเทา — ใช้แทนไอคอน/ปุ่มกลม
class SkelCircle extends StatelessWidget {
  const SkelCircle({super.key, this.size = 48});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: Colors.grey.shade300,
      shape: BoxShape.circle,
    ),
  );
}

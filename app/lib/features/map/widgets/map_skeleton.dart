import 'package:flutter/material.dart';

/// Skeleton เลียนแบบหน้าแผนที่จริง — พื้นเทาเต็มจอเหมือน tile กำลัง
/// โหลด + วงกลมขาวตำแหน่งเดียวกับปุ่มจริง (ย้อนกลับ/ชั้นแผนที่/GPS)
/// + แถบขาวล่างพร้อมช่องปุ่มสองอันเหมือน "เดินวัด/แตะวาด"
/// ใช้ทั้งตอนโหลดแปลงใน MapView และตอนเตรียมข้อมูลหลังดาวน์โหลด
class MapSkeleton extends StatefulWidget {
  const MapSkeleton({super.key});

  @override
  State<MapSkeleton> createState() => _MapSkeletonState();
}

class _MapSkeletonState extends State<MapSkeleton>
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
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) => Opacity(
        opacity: 0.55 + 0.35 * _c.value,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // พื้นแผนที่ — เต็มจอเหมือน GoogleMap จริง
            Container(color: Colors.grey.shade300),
            // ปุ่มย้อนกลับ (ซ้ายบน — ตำแหน่งเดียวกับของจริง)
            Positioned(
              top: top + 12,
              left: 16,
              child: const _Circle(),
            ),
            // คอลัมน์ปุ่มขวาล่าง — ชั้นแผนที่ + GPS ตำแหน่งเดียวกับ
            // ของจริง (right:16,bottom:16 เหนือแถบล่าง ~84px)
            const Positioned(
              right: 16,
              bottom: 100,
              child: Column(
                children: [
                  _Circle(),
                  SizedBox(height: 10),
                  _Circle(),
                ],
              ),
            ),
            // แถบล่าง — ขาวเต็มจอเหมือนแถบปุ่มจริง + ช่องปุ่มสองอัน
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                child: Row(
                  children: [
                    Expanded(child: _ButtonSlot()),
                    const SizedBox(width: 12),
                    Expanded(child: _ButtonSlot()),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// วงกลมขาว 48px ตำแหน่งเดียวกับ MapButton จริง
class _Circle extends StatelessWidget {
  const _Circle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 6)],
      ),
    );
  }
}

/// ช่องปุ่มเทาในแถบล่าง — รูปทรงเดียวกับปุ่มเดินวัด/แตะวาดจริง
class _ButtonSlot extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: Colors.grey.shade300,
        borderRadius: BorderRadius.circular(24),
      ),
    );
  }
}

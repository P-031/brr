import 'package:flutter/material.dart';
import 'package:brr/core/widgets/skeleton.dart';

/// Skeleton เลียนแบบหน้าแผนที่จริง — พื้นเทาเต็มจอเหมือน tile กำลัง
/// โหลด + วงกลมตำแหน่งเดียวกับปุ่มจริง + pill ฟิลเตอร์ปี
///
/// โหมดวัด ([parcelBrowser] = false): ปุ่มขวา 2 อัน (ชั้นแผนที่/GPS)
/// + แถบขาวล่างปุ่มสองอันเหมือน "เดินวัด/แตะวาด"
/// โหมดแผนที่แปลง (true): ปุ่มขวา 4 อัน (ชั้นแผนที่/ดาวน์โหลด/
/// ฉบับร่าง/GPS) ไม่มีแถบล่าง
class MapSkeleton extends StatelessWidget {
  const MapSkeleton({super.key, this.parcelBrowser = false});

  final bool parcelBrowser;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return SkeletonPulse(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // พื้นแผนที่ — เต็มจอเหมือน GoogleMap จริง
          Container(color: Colors.grey.shade300),
          // ปุ่มย้อนกลับ (ซ้ายบน — ตำแหน่งเดียวกับของจริง)
          Positioned(top: top + 12, left: 16, child: const _Circle()),
          // ช่องค้นหา + ปุ่มฟิลเตอร์ — ตำแหน่งเดียวกับของจริง
          Positioned(
            top: top + 12,
            left: 84,
            right: 82,
            child: const SkelBox(height: 56, radius: 28),
          ),
          Positioned(top: top + 12, right: 16, child: const _Circle()),
          // คอลัมน์ปุ่มขวา — โหมดแปลงมี 4 อัน (ชั้น/GPS/ดาวน์โหลด/
          // ร่าง) ล่างสุดชิดขอบ; โหมดวัด 3 อัน (ชั้น/GPS/ร่าง)
          // เหนือแถบล่าง
          Positioned(
            right: 16,
            bottom: parcelBrowser ? 16 : 116,
            child: Column(
              children: [
                const _Circle(),
                const SizedBox(height: 10),
                const _Circle(),
                if (parcelBrowser) ...[
                  const SizedBox(height: 10),
                  const _Circle(),
                ],
                const SizedBox(height: 10),
                const _Circle(),
              ],
            ),
          ),
          // แถบล่างโหมดวัด — ขาวเต็มจอเหมือนแถบปุ่มจริง + ช่อง
          // ปุ่มสองอัน (โหมดแปลงไม่มีแถบนี้)
          if (!parcelBrowser)
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                child: const Row(
                  children: [
                    Expanded(child: _ButtonSlot()),
                    SizedBox(width: 12),
                    Expanded(child: _ButtonSlot()),
                  ],
                ),
              ),
            ),
        ],
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
      width: 56,
      height: 56,
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
  const _ButtonSlot();

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

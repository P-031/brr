import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:latlong2/latlong.dart' as ll;

/// thumbnail วาดขอบแปลงบนพื้นเขียวเข้ม — ใช้ซ้ำทั้งการ์ด list
/// (กิจกรรมแปลง) และ header หน้ารายละเอียดแปลง
class ParcelOutline extends StatelessWidget {
  const ParcelOutline({
    super.key,
    required this.points,
    this.width = 92,
    this.height = 92,
    this.radius = 10,
  });

  final List<ll.LatLng> points;
  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFF173F2A), // เขียวเข้มแบบ ref
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: const Color(0xFF0E2B1B)),
      ),
      clipBehavior: Clip.antiAlias,
      child: points.length >= 3
          ? CustomPaint(painter: _RingPainter(points))
          : const Center(
              child: Icon(
                Iconsax.map_1,
                color: Colors.white54,
                size: 28,
              ),
            ),
    );
  }
}

/// วาด polygon ของแปลงให้พอดีกรอบ thumbnail — normalize เข้า bounds
/// รักษาสัดส่วน (uniform scale + center) เห็นรูปแปลงเหมือนบนแผนที่
class _RingPainter extends CustomPainter {
  const _RingPainter(this.points);

  final List<ll.LatLng> points;

  @override
  void paint(Canvas canvas, Size size) {
    double minLat = 90, maxLat = -90, minLng = 180, maxLng = -180;
    for (final p in points) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLng = math.min(minLng, p.longitude);
      maxLng = math.max(maxLng, p.longitude);
    }
    final dx = maxLng - minLng;
    final dy = maxLat - minLat;
    if (dx <= 0 || dy <= 0) return;

    const pad = 8.0;
    final w = size.width - pad * 2;
    final h = size.height - pad * 2;
    final scale = math.min(w / dx, h / dy);
    final ox = pad + (w - dx * scale) / 2;
    final oy = pad + (h - dy * scale) / 2;

    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final x = ox + (points[i].longitude - minLng) * scale;
      final y = oy + (maxLat - points[i].latitude) * scale;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();

    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFFA8AB3A) // เขียวมะกอกแบบ ref
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFFD4D67A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.points != points;
}

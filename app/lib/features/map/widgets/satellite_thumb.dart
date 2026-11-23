import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:latlong2/latlong.dart' as ll;

import 'package:brr/features/map/models/sat_thumb.dart';

/// thumbnail ภาพดาวเทียมซูมพอดีแปลง + เส้นขอบทองทับ — วาดอย่างเดียว;
/// การโหลด/cache ผูกจาก VM ผ่าน [loader] (view ไม่แตะชั้น data ตรง)
class SatelliteThumb extends StatelessWidget {
  const SatelliteThumb({
    super.key,
    required this.points,
    required this.cacheKey,
    required this.loader,
    this.width = 92,
    this.height = 92,
    this.radius = 10,
    this.fallback,
  });

  final List<ll.LatLng> points;

  /// โหลด thumbnail — เจ้าของ VM ผูก SatelliteThumbService.load เข้ามา
  final SatThumbLoader loader;

  /// key ประจำแปลงสำหรับไฟล์ cache (เช่น parcel id)
  final String cacheKey;
  final double width;
  final double height;
  final double radius;

  /// widget สำรองตอนโหลด tile ไม่ได้ (ออฟไลน์ + ไม่มี cache)
  final Widget? fallback;

  @override
  Widget build(BuildContext context) {
    final child = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Container(
        width: width,
        height: height,
        color: const Color(0xFF173F2A),
        child: points.length < 3
            ? const Center(
                child: Icon(Iconsax.map_1, color: Colors.white54, size: 28),
              )
            : FutureBuilder<SatThumb>(
                future: loader(cacheKey, points, width.round(), height.round()),
                builder: (context, snap) {
                  final t = snap.data;
                  if (t == null) {
                    return snap.connectionState == ConnectionState.done
                        ? (fallback ??
                              const Center(
                                child: Icon(
                                  Iconsax.map_1,
                                  color: Colors.white54,
                                  size: 28,
                                ),
                              ))
                        : const Center(
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white54,
                              ),
                            ),
                          );
                  }
                  return CustomPaint(
                    painter: _SatPainter(t, points),
                    child: const SizedBox.expand(),
                  );
                },
              ),
      ),
    );
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: const Color(0xFF0E2B1B)),
      ),
      child: child,
    );
  }
}

/// วาดภาพดาวเทียมเฉพาะกรอบรอบแปลง (pad ~18% + ทำเป็นสี่เหลี่ยมจัตุรัส
/// ตรงกลาง) แล้วทับเส้นขอบแปลงสีทอง + เติมเขียวจาง
class _SatPainter extends CustomPainter {
  const _SatPainter(this.t, this.points);

  final SatThumb t;
  final List<ll.LatLng> points;

  Offset _project(ll.LatLng p) => Offset(
    (satPx(p.longitude, t.zoom) - t.originX) * t.imgScale,
    (satPy(p.latitude, t.zoom) - t.originY) * t.imgScale,
  );

  @override
  void paint(Canvas canvas, Size size) {
    final pts = [for (final p in points) _project(p)];
    var minX = double.infinity, maxX = -double.infinity;
    var minY = double.infinity, maxY = -double.infinity;
    for (final o in pts) {
      minX = math.min(minX, o.dx);
      maxX = math.max(maxX, o.dx);
      minY = math.min(minY, o.dy);
      maxY = math.max(maxY, o.dy);
    }
    final imgRect = Rect.fromLTWH(
      0,
      0,
      t.image.width.toDouble(),
      t.image.height.toDouble(),
    );
    late final Rect src;
    if (t.imgScale != 1) {
      // Google Static Maps — API zoom/centre มาพอดีอยู่แล้ว
      // วาดเต็มภาพไม่ crop (ไม่งั้นลายน้ำ Google ขอบล่างหลุด)
      src = imgRect;
    } else {
      // Esri composite — crop ตาม bbox พิกัด + pad ให้ aspect ตรง widget
      final pad = math.max(maxX - minX, maxY - minY) * 0.18 + 6;
      final cx = (minX + maxX) / 2, cy = (minY + maxY) / 2;
      var w = maxX - minX + pad * 2;
      var h = maxY - minY + pad * 2;
      final aspect = size.width / size.height;
      if (w / h < aspect) {
        w = h * aspect;
      } else {
        h = w / aspect;
      }
      src = Rect.fromCenter(center: Offset(cx, cy), width: w, height: h);
    }
    // วาดเฉพาะส่วน src ที่มีภาพจริง — กรอบขยายตาม aspect อาจล้นขอบ
    // tile composite ได้ ถ้ายืด src ล้นจะเห็นแถบมืด/เพี้ยน
    final visSrc = src.intersect(imgRect);
    if (!visSrc.isEmpty) {
      final visDst = Rect.fromLTWH(
        (visSrc.left - src.left) / src.width * size.width,
        (visSrc.top - src.top) / src.height * size.height,
        visSrc.width / src.width * size.width,
        visSrc.height / src.height * size.height,
      );
      canvas.drawImageRect(t.image, visSrc, visDst, Paint());
    }

    // พิกัด → พิกเบิลบน widget = (จุด - src.topleft) × scale แยกแกน
    final sx = size.width / src.width;
    final sy = size.height / src.height;
    Offset map(Offset o) =>
        Offset((o.dx - src.left) * sx, (o.dy - src.top) * sy);
    final path = Path()..addPolygon([for (final o in pts) map(o)], true);
    canvas.drawPath(path, Paint()..color = const Color(0x552E7D32));
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFFC9A227),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = Colors.white.withValues(alpha: 0.35),
    );
  }

  @override
  bool shouldRepaint(_SatPainter old) => old.t != t || old.points != points;
}

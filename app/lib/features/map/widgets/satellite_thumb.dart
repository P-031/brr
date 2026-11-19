import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax/iconsax.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart' as ll;
import 'package:path_provider/path_provider.dart';

/// thumbnail ภาพดาวเทียมซูมพอดีแปลง + เส้นขอบทองทับ — เรียก Google
/// Static Maps API (key ตัวเดียวกับแผนที่ อ่านจาก manifest ผ่าน
/// method channel `brr/maps`) ถ้า key/เน็ตมีปัญหา fallback เป็น
/// tile ของ Esri World Imagery (ฟรี ไม่ต้องมี key) แล้ว cache
/// ลงเครื่องทั้งคู่ — ออฟไลน์ยังโชว์ได้
const _mapsChannel = MethodChannel('brr/maps');
final _mapsKey = _mapsChannel.invokeMethod<String>('apiKey').catchError(
      (_) => null,
    );
class SatelliteThumb extends StatelessWidget {
  const SatelliteThumb({
    super.key,
    required this.points,
    required this.cacheKey,
    this.width = 92,
    this.height = 92,
    this.radius = 10,
    this.fallback,
  });

  final List<ll.LatLng> points;

  /// key ประจำแปลงสำหรับไฟล์ cache (เช่น parcel id)
  final String cacheKey;
  final double width;
  final double height;
  final double radius;

  /// widget สำรองตอนโหลด tile ไม่ได้ (ออฟไลน์ + ไม่มี cache)
  final Widget? fallback;

  /// in-memory cache จำกัด — list ยาวๆ (กิจกรรมแปลง) เลื่อนผ่าน
  /// แปลงนับพัน เก็บ bitmap ทุกใบจะล้น RAM เครื่องสเปกต่ำ
  /// evict ใบเก่าสุดออก (disk cache ยังอยู่ โหลดคืนเร็ว)
  static const _memCacheLimit = 24;
  static final _cache = <String, Future<_Thumb>>{};

  static Future<_Thumb> _cached(
    String key,
    List<ll.LatLng> points,
    int w,
    int h,
  ) {
    final memKey = '$key|${w}x$h';
    final hit = _cache.remove(memKey); // touch → ไปท้าย (LRU)
    if (hit != null) return _cache[memKey] = hit;
    if (_cache.length >= _memCacheLimit) {
      _cache.remove(_cache.keys.first);
    }
    final fut = _load(points, key, w, h);
    _cache[memKey] = fut;
    // future ที่ fail (เน็ตหลุดกลางดึง tile) ต้องออกจาก cache —
    // ไม่งั้น error ค้างถาวรใน map ทำให้ widget ไม่เคย retry
    fut.then<void>(
      (_) {},
      onError: (_) {
        if (identical(_cache[memKey], fut)) _cache.remove(memKey);
      },
    );
    return fut;
  }

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
                child: Icon(
                  Iconsax.map_1,
                  color: Colors.white54,
                  size: 28,
                ),
              )
            : FutureBuilder<_Thumb>(
                future: _cached(
                  cacheKey,
                  points,
                  width.round(),
                  height.round(),
                ),
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

/// ผลโหลด — bitmap + origin (mercator px ขอบซ้ายบนของภาพ) + zoom +
/// imgScale (image px ต่อ 1 mercator px: google scale=2, esri=1)
class _Thumb {
  _Thumb(this.image, this.originX, this.originY, this.zoom, this.imgScale);
  final ui.Image image;
  final double originX;
  final double originY;
  final int zoom;
  final double imgScale;
}

/// Web-Mercator pixel space ที่ zoom z (tile ละ 256px)
double _px(double lng, int z) => (lng + 180) / 360 * 256 * (1 << z);

double _py(double lat, int z) {
  final r = lat * math.pi / 180;
  return (1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) /
      2 *
      256 *
      (1 << z);
}

Future<ui.Image> _decode(List<int> bytes) async {
  final codec = await ui.instantiateImageCodec(
    bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
  );
  return (await codec.getNextFrame()).image;
}

Future<void> _cachePng(File file, ui.Image img) async {
  try {
    await file.parent.create(recursive: true);
    await file.writeAsBytes(
      (await img.toByteData(format: ui.ImageByteFormat.png))!
          .buffer
          .asUint8List(),
    );
  } catch (_) {}
}

Future<_Thumb> _load(
  List<ll.LatLng> points,
  String cacheKey,
  int w,
  int h,
) async {
  var minLat = 90.0, maxLat = -90.0, minLng = 180.0, maxLng = -180.0;
  for (final p in points) {
    minLat = math.min(minLat, p.latitude);
    maxLat = math.max(maxLat, p.latitude);
    minLng = math.min(minLng, p.longitude);
    maxLng = math.max(maxLng, p.longitude);
  }
  final cLat = (minLat + maxLat) / 2, cLng = (minLng + maxLng) / 2;
  final dir = await getApplicationDocumentsDirectory();

  // --- Google Static Maps (ภาพดาวเทียม Google มีลายน้ำ) ---
  // size = css px ของ widget (clamp ≤640 ตาม limit API), scale=2
  // → ภาพ 2w×2h px ครอบ w mercator px ⇒ imgScale = 2
  final gw = w.clamp(64, 640), gh = h.clamp(64, 640);
  var gz = 20;
  while (gz > 8 &&
      (_px(maxLng, gz) - _px(minLng, gz) > gw * 0.82 ||
          _py(minLat, gz) - _py(maxLat, gz) > gh * 0.82)) {
    gz--;
  }
  final gFile = File(
    '${dir.path}/sat_thumbs/${cacheKey}_${gw}x${gh}_g$gz.png',
  );
  final gOriginX = _px(cLng, gz) - gw / 2;
  final gOriginY = _py(cLat, gz) - gh / 2;
  if (await gFile.exists()) {
    return _Thumb(
      await _decode(await gFile.readAsBytes()),
      gOriginX,
      gOriginY,
      gz,
      2,
    );
  }
  final key = await _mapsKey;
  if (key != null && key.isNotEmpty) {
    try {
      final res = await http.get(
        Uri.parse(
          'https://maps.googleapis.com/maps/api/staticmap'
          '?center=$cLat,$cLng&zoom=$gz&size=${gw}x$gh'
          '&scale=2&maptype=satellite&key=$key',
        ),
      );
      if (res.statusCode == 200) {
        final img = await _decode(res.bodyBytes);
        await _cachePng(gFile, img);
        return _Thumb(img, gOriginX, gOriginY, gz, 2);
      }
    } catch (_) {}
  }

  // --- fallback Esri World Imagery (ฟรี ไม่ต้องมี key) ---
  // zoom ละเอียดสุดที่ bbox ครอบใน ≤3×3 tile
  var z = 17;
  int x0, x1, y0, y1;
  while (true) {
    x0 = _px(minLng, z) ~/ 256;
    x1 = _px(maxLng, z) ~/ 256;
    y0 = _py(maxLat, z) ~/ 256;
    y1 = _py(minLat, z) ~/ 256;
    if ((x1 - x0 + 1) * (y1 - y0 + 1) <= 9 || z <= 8) break;
    z--;
  }
  final file = File('${dir.path}/sat_thumbs/${cacheKey}_z$z.png');
  if (await file.exists()) {
    return _Thumb(
      await _decode(await file.readAsBytes()),
      x0 * 256.0,
      y0 * 256.0,
      z,
      1,
    );
  }
  // composite tile ทั้งหมดที่ bbox ทับ
  final tw = (x1 - x0 + 1) * 256, th = (y1 - y0 + 1) * 256;
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  for (var x = x0; x <= x1; x++) {
    for (var y = y0; y <= y1; y++) {
      final res = await http.get(
        Uri.parse(
          'https://server.arcgisonline.com/ArcGIS/rest/services/'
          'World_Imagery/MapServer/tile/$z/$y/$x',
        ),
      );
      if (res.statusCode != 200) throw Exception('tile $z/$y/$x');
      canvas.drawImage(
        await _decode(res.bodyBytes),
        Offset((x - x0) * 256.0, (y - y0) * 256.0),
        Paint(),
      );
    }
  }
  final img = await rec.endRecording().toImage(tw, th);
  await _cachePng(file, img);
  return _Thumb(img, x0 * 256.0, y0 * 256.0, z, 1);
}

/// วาดภาพดาวเทียมเฉพาะกรอบรอบแปลง (pad ~18% + ทำเป็นสี่เหลี่ยมจัตุรัส
/// ตรงกลาง) แล้วทับเส้นขอบแปลงสีทอง + เติมเขียวจาง
class _SatPainter extends CustomPainter {
  const _SatPainter(this.t, this.points);

  final _Thumb t;
  final List<ll.LatLng> points;

  Offset _project(ll.LatLng p) => Offset(
    (_px(p.longitude, t.zoom) - t.originX) * t.imgScale,
    (_py(p.latitude, t.zoom) - t.originY) * t.imgScale,
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
      src = Rect.fromCenter(
        center: Offset(cx, cy),
        width: w,
        height: h,
      );
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
    canvas.drawPath(
      path,
      Paint()..color = const Color(0x552E7D32),
    );
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

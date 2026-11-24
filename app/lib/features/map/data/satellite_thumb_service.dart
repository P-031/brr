import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart' as ll;
import 'package:path_provider/path_provider.dart';

import 'package:brr/features/map/models/sat_thumb.dart';

/// ชั้น data ของ [SatelliteThumb] — โหลดภาพดาวเทียม + disk/memory cache
/// Widget เรียก [load] เท่านั้น ไม่แตะ http/disk/channel เอง
///
/// แหล่งภาพ: Google Static Maps API (key ตัวเดียวกับแผนที่ อ่านจาก
/// manifest ผ่าน method channel `brr/maps`) ถ้า key/เน็ตมีปัญหา
/// fallback เป็น tile ของ Esri World Imagery (ฟรี ไม่ต้องมี key)
/// แล้ว cache ลงเครื่องทั้งคู่ — ออฟไลน์ยังโชว์ได้
class SatelliteThumbService {
  const SatelliteThumbService._();

  static const _mapsChannel = MethodChannel('brr/maps');
  static final _mapsKey = _mapsChannel
      .invokeMethod<String>('apiKey')
      .catchError((_) => null);

  /// in-memory cache จำกัด — list ยาวๆ (กิจกรรมแปลง) เลื่อนผ่าน
  /// แปลงนับพัน เก็บ bitmap ทุกใบจะล้น RAM เครื่องสเปกต่ำ
  /// evict ใบเก่าสุดออก (disk cache ยังอยู่ โหลดคืนเร็ว)
  static const _memCacheLimit = 24;
  static final _cache = <String, Future<SatThumb>>{};

  /// disk cache เพดาน — sat_thumbs/ โตไม่จำกัดจะกินพื้นที่เครื่อง
  /// สเปกต่ำ ลบไฟล์เก่าสุดออกเหลือตาม limit (re-fetch ได้เสมอ)
  static const _diskCacheLimit = 400;
  static const _capInterval = Duration(minutes: 10);
  static DateTime? _lastCapRun;

  /// LRU บน disk — list+stat ทั้งโฟลเดอร์แพง เลย throttle ไว้
  /// 10 นาที/รอบ (ไฟล์ใหม่ต่อรอบไม่กี่ใบ overrun นิดไม่เป็นไร)
  static Future<void> _capDiskCache(Directory appDir) async {
    final now = DateTime.now();
    final last = _lastCapRun;
    if (last != null && now.difference(last) < _capInterval) return;
    _lastCapRun = now;
    try {
      final dir = Directory('${appDir.path}/sat_thumbs');
      if (!await dir.exists()) return;
      final files = <File>[];
      await for (final e in dir.list()) {
        if (e is File) files.add(e);
      }
      if (files.length <= _diskCacheLimit) return;
      final mtime = {for (final f in files) f: (await f.stat()).modified};
      files.sort((a, b) => mtime[a]!.compareTo(mtime[b]!));
      for (final f in files.take(files.length - _diskCacheLimit)) {
        await f.delete().catchError((_) => f);
      }
    } catch (_) {}
  }

  /// โหลด thumbnail พร้อม LRU memory cache — future ที่ fail
  /// (เน็ตหลุดกลางดึง tile) ถูกถอดออกจาก cache เพื่อให้ retry ได้
  static Future<SatThumb> load(
    String cacheKey,
    List<ll.LatLng> points,
    int w,
    int h,
  ) {
    final memKey = '$cacheKey|${w}x$h';
    final hit = _cache.remove(memKey); // touch → ไปท้าย (LRU)
    if (hit != null) return _cache[memKey] = hit;
    if (_cache.length >= _memCacheLimit) {
      _cache.remove(_cache.keys.first);
    }
    final fut = _load(points, cacheKey, w, h);
    _cache[memKey] = fut;
    fut.then<void>(
      (_) {},
      onError: (_) {
        if (identical(_cache[memKey], fut)) _cache.remove(memKey);
      },
    );
    return fut;
  }

  static Future<ui.Image> _decode(List<int> bytes) async {
    final codec = await ui.instantiateImageCodec(
      bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
    );
    return (await codec.getNextFrame()).image;
  }

  static Future<void> _cachePng(File file, ui.Image img) async {
    try {
      await file.parent.create(recursive: true);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return; // encode ล้มเหลว — ข้าม cache เงียบๆ
      await file.writeAsBytes(data.buffer.asUint8List());
    } catch (_) {}
  }

  /// อ่านภาพจาก disk cache — ไฟล์เสีย (เขียนไม่ครบตอนเครื่องดับ) ลบทิ้ง
  /// แล้วคืน null ให้ไปดึงเน็ตต่อ ไม่งั้น thumbnail พังถาวร
  static Future<ui.Image?> _readCached(File file) async {
    if (!await file.exists()) return null;
    try {
      return await _decode(await file.readAsBytes());
    } catch (_) {
      await file.delete().catchError((_) => file);
      return null;
    }
  }

  static Future<SatThumb> _load(
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
        (satPx(maxLng, gz) - satPx(minLng, gz) > gw * 0.82 ||
            satPy(minLat, gz) - satPy(maxLat, gz) > gh * 0.82)) {
      gz--;
    }
    final gFile = File(
      '${dir.path}/sat_thumbs/${cacheKey}_${gw}x${gh}_g$gz.png',
    );
    final gOriginX = satPx(cLng, gz) - gw / 2;
    final gOriginY = satPy(cLat, gz) - gh / 2;
    final gCached = await _readCached(gFile);
    if (gCached != null) {
      return SatThumb(gCached, gOriginX, gOriginY, gz, 2);
    }
    final key = await _mapsKey;
    if (key != null && key.isNotEmpty) {
      try {
        final res = await http
            .get(
              Uri.parse(
                'https://maps.googleapis.com/maps/api/staticmap'
                '?center=$cLat,$cLng&zoom=$gz&size=${gw}x$gh'
                '&scale=2&maptype=satellite&key=$key',
              ),
            )
            .timeout(const Duration(seconds: 15));
        if (res.statusCode == 200) {
          final img = await _decode(res.bodyBytes);
          await _cachePng(gFile, img);
          unawaited(_capDiskCache(dir));
          return SatThumb(img, gOriginX, gOriginY, gz, 2);
        }
      } catch (_) {}
    }

    // --- fallback Esri World Imagery (ฟรี ไม่ต้องมี key) ---
    // zoom ละเอียดสุดที่ bbox ครอบใน ≤3×3 tile
    var z = 17;
    int x0, x1, y0, y1;
    while (true) {
      x0 = satPx(minLng, z) ~/ 256;
      x1 = satPx(maxLng, z) ~/ 256;
      y0 = satPy(maxLat, z) ~/ 256;
      y1 = satPy(minLat, z) ~/ 256;
      if ((x1 - x0 + 1) * (y1 - y0 + 1) <= 9 || z <= 8) break;
      z--;
    }
    final file = File('${dir.path}/sat_thumbs/${cacheKey}_z$z.png');
    final cached = await _readCached(file);
    if (cached != null) {
      return SatThumb(cached, x0 * 256.0, y0 * 256.0, z, 1);
    }
    // composite tile ทั้งหมดที่ bbox ทับ — ดาวน์โหลดขนานกัน
    // (ทีละอัน worst case = 9×15s timeout = นานกว่า 2 นาทีต่อการ์ด)
    final tw = (x1 - x0 + 1) * 256, th = (y1 - y0 + 1) * 256;
    final futures = [
      for (var x = x0; x <= x1; x++)
        for (var y = y0; y <= y1; y++)
          (() async {
            final res = await http
                .get(
                  Uri.parse(
                    'https://server.arcgisonline.com/ArcGIS/rest/'
                    'services/World_Imagery/MapServer/tile/$z/$y/$x',
                  ),
                )
                .timeout(const Duration(seconds: 15));
            if (res.statusCode != 200) throw Exception('tile $z/$y/$x');
            return (x: x, y: y, img: await _decode(res.bodyBytes));
          })(),
    ];
    final List<({int x, int y, ui.Image img})> tiles;
    try {
      tiles = await Future.wait(futures);
    } catch (_) {
      // tile ที่ decode เสร็จก่อนตัวอื่นพัง — dispose คืน GPU memory
      // ไม่ปล่อยค้างทุกครั้งที่โหลด thumb ล้ม
      for (final f in futures) {
        unawaited(f.then((t) => t.img.dispose(), onError: (_) {}));
      }
      rethrow;
    }
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    for (final t in tiles) {
      canvas.drawImage(
        t.img,
        Offset((t.x - x0) * 256.0, (t.y - y0) * 256.0),
        Paint(),
      );
    }
    final img = await rec.endRecording().toImage(tw, th);
    // tile ย่อยถูกวาดลง canvas แล้ว — dispose ทิ้งทันที ไม่ปล่อย
    // ให้ GPU memory ค้างรอ GC บนเครื่อง RAM น้อย
    for (final t in tiles) {
      t.img.dispose();
    }
    await _cachePng(file, img);
    unawaited(_capDiskCache(dir));
    return SatThumb(img, x0 * 256.0, y0 * 256.0, z, 1);
  }
}

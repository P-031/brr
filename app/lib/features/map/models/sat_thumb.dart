import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:latlong2/latlong.dart' as ll;

/// ผลโหลด thumbnail — bitmap + origin (mercator px ขอบซ้ายบนของภาพ) +
/// zoom + imgScale (image px ต่อ 1 mercator px: google scale=2, esri=1)
class SatThumb {
  SatThumb(this.image, this.originX, this.originY, this.zoom, this.imgScale);
  final ui.Image image;
  final double originX;
  final double originY;
  final int zoom;
  final double imgScale;
}

/// loader ของ thumbnail — VM ผูก SatelliteThumbService.load เข้ามาให้
/// widget (view ไม่เห็นชั้น data ตรงๆ ตาม MVVM)
typedef SatThumbLoader = Future<SatThumb> Function(
  String cacheKey,
  List<ll.LatLng> points,
  int w,
  int h,
);

/// Web-Mercator pixel space ที่ zoom z (tile ละ 256px)
double satPx(double lng, int z) => (lng + 180) / 360 * 256 * (1 << z);

double satPy(double lat, int z) {
  final r = lat * math.pi / 180;
  return (1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) /
      2 *
      256 *
      (1 << z);
}

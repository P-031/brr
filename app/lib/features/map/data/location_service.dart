import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// Device location source — permission handling plus the position
/// stream used by walk-measure mode. Views never call Geolocator
/// directly.
class LocationService {
  /// Ensures location services are on and permission granted.
  Future<bool> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    return perm == LocationPermission.always ||
        perm == LocationPermission.whileInUse;
  }

  /// One-shot position — returns null when permission is missing.
  /// ลอง lastKnown ก่อน (~instant พอสำหรับตั้งกล้อง) ถ้าไม่มีค่อย
  /// รอ fix ใหม่แต่จำกัด 10 วิ — เครื่องไม่มี fix เดิมจะได้
  /// fallback เร็วแทนที่จะรอค้าง
  Future<LatLng?> currentPosition() async {
    if (!await ensurePermission()) return null;
    final last = await Geolocator.getLastKnownPosition();
    if (last != null) return LatLng(last.latitude, last.longitude);
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          timeLimit: Duration(seconds: 10),
        ),
      );
      return LatLng(p.latitude, p.longitude);
    } catch (_) {
      return null;
    }
  }

  /// Continuous fixes for walk-measure — ~3 m between emissions.
  Stream<Position> positionStream() => Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 3,
    ),
  );
}

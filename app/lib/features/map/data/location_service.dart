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
  Future<LatLng?> currentPosition() async {
    if (!await ensurePermission()) return null;
    final p = await Geolocator.getCurrentPosition();
    return LatLng(p.latitude, p.longitude);
  }

  /// Continuous fixes for walk-measure — ~3 m between emissions.
  Stream<Position> positionStream() => Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 3,
    ),
  );
}

import 'dart:math';

import 'package:latlong2/latlong.dart';

/// A land parcel fetched from the backend — boundary coordinates plus
/// a display name. Area is computed locally with the shoelace formula.
class Parcel {
  const Parcel({
    required this.id,
    required this.name,
    required this.points,
  });

  final String id;
  final String name;
  final List<LatLng> points;

  factory Parcel.fromJson(Map<String, dynamic> json) {
    final coords = (json['coordinates'] as List)
        .map(
          (c) => LatLng(
            (c[0] as num).toDouble(),
            (c[1] as num).toDouble(),
          ),
        )
        .toList();
    return Parcel(
      id: json['id'] as String,
      name: json['name'] as String,
      points: coords,
    );
  }

  LatLng get center {
    var lat = 0.0, lng = 0.0;
    for (final p in points) {
      lat += p.latitude;
      lng += p.longitude;
    }
    return LatLng(lat / points.length, lng / points.length);
  }

  /// Approximate area in square meters (shoelace on projected coords).
  double get areaSquareMeters {
    if (points.length < 3) return 0;
    const mPerDegLat = 111320.0;
    final cosLat = cos(points.first.latitude * pi / 180);
    double sum = 0;
    for (var i = 0; i < points.length; i++) {
      final a = points[i];
      final b = points[(i + 1) % points.length];
      final ax = a.longitude * mPerDegLat * cosLat;
      final ay = a.latitude * mPerDegLat;
      final bx = b.longitude * mPerDegLat * cosLat;
      final by = b.latitude * mPerDegLat;
      sum += ax * by - bx * ay;
    }
    return (sum / 2).abs();
  }

  /// Thai land unit: 1 rai = 1600 m².
  double get areaRai => areaSquareMeters / 1600;
}

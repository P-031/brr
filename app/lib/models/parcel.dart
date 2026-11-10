import 'dart:math';

import 'package:latlong2/latlong.dart';

/// A land parcel fetched from the backend — boundary coordinates plus
/// a display name. Area is computed locally with the shoelace formula.
class Parcel {
  const Parcel({
    required this.id,
    required this.name,
    required this.points,
    this.variety,
    this.owner,
  });

  final String id;
  final String name;
  final String? variety;
  final String? owner;
  final List<LatLng> points;

  /// Backend `/plots/map` item — outline is a list of
  /// `{latitude, longitude}` objects.
  factory Parcel.fromJson(Map<String, dynamic> json) {
    final outline = (json['outline'] as List? ?? [])
        .map(
          (c) => LatLng(
            (c['latitude'] as num).toDouble(),
            (c['longitude'] as num).toDouble(),
          ),
        )
        .toList();
    final farmer = json['farmer'] as Map<String, dynamic>?;
    return Parcel(
      id: '${json['id']}',
      name: '${json['name']}',
      variety: json['variety'] as String?,
      owner: farmer?['displayName'] as String?,
      points: outline,
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

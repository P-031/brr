import 'package:latlong2/latlong.dart';
import 'package:maps_toolkit/maps_toolkit.dart' as mt;

/// A land parcel fetched from the backend — boundary coordinates plus
/// a display name. Area is computed locally with the shoelace formula.
class Parcel {
  const Parcel({
    required this.id,
    required this.name,
    required this.points,
    this.variety,
    this.owner,
    this.status,
    this.productionYear,
    this.centerOverride,
    this.isDraft = false,
  });

  final String id;
  final String name;
  final String? variety;
  final String? owner;
  final String? productionYear;

  /// Approval status — backend supplies it later; until then items
  /// land in the 'รออนุมัติ' tab.
  final String? status;
  final List<LatLng> points;

  /// Device-only draft saved with "บันทึกร่าง" — never posted to the
  /// backend; persisted in SharedPreferences so it survives restarts.
  final bool isDraft;

  /// Backend-supplied centroid — preferred over averaging when set.
  final LatLng? centerOverride;

  /// Backend shape — `/plots/map` returns `outline`, while `POST /plots`
  /// and `/plots/:id` return `points`; both are `{latitude, longitude}`.
  factory Parcel.fromJson(Map<String, dynamic> json) {
    final raw = (json['outline'] ?? json['points']) as List? ?? [];
    final points = raw
        .map(
          (c) => LatLng(
            (c['latitude'] as num).toDouble(),
            (c['longitude'] as num).toDouble(),
          ),
        )
        .toList();
    final farmer = json['farmer'] as Map<String, dynamic>?;
    final center = json['center'] as Map<String, dynamic>?;
    return Parcel(
      id: '${json['id']}',
      name: '${json['name']}',
      variety: json['variety'] as String?,
      owner: farmer?['displayName'] as String?,
      status: json['status'] as String?,
      productionYear:
          (json['meta'] as Map<String, dynamic>?)?['productionYear']
              as String? ??
          json['productionYear'] as String?,
      points: points,
      isDraft: json['isDraft'] == true,
      centerOverride: center == null
          ? null
          : LatLng(
              (center['latitude'] as num).toDouble(),
              (center['longitude'] as num).toDouble(),
            ),
    );
  }

  /// Local persistence for drafts — SharedPreferences JSON.
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'variety': variety,
    'owner': owner,
    'status': status,
    'productionYear': productionYear,
    'isDraft': isDraft,
    'points': [
      for (final p in points)
        {'latitude': p.latitude, 'longitude': p.longitude},
    ],
  };

  LatLng get center {
    if (centerOverride != null) return centerOverride!;
    if (points.isEmpty) return const LatLng(0, 0);
    var lat = 0.0, lng = 0.0;
    for (final p in points) {
      lat += p.latitude;
      lng += p.longitude;
    }
    return LatLng(lat / points.length, lng / points.length);
  }

  /// Geodesic area in square meters — spherical-excess formula on the
  /// WGS84 mean radius, the same algorithm Google Maps uses
  /// (SphericalUtil.computeArea). Accurate to ~0.1% for land parcels.
  /// TODO: once the backend is connected, PostGIS `ST_Area(geography)`
  /// should be the authoritative value (full-ellipsoid precision).
  double get areaSquareMeters {
    if (points.length < 3) return 0;
    return mt.SphericalUtil.computeArea([
      for (final p in points) mt.LatLng(p.latitude, p.longitude),
    ]).toDouble();
  }

  /// Thai land unit: 1 rai = 1600 m².
  double get areaRai => areaSquareMeters / 1600;

  /// Formats square meters as Thai land units —
  /// "x ไร่ y งาน z ตร.วา" (1 ไร่ = 4 งาน, 1 งาน = 100 ตร.วา).
  static String formatThaiArea(double sqm) {
    final sqWa = sqm / 4; // 1 ตร.วา = 4 ตร.ม.
    final rai = sqWa ~/ 400;
    final ngan = (sqWa % 400) ~/ 100;
    final wa = sqWa % 100;
    return '$rai ไร่ $ngan งาน ${wa.toStringAsFixed(0)} ตร.วา';
  }

  String get areaThai => formatThaiArea(areaSquareMeters);
}

/// A farmer account an officer can pick as the plot owner —
/// `{id, displayName}` pair from `/accounts/farmers`.
class FarmerRef {
  const FarmerRef({required this.id, required this.name});

  final String id;
  final String name;
}

/// `{code, name}` pair for pickers whose value isn't the display text
/// (e.g. prevPlots carries the plot id in [code]).
typedef OptionItem = ({String code, String name});

/// Option lists for the measurement save form — fetched from the
/// backend (`GET /meta/options`), never hardcoded in the app.
class FormOptions {
  const FormOptions({
    this.zones = const [],
    this.provinces = const [],
    this.locations = const {},
    this.projects = const [],
    this.caneGroups = const [],
    this.caneTypes = const [],
    this.caneVarieties = const [],
    this.ownerships = const [],
    this.terrains = const [],
    this.lossOptions = const [],
    this.prevPlots = const [],
  });

  factory FormOptions.fromJson(Map<String, dynamic> j) {
    List<String> names(String k) =>
        [for (final v in j[k] as List? ?? const []) '$v'];
    return FormOptions(
      zones: names('zones'),
      provinces: names('provinces'),
      locations: _parseLocations(j['locations']),
      projects: names('projects'),
      caneGroups: names('caneGroups'),
      caneTypes: names('caneTypes'),
      caneVarieties: names('caneVarieties'),
      ownerships: names('ownerships'),
      terrains: names('terrains'),
      lossOptions: names('lossOptions'),
      prevPlots: [
        for (final v in j['prevPlots'] as List? ?? const [])
          (code: '${v['code']}', name: '${v['name']}'),
      ],
    );
  }

  /// จังหวัด → อำเภอ → ตำบล → [หมู่บ้าน] for cascading pickers.
  static Map<String, Map<String, Map<String, List<String>>>>
      _parseLocations(dynamic j) {
    if (j is! Map) return const {};
    List<String> strs(dynamic v) =>
        [for (final e in v as List? ?? const []) '$e'];
    Map<String, List<String>> tambons(dynamic v) => {
      if (v is Map)
        for (final e in v.entries) '${e.key}': strs(e.value),
    };
    Map<String, Map<String, List<String>>> districts(dynamic v) => {
      if (v is Map)
        for (final e in v.entries) '${e.key}': tambons(e.value),
    };
    return {
      for (final e in j.entries) '${e.key}': districts(e.value),
    };
  }

  /// อำเภอในจังหวัดที่เลือก — empty until a province is picked.
  List<String> districtsOf(String? province) =>
      locations[province]?.keys.toList() ?? const [];

  /// ตำบลในอำเภอที่เลือก.
  List<String> subdistrictsOf(String? province, String? district) =>
      locations[province]?[district]?.keys.toList() ?? const [];

  /// หมู่บ้านในตำบลที่เลือก.
  List<String> villagesOf(
    String? province,
    String? district,
    String? subdistrict,
  ) =>
      locations[province]?[district]?[subdistrict] ?? const [];

  final List<String> zones;
  final List<String> provinces;
  final Map<String, Map<String, Map<String, List<String>>>> locations;
  final List<String> projects;
  final List<String> caneGroups;
  final List<String> caneTypes;
  final List<String> caneVarieties;
  final List<String> ownerships;
  final List<String> terrains;
  final List<String> lossOptions;
  final List<OptionItem> prevPlots;
}

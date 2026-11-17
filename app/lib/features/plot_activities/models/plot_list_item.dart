import 'package:latlong2/latlong.dart';

import 'package:brr/features/map/models/parcel.dart';

/// แถวข้อมูลแปลงจาก `GET /plots` (list endpoint) — เบากว่า Parcel
/// เพราะไม่มี outline; meta ถูกแบนออกมาเป็นฟิลด์ที่ใช้โชว์การ์ด
class PlotListItem {
  const PlotListItem({
    required this.id,
    required this.name,
    this.farmerName,
    this.farmerCode,
    this.rootNo,
    this.sequenceNo,
    this.productionYear,
    this.caneGroup,
    this.zone,
    this.caneType,
    this.caneVariety,
    this.village,
    this.subdistrict,
    this.district,
    this.province,
    this.areaSqm,
    this.centerLat,
    this.centerLng,
    this.points = const [],
  });

  final String id;
  final String name;
  final String? farmerName;
  final String? farmerCode;
  final String? rootNo;
  final String? sequenceNo;
  final String? productionYear;
  final String? caneGroup;
  final String? zone;
  final String? caneType;
  final String? caneVariety;
  final String? village;
  final String? subdistrict;
  final String? district;
  final String? province;
  final double? areaSqm;
  final double? centerLat;
  final double? centerLng;

  /// เส้นขอบแปลงตอนวัด (latlong2) — backend ส่งมาใน `outline`
  /// ใช้วาด thumbnail สี่เหลี่ยมหน้าการ์ด
  final List<LatLng> points;

  factory PlotListItem.fromJson(Map<String, dynamic> j) {
    final meta = j['meta'] as Map<String, dynamic>? ?? const {};
    final farmer = j['farmer'] as Map<String, dynamic>?;
    final center = j['center'] as Map<String, dynamic>?;
    String? s(String k) {
      final v = meta[k];
      return v == null || '$v'.isEmpty ? null : '$v';
    }

    return PlotListItem(
      id: '${j['id']}',
      // ตัด " #ตัวเลข" ท้ายชื่อออก — โชว์แค่ชื่อแปลงที่บันทึกไว้
      name: '${j['name']}'.replaceAll(RegExp(r'\s*#\d+\s*$'), ''),
      farmerName: farmer?['displayName'] as String?,
      farmerCode: farmer?['username'] as String?,
      rootNo: s('rootNo'),
      sequenceNo: s('sequenceNo'),
      productionYear: s('productionYear'),
      caneGroup: s('caneGroup'),
      zone: s('zone'),
      caneType: s('caneType'),
      caneVariety: s('caneVariety'),
      village: s('village'),
      subdistrict: s('subdistrict'),
      district: s('district'),
      province: s('province'),
      areaSqm: (j['areaSqm'] as num?)?.toDouble(),
      centerLat: (center?['latitude'] as num?)?.toDouble(),
      centerLng: (center?['longitude'] as num?)?.toDouble(),
      points: [
        for (final c in j['outline'] as List? ?? const [])
          if (c is Map)
            LatLng(
              (c['latitude'] as num).toDouble(),
              (c['longitude'] as num).toDouble(),
            ),
      ],
    );
  }

  /// พื้นที่เป็นหน่วยไทย — ใช้ formatter เดียวกับ Parcel
  String get areaThai => Parcel.formatThaiArea(areaSqm ?? 0);

  /// สถานะปลูก — ตรงกับเกณฑ์ backend (caneType มีค่า = ปลูกแล้ว)
  bool get planted => caneType != null && caneType!.isNotEmpty;

  /// ที่ตั้งรวมบรรทัดเดียว — เอาเฉพาะส่วนที่มีค่า
  String get locationText => [
    if (village != null) 'บ้าน$village',
    if (subdistrict != null) 'ต.$subdistrict',
    if (district != null) 'อ.$district',
    if (province != null) 'จ.$province',
  ].join(' ');
}

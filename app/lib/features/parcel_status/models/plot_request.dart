import 'package:latlong2/latlong.dart';

/// คำขอแปลงจาก `GET /plot-requests` — บันทึกจริงบน backend
/// (ตาราง PlotRequest) ใช้แสดงในหน้าสถานะแปลงตาม tab
class PlotRequestEntry {
  const PlotRequestEntry({
    required this.id,
    required this.plotId,
    required this.plotName,
    required this.kind,
    required this.status,
    required this.createdAt,
    this.productionYear,
    this.requester,
    this.payload = const {},
    this.points = const [],
  });

  final String id;
  final String plotId;
  final String plotName;
  final String? productionYear;

  /// ชื่อผู้ส่งคำขอ (displayName)
  final String? requester;

  /// status | edit | group
  final String kind;
  final Map<String, dynamic> payload;
  final String status;
  final DateTime? createdAt;

  /// เส้นขอบแปลงจาก `outline` — วาด thumbnail ดาวเทียมบนการ์ด
  final List<LatLng> points;

  /// ค่าหลักของคำขอ — status/edit = value(+เหตุผลประกอบ),
  /// group = รวมชื่อกลุ่ม
  String get detail {
    final v = payload['value'];
    final reason = payload['reason'];
    if (v is String && v.isNotEmpty) {
      final extras = [
        if (reason is String && reason.isNotEmpty) reason,
        if (payload['canePlantMode'] case final s?)
          'อ้อยหลักใหม่: $s',
        if (payload['caneTypeNew'] case final s?)
          'อ้อยปลูกใหม่: $s',
        if (payload['newPlotCode'] case final s?)
          'รหัสแปลงใหม่: $s',
        if (payload['newFarmer'] case final s?) 'ชาวไร่ใหม่: $s',
      ];
      return extras.isEmpty ? v : '$v — ${extras.join(' • ')}';
    }
    final parts = [
      if (payload['maintainGroup'] case final s?)
        'กลุ่มบำรุง: $s',
      if (payload['harvestGroup'] case final s?) 'กลุ่มตัด: $s',
    ];
    return parts.join('  •  ');
  }

  String get kindLabel => switch (kind) {
    'status' => 'คำขอเปลี่ยนสถานะ',
    'edit' => 'คำขอแก้ไขข้อมูล',
    'group' => 'คำขอจัดกลุ่ม',
    _ => kind,
  };

  factory PlotRequestEntry.fromJson(Map<String, dynamic> j) =>
      PlotRequestEntry(
        id: '${j['id'] ?? ''}',
        plotId: '${j['plotId'] ?? ''}',
        plotName: '${j['plotName'] ?? ''}',
        productionYear: j['productionYear'] as String?,
        requester: j['requester'] as String?,
        kind: '${j['kind'] ?? ''}',
        payload: j['payload'] is Map<String, dynamic>
            ? j['payload'] as Map<String, dynamic>
            : const {},
        status: '${j['status'] ?? ''}',
        createdAt: DateTime.tryParse('${j['createdAt']}'),
        points: [
          for (final c in j['outline'] as List? ?? const [])
            if (c is Map && c['latitude'] is num && c['longitude'] is num)
              LatLng(
                (c['latitude'] as num).toDouble(),
                (c['longitude'] as num).toDouble(),
              ),
        ],
      );
}

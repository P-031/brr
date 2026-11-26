import 'package:latlong2/latlong.dart';

import 'package:brr/features/map/models/geo_outline.dart';

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
    this.farmerName,
    this.areaSqm,
    this.payload = const {},
    this.points = const [],
  });

  final String id;
  final String plotId;
  final String plotName;
  final String? productionYear;

  /// ชื่อชาวไร่เจ้าของแปลง + พื้นที่ ตร.ม. — officer ใช้ประกอบ
  /// การตัดสิน (backend แนบมาตั้งแต่ GET /plot-requests)
  final String? farmerName;
  final double? areaSqm;

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
        if (payload['canePlantMode'] case final s?) 'อ้อยหลักใหม่: $s',
        if (payload['caneTypeNew'] case final s?) 'อ้อยปลูกใหม่: $s',
        if (payload['newPlotCode'] case final s?) 'รหัสแปลงใหม่: $s',
        if (payload['newFarmer'] case final s?) 'ชาวไร่ใหม่: $s',
        if (payload['newProductionYear'] case final s?) 'ปีการผลิตใหม่: $s',
        if (payload['newZone'] case final s?) 'เขตใหม่: $s',
      ];
      return extras.isEmpty ? v : '$v — ${extras.join(' • ')}';
    }
    final parts = [
      if (payload['maintainGroup'] case final s?) 'กลุ่มบำรุง: $s',
      if (payload['harvestGroup'] case final s?) 'กลุ่มตัด: $s',
    ];
    return parts.join('  •  ');
  }

  /// ทุกฟิลด์ที่ส่งมาในคำขอเป็นคู่ (label, ค่า) — หน้าอนุมัติ
  /// ต้องเห็นรายละเอียดครบก่อนตัดสิน ไม่ย่อเป็นบรรทัดเดียว
  List<(String, String)> get detailRows {
    final rows = <(String, String)>[];
    void add(String label, dynamic raw) {
      if (raw is String && raw.isNotEmpty) rows.add((label, raw));
    }

    add(
      switch (kind) {
        'status' => 'สถานะที่ขอ',
        'edit' => 'สิ่งที่ขอแก้ไข',
        _ => 'รายละเอียด',
      },
      payload['value'],
    );
    add('เหตุผลประกอบ', payload['reason']);
    add('อ้อยหลักใหม่', payload['canePlantMode']);
    add('อ้อยปลูกใหม่', payload['caneTypeNew']);
    add('รหัสแปลงใหม่', payload['newPlotCode']);
    add('ชาวไร่ใหม่', payload['newFarmer']);
    add('รหัสชาวไร่ใหม่', payload['newFarmerId']);
    add('ปีการผลิตใหม่', payload['newProductionYear']);
    add('เขตใหม่', payload['newZone']);
    add('กลุ่มบำรุง', payload['maintainGroup']);
    add('กลุ่มตัด', payload['harvestGroup']);
    return rows;
  }

  String get kindLabel => switch (kind) {
    'status' => 'คำขอเปลี่ยนสถานะ',
    'edit' => 'คำขอแก้ไขข้อมูล',
    'group' => 'คำขอจัดกลุ่ม',
    _ => kind,
  };

  factory PlotRequestEntry.fromJson(Map<String, dynamic> j) => PlotRequestEntry(
    id: '${j['id'] ?? ''}',
    plotId: '${j['plotId'] ?? ''}',
    plotName: '${j['plotName'] ?? ''}',
    productionYear: j['productionYear']?.toString(),
    requester: j['requester']?.toString(),
    farmerName: j['farmerName']?.toString(),
    areaSqm: j['areaSqm'] is num ? (j['areaSqm'] as num).toDouble() : null,
    kind: '${j['kind'] ?? ''}',
    payload: j['payload'] is Map
        ? Map<String, dynamic>.from(j['payload'] as Map)
        : const {},
    status: '${j['status'] ?? ''}',
    createdAt: DateTime.tryParse('${j['createdAt']}'),
    points: outlineLatLngs(j['outline']),
  );
}

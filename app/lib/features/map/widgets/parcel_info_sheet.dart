import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax/iconsax.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:brr/core/theme/app_theme.dart';
import 'package:brr/features/map/models/parcel.dart';
import 'package:brr/features/map/viewmodels/parcel_detail_viewmodel.dart';
import 'package:brr/features/map/views/activity_record_view.dart';
import 'package:brr/features/map/views/parcel_detail_view.dart';
import 'package:brr/features/map/views/parcel_edit_views.dart';
import 'package:brr/features/map/widgets/risk_point_sheet.dart';

/// Sheet ข้อมูลแปลง (ตาม ref แอปจริง) — header เลขแปลง + ตารางข้อมูล
/// + เมนูทางลัด + กิจกรรม — ปุ่มทุกตัวยังเป็น stub (_todo) รอนิยาม
/// หน้าที่ทีหลัง
///
/// [onCovered] ยิง true ตอน sheet ลากขึ้นทับเต็มจอ — หน้าแผนที่ใช้
/// unmount GoogleMap ชั่วคราวตอนถูกทับมิด (กัน platform view เผาผลาญ
/// GPU ทั้งที่ไม่เห็น) แล้ว mount กลับตอน sheet หด/ปิด
Future<void> showParcelInfoSheet(
  BuildContext context, {
  required ParcelDetailViewModel vm,
  ValueChanged<bool>? onCovered,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    // Scaffold ชั้นใน — ให้ snackbar ของปุ่ม stub ลอยเหนือ sheet ได้
    // (ไม่งั้นไปโผล่ใต้ modal route)
    builder: (_) => Scaffold(
      backgroundColor: Colors.transparent,
      body: NotificationListener<DraggableScrollableNotification>(
        onNotification: (n) {
          onCovered?.call(n.extent >= 0.99);
          return false;
        },
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.9,
          minChildSize: 0.4,
          maxChildSize: 1.0,
          snap: true,
          builder: (_, scroll) => _ParcelInfoSheet(
            vm: vm,
            scrollController: scroll,
            onCovered: onCovered,
          ),
        ),
      ),
    ),
  );
}

class _ParcelInfoSheet extends StatefulWidget {
  const _ParcelInfoSheet({
    required this.vm,
    required this.scrollController,
    this.onCovered,
  });

  final ParcelDetailViewModel vm;
  final ScrollController scrollController;
  final ValueChanged<bool>? onCovered;

  @override
  State<_ParcelInfoSheet> createState() => _ParcelInfoSheetState();
}

class _ParcelInfoSheetState extends State<_ParcelInfoSheet> {
  /// จุดเสี่ยงที่บันทึกไว้ในเครื่องของแปลง — การ์ด preview ใช้โชว์
  /// สถานะ; refresh หลัง sheet ฟอร์มบันทึกกลับมา
  late Future<Map<String, dynamic>?> _riskPoint = widget.vm.riskPoint();

  /// meta/farmer ล่าสุดที่ build เตรียมไว้ — ปุ่มเมนูอ่านตอนกด
  Map<String, dynamic> _meta = const {};
  Map<String, dynamic>? _farmer;

  /// ตัวเลือกจุดเสี่ยงจาก backend (/meta/options → riskLevels)
  late final Future<FormOptions> _options = widget.vm.loadOptions();

  /// extent ล่าสุดของ sheet — ใช้คืนสถานะทับจอหลัง pop กลับจาก
  /// หน้ารายละเอียด (onCovered ไม่ refire ถ้า extent ไม่เปลี่ยน)
  double _extent = 0.9;

  /// เมนูทางลัด — (icon, label, color) หน้าที่แต่ละอันรอนิยาม
  static const _menus = [
    (Iconsax.send_2, 'นำทาง', AppColors.sky),
    (Iconsax.home_2, 'บ้านชาวไร่', AppColors.gold),
    (Iconsax.call, 'เบอร์โทร', AppColors.green),
    (Iconsax.edit_2, 'แก้ไข รูท & ลำดับ', AppColors.green),
    (Iconsax.refresh, 'คำขออัปเดตสถานะแปลง1', AppColors.green),
    (Iconsax.clock, 'คำขออัปเดตสถานะแปลง2', AppColors.green),
    (Iconsax.more, 'กลุ่มบำรุง / ตัด', AppColors.green),
  ];

  static const _thaiMonths = [
    'ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.',
    'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.',
  ];

  static String? _str(dynamic v) {
    final s = '$v';
    return (v == null || s.isEmpty) ? null : s;
  }

  /// วันปลูก — meta.plantedAt ยังไม่มีใน schema ตอนนี้ fallback
  /// createdAt ของ record ไปก่อน (เปลี่ยนทีหลังได้จุดเดียว)
  static DateTime? _plantedDate(Map meta, Map<String, dynamic>? detail) {
    for (final k in ['plantedAt', 'plantDate', 'plantedDate']) {
      final d = DateTime.tryParse('${meta[k]}');
      if (d != null) return d;
    }
    return DateTime.tryParse('${detail?['createdAt']}');
  }

  static String _fmtDate(DateTime d) =>
      '${d.day} ${_thaiMonths[d.month - 1]} ${d.year + 543}';

  /// stub ชั่วคราว — แตะแล้วบอกว่าปุ่มไหนถูกกด รอผู้ใช้นิยามการทำงานจริง
  void _todo(String label) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label — ยังไม่เปิดใช้งาน')),
    );
  }

  /// push หน้าเต็มจอ (รายละเอียด/เมนูแก้ไข) — บอกหน้าแผนที่พัก
  /// platform view ระหว่างเปิด แล้วรายงาน extent จริงคืนหลัง pop
  void _pushFullScreen(Widget page) {
    widget.onCovered?.call(true);
    Navigator.of(context)
        .push(MaterialPageRoute<Object>(builder: (_) => page))
        .then((saved) {
          if (!mounted) return;
          widget.onCovered?.call(_extent >= 0.99);
          if (saved != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  saved is String ? saved : 'บันทึกสำเร็จ',
                ),
              ),
            );
          }
        });
  }

  /// เพิ่มเติม → push หน้ารายละเอียดเต็มจอ (แชร์ VM เดียวกัน —
  /// PATCH จากหน้าลูกแล้ว sheet/detail เห็นค่าใหม่ทันที)
  void _openDetail() => _pushFullScreen(ParcelDetailView(vm: widget.vm));

  /// นำทาง — เปิด Google Maps เส้นทางไปยังพิกัดกึ่งกลางแปลงที่บันทึกไว้
  /// google.navigation = turn-by-turn ในแอป Maps โดยตรง (Android);
  /// ไม่มีแอป → fallback https เปิดใน browser/chooser
  Future<void> _navigate() async {
    final c = widget.vm.parcel.center;
    final latLng = '${c.latitude},${c.longitude}';
    for (final raw in [
      'google.navigation:q=$latLng',
      'https://www.google.com/maps/dir/?api=1&destination=$latLng',
    ]) {
      try {
        if (await launchUrl(
          Uri.parse(raw),
          mode: LaunchMode.externalApplication,
        )) {
          return;
        }
      } catch (_) {
        // plugin channel ยังไม่ขึ้น (hot reload หลังเพิ่ม package)
        // → ลอง fallback ถัดไป
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ไม่สามารถเปิด Google Maps ได้')),
      );
    }
  }

  /// บ้านชาวไร่ — dialog ข้อมูลที่อยู่ที่เกี่ยวข้องจาก backend
  /// (หมู่บ้าน/ตำบล/อำเภอ/จังหวัด) เฉพาะฟิลด์ที่มีค่าจริง
  void _farmerHome() {
    final name = _str(_farmer?['displayName']);
    final rows = <(String, String)>[
      if (name != null) ('ชาวไร่', name),
      for (final (k, label) in const [
        ('village', 'หมู่บ้าน'),
        ('subdistrict', 'ตำบล'),
        ('district', 'อำเภอ'),
        ('province', 'จังหวัด'),
      ])
        if (_str(_meta[k]) != null) (label, _str(_meta[k])!),
    ];
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        icon: const Icon(Iconsax.home_2, color: AppColors.gold, size: 28),
        title: const Text('บ้านชาวไร่'),
        content: rows.isEmpty
            ? const Text('ยังไม่มีข้อมูลที่อยู่')
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final (label, value) in rows)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text.rich(
                        TextSpan(
                          text: '$label : ',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                          children: [
                            TextSpan(
                              text: value,
                              style: const TextStyle(
                                fontWeight: FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('ปิด'),
          ),
        ],
      ),
    );
  }

  /// เบอร์โทร — เด้ง dialer พร้อมเบอร์ที่บันทึกไว้ (farmer.phone /
  /// meta.phone… — schema ยังไม่มีฟิลด์นี้ แสดงข้อความแทนจนกว่า
  /// backend จะมี)
  Future<void> _call() async {
    final phone =
        _str(_farmer?['phone']) ??
        _str(_meta['phone']) ??
        _str(_meta['farmerPhone']) ??
        _str(_meta['tel']);
    if (phone == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ไม่มีเบอร์โทรที่บันทึกไว้')),
      );
      return;
    }
    var ok = false;
    try {
      ok = await launchUrl(
        Uri.parse('tel:$phone'),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {}
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ไม่สามารถเปิดแอปโทรศัพท์ได้')),
      );
    }
  }

  /// ปุ่มเมนูที่ต่อหน้าจริงแล้ว — ที่เหลือยัง stub
  VoidCallback _menuAction(String label) {
    final vm = widget.vm;
    return switch (label) {
      'นำทาง' => () => _navigate(),
      'บ้านชาวไร่' => _farmerHome,
      'เบอร์โทร' => () => _call(),
      'แก้ไข รูท & ลำดับ' => () => _pushFullScreen(EditRouteSeqView(vm: vm)),
      'คำขออัปเดตสถานะแปลง1' => () => _pushFullScreen(
        StatusRequestView(vm: vm),
      ),
      'คำขออัปเดตสถานะแปลง2' => () => _pushFullScreen(
        EditRequestView(vm: vm),
      ),
      'กลุ่มบำรุง / ตัด' => () => _pushFullScreen(
        GroupRequestView(vm: vm),
      ),
      _ => () => _todo(label),
    };
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.vm.parcel;
    return ListenableBuilder(
      listenable: widget.vm,
      builder: (context, _) => FutureBuilder<Map<String, dynamic>?>(
        future: widget.vm.detail,
        builder: (context, snap) {
        final detail = snap.data;
        final meta =
            (detail?['meta'] as Map<String, dynamic>?) ?? p.meta ?? const {};
        final farmer = detail?['farmer'] as Map<String, dynamic>?;
        _meta = meta;
        _farmer = farmer;
        final farmerName = _str(farmer?['displayName']) ?? p.owner;
        final farmerCode = _str(farmer?['username']) ?? _str(farmer?['id']);
        final loadingDetail =
            snap.connectionState != ConnectionState.done && !p.isDraft;

        final planted = _plantedDate(meta, detail);
        final ageDays =
            planted == null ? null : DateTime.now().difference(planted).inDays;
        // พื้นที่แบบละเอียด "x ไร่ y งาน z ตร.วา" — detail มี area
        // จาก backend (splitThaiArea); draft ไม่มี detail ใช้คำนวณ
        // ฝั่งเครื่องแทน
        final areaMap = detail?['area'] as Map<String, dynamic>?;
        final areaText = areaMap == null
            ? p.areaThai
            : '${areaMap['rai'] ?? 0} ไร่ ${areaMap['ngan'] ?? 0} งาน '
                  '${(areaMap['wa'] as num? ?? 0).toStringAsFixed(0)} ตร.วา';
        final grade = _str(meta['grade']) ?? _str(meta['plotGrade']);
        final status = p.isDraft
            ? 'แปลงร่าง (ยังไม่บันทึก)'
            : _str(p.status) ?? _str(detail?['status']);
        final landNo = p.landNo;
        // รหัสแปลง = เลข #NNN ท้ายชื่อ (schema ไม่มีฟิลด์แยก)
        final plotCode = p.plotCode;

        // (label, value, ไฮไลต์ฟ้า) — แถวหลักโชว์เสมอ ค่าว่างแสดง '—'
        // (รองรับอนาคตที่ backend จะมีฟิลด์พวกนี้ครบ)
        final rows = <(String, String?, bool)>[
          ('ชื่อแปลง', landNo, false),
          ('ปีการผลิต', _str(meta['productionYear']) ?? p.productionYear, false),
          ('ประเภทอ้อย', _str(meta['caneType']), false),
          ('รหัสชาวไร่', farmerCode, true),
          ('ชื่อ(ชาวไร่)', farmerName, false),
          ('ชื่อ(ผู้ดูแล)', _str(meta['officerName']), false),
          ('พื้นที่', areaText, true),
          ('เขต', _str(meta['zone']), false),
          ('รูท', _str(meta['rootNo']), false),
          ('ลำดับ', _str(meta['sequenceNo']), false),
          ('ปลูกเมื่อ', planted == null ? null : _fmtDate(planted), false),
          ('สถานะแปลง', status, false),
        ];

        return NotificationListener<DraggableScrollableNotification>(
          onNotification: (n) {
            _extent = n.extent;
            return false; // ปล่อยลอยต่อไปหา listener ชั้นนอก (onCovered)
          },
          child: ListView(
          controller: widget.scrollController,
          // เผื่อ status bar — sheet ลากขึ้นเต็มจอได้ (max 1.0) เนื้อ
          // บนสุดจะได้ไม่จมใต้ status bar/รูกล้อง
          padding: EdgeInsets.fromLTRB(
            16,
            MediaQuery.of(context).padding.top + 10,
            16,
            32,
          ),
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    landNo,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: AppColors.green,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (ageDays != null && ageDays >= 0) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'อายุ $ageDays วัน',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.green,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, color: Colors.black54),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // หมายเลขแปลง + ปุ่มก็อป + เกรด — ไม่มีเลขโชว์ '—'
            // (รองรับอนาคต backend มีฟิลด์รหัส/เกรดจริงแยก)
            Row(
              children: [
                Text(
                  'หมายเลขแปลง : ${plotCode ?? '—'}',
                  style: const TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                if (plotCode != null)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'คัดลอกหมายเลขแปลง',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: plotCode));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('คัดลอกหมายเลขแปลงแล้ว'),
                        ),
                      );
                    },
                    icon: const Icon(
                      Iconsax.copy,
                      size: 20,
                      color: AppColors.green,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.gold, width: 1.4),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'แปลงเกรด ${grade ?? '—'}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppColors.gold,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            if (loadingDetail)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.green,
                      ),
                    ),
                    SizedBox(width: 8),
                    Text(
                      'กำลังโหลดรายละเอียด…',
                      style: TextStyle(fontSize: 15, color: Colors.black54),
                    ),
                  ],
                ),
              ),
            // ตารางข้อมูล — แถวสลับสีตาม ref
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < rows.length; i++)
                      _infoRow(rows[i], i.isOdd),
                    // เพิ่มเติม → push หน้ารายละเอียดเต็มจอ
                    InkWell(
                      onTap: _openDetail,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        color: rows.length.isOdd
                            ? const Color(0xFFF6F6F6)
                            : Colors.white,
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'เพิ่มเติม',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.black54,
                              ),
                            ),
                            Icon(
                              Iconsax.arrow_right_3,
                              size: 18,
                              color: Colors.black54,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 64),
            const Text(
              'เมนู',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 26),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 14,
              crossAxisSpacing: 12,
              childAspectRatio: 0.78,
              children: [
                for (final m in _menus)
                  _menuTile(m.$1, m.$2, m.$3, _menuAction(m.$2)),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'กิจกรรม',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _actionCard(
              color: Colors.white,
              border: Border.all(color: Colors.grey.shade300),
              leading: _iconBox(AppColors.green, Iconsax.clipboard_text),
              title: 'บันทึกกิจกรรม',
              subtitle: 'เก็บข้อมูล',
              onTap: () =>
                  _pushFullScreen(ActivityRecordView(vm: widget.vm)),
            ),
            const SizedBox(height: 10),
            _actionCard(
              color: const Color(0xFFF2F2F2),
              leading: const Icon(
                Iconsax.menu_1,
                color: Colors.black87,
                size: 30,
              ),
              title: 'ประวัติการบันทึกกิจกรรม',
              onTap: () => _todo('ประวัติการบันทึกกิจกรรม'),
            ),
            const SizedBox(height: 10),
            _actionCard(
              color: Colors.white,
              border: Border.all(color: Colors.grey.shade300),
              leading: const Icon(
                Iconsax.cloud_plus,
                color: AppColors.sky,
                size: 36,
              ),
              title: 'นำส่งกิจกรรมที่บันทึกไว้ในเครื่อง',
              subtitle: 'ส่งข้อมูลครบแล้ว (ไม่มีข้อมูลค้าง)',
              subtitleColor: AppColors.green,
              trailing: const Icon(
                Iconsax.arrow_right_3,
                color: Colors.black38,
                size: 24,
              ),
              onTap: () => _todo('นำส่งกิจกรรมที่บันทึกไว้ในเครื่อง'),
            ),
            const SizedBox(height: 10),
            _actionCard(
              color: AppColors.sky,
              leading: const Icon(
                Iconsax.calendar_edit,
                color: Colors.white,
                size: 36,
              ),
              title: 'อัปเดตสถานะแปลงตัด',
              subtitle: 'เปิดแปลง->ตัดอ้อย->ปิดแปลง',
              titleColor: Colors.white,
              subtitleColor: Colors.white70,
              trailing: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.help_outline,
                      size: 18,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _str(meta['cutStatus']) ?? 'ยังไม่ระบุ',
                      style: const TextStyle(fontSize: 14, color: Colors.white),
                    ),
                  ],
                ),
              ),
              onTap: () => _todo('อัปเดตสถานะแปลงตัด'),
            ),
            const SizedBox(height: 10),
            _actionCard(
              color: const Color(0xFF7B1FA2),
              leading: CircleAvatar(
                radius: 23,
                backgroundColor: Colors.white.withValues(alpha: 0.25),
                child: const Icon(
                  Iconsax.star_1,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              title: 'ข้อมูลโครงการส่งเสริมแปลง',
              subtitle: 'อัปเดตโครงการที่เข้าร่วม (นสล.)',
              titleColor: Colors.white,
              subtitleColor: Colors.white70,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _str(meta['project']) ?? 'ยังไม่ระบุ',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF7B1FA2),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(
                    Iconsax.arrow_right_3,
                    color: Colors.white70,
                    size: 24,
                  ),
                ],
              ),
              onTap: () => _todo('ข้อมูลโครงการส่งเสริมแปลง'),
            ),
            const SizedBox(height: 10),
            _actionCard(
              color: AppColors.green,
              leading: const Icon(
                Iconsax.tick_circle,
                color: Colors.white,
                size: 54,
              ),
              title: 'ยืนยันแปลง',
              subtitle: 'ยืนยันแปลงข้ามปี',
              titleColor: Colors.white,
              subtitleColor: Colors.white70,
              onTap: () => _todo('ยืนยันแปลง'),
            ),
            const SizedBox(height: 10),
            // การ์ดจุดเสี่ยง — preview สถานะที่บันทึกไว้ แตะเปิด
            // sheet ฟอร์มกำหนดจุดเสี่ยง (ประเภท/ชื่อ/ระดับ/หมายเหตุ)
            FutureBuilder<FormOptions>(
              future: _options,
              builder: (context, snap) {
                final levels = snap.data?.riskLevels ?? const <String>[];
                if (levels.isEmpty) return const SizedBox.shrink();
                return FutureBuilder<Map<String, dynamic>?>(
                  future: _riskPoint,
                  builder: (context, r) {
                    final saved = r.data;
                    return InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: _openRiskSheet,
                      child: Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'กำหนดเป็นจุดเสี่ยงภัยพิบัติ',
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Icon(
                                  Iconsax.arrow_right_3,
                                  size: 20,
                                  color: Colors.black38,
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                for (var i = 0; i < levels.length; i++) ...[
                                  _riskPreviewChip(
                                    levels[i],
                                    '${saved?['type']}' == levels[i],
                                  ),
                                  if (i < levels.length - 1)
                                    const SizedBox(width: 10),
                                ],
                              ],
                            ),
                            if (saved != null) ...[
                              const SizedBox(height: 10),
                              Text(
                                'ระดับ ${saved['severity'] ?? '—'}'
                                '${'${saved['note'] ?? ''}'.isEmpty ? '' : ' • ${saved['note']}'}',
                                style: const TextStyle(
                                  fontSize: 14.5,
                                  color: Colors.black54,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ],
          ),
        );
        },
      ),
    );
  }

  /// แถวข้อมูลในตาราง — label ซ้ายเทา / value ขวา (highlight = ฟ้า)
  Widget _infoRow((String, String?, bool) row, bool shaded) {
    return Container(
      color: shaded ? const Color(0xFFF6F6F6) : Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Text(
              row.$1,
              style: const TextStyle(fontSize: 16, color: Colors.black87),
            ),
          ),
          Expanded(
            flex: 7,
            child: Text(
              row.$2 == null || row.$2!.isEmpty ? '—' : row.$2!,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: row.$3 ? AppColors.sky : Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// กระเบื้องเมนู — สี่เหลี่ยมขาวมน + icon สี + label ใต้
  Widget _menuTile(
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.grey.shade200),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Icon(icon, color: color, size: 34),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }

  /// การ์ดกิจกรรมแถวเดียว — leading icon + title/subtitle + trailing
  Widget _actionCard({
    required Color color,
    required Widget leading,
    required String title,
    String? subtitle,
    Color titleColor = Colors.black87,
    Color subtitleColor = Colors.black45,
    Widget? trailing,
    BoxBorder? border,
    VoidCallback? onTap,
  }) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          decoration: BoxDecoration(
            border: border,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              leading,
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: titleColor,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle,
                        style: TextStyle(fontSize: 15, color: subtitleColor),
                      ),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }

  /// กล่อง icon มุมมนพื้นสี — leading ของการ์ดขาว
  Widget _iconBox(Color bg, IconData icon) {
    return Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: Colors.white, size: 28),
    );
  }

  /// เปิด sheet ฟอร์มจุดเสี่ยง — บันทึกสำเร็จ refresh preview +
  /// แจ้ง snackbar; [type] = ประเภทที่เลือกมาจาก chip บนการ์ด
  Future<void> _openRiskSheet({String? type}) async {
    final saved = await showRiskPointSheet(
      context,
      vm: widget.vm,
      initialType: type,
    );
    if (!mounted) return;
    setState(() => _riskPoint = widget.vm.riskPoint());
    if (saved != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('บันทึกจุดเสี่ยงภัยแล้ว')),
      );
    }
  }

  /// chip preview ในการ์ด — แตะเลือกประเภทแล้วเปิด sheet ฟอร์ม
  /// พร้อมประเภทนั้น; ตัวที่บันทึกไว้ = พื้นเข้ม + ขอบสีชัด
  Widget _riskPreviewChip(String label, bool selected) {
    final (icon, bg, fg) = riskChipStyle(label);
    return Expanded(
      child: GestureDetector(
        onTap: () => _openRiskSheet(type: label),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            color: selected ? bg : bg.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? fg : Colors.grey.shade300,
              width: selected ? 2.2 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 21, color: fg),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: fg,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

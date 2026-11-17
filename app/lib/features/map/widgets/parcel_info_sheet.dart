import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import 'package:brr/core/theme/app_theme.dart';
import 'package:brr/features/map/models/parcel.dart';
import 'package:brr/features/map/viewmodels/parcel_detail_viewmodel.dart';
import 'package:brr/features/map/views/parcel_detail_view.dart';
import 'package:brr/features/map/views/parcel_edit_views.dart';

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
  String? _risk;

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
    (Iconsax.edit_2, 'แก้ไข รูท & ลำดับ', AppColors.navy),
    (Iconsax.refresh, 'คำขออัปเดตสถานะแปลง1', AppColors.navy),
    (Iconsax.clock, 'คำขออัปเดตสถานะแปลง2', AppColors.navy),
    (Iconsax.more, 'กลุ่มบำรุง / ตัด', AppColors.navy),
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
        .push(MaterialPageRoute<bool>(builder: (_) => page))
        .then((saved) {
          if (!mounted) return;
          widget.onCovered?.call(_extent >= 0.99);
          if (saved == true) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('บันทึกข้อมูลแล้ว')),
            );
          }
        });
  }

  /// เพิ่มเติม → push หน้ารายละเอียดเต็มจอ (แชร์ VM เดียวกัน —
  /// PATCH จากหน้าลูกแล้ว sheet/detail เห็นค่าใหม่ทันที)
  void _openDetail() => _pushFullScreen(ParcelDetailView(vm: widget.vm));

  /// ปุ่มเมนูที่ต่อหน้าจริงแล้ว — ที่เหลือยัง stub
  VoidCallback _menuAction(String label) {
    final vm = widget.vm;
    return switch (label) {
      'แก้ไข รูท & ลำดับ' => () => _pushFullScreen(EditRouteSeqView(vm: vm)),
      'คำขออัปเดตสถานะแปลง1' => () => _pushFullScreen(
        StatusRequestView(vm: vm),
      ),
      'คำขออัปเดตสถานะแปลง2' => () => _pushFullScreen(
        EditRequestView(vm: vm),
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
        final landNo = p.name.replaceAll(RegExp(r'\s*#\d+\s*$'), '');

        // (label, value, ไฮไลต์ฟ้า) — แถวหลักโชว์เสมอ ค่าว่างแสดง '—'
        // (รองรับอนาคตที่ backend จะมีฟิลด์พวกนี้ครบ)
        final rows = <(String, String?, bool)>[
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
            const Text(
              'Land No',
              style: TextStyle(fontSize: 12, color: Colors.black45),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Iconsax.crop, color: AppColors.navy, size: 30),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    landNo,
                    style: const TextStyle(
                      fontSize: 21,
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
                        fontSize: 13,
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
            if (grade != null) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.only(left: 40),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.gold, width: 1.4),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'แปลงเกรด $grade',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: AppColors.gold,
                    ),
                  ),
                ),
              ),
            ],
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
                      style: TextStyle(fontSize: 13, color: Colors.black54),
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
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.black54,
                              ),
                            ),
                            Icon(
                              Iconsax.arrow_right_3,
                              size: 16,
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
            const SizedBox(height: 36),
            const Text(
              'เมนู',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 14,
              crossAxisSpacing: 12,
              childAspectRatio: 0.9,
              children: [
                for (final m in _menus)
                  _menuTile(m.$1, m.$2, m.$3, _menuAction(m.$2)),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'กิจกรรม',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _actionCard(
              color: Colors.white,
              border: Border.all(color: Colors.grey.shade300),
              leading: _iconBox(AppColors.navy, Iconsax.clipboard_text),
              title: 'บันทึกกิจกรรม',
              subtitle: 'เก็บข้อมูล',
              onTap: () => _todo('บันทึกกิจกรรม'),
            ),
            const SizedBox(height: 10),
            _actionCard(
              color: const Color(0xFFF2F2F2),
              leading: const Icon(
                Iconsax.menu_1,
                color: Colors.black87,
                size: 22,
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
                size: 28,
              ),
              title: 'นำส่งกิจกรรมที่บันทึกไว้ในเครื่อง',
              subtitle: 'ส่งข้อมูลครบแล้ว (ไม่มีข้อมูลค้าง)',
              subtitleColor: AppColors.green,
              trailing: const Icon(
                Iconsax.arrow_right_3,
                color: Colors.black38,
                size: 20,
              ),
              onTap: () => _todo('นำส่งกิจกรรมที่บันทึกไว้ในเครื่อง'),
            ),
            const SizedBox(height: 10),
            _actionCard(
              color: AppColors.navy,
              leading: const Icon(
                Iconsax.calendar_edit,
                color: Colors.white,
                size: 28,
              ),
              title: 'อัปเดตสถานะแปลงตัด',
              subtitle: 'เปิดแปลง->ตัดอ้อย->ปิดแปลง',
              titleColor: Colors.white,
              subtitleColor: Colors.white70,
              trailing: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
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
                      size: 14,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _str(meta['cutStatus']) ?? 'ยังไม่ระบุ',
                      style: const TextStyle(fontSize: 12, color: Colors.white),
                    ),
                  ],
                ),
              ),
              onTap: () => _todo('อัปเดตสถานะแปลงตัด'),
            ),
            const SizedBox(height: 10),
            _actionCard(
              color: AppColors.green,
              leading: CircleAvatar(
                radius: 16,
                backgroundColor: Colors.white.withValues(alpha: 0.25),
                child: const Icon(
                  Iconsax.star_1,
                  color: Colors.white,
                  size: 18,
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
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.gold,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _str(meta['project']) ?? 'ยังไม่ระบุ',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Iconsax.arrow_right_3,
                    color: Colors.white70,
                    size: 20,
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
                size: 40,
              ),
              title: 'ยืนยันแปลง',
              subtitle: 'ยืนยันแปลงข้ามปี',
              titleColor: Colors.white,
              subtitleColor: Colors.white70,
              onTap: () => _todo('ยืนยันแปลง'),
            ),
            const SizedBox(height: 10),
            // กำหนดจุดเสี่ยง — เลือกได้ 1 ค่า (ยังไม่ส่ง backend)
            Container(
              padding: const EdgeInsets.all(14),
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
                      Icon(Iconsax.flash_1, size: 18, color: AppColors.gold),
                      SizedBox(width: 6),
                      Text(
                        'กำหนดเป็นจุดเสี่ยงจากแปลงนี้:',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // ตัวเลือกจุดเสี่ยงจาก backend — ว่าง/โหลดไม่ได้
                  // → ไม่แสดงแถว chip
                  FutureBuilder<FormOptions>(
                    future: _options,
                    builder: (context, snap) {
                      final levels =
                          snap.data?.riskLevels ?? const <String>[];
                      if (levels.isEmpty) return const SizedBox.shrink();
                      return Row(
                        children: [
                          for (var i = 0; i < levels.length; i++) ...[
                            _riskChip(levels[i]),
                            if (i < levels.length - 1)
                              const SizedBox(width: 10),
                          ],
                        ],
                      );
                    },
                  ),
                ],
              ),
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Text(
              row.$1,
              style: const TextStyle(fontSize: 14, color: Colors.black87),
            ),
          ),
          Expanded(
            flex: 7,
            child: Text(
              row.$2 == null || row.$2!.isEmpty ? '—' : row.$2!,
              style: TextStyle(
                fontSize: 15,
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
            child: Icon(icon, color: color, size: 30),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12.5, height: 1.25),
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            border: border,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              leading,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: titleColor,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle,
                        style: TextStyle(fontSize: 12.5, color: subtitleColor),
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
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: Colors.white, size: 22),
    );
  }

  /// (icon, พื้น, ตัวหนังสือ) ต่อระดับจุดเสี่ยง — map จากชื่อที่
  /// backend ส่งมา; ชื่อใหม่ที่ยังไม่รู้จักได้ icon/สี generic
  static (IconData, Color, Color) _riskStyle(String name) {
    if (name.contains('น้ำ')) {
      return (
        Iconsax.cloud_drizzle,
        const Color(0xFFFCE4EC),
        const Color(0xFFC2185B),
      );
    }
    if (name.contains('แล้ง')) {
      return (
        Iconsax.sun_1,
        const Color(0xFFFFF8E1),
        const Color(0xFF9C6B00),
      );
    }
    return (
      Iconsax.cloud_sunny,
      const Color(0xFFFFF8E1),
      const Color(0xFF9C6B00),
    );
  }

  /// chip จุดเสี่ยง — เลือกได้ทีละอัน แตะซ้ำเพื่อยกเลิก
  Widget _riskChip(String label) {
    final (icon, bg, fg) = _riskStyle(label);
    final selected = _risk == label;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _risk = selected ? null : label),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? fg : Colors.transparent,
              width: 1.6,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

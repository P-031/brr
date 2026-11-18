import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import 'package:brr/core/theme/app_theme.dart';
import 'package:brr/core/widgets/skeleton.dart';
import 'package:brr/features/map/viewmodels/parcel_detail_viewmodel.dart';
import 'package:brr/features/map/views/parcel_edit_views.dart';

/// หน้ารายละเอียดแปลงเต็มจอ (ตาม ref แอปจริง) — เปิดจากปุ่ม "เพิ่มเติม"
/// ใน info sheet — section cards: ข้อมูลแปลง / การปลูก / ชาวไร่ /
/// นักส่งเสริม / สถานที่ / รูท & ลำดับ / ข้อมูลกลุ่ม / เพิ่มเติม
class ParcelDetailView extends StatelessWidget {
  const ParcelDetailView({super.key, required this.vm});

  /// VM เดียวกับ info sheet — detail future แชร์กันและ PATCH จาก
  /// หน้าในเมนู ⋮ จะ notify ให้หน้านี้โหลดข้อมูลใหม่อัตโนมัติ
  final ParcelDetailViewModel vm;

  static const _thaiMonths = [
    'ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.',
    'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.',
  ];

  static String? _str(dynamic v) {
    final s = '$v';
    return (v == null || s.isEmpty) ? null : s;
  }

  /// เหมือนใน sheet — meta.plantedAt ยังไม่มีใน schema ตอนนี้
  /// fallback createdAt ของ record ไปก่อน
  static DateTime? _plantedDate(Map meta, Map<String, dynamic>? detail) {
    for (final k in ['plantedAt', 'plantDate', 'plantedDate']) {
      final d = DateTime.tryParse('${meta[k]}');
      if (d != null) return d;
    }
    return DateTime.tryParse('${detail?['createdAt']}');
  }

  static String _fmtDate(DateTime d) =>
      '${d.day} ${_thaiMonths[d.month - 1]} ${d.year + 543}';

  @override
  Widget build(BuildContext context) {
    final p = vm.parcel;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F4F4),
      appBar: AppBar(
        backgroundColor: AppColors.green,
        title: const Text('รายละเอียด'),
        actions: [
          IconButton(
            onPressed: () => _openMenu(context),
            icon: const Icon(Icons.more_vert),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: vm,
        builder: (context, _) => FutureBuilder<Map<String, dynamic>?>(
          future: vm.detail,
          builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done && !p.isDraft) {
            // skeleton เลียนหน้าจริง — บล็อกรูปถ่าย + การ์ด
            // section (หัวข้อ + แถว label:value)
            return const _DetailSkeleton();
          }
          final detail = snap.data;
          final meta =
              (detail?['meta'] as Map<String, dynamic>?) ?? p.meta ?? const {};
          final farmer = detail?['farmer'] as Map<String, dynamic>?;
          final landNo = p.landNo;
          final plotCode = p.plotCode;
          final variety =
              _str(detail?['variety']) ??
              _str(meta['caneVariety']) ??
              p.variety;
          final planted = _plantedDate(meta, detail);
          final ageDays = planted == null
              ? null
              : DateTime.now().difference(planted).inDays;
          final areaMap = detail?['area'] as Map<String, dynamic>?;
          final areaText = areaMap == null
              ? p.areaThai
              : '${areaMap['rai'] ?? 0} ไร่ ${areaMap['ngan'] ?? 0} งาน '
                    '${(areaMap['wa'] as num? ?? 0).toStringAsFixed(0)} ตร.วา';
          final grade = _str(meta['grade']) ?? _str(meta['plotGrade']);
          final status = p.isDraft
              ? 'แปลงร่าง (ยังไม่บันทึก)'
              : _str(p.status) ?? _str(detail?['status']);
          final caneGroup = _str(meta['caneGroup']);
          // รูปถ่ายแปลงจาก backend — schema ยังไม่มี ลองหลาย key
          // เผื่ออนาคต; ไม่มี → placeholder กล้อง
          final photoUrl =
              _str(detail?['photoUrl']) ??
              _str(detail?['imageUrl']) ??
              _str(meta['photoUrl']) ??
              _str(meta['imageUrl']);

          // meta ที่ยังไม่ได้โชว์ใน section ไหน — รวมไว้ท้ายหน้า
          final misc = <(String, String?)>[
            ('โครงการ', _str(meta['project'])),
            ('แปลงก่อนหน้า', _str(meta['prevPlotNo'])),
            ('กรรมสิทธิ์', _str(meta['ownership'])),
            ('ภูมิประเทศ', _str(meta['terrain'])),
            ('พื้นที่สูญเสีย', _str(meta['hasLoss'])),
            ('สูญเสีย (ไร่)', _str(meta['lossRai'])),
            ('ผลผลิตเป้าหมาย (ตัน)', _str(meta['targetYield'])),
            ('หมายเหตุ', _str(meta['note'])),
          ].where((r) => r.$2 != null).toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
            children: [
              // รูปถ่ายแปลง — จาก backend เท่านั้น ไม่มี → placeholder
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.all(10),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: photoUrl != null
                      ? Image.network(
                          photoUrl,
                          height: 170,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => _photoPlaceholder(),
                        )
                      : _photoPlaceholder(),
                ),
              ),
              const SizedBox(height: 10),
              _Section(
                rows: [
                  _row('ปีการผลิต', _str(meta['productionYear'])),
                  _row('ชื่อแปลง', landNo),
                  _row('รหัสแปลง', plotCode, blue: true),
                  _row('ประเภทอ้อย', _str(meta['caneType'])),
                  _row('พื้นที่(ไร่)', areaText, blue: true),
                  _row('พันธุ์อ้อย', variety),
                  _row('สถานะแปลง', status),
                  _row(
                    'เกรดแปลง',
                    grade == null ? null : 'เกรด $grade',
                    color: AppColors.gold,
                  ),
                ],
              ),
              _Section(
                title: 'การปลูก',
                rows: [
                  _row(
                    'วันที่ปลูก',
                    planted == null ? null : _fmtDate(planted),
                  ),
                  _row(
                    'อายุอ้อย',
                    ageDays == null || ageDays < 0 ? null : 'อายุ $ageDays วัน',
                    blue: true,
                  ),
                ],
              ),
              _Section(
                title: 'ข้อมูลชาวไร่',
                rows: [
                  _row(
                    'รหัส',
                    _str(farmer?['username']) ?? _str(farmer?['id']),
                    blue: true,
                  ),
                  _row('ชื่อ', _str(farmer?['displayName']) ?? p.owner),
                  _row('อีเมล', _str(farmer?['email'])),
                ],
              ),
              _Section(
                title: 'ข้อมูลนักส่งเสริม',
                rows: [
                  _row('รหัส', _str(meta['officerCode']), blue: true),
                  _row('ชื่อ', _str(meta['officerName'])),
                  _row('อีเมล', _str(meta['officerEmail'])),
                ],
              ),
              _Section(
                title: 'สถานที่',
                rows: [
                  _row('เขต', _str(meta['zone'])),
                  _row('จังหวัด', _str(meta['province'])),
                  _row('อำเภอ', _str(meta['district'])),
                  _row('ตำบล', _str(meta['subdistrict'])),
                  _row('หมู่บ้าน', _str(meta['village'])),
                ],
              ),
              _Section(
                title: 'รูท & ลำดับ',
                rows: [
                  _row('รูท', _str(meta['rootNo'])),
                  _row('ลำดับ', _str(meta['sequenceNo'])),
                ],
              ),
              _Section(
                title: 'ข้อมูลกลุ่ม',
                rows: const [],
                // schema มี caneGroup ชุดเดียว — การ์ดไหนที่ชื่อกลุ่ม
                // ตรงประเภทก็ใส่ให้ อีกใบรอ backend เพิ่มฟิลด์
                // (maintainGroup/harvestGroup + *Code/*OwnerName)
                child: Column(
                  children: [
                    _groupCard(
                      'กลุ่มบำรุง',
                      'maintainGroup',
                      caneGroup,
                      caneGroup?.contains('บำรุง') == true,
                      meta,
                    ),
                    const SizedBox(height: 8),
                    _groupCard(
                      'กลุ่มตัด',
                      'harvestGroup',
                      caneGroup,
                      caneGroup?.contains('ตัด') == true,
                      meta,
                    ),
                  ],
                ),
              ),
              if (misc.isNotEmpty)
                _Section(
                  title: 'ข้อมูลเพิ่มเติม',
                  rows: [for (final r in misc) _row(r.$1, r.$2)],
                ),
            ],
          );
          },
        ),
      ),
    );
  }

  /// ⋮ → sheet เมนูแบบ ref — แก้ไขรูท&ลำดับ / คำขอสถานะแปลง1,2
  void _openMenu(BuildContext context) {
    Widget item(IconData icon, String label, Widget page) => ListTile(
      leading: CircleAvatar(
        radius: 20,
        backgroundColor: AppColors.green.withValues(alpha: 0.12),
        child: Icon(icon, color: AppColors.green, size: 20),
      ),
      title: Text(label, style: const TextStyle(fontSize: 15)),
      onTap: () async {
        Navigator.of(context).pop();
        final saved = await Navigator.of(context).push<Object>(
          MaterialPageRoute(builder: (_) => page),
        );
        if (saved != null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(saved is String ? saved : 'บันทึกสำเร็จ'),
            ),
          );
        }
      },
    );
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'เมนู',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              item(
                Iconsax.edit_2,
                'แก้ไข รูท & ลำดับ',
                EditRouteSeqView(vm: vm),
              ),
              item(
                Iconsax.refresh,
                'ยื่นคำขออัปเดตสถานะแปลง1',
                StatusRequestView(vm: vm),
              ),
              item(
                Iconsax.clock,
                'ยื่นคำขออัปเดตสถานะแปลง2',
                EditRequestView(vm: vm),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// ช่องรูปเมื่อ backend ยังไม่มีรูปถ่ายแปลง
  static Widget _photoPlaceholder() {
    return Container(
      height: 170,
      width: double.infinity,
      color: const Color(0xFFE8E8E8),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.photo_camera_outlined, size: 40, color: Colors.black38),
          SizedBox(height: 6),
          Text(
            'ยังไม่มีรูปถ่าย',
            style: TextStyle(fontSize: 13, color: Colors.black45),
          ),
        ],
      ),
    );
  }

  /// sub-card กลุ่ม (บำรุง/ตัด) — [keyPrefix] = maintainGroup/harvestGroup
  /// สำหรับฟิลด์แยกในอนาคต; ตอนนี้ [caneGroup] เดียว ใส่การ์ดที่ชื่อ
  /// มีคำตรงประเภท ([matches])
  static Widget _groupCard(
    String title,
    String keyPrefix,
    String? caneGroup,
    bool matches,
    Map meta,
  ) {
    final name = _str(meta[keyPrefix]) ?? (matches ? caneGroup : null);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEDF3EE),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppColors.green,
            ),
          ),
          const SizedBox(height: 8),
          _row(
            'รหัสกลุ่ม',
            _str(meta['${keyPrefix}Code']) ?? _str(meta['groupCode']),
          ),
          _row('ชื่อกลุ่ม', name),
          _row(
            'ชื่อ',
            _str(meta['${keyPrefix}OwnerName']) ??
                _str(meta['groupOwnerName']),
          ),
        ],
      ),
    );
  }

  /// แถว label ซ้าย / value ขวาติดขอบ — ค่าว่างแสดง '—'
  static Widget _row(String label, String? value,
      {bool blue = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Text(
              label,
              style: const TextStyle(fontSize: 14, color: Colors.black87),
            ),
          ),
          Expanded(
            flex: 7,
            child: Text(
              value == null || value.isEmpty ? '—' : value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: color ?? (blue ? AppColors.sky : Colors.black87),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// การ์ดขาว section เดียว — title (ถ้ามี) + divider + rows
class _Section extends StatelessWidget {
  const _Section({this.title, required this.rows, this.child});

  final String? title;
  final List<Widget> rows;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(
              title!,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const Divider(height: 16, color: Colors.black12),
          ],
          ...rows,
          ?child,
        ],
      ),
    );
  }
}

/// skeleton หน้ารายละเอียด — เลียนโครงจริง: บล็อกรูปถ่ายสูง 170
/// + การ์ด section หลายใบ (หัวข้อ + แถว label:value)
class _DetailSkeleton extends StatelessWidget {
  const _DetailSkeleton();

  @override
  Widget build(BuildContext context) {
    return SkeletonPulse(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
        children: const [
          SkelBox(height: 190, radius: 14),
          SizedBox(height: 10),
          _SectionSkeleton(rows: 5),
          _SectionSkeleton(rows: 4),
          _SectionSkeleton(rows: 3),
        ],
      ),
    );
  }
}

/// การ์ด section เทา — หัวข้อ + เส้นคั่น + แถว label:value
/// สัดส่วนเดียวกับ _Section จริง
class _SectionSkeleton extends StatelessWidget {
  const _SectionSkeleton({required this.rows});

  final int rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SkelLine(width: 120, height: 15),
          const Divider(height: 16, color: Colors.black12),
          for (var i = 0; i < rows; i++)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  SkelLine(width: 100),
                  SizedBox(width: 14),
                  Expanded(child: SkelLine()),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax/iconsax.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:brr/core/utils/thai_date.dart';
import 'package:brr/core/theme/app_theme.dart';
import 'package:brr/core/widgets/result_dialog.dart';
import 'package:brr/core/widgets/sheet_close_button.dart';
import 'package:brr/features/map/models/parcel.dart';
import 'package:brr/features/map/viewmodels/parcel_detail_viewmodel.dart';
import 'package:brr/features/map/views/activity_drafts_view.dart';
import 'package:brr/features/map/views/activity_history_view.dart';
import 'package:brr/features/map/views/activity_record_view.dart';
import 'package:brr/features/map/views/parcel_confirm_view.dart';
import 'package:brr/features/map/views/parcel_detail_view.dart';
import 'package:brr/features/map/views/parcel_edit_views.dart';
import 'package:brr/features/map/widgets/cut_status_sheet.dart';
import 'package:brr/features/map/widgets/plot_project_sheet.dart';
import 'package:brr/features/map/widgets/risk_point_sheet.dart';
import 'package:brr/core/utils/json_safe.dart';
part 'parcel_info_sections.dart';


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

  /// กิจกรรมที่บันทึกไว้ในเครื่อง — subtitle การ์ดนำส่งนับจำนวน
  /// จริง; refresh หลังกลับจากหน้ารายการ (อาจลบ/เพิ่มรายการ)
  late Future<List<Map<String, dynamic>>> _acts = widget.vm.activityDrafts();

  /// จำนวนกิจกรรมใหม่ที่ยังไม่ได้เปิดดู — badge แดงบนปุ่ม
  late Future<int> _unseen = widget.vm.unseenActivityCount();


  /// meta/farmer ล่าสุดที่ build เตรียมไว้ — ปุ่มเมนูอ่านตอนกด
  Map<String, dynamic> _meta = const {};
  Map<String, dynamic>? _farmer;

  /// ตัวเลือกจุดเสี่ยงจาก backend (/meta/options → riskLevels)
  late final Future<FormOptions> _options = widget.vm.loadOptions();

  /// extent ล่าสุดของ sheet — ใช้คืนสถานะทับจอหลัง pop กลับจาก
  /// หน้ารายละเอียด (onCovered ไม่ refire ถ้า extent ไม่เปลี่ยน)
  double _extent = 0.9;

  /// setState proxy — extension ใน part file เรียก setState ตรงๆ
  /// ไม่ได้ เลยใช้ helper นี้แทน
  void _set(VoidCallback fn) => setState(fn);

  /// เมนูทางลัด — (icon, label, color) ทุกอันต่อหน้าจริงแล้ว
  /// (ดู _menuAction)
  static const _menus = [
    (Iconsax.send_2, 'นำทาง', AppColors.sky),
    (Iconsax.home_2, 'บ้านชาวไร่', AppColors.gold),
    (Iconsax.call, 'เบอร์โทร', AppColors.green),
    (Iconsax.edit_2, 'แก้ไข รูท & ลำดับ', AppColors.green),
    (Icons.autorenew, 'คำขออัปเดตสถานะแปลง1', AppColors.green),
    (Iconsax.clock, 'คำขออัปเดตสถานะแปลง2', AppColors.green),
    (Iconsax.more, 'กลุ่มบำรุง / ตัด', AppColors.green),
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

  static String _fmtDate(DateTime d) => formatThaiDate(d);







  /// ปุ่มเมนูทั้งหมดต่อหน้าจริงแล้ว — `_todo` เป็น fallback
  /// เผื่อเพิ่ม label ใน _menus แล้วลืม map ที่นี่
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
      'คำขออัปเดตสถานะแปลง2' => () => _pushFullScreen(EditRequestView(vm: vm)),
      'กลุ่มบำรุง / ตัด' => () => _pushFullScreen(GroupRequestView(vm: vm)),
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
          final meta = asStringMap(detail?['meta']) ?? p.meta ?? const {};
          final farmer = asStringMap(detail?['farmer']);
          _meta = meta;
          _farmer = farmer;
          final farmerName = _str(farmer?['displayName']) ?? p.owner;
          final farmerCode = _str(farmer?['username']) ?? _str(farmer?['id']);
          final loadingDetail =
              snap.connectionState != ConnectionState.done && !p.isDraft;

          final planted = _plantedDate(meta, detail);
          final ageDays = planted == null
              ? null
              : DateTime.now().difference(planted).inDays;
          // พื้นที่แบบละเอียด "x ไร่ y งาน z ตร.วา" — detail มี area
          // จาก backend (splitThaiArea); draft ไม่มี detail ใช้คำนวณ
          // ฝั่งเครื่องแทน
          final areaMap = asStringMap(detail?['area']);
          final areaText = areaMap == null
              ? p.areaThai
              : '${areaMap['rai'] ?? 0} ไร่ ${areaMap['ngan'] ?? 0} งาน '
                    '${(toDoubleOrNull(areaMap['wa']) ?? 0).toStringAsFixed(0)} ตร.วา';
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
            (
              'ปีการผลิต',
              _str(meta['productionYear']) ?? p.productionYear,
              false,
            ),
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
                    const SheetCloseButton(),
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
                FutureBuilder<int>(
                  future: _unseen,
                  builder: (context, snap) => _actionCard(
                    color: const Color(0xFFF2F2F2),
                    leading: const Icon(
                      Iconsax.menu_1,
                      color: Colors.black87,
                      size: 30,
                    ),
                    title: 'ประวัติการบันทึกกิจกรรม',
                    badgeCount: snap.data ?? 0,
                    onTap: () => _pushFullScreen(
                      ActivityHistoryView(vm: widget.vm),
                      onReturn: () async {
                        await widget.vm.markActivitiesSeen();
                        _reloadActivities();
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                FutureBuilder<List<Map<String, dynamic>>>(
                  future: _acts,
                  builder: (context, snap) {
                    final items = snap.data ?? const [];
                    final pending = items
                        .where((a) => a['detailPending'] == true)
                        .length;
                    final String sub;
                    final Color subColor;
                    if (pending > 0) {
                      sub = 'ค้างกรอกรายละเอียด $pending รายการ';
                      subColor = const Color(0xFFE65100);
                    } else if (items.isNotEmpty) {
                      sub = 'บันทึกไว้ ${items.length} รายการ รอนำส่ง';
                      subColor = AppColors.green;
                    } else {
                      sub = 'ส่งข้อมูลครบแล้ว (ไม่มีข้อมูลค้าง)';
                      subColor = AppColors.green;
                    }
                    return FutureBuilder<int>(
                      future: _unseen,
                      builder: (context, snap) => _actionCard(
                        color: Colors.white,
                        border: Border.all(color: Colors.grey.shade300),
                        leading: const Icon(
                          Iconsax.cloud_plus,
                          color: AppColors.sky,
                          size: 36,
                        ),
                        title: 'นำส่งกิจกรรมที่บันทึกไว้ในเครื่อง',
                        subtitle: sub,
                        subtitleColor: subColor,
                        badgeCount: snap.data ?? 0,
                        trailing: const Icon(
                          Iconsax.arrow_right_3,
                          color: Colors.black38,
                          size: 24,
                        ),
                        onTap: () => _pushFullScreen(
                          ActivityDraftsView(vm: widget.vm),
                          onReturn: () async {
                            await widget.vm.markActivitiesSeen();
                            _reloadActivities();
                          },
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 10),
                _actionCard(
                  color: AppColors.sky,
                  leading: const Icon(
                    Icons.edit_calendar,
                    color: Colors.white,
                    size: 36,
                  ),
                  title: 'อัปเดตสถานะแปลงตัด',
                  subtitle: 'เปิดแปลง->ตัดอ้อย->ปิดแปลง',
                  titleColor: Colors.white,
                  subtitleColor: Colors.white,
                  onTap: _openCutSheet,
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
                  subtitleColor: Colors.white,
                  trailing: const Icon(
                    Iconsax.arrow_right_3,
                    color: Colors.white70,
                    size: 24,
                  ),
                  onTap: _openProjectSheet,
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
                  subtitleColor: Colors.white,
                  onTap: () =>
                      _pushFullScreen(ParcelConfirmView(vm: widget.vm)),
                ),
                const SizedBox(height: 10),
                // การ์ดจุดเสี่ยง — preview สถานะที่บันทึกไว้ แตะเปิด
                // sheet ฟอร์มกำหนดจุดเสี่ยง (ประเภท/ชื่อ/ระดับ/หมายเหตุ)
                FutureBuilder<FormOptions>(
                  future: _options,
                  builder: (context, snap) {
                    // แสดงชื่อชนิดภัยเหมือนใน sheet — น้ำท่วมก่อน 50-50 ท้าย
                    // ว่าง (options โหลดไม่ได้/ออฟไลน์) ก็ยังโชว์การ์ด
                    // ให้เข้า sheet ได้ — sheet โหลด options เองอีกชั้น
                    final levels = [
                      for (final l in snap.data?.riskLevels ?? const <String>[])
                        riskDisplayName(l),
                    ].reversed.toList();
                    return FutureBuilder<Map<String, dynamic>?>(
                      future: _riskPoint,
                      builder: (context, r) {
                        final saved = r.data;
                        final savedType = '${saved?['type'] ?? ''}';
                        // สีตามประเภทที่บันทึก (น้ำท่วม=แดง/แล้ง=ส้ม/50-50=เหลือง)
                        // ยังไม่บันทึก = ขาวเทาปกติ
                        final (icon, bg, fg) = savedType.isEmpty
                            ? (Iconsax.warning_2, Colors.white, Colors.black38)
                            : riskChipStyle(savedType);
                        return InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: _openRiskSheet,
                          child: Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: savedType.isEmpty
                                  ? Colors.white
                                  : bg.withValues(alpha: 0.3),
                              border: Border.all(
                                color: savedType.isEmpty
                                    ? Colors.grey.shade300
                                    : fg,
                                width: savedType.isEmpty ? 1 : 1.8,
                              ),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Expanded(
                                      child: Text(
                                        'กำหนดเป็นจุดเสี่ยงภัยพิบัติ',
                                        style: TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    if (savedType.isNotEmpty)
                                      Icon(icon, size: 22, color: fg),
                                    const SizedBox(width: 4),
                                    const Icon(
                                      Iconsax.arrow_right_3,
                                      size: 20,
                                      color: Colors.black38,
                                    ),
                                  ],
                                ),
                                if (levels.isNotEmpty) ...[
                                  const SizedBox(height: 14),
                                  Row(
                                    children: [
                                      for (
                                        var i = 0;
                                        i < levels.length;
                                        i++
                                      ) ...[
                                        _riskPreviewChip(
                                          levels[i],
                                          riskDisplayName(savedType) ==
                                              levels[i],
                                        ),
                                        if (i < levels.length - 1)
                                          const SizedBox(width: 10),
                                      ],
                                    ],
                                  ),
                                ],
                                if (saved != null) ...[
                                  const SizedBox(height: 10),
                                  Text(
                                    '${riskDisplayName(savedType)} • ระดับ ${saved['severity'] ?? '—'}'
                                    '${'${saved['note'] ?? ''}'.isEmpty ? '' : ' • ${saved['note']}'}',
                                    style: TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.bold,
                                      color: fg,
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









}

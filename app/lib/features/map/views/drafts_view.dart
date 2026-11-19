import 'dart:io';

import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import 'package:brr/core/theme/app_theme.dart';
import 'package:brr/core/widgets/skeleton.dart';
import 'package:brr/features/map/models/measurement_result.dart';
import 'package:brr/features/map/models/parcel.dart';
import 'package:brr/features/map/viewmodels/drafts_viewmodel.dart';
import 'package:brr/features/map/views/measurement_save_view.dart';
import 'package:brr/features/map/widgets/parcel_outline.dart';
import 'package:brr/features/map/widgets/satellite_thumb.dart';

/// หน้า "ข้อมูลฉบับร่าง" — แปลงที่กด "บันทึกข้อมูลลงเครื่อง (ฉบับร่าง)"
/// มาแสดงเป็น list เฉพาะ ข้อมูลอยู่ในเครื่องล้วน (ไม่เคยขึ้น server)
///
/// ใช้เป็นหน้าคั่นก่อนเข้าโหมดวัดพื้นที่ — ส่ง [onStartMeasure]
/// มาจะมีปุ่ม "เริ่มวัดพื้นที่ใหม่" ล่างสุด; ไม่ส่ง = โหมดดูอย่าง
/// เดียว (ทางเข้าจากปุ่มลอยบนแผนที่)
///
/// การ์ดแต่ละใบทำได้ 3 อย่าง: แก้ไข (เปิดฟอร์ม prefill แล้วบันทึก
/// ทับ/ส่งจริง), ยืนยัน (POST /plots ด้วยข้อมูลที่บันทึกไว้แล้วลบ
/// ร่าง), ลบ (confirm ก่อน). pop คืน true เมื่อมีร่างเปลี่ยน
class DraftsView extends StatelessWidget {
  const DraftsView({
    super.key,
    required this.vm,
    this.onStartMeasure,
    this.isOfficer = false,
  });

  final DraftsViewModel vm;

  /// ปุ่มไปหน้าวัดพื้นที่ — null = ไม่แสดง (เข้าจากแผนที่อยู่แล้ว)
  /// await แล้ว refresh — ร่างที่เพิ่งบันทึกจากหน้าวัดโชว์ทันที
  final Future<void> Function()? onStartMeasure;

  /// officer → ฟอร์มแก้ไขมีตัวเลือกชาวไร่เจ้าของแปลง
  final bool isOfficer;

  void _toast(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// แก้ไข — เปิดฟอร์มบันทึกการวัดที่ prefill จากร่าง ผลลัพธ์
  /// บันทึกทับร่างเดิม (ร่างใหม่/ส่งจริงตามปุ่มที่กดในฟอร์ม)
  Future<void> _edit(BuildContext context, Parcel p) async {
    final result = await Navigator.of(context).push<MeasurementResult>(
      MaterialPageRoute(
        builder: (_) => MeasurementSaveView(
          areaSquareMeters: p.areaSquareMeters,
          officers: vm.fetchOfficers,
          farmers: vm.fetchFarmers,
          options: vm.fetchOptions,
          isOfficer: isOfficer,
          initial: p,
        ),
      ),
    );
    if (result == null || !context.mounted) return;
    final err = await vm.applyEdit(p, result);
    if (!context.mounted) return;
    _toast(
      context,
      err ?? (result.draft ? 'บันทึกร่างแล้ว' : 'บันทึกแปลงแล้ว'),
    );
  }

  /// ยืนยัน — ส่งข้อมูลที่บันทึกไว้ขึ้น server โดยไม่ต้องกรอกใหม่
  Future<void> _confirm(BuildContext context, Parcel p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        icon: const Icon(Iconsax.tick_circle, color: AppColors.green, size: 28),
        title: const Text('ยืนยันบันทึกแปลง'),
        content: Text(
          'ส่ง "${_landNo(p)}" ขึ้น server ด้วยข้อมูลที่บันทึกไว้'
          ' — ร่างจะถูกบันทึกว่า "ยืนยันแล้ว" และแก้ไขไม่ได้อีก',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('ยืนยัน'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final err = await vm.confirm(p);
    if (!context.mounted) return;
    _toast(context, err ?? 'บันทึกแปลงขึ้น server แล้ว');
  }

  Future<void> _delete(BuildContext context, Parcel p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        icon: const Icon(Iconsax.trash, color: Colors.red, size: 28),
        title: const Text('ลบฉบับร่าง'),
        content: Text(
          'ลบ "${_landNo(p)}" ออกจากเครื่องถาวร — ข้อมูลร่างไม่ได้ส่งขึ้น'
          ' server ลบแล้วกู้ไม่ได้',
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.black87),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDC4444),
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('ลบ'),
          ),
        ],
      ),
    );
    if (ok == true) await vm.remove(p);
  }

  void _openInfo(BuildContext context, Parcel p) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => _DraftDetailView(p)));
  }

  /// ปุ่มดาวโหลดขวาบน — confirm ก่อนแล้วยิง GET /risk-points
  /// เก็บลงเครื่อง (endpoint ยังรอ backend — 404 จะโชว์ซื่อสัตย์)
  Future<void> _downloadRisk(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        icon: const Icon(
          Icons.cloud_download,
          color: AppColors.green,
          size: 32,
        ),
        title: const Text('ดาวน์โหลดข้อมูลจุดเสี่ยง'),
        content: const Text(
          'คุณต้องการดาวน์โหลดหรืออัปเดตข้อมูลจุดเสี่ยง'
          'ภัยพิบัติล่าสุดใช่หรือไม่',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('ยืนยัน'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final err = await vm.downloadRiskData();
    if (!context.mounted) return;
    _toast(context, err ?? 'ดาวน์โหลดข้อมูลจุดเสี่ยงล่าสุดแล้ว');
  }

  /// ฟิลเตอร์สถานะ — bottom sheet เลือก ทั้งหมด/ยืนยันแล้ว/ยังไม่ยืนยัน
  void _openFilter(BuildContext context) {
    const options = [
      ('all', 'ทั้งหมด'),
      ('confirmed', 'ยืนยันแล้ว'),
      ('pending', 'ยังไม่ยืนยัน'),
    ];
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (value, label) in options)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        vm.statusFilter = value;
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: vm.statusFilter == value
                                ? AppColors.green
                                : const Color(0xFFE0E0E0),
                            width: vm.statusFilter == value ? 1.5 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              vm.statusFilter == value
                                  ? Iconsax.tick_circle5
                                  : Iconsax.record_circle,
                              size: 20,
                              color: vm.statusFilter == value
                                  ? AppColors.green
                                  : Colors.black38,
                            ),
                            const SizedBox(width: 14),
                            Text(
                              label,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: vm.statusFilter == value
                                    ? AppColors.green
                                    : Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(vm.changed);
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F4F4),
        appBar: AppBar(
          backgroundColor: AppColors.green,
          title: const Text('ข้อมูลฉบับร่าง'),
          actions: [
            IconButton(
              tooltip: 'ตัวกรองสถานะ',
              icon: const Icon(Icons.filter_list, size: 26),
              onPressed: () => _openFilter(context),
            ),
            IconButton(
              tooltip: 'รีเฟรช',
              icon: const Icon(Iconsax.refresh, size: 24),
              onPressed: vm.refresh,
            ),
            IconButton(
              tooltip: 'ดาวน์โหลดจุดเสี่ยง',
              icon: const Icon(Icons.cloud_download, size: 26),
              onPressed: () => _downloadRisk(context),
            ),
          ],
        ),
        // ปุ่มเข้าโหมดวัด — แสดงเฉพาะเมื่อเป็นหน้าคั่นก่อนวัด
        bottomNavigationBar: onStartMeasure == null
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () async {
                      await onStartMeasure!();
                      // อาจมีร่างใหม่จากการวัด — โหลด list ใหม่
                      await vm.refresh();
                    },
                    icon: const Icon(Iconsax.rulerpen, size: 20),
                    label: const Text(
                      'เริ่มวัดพื้นที่ใหม่',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
        body: ListenableBuilder(
          listenable: vm,
          builder: (context, _) {
            if (vm.loading) {
              // skeleton รูปการ์ดจริง — thumb ซ้าย + ข้อความ +
              // คอลัมน์ขวา (⋮/ยืนยัน) ตำแหน่งเดียวกับ _DraftCard
              return SkeletonPulse(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                  itemCount: 3,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, _) => const _DraftCardSkeleton(),
                ),
              );
            }
            if (vm.drafts.isEmpty) {
              return const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Iconsax.document, size: 56, color: Colors.black26),
                    SizedBox(height: 12),
                    Text(
                      'ยังไม่มีข้อมูลฉบับร่าง',
                      style: TextStyle(fontSize: 16, color: Colors.black45),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'แปลงที่กด "บันทึกข้อมูลลงเครื่อง" จะมาแสดงที่นี่',
                      style: TextStyle(fontSize: 13, color: Colors.black38),
                    ),
                  ],
                ),
              );
            }
            final visible = vm.filteredDrafts;
            if (visible.isEmpty) {
              return const Center(
                child: Text(
                  'ไม่มีรายการตามสถานะที่เลือก',
                  style: TextStyle(fontSize: 15, color: Colors.black45),
                ),
              );
            }
            final shown = vm.visibleDrafts;
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              itemCount: shown.length + 1,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                // ท้าย list — ปุ่มโหลดเพิ่ม (เหมือนหน้ากิจกรรมแปลง)
                // หรือข้อความครบแล้วถ้าเคยต้องกดเพิ่ม
                if (i == shown.length) {
                  if (!vm.hasMore) {
                    if (visible.length <= DraftsViewModel.pageSize) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: Center(
                        child: Text(
                          'แสดงครบ ${visible.length} รายการแล้ว',
                          style: const TextStyle(
                            color: Colors.black45,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    );
                  }
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: vm.loadMore,
                        icon: const Icon(Iconsax.arrow_circle_down, size: 22),
                        label: const Text(
                          'โหลดเพิ่ม',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.green,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  );
                }
                final p = shown[i];
                return _DraftCard(
                  p,
                  busy: vm.busyId == p.id,
                  onTap: () => _openInfo(context, p),
                  onEdit: () => _edit(context, p),
                  onConfirm: () => _confirm(context, p),
                  onDelete: () => _delete(context, p),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

const _thaiMonths = [
  'ม.ค.',
  'ก.พ.',
  'มี.ค.',
  'เม.ย.',
  'พ.ค.',
  'มิ.ย.',
  'ก.ค.',
  'ส.ค.',
  'ก.ย.',
  'ต.ค.',
  'พ.ย.',
  'ธ.ค.',
];

/// เวลาบันทึก — savedAt ปกติ; ร่างเก่า (ก่อนมีฟิลด์) ถอด ms จาก
/// id `local-<millis>`
String _savedText(Parcel p) {
  var t = p.savedAt;
  if (t == null && p.id.startsWith('local-')) {
    // id รูปแบบ local-<millis|micros>(-<seq>) — เอาเลขก่อนขีดแรก
    final ms = int.tryParse(p.id.substring(6).split('-').first);
    if (ms != null) t = DateTime.fromMillisecondsSinceEpoch(ms);
  }
  if (t == null) return '—';
  final hm =
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  return '${t.day} ${_thaiMonths[t.month - 1]} ${t.year + 543} $hm น.';
}

String _landNo(Parcel p) {
  final n = p.name.replaceAll(RegExp(r'\s*#\d+\s*$'), '').trim();
  return n.isEmpty ? 'ไม่ระบุชื่อ' : n;
}

/// การ์ดร่าง 1 ใบ — ชื่อไร่/ขนาดพื้นที่/เวลาบันทึก + ปุ่มการกระทำ
/// 3 ปุ่มล่างการ์ด แก้ไข/ลบ/ยืนยัน; แตะการ์ดเปิดหน้ารายละเอียด;
/// busy = กำลังยิง API อยู่
class _DraftCard extends StatelessWidget {
  const _DraftCard(
    this.p, {
    this.busy = false,
    this.onTap,
    this.onEdit,
    this.onConfirm,
    this.onDelete,
  });

  final Parcel p;
  final bool busy;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onConfirm;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SatelliteThumb(
                    points: p.points,
                    cacheKey: p.id,
                    fallback: ParcelOutline(points: p.points),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _landNo(p),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.green,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        // ขนาดพื้นที่เด่นแทนไอคอนเดิม
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.green.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: AppColors.green.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Text(
                            p.areaThai,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.green,
                            ),
                          ),
                        ),
                        const SizedBox(height: 7),
                        Row(
                          children: [
                            const Icon(
                              Iconsax.clock,
                              size: 14,
                              color: Colors.black45,
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                _savedText(p),
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Colors.black54,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (busy)
                    const Padding(
                      padding: EdgeInsets.all(10),
                      child: SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.green,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 10),
              // ปุ่มการกระทำ 3 ปุ่มล่างการ์ด — แก้ไข(ทอง)/ลบ(แดง)/
              // ยืนยัน(เขียว); ยืนยันแล้ว → badge แทนปุ่ม กันกดซ้ำ
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        side: const BorderSide(
                          color: Colors.redAccent,
                          width: 1.6,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      onPressed: onDelete,
                      icon: const Icon(Iconsax.trash, size: 22),
                      label: const Text(
                        'ลบ',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (p.status != 'confirmed') ...[
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFFFA000),
                          side: const BorderSide(
                            color: Color(0xFFFFA000),
                            width: 1.6,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        onPressed: onEdit,
                        icon: const Icon(Iconsax.edit_2, size: 22),
                        label: const Text(
                          'แก้ไข',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (p.status == 'confirmed')
                    const Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Iconsax.tick_circle5,
                            size: 22,
                            color: AppColors.green,
                          ),
                          SizedBox(width: 5),
                          Text(
                            'ยืนยันแล้ว',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.green,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.green,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        onPressed: onConfirm,
                        child: const Text(
                          'ยืนยัน',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// หน้ารายละเอียดร่าง — แตะการ์ดแล้วมาหน้านี้ 3 การ์ด:
/// ข้อมูลแปลง / รูปแปลงดาวเทียม / รูปที่ถ่ายตอนบันทึก
class _DraftDetailView extends StatelessWidget {
  const _DraftDetailView(this.p);

  final Parcel p;

  @override
  Widget build(BuildContext context) {
    final photos = [
      for (final x in p.meta?['photos'] as List? ?? const []) '$x',
    ];
    return Scaffold(
      backgroundColor: const Color(0xFFF4F4F4),
      appBar: AppBar(
        backgroundColor: AppColors.green,
        title: const Text('รายละเอียดฉบับร่าง'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          // การ์ด 1 — ข้อมูลแปลง
          _Section(
            title: 'ข้อมูลแปลง',
            child: Column(
              children: [
                _InfoRow('ชื่อไร่', _landNo(p)),
                _InfoRow('ขนาดพื้นที่', p.areaThai),
                _InfoRow('บันทึกเมื่อ', _savedText(p)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // การ์ด 2 — ภาพแปลงดาวเทียม
          _Section(
            title: 'รูปแปลง (ดาวเทียม)',
            child: LayoutBuilder(
              builder: (context, cons) => Center(
                child: SatelliteThumb(
                  points: p.points,
                  cacheKey: p.id,
                  width: cons.maxWidth,
                  height: 220,
                  radius: 12,
                  fallback: ParcelOutline(
                    points: p.points,
                    width: cons.maxWidth,
                    height: 220,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // การ์ด 3 — รูปที่ถ่ายตอนบันทึก (path ในเครื่อง) + จำนวน
          _Section(
            title: 'รูปภาพที่ถ่าย (${photos.length})',
            child: photos.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Center(
                      child: Text(
                        'ยังไม่มีรูปภาพที่ถ่ายไว้',
                        style: TextStyle(fontSize: 14, color: Colors.black38),
                      ),
                    ),
                  )
                : GridView.count(
                    crossAxisCount: 3,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    children: [
                      for (final path in photos)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.file(
                            File(path),
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Container(
                              color: Colors.black12,
                              child: const Icon(
                                Iconsax.gallery_slash,
                                color: Colors.black38,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// skeleton การ์ดร่าง — รูปทรง/ตำแหน่งเดียวกับ _DraftCard จริง:
/// thumb 92×92 ซ้าย / ชื่อ + pill พื้นที่ + เวลา / คอลัมน์ขวา
/// (วงกลม ⋮ + ปุ่มยืนยันสี่เหลี่ยมมน)
class _DraftCardSkeleton extends StatelessWidget {
  const _DraftCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkelBox(width: 92, height: 92, radius: 12),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: 2),
                SkelLine(width: 110, height: 16),
                SizedBox(height: 10),
                SkelBox(width: 96, height: 28, radius: 8),
                SizedBox(height: 10),
                SkelLine(width: 160),
              ],
            ),
          ),
          SizedBox(width: 8),
          Column(
            children: [
              SkelCircle(size: 36),
              SizedBox(height: 8),
              SkelBox(width: 76, height: 38, radius: 19),
            ],
          ),
        ],
      ),
    );
  }
}

/// การ์ดขาวหัวข้อเขียว — โครงเดียวกับ section card หน้ารายละเอียดแปลง
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

/// แถว label: value ในการ์ดข้อมูลแปลง
class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.black87,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const Text(
            ':',
            style: TextStyle(fontSize: 14, color: Colors.black54),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

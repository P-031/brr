import 'dart:io';

import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import 'package:brr/core/theme/app_theme.dart';
import 'package:brr/core/widgets/brr_app_bar.dart';
import 'package:brr/features/map/viewmodels/parcel_detail_viewmodel.dart';
import 'package:brr/features/map/views/activity_detail_view.dart';

/// หน้า "นำส่งกิจกรรมที่บันทึกไว้ในเครื่อง" — list กิจกรรมของแปลง
/// ที่บันทึกลงเครื่อง (รูปเท่านั้นรอรายละเอียด / กรอกครบรอนำส่ง)
/// ลบรายการได้; นำส่งเรียก `POST /plots/:id/activities` (รอ backend)
class ActivityDraftsView extends StatefulWidget {
  const ActivityDraftsView({super.key, required this.vm});

  final ParcelDetailViewModel vm;

  @override
  State<ActivityDraftsView> createState() => _ActivityDraftsViewState();
}

class _ActivityDraftsViewState extends State<ActivityDraftsView> {
  late Future<List<Map<String, dynamic>>> _items = widget.vm.activityDrafts();

  void _reload() => setState(() {
    _items = widget.vm.activityDrafts();
  });

  static String _fmtThai(String? iso) {
    final d = DateTime.tryParse('$iso');
    if (d == null) return '—';
    return '${d.day}/${d.month}/${d.year + 543}';
  }

  static String _fmtThaiTime(String? iso) {
    final d = DateTime.tryParse('$iso');
    if (d == null) return '—';
    return '${d.day}/${d.month}/${d.year + 543} '
        '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _confirmDelete(Map<String, dynamic> a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'ลบกิจกรรมนี้?',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'รูปและรายละเอียดที่บันทึกไว้จะถูกลบออกจากเครื่อง',
          style: TextStyle(fontSize: 17),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('ยกเลิก', style: TextStyle(fontSize: 17)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('ลบ', style: TextStyle(fontSize: 17)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.vm.removeActivityDraft('${a['id']}');
    if (mounted) {
      _reload();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('ลบกิจกรรมแล้ว')));
    }
  }

  String? _sendingId;

  /// นำส่งร่างขึ้นระบบ — สำเร็จไปแท็บ "ส่งสำเร็จ" / พลาดไป
  /// "ส่งไม่สำเร็จ" (endpoint ยังไม่มี → ตก failed ซื่อสัตย์)
  Future<void> _submit(Map<String, dynamic> a) async {
    final id = '${a['id']}';
    setState(() => _sendingId = id);
    try {
      final queued = await widget.vm.submitActivity(a);
      if (!mounted) return;
      _reload();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            queued
                ? 'ออฟไลน์อยู่ — บันทึกไว้ส่งอัตโนมัติเมื่อออนไลน์'
                : 'นำส่งกิจกรรมสำเร็จ',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _reload();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'นำส่งไม่สำเร็จ — '
            '${'$e'.replaceFirst('Exception: ', '')}',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _sendingId = null);
    }
  }

  Widget _thumb(Map<String, dynamic> a) {
    final rawPhotos = a['photos'];
    final photos = rawPhotos is List ? rawPhotos : const [];
    if (photos.isEmpty) {
      return Container(
        width: 76,
        height: 76,
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Iconsax.gallery, size: 30, color: Colors.black38),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.file(
        File('${photos.first}'),
        width: 76,
        height: 76,
        cacheWidth: 152,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Container(
          width: 76,
          height: 76,
          color: Colors.grey.shade200,
          child: const Icon(
            Iconsax.gallery_slash,
            size: 30,
            color: Colors.black38,
          ),
        ),
      ),
    );
  }

  Widget _statusChip(bool pending) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: pending ? const Color(0xFFFFF3E0) : const Color(0xFFE8F5E9),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(
        color: pending ? const Color(0xFFE65100) : AppColors.green,
      ),
    ),
    child: Text(
      pending ? 'รอกรอกรายละเอียด' : 'พร้อมนำส่ง',
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.bold,
        color: pending ? const Color(0xFFE65100) : AppColors.green,
      ),
    ),
  );

  /// ปุ่มแก้ไข — เด้งหน้าบันทึกกิจกรรมพร้อม prefill จากร่าง
  /// บันทึกแล้ว reload list (รายการเดิมถูกเขียนทับด้วย id เดิม)
  Future<void> _openEdit(int no, Map<String, dynamic> a) async {
    final msg = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => ActivityDetailView(
          vm: widget.vm,
          photoPaths: const [],
          activityNo: no,
          draft: a,
        ),
      ),
    );
    if (!mounted) return;
    _reload();
    if (msg != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Widget _card(int no, Map<String, dynamic> a) {
    final pending = a['detailPending'] == true;
    final rawPhotos = a['photos'];
    final photos = rawPhotos is List ? rawPhotos : const [];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _thumb(a),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'กิจกรรม ครั้งที่ $no',
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        _statusChip(pending),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'รูป ${photos.length} ใบ'
                      '${a['plantedAt'] != null ? '  •  ปลูก ${_fmtThai('${a['plantedAt']}')}' : ''}',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black54,
                      ),
                    ),
                    Text(
                      'บันทึกเมื่อ ${_fmtThaiTime('${a['createdAt']}')}',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // ปุ่มล่างการ์ด: แก้ไข / ลบ / นำส่ง (นำส่งเฉพาะรายการที่ยังไม่ส่งสำเร็จ)
          Row(
            children: [
              _actionBtn(
                icon: Iconsax.trash,
                label: 'ลบ',
                color: Colors.red,
                onTap: () => _confirmDelete(a),
              ),
              const SizedBox(width: 8),
              _actionBtn(
                icon: Iconsax.edit,
                label: 'แก้ไข',
                color: Colors.amber.shade800,
                onTap: () => _openEdit(no, a),
              ),
              if ('${a['submitStatus'] ?? 'pending'}' != 'sent') ...[
                const SizedBox(width: 8),
                _sendingId == '${a['id']}'
                    ? const Expanded(
                        child: Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      )
                    : _actionBtn(
                        icon: Iconsax.send_2,
                        label: 'นำส่ง',
                        color: AppColors.green,
                        onTap: () => _submit(a),
                      ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// ปุ่ม action ล่างการ์ด — ไอคอน+label กรอบบางสีตาม action
  Widget _actionBtn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) => Expanded(
    child: InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF4F4F4),
    appBar: brrAppBar(
      'นำส่งกิจกรรมที่บันทึกไว้ในเครื่อง',
      actions: [
        IconButton(
          tooltip: 'รีเฟรช',
          icon: const Icon(Icons.refresh, size: 26),
          onPressed: _reload,
        ),
      ],
    ),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: _items,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final items = snap.data ?? const [];
        // แบ่งตามสถานะการส่ง — รายการเก่าไม่มี field นับเป็น
        // "รอส่งขึ้นระบบ"; 'queued' = เน็ตหลุดตอนส่ง รอ flush
        // อัตโนมัติเมื่อ connectivity กลับ (flushQueuedActivities)
        final pending = [
          for (final a in items)
            if ('${a['submitStatus'] ?? 'pending'}' == 'pending' ||
                a['submitStatus'] == 'queued')
              a,
        ];
        final failed = [
          for (final a in items)
            if (a['submitStatus'] == 'failed') a,
        ];
        final sent = [
          for (final a in items)
            if (a['submitStatus'] == 'sent') a,
        ];
        return DefaultTabController(
          length: 3,
          child: Column(
            children: [
              Container(
                color: Colors.white,
                child: TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  labelColor: Colors.black87,
                  unselectedLabelColor: Colors.black54,
                  indicatorColor: AppColors.gold,
                  labelPadding: const EdgeInsets.symmetric(horizontal: 20),
                  labelStyle: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                  tabs: [
                    Tab(text: 'รอส่งขึ้นระบบ (${pending.length})'),
                    Tab(text: 'ส่งไม่สำเร็จ (${failed.length})'),
                    Tab(text: 'ส่งสำเร็จแล้ว (${sent.length})'),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  children: [_list(pending), _list(failed), _list(sent)],
                ),
              ),
            ],
          ),
        );
      },
    ),
  );

  Widget _list(List<Map<String, dynamic>> items) {
    if (items.isEmpty) {
      return const Center(
        child: Text(
          'ไม่มีรายการ',
          style: TextStyle(fontSize: 16, color: Colors.black45),
        ),
      );
    }
    // "ครั้งที่ N" นับตามเวลาบันทึก (เก่าสุด = ครั้งที่ 1) —
    // แสดงใหม่สุดบนสุดแต่เลขครั้งยังเรียงถูก
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
      itemCount: items.length,
      itemBuilder: (_, i) => _card(items.length - i, items[i]),
    );
  }
}

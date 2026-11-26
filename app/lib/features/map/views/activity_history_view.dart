import 'dart:io';

import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import 'package:brr/core/theme/app_theme.dart';
import 'package:brr/core/widgets/brr_app_bar.dart';
import 'package:brr/features/auth/models/user_profile.dart';
import 'package:brr/features/map/viewmodels/parcel_detail_viewmodel.dart';
import 'package:brr/features/map/views/activity_view_view.dart';

/// หน้า "ประวัติบันทึกกิจกรรม" — list กิจกรรมที่บันทึกในเครื่อง
/// ของแปลง (เลขแปลง + เวลาบันทึก + ผู้บันทึก + สถานะ + รูป)
/// แตะรายการเพื่อเปิดดู/แก้รายละเอียดผ่านหน้าบันทึกกิจกรรม
class ActivityHistoryView extends StatefulWidget {
  const ActivityHistoryView({super.key, required this.vm});

  final ParcelDetailViewModel vm;

  @override
  State<ActivityHistoryView> createState() => _ActivityHistoryViewState();
}

class _ActivityHistoryViewState extends State<ActivityHistoryView> {
  late Future<List<Map<String, dynamic>>> _items = widget.vm.activityDrafts();
  bool _newestFirst = true;

  void _reload() => setState(() {
    _items = widget.vm.activityDrafts();
  });

  static String _fmtThaiTime(String? iso) {
    final d = DateTime.tryParse('$iso');
    if (d == null) return '—';
    return '${d.day}/${d.month}/${d.year + 543} '
        '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
  }

  static String _roleLabel(String? role) => switch (role) {
    UserProfile.roleOfficer => 'นักส่งเสริม',
    UserProfile.roleFarmer => 'ชาวไร่',
    _ => '',
  };

  /// chip สถานะตาม ref — ค้างกรอก / รอดำเนินการอ้อยพันธุ์ / ครบ
  (String, Color) _status(Map<String, dynamic> a) {
    if (a['detailPending'] == true) {
      return ('รอกรอกรายละเอียด', const Color(0xFFE65100));
    }
    if (a['seedCane'] == true) {
      return ('รอดำเนินการอ้อยพันธุ์', const Color(0xFFE65100));
    }
    return ('บันทึกเรียบร้อย', AppColors.green);
  }

  Future<void> _openItem(Map<String, dynamic> a) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ActivityViewView(vm: widget.vm, activity: a),
      ),
    );
    if (!mounted) return;
    _reload();
  }

  Widget _thumb(Map<String, dynamic> a) {
    final rawPhotos = a['photos'];
    final photos = rawPhotos is List ? rawPhotos : const [];
    if (photos.isEmpty) {
      return Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Iconsax.gallery, size: 32, color: Colors.black38),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.file(
        File('${photos.first}'),
        width: 96,
        height: 96,
        cacheWidth: 192,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Container(
          width: 96,
          height: 96,
          color: Colors.grey.shade200,
          child: const Icon(
            Iconsax.gallery_slash,
            size: 32,
            color: Colors.black38,
          ),
        ),
      ),
    );
  }

  Widget _card(Map<String, dynamic> a) {
    final (label, color) = _status(a);
    final recordedBy = '${a['recordedBy'] ?? ''}';
    final role = _roleLabel('${a['recordedByRole'] ?? ''}');
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _openItem(a),
      child: Container(
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
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${widget.vm.parcel.plotCode != null ? '[${widget.vm.parcel.plotCode}] ' : ''}'
                        '${widget.vm.parcel.landNo}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'บันทึกเมื่อ: ${_fmtThaiTime('${a['createdAt']}')}',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: color == AppColors.green
                        ? const Color(0xFFE8F5E9)
                        : const Color(0xFFFFF3E0),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: color),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ),
                const Icon(
                  Iconsax.arrow_right_3,
                  color: Colors.black38,
                  size: 22,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Iconsax.edit_2, size: 15, color: Colors.black45),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'บันทึกโดย: '
                    '${recordedBy.isEmpty ? '—' : recordedBy}'
                    '${role.isEmpty ? '' : ' ($role)'}',
                    style: const TextStyle(fontSize: 14, color: Colors.black54),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _thumb(a),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF4F4F4),
    appBar: brrAppBar('ประวัติบันทึกกิจกรรม'),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: _items,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final raw = snap.data ?? const [];
        // service คืนใหม่สุดก่อนเสมอ — toggle กลับลำดับตามปุ่ม
        final items = _newestFirst ? raw : raw.reversed.toList(growable: false);
        return Column(
          children: [
            Container(
              width: double.infinity,
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              child: Row(
                children: [
                  const Icon(
                    Iconsax.clipboard_text,
                    size: 22,
                    color: Colors.black54,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Row(
                      children: [
                        const Flexible(
                          child: Text(
                            'กิจกรรมทั้งหมด',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${items.length}',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.black54,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<bool>(
                    tooltip: 'เรียงลำดับ',
                    initialValue: _newestFirst,
                    onSelected: (v) => setState(() => _newestFirst = v),
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: true,
                        height: 56,
                        child: Text(
                          'ใหม่สุดไปเก่าสุด',
                          style: TextStyle(fontSize: 17),
                        ),
                      ),
                      PopupMenuItem(
                        value: false,
                        height: 56,
                        child: Text(
                          'เก่าสุดไปใหม่สุด',
                          style: TextStyle(fontSize: 17),
                        ),
                      ),
                    ],
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: const Icon(
                        Iconsax.setting_4,
                        size: 24,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: _reload,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: const Icon(
                        Icons.autorenew,
                        size: 22,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: items.isEmpty
                  ? const Center(
                      child: Text(
                        'ยังไม่มีประวัติการบันทึกกิจกรรม',
                        style: TextStyle(fontSize: 16, color: Colors.black45),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
                      itemCount: items.length,
                      itemBuilder: (_, i) => _card(items[i]),
                    ),
            ),
          ],
        );
      },
    ),
  );
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import 'package:brr/core/theme/app_theme.dart';
import 'package:brr/features/map/viewmodels/parcel_detail_viewmodel.dart';

/// หน้า "นำส่งกิจกรรมที่บันทึกไว้ในเครื่อง" — list กิจกรรมของแปลง
/// ที่บันทึกลงเครื่อง (รูปเท่านั้นรอรายละเอียด / กรอกครบรอนำส่ง)
/// ลบรายการได้; นำส่งจริงรอ endpoint backend
class ActivityDraftsView extends StatefulWidget {
  const ActivityDraftsView({super.key, required this.vm});

  final ParcelDetailViewModel vm;

  @override
  State<ActivityDraftsView> createState() => _ActivityDraftsViewState();
}

class _ActivityDraftsViewState extends State<ActivityDraftsView> {
  late Future<List<Map<String, dynamic>>> _items = widget.vm.activityDrafts();

  void _reload() => setState(() => _items = widget.vm.activityDrafts());

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
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'รูปและรายละเอียดที่บันทึกไว้จะถูกลบออกจากเครื่อง',
          style: TextStyle(fontSize: 15),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('ยกเลิก', style: TextStyle(fontSize: 16)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('ลบ', style: TextStyle(fontSize: 16)),
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

  Widget _thumb(Map<String, dynamic> a) {
    final photos = a['photos'] as List? ?? const [];
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

  Widget _card(int no, Map<String, dynamic> a) {
    final pending = a['detailPending'] == true;
    final photos = a['photos'] as List? ?? const [];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
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
                    InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => _confirmDelete(a),
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(Iconsax.trash, size: 22, color: Colors.red),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                _statusChip(pending),
                const SizedBox(height: 8),
                Text(
                  'รูป ${photos.length} ใบ'
                  '${a['plantedAt'] != null ? '  •  ปลูก ${_fmtThai('${a['plantedAt']}')}' : ''}',
                  style: const TextStyle(fontSize: 14, color: Colors.black54),
                ),
                Text(
                  'บันทึกเมื่อ ${_fmtThaiTime('${a['createdAt']}')}',
                  style: const TextStyle(fontSize: 14, color: Colors.black54),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF4F4F4),
    appBar: AppBar(
      backgroundColor: AppColors.green,
      title: const Text(
        'นำส่งกิจกรรมที่บันทึกไว้ในเครื่อง',
        style: TextStyle(fontSize: 18),
      ),
    ),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: _items,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final items = snap.data ?? const [];
        if (items.isEmpty) {
          return const Center(
            child: Text(
              'ยังไม่มีกิจกรรมที่บันทึกไว้ในเครื่อง',
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
      },
    ),
  );
}

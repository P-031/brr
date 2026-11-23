import 'dart:io';

import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import 'package:brr/core/theme/app_theme.dart';
import 'package:brr/core/widgets/brr_app_bar.dart';
import 'package:brr/core/widgets/discard_guard.dart';
import 'package:brr/core/widgets/image_source_sheet.dart';
import 'package:brr/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:brr/features/map/viewmodels/parcel_detail_viewmodel.dart';
import 'package:brr/features/map/views/activity_detail_view.dart';
import 'package:brr/core/utils/json_safe.dart';

/// หน้า "บันทึกกิจกรรม ครั้งที่ N" — เปิดจากการ์ดกิจกรรมใน
/// info sheet: สรุปแปลง + ถ่ายรูป (สูงสุด 3) + ปุ่มบันทึก
/// บังคับมีรูปอย่างน้อย 1 รูปก่อนบันทึก (เด้งเตือนกลางจอ)
class ActivityRecordView extends StatefulWidget {
  const ActivityRecordView({super.key, required this.vm});

  final ParcelDetailViewModel vm;

  @override
  State<ActivityRecordView> createState() => _ActivityRecordViewState();
}

class _ActivityRecordViewState extends State<ActivityRecordView> {
  static const _maxPhotos = 3;
  final _photos = <XFile>[];
  int _activityNo = 1;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _recoverLostPhoto();
    // "ครั้งที่ N" = จำนวนกิจกรรมในเครื่องของแปลง + 1 — อนาคต
    // นับรวมกิจกรรมบน backend ได้เมื่อมี endpoint นำส่ง
    widget.vm.activityDraftCount().then((n) {
      if (mounted) setState(() => _activityNo = n + 1);
    });
  }

  Future<void> _pickPhoto() async {
    if (_photos.length >= _maxPhotos) return;
    final source = await showImageSourceSheet(context);
    if (source == null) return;
    // pickImage throw ได้ (already_active / camera busy บนบางเครื่อง)
    try {
      final x = await ImagePicker().pickImage(source: source, maxWidth: 1600);
      if (x != null && mounted) setState(() => _photos.add(x));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('เปิดกล้องไม่สำเร็จ')));
    }
  }

  /// Android ฆ่าแอประหว่างเปิดกล้อง → รูปที่ถ่ายค้างใน pending
  /// state ของ image_picker — ดึงกลับตอนเปิดหน้าใหม่
  Future<void> _recoverLostPhoto() async {
    try {
      final lost = await ImagePicker().retrieveLostData();
      final file = lost.file;
      if (file != null && mounted && _photos.length < _maxPhotos) {
        setState(() => _photos.add(file));
      }
    } catch (_) {}
  }

  /// แจ้งเตือนกลางจอเมื่อยังไม่มีรูป — ทั้งสองปุ่มบังคับรูปก่อน
  Future<void> _needPhoto() => showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Iconsax.warning_2, size: 56, color: Color(0xFFE65100)),
          const SizedBox(height: 14),
          const Text(
            'กรุณาเพิ่มรูปภาพก่อน',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'ต้องมีรูปภาพกิจกรรมอย่างน้อย 1 รูป\nก่อนบันทึก',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.black54),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.green),
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('ตกลง', style: TextStyle(fontSize: 16)),
            ),
          ),
        ],
      ),
    ),
  );

  /// ปุ่มเขียว — มีรูปแล้วไปหน้ากรอกรายละเอียดต่อ; หน้านั้นบันทึก
  /// แล้วส่งข้อความกลับมาให้หน้านี้ปิดตัวเองพร้อม snackbar
  Future<void> _continueToDetail() async {
    if (_photos.isEmpty) {
      _needPhoto();
      return;
    }
    final msg = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => ActivityDetailView(
          vm: widget.vm,
          photoPaths: [for (final p in _photos) p.path],
          activityNo: _activityNo,
        ),
      ),
    );
    if (msg != null && mounted) Navigator.of(context).pop(msg);
  }

  /// ปุ่มทอง — บันทึกเฉพาะรูปลงเครื่องทันที (รอกรอกรายละเอียด)
  Future<void> _savePhotosOnly() async {
    if (_saving) return;
    if (_photos.isEmpty) {
      _needPhoto();
      return;
    }
    setState(() => _saving = true);
    try {
      final user = context.read<AuthViewModel>().user;
      await widget.vm.saveActivityDraft(
        photoPaths: [for (final p in _photos) p.path],
        detailPending: true,
        recordedBy: user?.displayName,
        recordedByRole: user?.role,
      );
      if (mounted) {
        Navigator.of(context).pop('บันทึกลงเครื่องแล้ว — รอกรอกรายละเอียด');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _line(String label, String? value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Text(
          '$label :',
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: Colors.black54,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value == null || value.isEmpty ? '—' : value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final p = widget.vm.parcel;
    // มีรูปอยู่แล้วกดย้อน = งานค้างหาย — ยืนยันก่อน
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (_photos.isNotEmpty) {
          if (await confirmDiscardChanges(context) && context.mounted) {
            Navigator.of(context).pop();
          }
        } else if (context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F4F4),
        appBar: brrAppBar(
          'บันทึก กิจกรรม ครั้งที่ $_activityNo',
          subtitle: FutureBuilder<Map<String, dynamic>?>(
            future: widget.vm.detail,
            builder: (context, snap) {
              final meta =
                  asStringMap(snap.data?['meta']) ?? p.meta ?? const {};
              final cane = '${meta['caneType'] ?? ''}';
              if (cane.isEmpty) return const SizedBox.shrink();
              return Text(cane);
            },
          ),
        ),
        body: FutureBuilder<Map<String, dynamic>?>(
          future: widget.vm.detail,
          builder: (context, snap) {
            final meta = asStringMap(snap.data?['meta']) ?? p.meta ?? const {};
            final rawArea = snap.data?['area'];
            final areaMap = rawArea is Map<String, dynamic> ? rawArea : null;
            final rai = toDoubleOrNull(areaMap?['raiDecimal']) ?? p.areaRai;
            return ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
              children: [
                // การ์ดสรุปแปลง — เทาชุดเดียวกับหน้าคำขอ
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      _line(
                        'ปีการผลิต',
                        '${meta['productionYear'] ?? p.productionYear ?? ''}',
                      ),
                      _line('หมายเลขแปลง', p.plotCode),
                      _line('พื้นที่สำรวจ(ไร่)', rai.toStringAsFixed(2)),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                // การ์ดภาพถ่าย — บังคับอย่างน้อย 1 รูปก่อนบันทึก
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'ภาพถ่าย',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Text(
                            '${_photos.length}/$_maxPhotos',
                            style: const TextStyle(
                              fontSize: 16,
                              color: Colors.black54,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_photos.isNotEmpty) ...[
                        SizedBox(
                          height: 92,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: _photos.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: 10),
                            itemBuilder: (context, i) => Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.file(
                                    File(_photos[i].path),
                                    width: 92,
                                    height: 92,
                                    cacheWidth: 184,
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
                                Positioned(
                                  top: -4,
                                  right: -4,
                                  child: GestureDetector(
                                    onTap: () =>
                                        setState(() => _photos.removeAt(i)),
                                    child: const CircleAvatar(
                                      radius: 11,
                                      backgroundColor: Colors.white,
                                      child: Icon(
                                        Iconsax.close_circle,
                                        size: 16,
                                        color: Colors.black87,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: OutlinedButton.icon(
                          onPressed: _photos.length < _maxPhotos
                              ? _pickPhoto
                              : null,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.green,
                            side: const BorderSide(color: Color(0xFFDDDDDD)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          icon: const Icon(Iconsax.camera, size: 22),
                          label: const Text(
                            'เพิ่มรูปภาพ',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // ปุ่มเขียว — บันทึกรูปแล้วไปกรอกรายละเอียดต่อ
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.green,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                  onPressed: _saving ? null : _continueToDetail,
                  icon: const Icon(Iconsax.arrow_right_3, size: 22),
                  label: const Text(
                    'บันทึกภาพและกรอกรายละเอียดต่อ',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 12),
                // ปุ่มทอง — บันทึกเฉพาะรูปลงเครื่องทันที
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.gold,
                    side: const BorderSide(color: AppColors.gold, width: 1.5),
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                  onPressed: _saving ? null : _savePhotosOnly,
                  icon: const Icon(Iconsax.camera, size: 22),
                  label: const Text(
                    'บันทึกลงเครื่องทันที (มีแค่รูปภาพ)',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:image_picker/image_picker.dart';

import 'package:brr/core/theme/app_theme.dart';
import 'package:brr/core/widgets/brr_app_bar.dart';
import 'package:brr/core/widgets/discard_guard.dart';
import 'package:brr/core/widgets/image_source_sheet.dart';
import 'package:brr/core/widgets/option_popup.dart';
import 'package:brr/features/map/models/parcel.dart';
import 'package:brr/features/map/viewmodels/parcel_detail_viewmodel.dart';
import 'package:brr/core/utils/json_safe.dart';

/// หน้า "ยืนยันแปลงข้ามปี" — การ์ดสรุปแปลง + เลือกปีเป้าหมาย +
/// สถานะแปลง + ข้อเสนอแนะ + รูปถ่าย (สูงสุด 3)
/// บันทึกลงเครื่องเก็บทับรายการเดิมของแปลง รอ endpoint นำส่ง
class ParcelConfirmView extends StatefulWidget {
  const ParcelConfirmView({super.key, required this.vm});

  final ParcelDetailViewModel vm;

  @override
  State<ParcelConfirmView> createState() => _ParcelConfirmViewState();
}

class _ParcelConfirmViewState extends State<ParcelConfirmView> {
  static const _maxPhotos = 3;

  final _noteCtrl = TextEditingController();
  String? _targetYear;
  String? _status;
  final _photos = <String>[];
  bool _saving = false;
  late String _baseline;

  /// signature ข้อมูลฟอร์ม — เทียบ baseline ตอนกดย้อน
  String _formSig() =>
      [_noteCtrl.text, '$_targetYear', '$_status', _photos.join(',')].join('|');

  late final Future<
    ({List<String> years, FormOptions? opts, Map meta, double rai})
  >
  _dataFut = _load();

  Future<({List<String> years, FormOptions? opts, Map meta, double rai})>
  _load() async {
    // catch ทีละ call — ออฟไลน์/endpoint พังตัวใดตัวหนึ่งไม่ให้
    // ทั้งหน้าว่าง (เดิม future ล้ม = ไม่มี error UI แสดงอะไรเลย)
    List<String> years = const [];
    FormOptions? opts;
    Map<String, dynamic>? detail;
    try {
      years = await widget.vm.loadYears();
    } catch (_) {}
    try {
      opts = await widget.vm.loadOptions();
    } catch (_) {}
    try {
      detail = await widget.vm.detail;
    } catch (_) {}
    // meta/พื้นที่ล่าสุดจาก /plots/:id — fallback ข้อมูลแปลงที่มีอยู่
    final meta =
        asStringMap(detail?['meta']) ?? widget.vm.parcel.meta ?? const {};
    final rawArea = detail?['area'];
    final rai =
        toDoubleOrNull(rawArea is Map ? rawArea['raiDecimal'] : null) ??
        widget.vm.parcel.areaRai;
    return (years: years, opts: opts, meta: meta, rai: rai);
  }

  @override
  void initState() {
    super.initState();
    _recoverLostPhoto();
    _baseline = _formSig();
    // เติมค่ายืนยันเดิมถ้าเคยบันทึกไว้
    widget.vm.parcelConfirm().then((r) {
      if (r == null || !mounted) return;
      setState(() {
        _targetYear = '${r['targetYear'] ?? ''}'.isEmpty
            ? null
            : '${r['targetYear']}';
        _status = '${r['status'] ?? ''}'.isEmpty ? null : '${r['status']}';
        _noteCtrl.text = '${r['note'] ?? ''}';
        final recPhotos = r['photos'];
        for (final p in recPhotos is List ? recPhotos : const []) {
          if (_photos.length >= _maxPhotos) break;
          _photos.add('$p');
        }
        // baseline หลังเติมค่าเดิม — เทียบตอนกดย้อน
        _baseline = _formSig();
      });
    });
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    if (_photos.length >= _maxPhotos) return;
    final source = await showImageSourceSheet(context);
    if (source == null) return;
    try {
      final x = await ImagePicker().pickImage(source: source, maxWidth: 1600);
      if (x != null && mounted) setState(() => _photos.add(x.path));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('เปิดกล้องไม่สำเร็จ')));
    }
  }

  /// Android ฆ่าแอประหว่างเปิดกล้อง (เครื่อง RAM น้อย) — ดึงรูปที่
  /// ค้างใน pending state กลับมาตอนเปิดหน้าอีกครั้ง
  Future<void> _recoverLostPhoto() async {
    try {
      final lost = await ImagePicker().retrieveLostData();
      final file = lost.file;
      if (file != null && mounted && _photos.length < _maxPhotos) {
        setState(() => _photos.add(file.path));
      }
    } catch (_) {}
  }

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _pickYear(List<String> years) async {
    if (years.isEmpty) {
      _toast('โหลดรายการปีการผลิตไม่สำเร็จ');
      return;
    }
    final idx = await showOptionPopup(
      context,
      title: 'ปีการผลิตเป้าหมาย',
      labels: years,
      selectedIndex: _targetYear == null ? null : years.indexOf(_targetYear!),
    );
    if (idx != null) setState(() => _targetYear = years[idx]);
  }

  Future<void> _pickStatus(FormOptions opts) async {
    if (opts.confirmStatuses.isEmpty) {
      _toast('ยังไม่มีตัวเลือกสถานะแปลง');
      return;
    }
    final idx = await showOptionPopup(
      context,
      title: 'สถานะแปลง',
      labels: opts.confirmStatuses,
      selectedIndex: _status == null
          ? null
          : opts.confirmStatuses.indexOf(_status!),
    );
    if (idx != null) setState(() => _status = opts.confirmStatuses[idx]);
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_targetYear == null) {
      _toast('กรุณาเลือกปีการผลิตเป้าหมาย');
      return;
    }
    if (_status == null) {
      _toast('กรุณาเลือกสถานะแปลง');
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.vm.saveParcelConfirm(
        targetYear: _targetYear,
        status: _status,
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        photoPaths: _photos,
      );
      if (mounted) {
        Navigator.of(context).pop('บันทึกยืนยันแปลงข้ามปีแล้ว');
      }
    } catch (e) {
      if (mounted) _toast('$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// label อยู่บน + dropdown กรอบเทาเต็มความกว้าง — กรอบเขียว
  /// เมื่อเลือกแล้ว แบบเดียวกับแถวเลือกในหน้าบันทึกกิจกรรม
  Widget _optRow(
    String label,
    String? value,
    String hint,
    VoidCallback onTap,
  ) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 6),
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: value == null ? Colors.grey.shade300 : AppColors.green,
                width: value == null ? 1 : 1.5,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value ?? hint,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      color: value == null ? Colors.black38 : Colors.black87,
                    ),
                  ),
                ),
                const Icon(
                  Iconsax.arrow_circle_down,
                  size: 26,
                  color: Colors.black87,
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  /// แถวข้อมูลในการ์ดสรุปเทา — "label : value" ชุดเดียวกับ
  /// การ์ดสรุปแปลงในหน้าคำขอ/บันทึกกิจกรรม
  Widget _infoRow(String label, String? value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Text(
          '$label : ',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.black54,
          ),
        ),
        Expanded(
          child: Text(
            value == null || value.isEmpty ? '—' : value,
            style: const TextStyle(
              fontSize: 16.5,
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
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (_formSig() != _baseline) {
          if (await confirmDiscardChanges(context) && context.mounted) {
            Navigator.of(context).pop();
          }
        } else if (context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F4F4),
        appBar: brrAppBar('ยืนยันแปลงข้ามปี'),
        body:
            FutureBuilder<
              ({List<String> years, FormOptions? opts, Map meta, double rai})
            >(
              future: _dataFut,
              builder: (context, snap) {
                final meta = snap.data?.meta ?? const {};
                final rai = snap.data?.rai ?? p.areaRai;
                final years = snap.data?.years ?? const <String>[];
                final opts = snap.data?.opts;
                return ListView(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
                  children: [
                    // การ์ดสรุปแปลง — เทาชุดเดียวกับหน้าคำขอ/บันทึกกิจกรรม
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          _infoRow(
                            'ปีการผลิต',
                            '${meta['productionYear'] ?? p.productionYear ?? '—'}',
                          ),
                          _infoRow('หมายเลขแปลง', p.plotCode),
                          _infoRow('พื้นที่สำรวจ(ไร่)', rai.toStringAsFixed(2)),
                          _infoRow('ประเภทอ้อย', '${meta['caneType'] ?? '—'}'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    // ปีเป้าหมาย + สถานะแปลง — การ์ดขาวรวมแถวเลือก
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          _optRow(
                            'ปีการผลิตเป้าหมาย',
                            _targetYear,
                            'เลือก',
                            () => _pickYear(years),
                          ),
                          _optRow(
                            'สถานะแปลง',
                            _status,
                            'เลือก',
                            () => opts == null
                                ? _toast('กำลังโหลดตัวเลือก')
                                : _pickStatus(opts),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    // ข้อเสนอแนะ
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'ข้อเสนอแนะ',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 6),
                          SizedBox(
                            height: 96,
                            // hint วาดเองตรงกลาง — hintText ของ
                            // multiline ติดบนเสมอ
                            child: ValueListenableBuilder<TextEditingValue>(
                              valueListenable: _noteCtrl,
                              builder: (_, v, _) => Stack(
                                alignment: Alignment.center,
                                children: [
                                  TextField(
                                    textAlign: TextAlign.start,
                                    textAlignVertical: TextAlignVertical.top,
                                    controller: _noteCtrl,
                                    expands: true,
                                    maxLines: null,
                                    style: const TextStyle(fontSize: 16),
                                    decoration: InputDecoration(
                                      isDense: true,
                                      filled: true,
                                      fillColor: Colors.grey.shade100,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 12,
                                          ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        borderSide: BorderSide(
                                          color: Colors.grey.shade300,
                                        ),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        borderSide: BorderSide(
                                          color: Colors.grey.shade300,
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        borderSide: const BorderSide(
                                          color: AppColors.gold,
                                          width: 2,
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (v.text.isEmpty)
                                    const IgnorePointer(
                                      child: Text(
                                        'กรุณากรอกข้อเสนอแนะ',
                                        style: TextStyle(
                                          fontSize: 16,
                                          color: Colors.black38,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    // ภาพถ่าย — pattern เดียวกับหน้าบันทึกกิจกรรม
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
                                style: const TextStyle(color: Colors.black54),
                              ),
                            ],
                          ),
                          if (_photos.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            SizedBox(
                              height: 88,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: _photos.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(width: 10),
                                itemBuilder: (context, i) => Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: Image.file(
                                        File(_photos[i]),
                                        width: 88,
                                        height: 88,
                                        cacheWidth: 176,
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
                          ],
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            height: 46,
                            child: OutlinedButton.icon(
                              onPressed: _photos.length < _maxPhotos
                                  ? _pickPhoto
                                  : null,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.green,
                                side: const BorderSide(color: AppColors.green),
                              ),
                              icon: const Icon(Iconsax.camera, size: 24),
                              label: const Text(
                                'เพิ่มรูปภาพ',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.green,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                      ),
                      onPressed: _saving ? null : _save,
                      child: Text(
                        _saving ? 'กำลังบันทึก…' : 'บันทึกยืนยัน',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
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

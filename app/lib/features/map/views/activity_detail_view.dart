import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax/iconsax.dart';

import 'package:brr/core/theme/app_theme.dart';
import 'package:brr/features/map/viewmodels/parcel_detail_viewmodel.dart';

/// หน้ากรอกรายละเอียดกิจกรรม — เปิดหลังถ่ายรูปแล้วกด
/// "บันทึกภาพและกรอกรายละเอียดต่อ": การ์ดสรุปแปลง +
/// วันที่ปลูก (พิมพ์ วว/ดด/ปปปป พ.ศ. หรือเลือกจากปฏิทิน)
/// บันทึกสำเร็จ → pop คืนข้อความให้หน้าก่อนปิดตัวเอง
class ActivityDetailView extends StatefulWidget {
  const ActivityDetailView({
    super.key,
    required this.vm,
    required this.photoPaths,
    required this.activityNo,
  });

  final ParcelDetailViewModel vm;
  final List<String> photoPaths;
  final int activityNo;

  @override
  State<ActivityDetailView> createState() => _ActivityDetailViewState();
}

class _ActivityDetailViewState extends State<ActivityDetailView> {
  final _dateCtrl = TextEditingController();
  DateTime? _plantedAt;
  bool _saving = false;

  @override
  void dispose() {
    _dateCtrl.dispose();
    super.dispose();
  }

  /// แสดงวันที่เป็น วว/ดด/ปปปป (พ.ศ.)
  static String _fmtThai(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/'
      '${d.year + 543}';

  /// parse วว/ดด/ปปปป — รับทั้ง พ.ศ. (>=2400) และ ค.ศ.
  static DateTime? _parseThai(String raw) {
    final parts = raw.trim().split('/');
    if (parts.length != 3) return null;
    final d = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    var y = int.tryParse(parts[2]);
    if (d == null || m == null || y == null) return null;
    if (y >= 2400) y -= 543;
    if (y < 1900 || m < 1 || m > 12 || d < 1 || d > 31) return null;
    final dt = DateTime(y, m, d);
    if (dt.day != d || dt.month != m) return null;
    return dt;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _plantedAt ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('th'),
    );
    if (picked != null) {
      setState(() {
        _plantedAt = picked;
        _dateCtrl.text = _fmtThai(picked);
      });
    }
  }

  /// แจ้งเตือนกลางจอเมื่อวันที่ไม่ถูกต้อง
  Future<void> _warnDate() => showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Iconsax.warning_2, size: 56, color: Color(0xFFE65100)),
          const SizedBox(height: 14),
          const Text(
            'วันที่ไม่ถูกต้อง',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'กรุณากรอกเป็น วว/ดด/ปปปป (พ.ศ.)\nเช่น 15/06/2568 หรือเลือกจากปฏิทิน',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.black54),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.green,
              ),
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('ตกลง', style: TextStyle(fontSize: 16)),
            ),
          ),
        ],
      ),
    ),
  );

  Future<void> _save() async {
    if (_saving) return;
    var planted = _plantedAt;
    if (planted == null && _dateCtrl.text.trim().isNotEmpty) {
      planted = _parseThai(_dateCtrl.text);
      if (planted == null) {
        _warnDate();
        return;
      }
    }
    setState(() => _saving = true);
    try {
      await widget.vm.saveActivityDraft(
        photoPaths: widget.photoPaths,
        detailPending: false,
        plantedAt: planted == null
            ? null
            : '${planted.year.toString().padLeft(4, '0')}-'
                  '${planted.month.toString().padLeft(2, '0')}-'
                  '${planted.day.toString().padLeft(2, '0')}',
      );
      if (mounted) Navigator.of(context).pop('บันทึกกิจกรรมเรียบร้อย');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
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
    return Scaffold(
      backgroundColor: const Color(0xFFF4F4F4),
      appBar: AppBar(
        backgroundColor: AppColors.green,
        title: Text(
          'บันทึก กิจกรรม ครั้งที่ ${widget.activityNo}',
          style: const TextStyle(fontSize: 19),
        ),
      ),
      body: FutureBuilder<Map<String, dynamic>?>(
        future: widget.vm.detail,
        builder: (context, snap) {
          final meta =
              (snap.data?['meta'] as Map<String, dynamic>?) ??
              p.meta ??
              const {};
          final areaMap = snap.data?['area'] as Map<String, dynamic>?;
          final rai =
              (areaMap?['raiDecimal'] as num?)?.toDouble() ?? p.areaRai;
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
            children: [
              // การ์ดสรุปแปลง — ชุดเดียวกับหน้าถ่ายรูป
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
                    _line('พื้นที่(ไร่)', rai.toStringAsFixed(2)),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              // การ์ดวันที่ปลูก — พิมพ์เองหรือเลือกจากปฏิทิน
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
                      'วันที่ปลูก',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _dateCtrl,
                      keyboardType: TextInputType.datetime,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'[0-9/ก-ฮ]'),
                        ),
                      ],
                      style: const TextStyle(fontSize: 17),
                      decoration: InputDecoration(
                        hintText: 'วว/ดด/ปปปป (พ.ศ.)',
                        hintStyle: const TextStyle(
                          fontSize: 16,
                          color: Colors.black38,
                        ),
                        suffixIcon: IconButton(
                          icon: const Icon(
                            Iconsax.calendar_1,
                            color: AppColors.green,
                            size: 26,
                          ),
                          onPressed: _pickDate,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
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
                            color: AppColors.green,
                            width: 1.5,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                      ),
                      onChanged: (_) => _plantedAt = null,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.green,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
                onPressed: _saving ? null : _save,
                icon: const Icon(Iconsax.tick_circle, size: 22),
                label: Text(
                  _saving ? 'กำลังบันทึก…' : 'บันทึกกิจกรรม',
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
    );
  }
}

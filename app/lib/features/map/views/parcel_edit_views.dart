import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import 'package:brr/core/theme/app_theme.dart';
import 'package:brr/features/map/models/parcel.dart';
import 'package:brr/features/map/viewmodels/parcel_detail_viewmodel.dart';

/// หน้าในเมนู ⋮ ของรายละเอียดแปลง — ตาม ref แอปจริง สีตามธีมแอป
/// (navy card + ปุ่มเขียว)
///
/// - [EditRouteSeqView] แก้ไข รูท & ลำดับ — PATCH /plots/:id จริง
/// - [StatusRequestView] ยื่นคำขออัปเดตสถานะแปลง1 — dropdown จาก
///   /meta/options; submit ยัง stub รอ endpoint คำขอ
/// - [EditRequestView] ยื่นคำขออัปเดตสถานะแปลง2 — เช่นเดียวกัน

/// ข้อมูลที่ต้องใช้ร่วมกันของ 3 หน้า — resolve detail ครั้งเดียว
class _ParcelCtx {
  const _ParcelCtx({
    required this.landNo,
    required this.meta,
    required this.farmerName,
    required this.farmerCode,
    required this.areaText,
    this.status,
  });

  final String landNo;
  final Map meta;
  final String? farmerName;
  final String? farmerCode;
  final String areaText;
  final String? status;

  factory _ParcelCtx.of(Parcel p, Map<String, dynamic>? detail) {
    final meta =
        (detail?['meta'] as Map<String, dynamic>?) ?? p.meta ?? const {};
    final farmer = detail?['farmer'] as Map<String, dynamic>?;
    final areaMap = detail?['area'] as Map<String, dynamic>?;
    final rai = (areaMap?['raiDecimal'] as num?)?.toDouble() ?? p.areaRai;
    return _ParcelCtx(
      landNo: p.name.replaceAll(RegExp(r'\s*#\d+\s*$'), ''),
      meta: meta,
      farmerName: _str(farmer?['displayName']) ?? p.owner,
      farmerCode: _str(farmer?['username']) ?? _str(farmer?['id']),
      areaText: rai.toStringAsFixed(2),
      status: _str(p.status) ?? _str(detail?['status']),
    );
  }

  static String? _str(dynamic v) {
    final s = '$v';
    return (v == null || s.isEmpty) ? null : s;
  }

  String? metaStr(String k) => _str(meta[k]);
}

/// แถบ navy สรุปแปลงเหมือน ref — label ซ้าย / value ขวา
class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.ctx});

  final _ParcelCtx ctx;

  @override
  Widget build(BuildContext context) {
    Widget line(String label, String? value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Text(
            '$label : ',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          Expanded(
            child: Text(
              value == null || value.isEmpty ? '—' : value,
              style: const TextStyle(
                fontSize: 16.5,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.navy,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          line('ปีการผลิต', ctx.metaStr('productionYear')),
          line('หมายเลขแปลง', ctx.landNo),
          line('พื้นที่สำรวจ(ไร่)', ctx.areaText),
          line('ประเภทอ้อย', ctx.metaStr('caneType')),
        ],
      ),
    );
  }
}

/// หน้า "แก้ไข รูท & ลำดับ" — PATCH /plots/:id จริง pop คืน true
/// เมื่อบันทึกสำเร็จ
class EditRouteSeqView extends StatefulWidget {
  const EditRouteSeqView({super.key, required this.vm});

  final ParcelDetailViewModel vm;

  @override
  State<EditRouteSeqView> createState() => _EditRouteSeqViewState();
}

class _EditRouteSeqViewState extends State<EditRouteSeqView> {
  final _root = TextEditingController();
  final _seq = TextEditingController();
  bool _prefilled = false;
  bool _saving = false;

  @override
  void dispose() {
    _root.dispose();
    _seq.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.vm.updateRouteSeq(
        rootNo: _root.text.trim(),
        sequenceNo: _seq.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F4F4),
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        title: const Text('แก้ไข รูท & ลำดับ'),
      ),
      body: FutureBuilder<Map<String, dynamic>?>(
        future: widget.vm.detail,
        builder: (context, snap) {
          final ctx = _ParcelCtx.of(widget.vm.parcel, snap.data);
          if (!_prefilled && snap.connectionState == ConnectionState.done) {
            _prefilled = true;
            _root.text = ctx.metaStr('rootNo') ?? '';
            _seq.text = ctx.metaStr('sequenceNo') ?? '';
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
            children: [
              _HeaderCard(ctx: ctx),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    _field('รูท', _root),
                    _field('ลำดับ', _seq),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: AppColors.navy),
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Iconsax.save_2, size: 20),
                label: const Text(
                  'บันทึกข้อมูล',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// แถว label + ช่องเส้นใต้ตาม ref — text รับได้ทั้งเลขไทย/อังกฤษ
  /// ขอบใต้ช่องเปลี่ยนเป็นสีทองตอนโฟกัส
  Widget _field(String label, TextEditingController ctrl) {
    return Row(
      children: [
        SizedBox(
          width: 70,
          child: Text(
            '$label :',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
        ),
        Expanded(
          child: TextField(
            controller: ctrl,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16.5,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
            cursorColor: AppColors.gold,
            decoration: const InputDecoration(
              isDense: true,
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.black38),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: AppColors.gold, width: 2),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// base ของหน้าคำขอ 2 หน้า — โหลด options จาก backend + scaffold
/// พื้นเทา + header card
abstract class _RequestViewBase extends StatefulWidget {
  const _RequestViewBase({
    super.key,
    required this.vm,
    required this.title,
  });

  final ParcelDetailViewModel vm;
  final String title;
}

abstract class _RequestViewBaseState<T extends _RequestViewBase>
    extends State<T> {
  late final Future<FormOptions> _options = widget.vm.loadOptions();
  String? _selected;
  bool _sending = false;

  /// 'status' = คำขอ1 (เปลี่ยนสถานะ), 'edit' = คำขอ2 (ประเภทแก้ไข) —
  /// ส่งตรงไป backend ตาม docs/API_CONTRACT.md
  String get requestKind;

  /// ส่งคำขอจริงผ่าน VM — endpoint รอ backend; ล้มเหลว (เช่น 404
  /// ตอน endpoint ยังไม่มี) โชว์ error บนจอ ไม่แสร้งว่าสำเร็จ
  Future<void> _submit() async {
    final value = _selected;
    if (value == null || _sending) return;
    setState(() => _sending = true);
    try {
      await widget.vm.submitRequest(kind: requestKind, value: value);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// dropdown ในกรอบขาวแบบ ref — options จาก backend เท่านั้น
  Widget dropdown(
    List<String> options, {
    List<String>? display,
    String? value,
    ValueChanged<String?>? onChanged,
  }) {
    if (options.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          'ไม่มีตัวเลือกจากระบบ',
          style: TextStyle(fontSize: 14, color: Colors.black45),
        ),
      );
    }
    final shown = display ?? options;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.gold),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value ?? _selected,
          isExpanded: true,
          items: [
            for (var i = 0; i < options.length; i++)
              DropdownMenuItem(value: options[i], child: Text(shown[i])),
          ],
          onChanged: onChanged ?? (v) => setState(() => _selected = v),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F4F4),
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        title: Text(widget.title),
      ),
      body: FutureBuilder<Map<String, dynamic>?>(
        future: widget.vm.detail,
        builder: (context, snap) {
          final ctx = _ParcelCtx.of(widget.vm.parcel, snap.data);
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
            children: body(ctx),
          );
        },
      ),
    );
  }

  List<Widget> body(_ParcelCtx ctx);
}

/// หน้า "ยื่นคำขออัปเดตสถานะแปลง1" — dropdown สถานะ + ปุ่มส่งคำขอ
class StatusRequestView extends _RequestViewBase {
  const StatusRequestView({super.key, required super.vm})
    : super(title: 'ยื่นคำขออัปเดตสถานะแปลง1');

  @override
  State<StatusRequestView> createState() => _StatusRequestViewState();
}

class _StatusRequestViewState
    extends _RequestViewBaseState<StatusRequestView> {
  @override
  String get requestKind => 'status';

  @override
  List<Widget> body(_ParcelCtx ctx) => [
    _HeaderCard(ctx: ctx),
    const SizedBox(height: 10),
    FutureBuilder<FormOptions>(
      future: _options,
      builder: (context, snap) {
        final opts = snap.data?.plotStatuses ?? const [];
        // ค่าเริ่มต้น = สถานะปัจจุบันถ้าอยู่ใน list ไม่งั้นตัวแรก
        _selected ??= opts.contains(ctx.status)
            ? ctx.status
            : (opts.isNotEmpty ? opts.first : null);
        return dropdown(opts);
      },
    ),
    const SizedBox(height: 16),
    FilledButton.icon(
      style: FilledButton.styleFrom(backgroundColor: AppColors.navy),
      onPressed: _sending ? null : _submit,
      icon: const Icon(Iconsax.send_2, size: 20),
      label: const Text(
        'ส่งคำขอ',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    ),
  ];
}

/// หน้า "ยื่นคำขออัปเดตสถานะแปลง2" — เลือกประเภทคำขอ + การ์ดเตือน +
/// ปุ่มส่งคำขออัปเดตแปลง
class EditRequestView extends _RequestViewBase {
  const EditRequestView({super.key, required super.vm})
    : super(title: 'ยื่นคำขออัปเดตสถานะแปลง2');

  @override
  State<EditRequestView> createState() => _EditRequestViewState();
}

class _EditRequestViewState extends _RequestViewBaseState<EditRequestView> {
  @override
  String get requestKind => 'edit';

  @override
  List<Widget> body(_ParcelCtx ctx) {
    Widget line(String label, String? value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            '$label : ',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          Expanded(
            child: Text(
              value == null || value.isEmpty ? '—' : value,
              style: const TextStyle(
                fontSize: 16.5,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
    return [
      // การ์ด navy ข้อมูลแปลงปัจจุบัน — ละเอียดกว่าหน้าแรกตาม ref
      Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        decoration: BoxDecoration(
          color: AppColors.navy,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(
                  Iconsax.document_text,
                  size: 20,
                  color: Colors.white,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'ข้อมูลแปลงปัจจุบัน',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                if (ctx.metaStr('productionYear') != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.gold),
                    ),
                    child: Text(
                      'ปีการผลิต ${ctx.metaStr('productionYear')}',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
            const Divider(height: 18, color: Colors.white24),
            line('รหัสแปลง (Land No.)', ctx.landNo),
            line('ประเภทอ้อย', ctx.metaStr('caneType')),
            line('พื้นที่', '${ctx.areaText} ไร่'),
            line(
              'ชาวไร่เดิม',
              ctx.farmerName == null
                  ? null
                  : '[${ctx.farmerCode ?? '—'}] ${ctx.farmerName}',
            ),
            line('ผู้ดูแล/นักส่งเสริม', ctx.metaStr('officerName')),
          ],
        ),
      ),
      const SizedBox(height: 14),
      const Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'เลือกประเภทการร้องขอแก้ไขแปลง',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      const SizedBox(height: 8),
      FutureBuilder<FormOptions>(
        future: _options,
        builder: (context, snap) {
          final opts = snap.data?.plotRequestTypes ?? const [];
          _selected ??= opts.isNotEmpty ? opts.first : null;
          return dropdown(
            opts,
            display: [for (var i = 0; i < opts.length; i++) '${i + 1}. ${opts[i]}'],
          );
        },
      ),
      const SizedBox(height: 14),
      // การ์ดเตือนตามประเภทคำขอ — เหมือน ref
      if (_selected != null)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFFDEBEC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFF5C6CB)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Iconsax.warning_2,
                color: Color(0xFFD6336C),
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'คำเตือนเรื่องการ$_selected',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFA61E4D),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'การส่งคำขอนี้จะขอเปลี่ยนสถานะแปลงเพาะปลูกเป็น '
                      '"$_selected" เมื่อได้รับการอนุมัติจากผู้บังคับบัญชา '
                      'จะมีผลทางระบบ',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFFA61E4D),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      const SizedBox(height: 16),
      FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: AppColors.navy),
        onPressed: _sending ? null : _submit,
        icon: const Icon(Iconsax.send_2, size: 20),
        label: const Text(
          'ส่งคำขออัปเดตแปลง',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
    ];
  }
}

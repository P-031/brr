import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import 'package:brr/core/theme/app_theme.dart';
import 'package:brr/core/widgets/brr_app_bar.dart';
import 'package:brr/core/widgets/option_popup.dart';
import 'package:brr/features/map/models/parcel.dart';
import 'package:brr/features/map/viewmodels/parcel_detail_viewmodel.dart';
import 'package:brr/core/utils/json_safe.dart';

/// หน้าในเมนู ⋮ ของรายละเอียดแปลง — ตาม ref แอปจริง สีตามธีมแอป
/// (dark green card + ปุ่มเขียว)
///
/// - [EditRouteSeqView] แก้ไข รูท & ลำดับ — PATCH /plots/:id จริง
/// - [StatusRequestView] ยื่นคำขออัปเดตสถานะแปลง1 — dropdown จาก
///   /meta/options; submit ยัง stub รอ endpoint คำขอ
/// - [EditRequestView] ยื่นคำขออัปเดตสถานะแปลง2 — เช่นเดียวกัน

/// ข้อมูลที่ต้องใช้ร่วมกันของ 3 หน้า — resolve detail ครั้งเดียว
class _ParcelCtx {
  const _ParcelCtx({
    required this.landNo,
    required this.plotCode,
    required this.meta,
    required this.farmerName,
    required this.farmerCode,
    required this.areaText,
    this.status,
  });

  final String landNo;

  /// รหัสแปลง = เลข #NNN ท้ายชื่อ (schema ไม่มีฟิลด์ code แยก)
  final String? plotCode;
  final Map meta;
  final String? farmerName;
  final String? farmerCode;
  final String areaText;
  final String? status;

  factory _ParcelCtx.of(Parcel p, Map<String, dynamic>? detail) {
    final meta = asStringMap(detail?['meta']) ?? p.meta ?? const {};
    final farmer = asStringMap(detail?['farmer']);
    final areaMap = asStringMap(detail?['area']);
    final rai = toDoubleOrNull(areaMap?['raiDecimal']) ?? p.areaRai;
    return _ParcelCtx(
      landNo: p.landNo,
      plotCode: p.plotCode,
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

/// แถบเทาสรุปแปลง — label ซ้าย / value ขวา (เดิมเขียวเข้ม)
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          line('ปีการผลิต', ctx.metaStr('productionYear')),
          line('ชื่อแปลง', ctx.landNo),
          line('หมายเลขแปลง', ctx.plotCode),
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
      final queued = await widget.vm.updateRouteSeq(
        rootNo: _root.text.trim(),
        sequenceNo: _seq.text.trim(),
      );
      if (mounted) {
        if (queued) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('บันทึกไว้ในเครื่องแล้ว — จะส่งเมื่อออนไลน์'),
            ),
          );
        }
        Navigator.of(context).pop(true);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F4F4),
      appBar: brrAppBar('แก้ไข รูท & ลำดับ'),
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
                  children: [_field('รูท', _root), _field('ลำดับ', _seq)],
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: AppColors.green),
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

  /// label อยู่บน + ช่องพิมพ์ในกรอบเต็มความกว้าง — text รับได้
  /// ทั้งเลขไทย/อังกฤษ ขอบเปลี่ยนเป็นสีทองตอนโฟกัส
  Widget _field(String label, TextEditingController ctrl) {
    return Column(
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
        TextField(
          controller: ctrl,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 16.5,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
          cursorColor: AppColors.gold,
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: Colors.grey.shade100,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 10,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.gold, width: 2),
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
  const _RequestViewBase({super.key, required this.vm, required this.title});

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

  /// ฟิลด์เพิ่มเติมที่ส่งพ่วง body (เช่น reason ของคำขอ1) —
  /// null = ไม่มี
  Map<String, String?>? get requestFields => null;

  /// เช็กก่อนส่ง — คืนข้อความเตือนถ้ายังขาดข้อมูล
  String? get submitBlocker => null;

  /// ส่งคำขอจริงผ่าน VM — สำเร็จส่งสถานะจาก backend กลับให้หน้าแม่
  /// แจ้งผล; ล้มเหลวโชว์ error บนจอ ไม่แสร้งว่าสำเร็จ
  Future<void> _submit() async {
    final value = _selected;
    if (value == null || _sending) return;
    final blocker = submitBlocker;
    if (blocker != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(blocker)));
      return;
    }
    setState(() => _sending = true);
    try {
      final status = await widget.vm.submitRequest(
        kind: requestKind,
        value: value,
        fields: requestFields,
      );
      if (mounted) {
        Navigator.of(context).pop('ส่งคำขอสำเร็จ — สถานะ: $status');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// dropdown ในกรอบขาวแบบ ref — options จาก backend เท่านั้น
  /// [bindSelected] false = ช่องอิสระ (เช่น เหตุผลประกอบ) ไม่ผูก
  /// กับ [_selected] ของ dropdown หลัก — ค่า null โชว์ [hint]
  Widget dropdown(
    List<String> options, {
    List<String>? display,
    String? value,
    ValueChanged<String?>? onChanged,
    bool bindSelected = true,
    String? hint,
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
    final current = value ?? (bindSelected ? _selected : null);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        final i = await showOptionPopup(
          context,
          title: hint,
          labels: shown,
          selectedIndex: current == null ? null : options.indexOf(current),
        );
        if (i == null) return;
        (onChanged ?? (v) => setState(() => _selected = v))(options[i]);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.gold),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                current ?? hint ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  color: current == null ? Colors.black45 : Colors.black87,
                ),
              ),
            ),
            const Icon(
              Iconsax.arrow_circle_down,
              size: 28,
              color: Colors.black87,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F4F4),
      appBar: brrAppBar(widget.title),
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

class _StatusRequestViewState extends _RequestViewBaseState<StatusRequestView> {
  String? _reason;
  List<String> _activeReasons = const [];

  @override
  String get requestKind => 'status';

  @override
  Map<String, String?>? get requestFields =>
      _reason == null ? null : {'reason': _reason};

  /// สถานะที่มีเหตุผลประกอบต้องเลือกเหตุผลก่อนส่ง
  @override
  String? get submitBlocker => _activeReasons.isNotEmpty && _reason == null
      ? 'กรุณาเลือกเหตุผลประกอบสถานะแปลง'
      : null;

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
        final reasons = snap.data?.statusReasons[_selected] ?? const <String>[];
        _activeReasons = reasons;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            dropdown(
              opts,
              onChanged: (v) => setState(() {
                _selected = v;
                _reason = null;
              }),
            ),
            // สถานะที่ backend กำหนดเหตุผลไว้ → dropdown ที่สอง
            if (reasons.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.gold),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'เหตุผลประกอบสถานะแปลง',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    dropdown(
                      reasons,
                      value: _reason,
                      bindSelected: false,
                      hint: 'เลือกเหตุผลประกอบสถานะแปลง',
                      onChanged: (v) => setState(() => _reason = v),
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    ),
    const SizedBox(height: 16),
    FilledButton.icon(
      style: FilledButton.styleFrom(backgroundColor: AppColors.green),
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
  // การ์ด "แก้ไขประเภทอ้อย"
  String? _caneMode;
  String? _caneTypeNew;
  // การ์ด "แก้ไขชาวไร"
  final _plotCodeCtrl = TextEditingController();
  FarmerRef? _newFarmer;
  List<FarmerRef>? _farmers;

  @override
  void dispose() {
    _plotCodeCtrl.dispose();
    super.dispose();
  }

  @override
  String get requestKind => 'edit';

  /// payload เพิ่มเติมตามประเภทคำขอ — backend เก็บลง PlotRequest.payload
  @override
  Map<String, String?>? get requestFields {
    if (_selected == 'แก้ไขประเภทอ้อย') {
      return {'canePlantMode': _caneMode, 'caneTypeNew': _caneTypeNew};
    }
    if (_selected == 'แก้ไขชาวไร') {
      final code = _plotCodeCtrl.text.trim();
      return {
        'newPlotCode': code.isEmpty ? null : code,
        'newFarmer': _newFarmer?.name,
        'newFarmerId': _newFarmer?.id,
      };
    }
    return null;
  }

  /// การ์ดที่โผล่แล้วต้องกรอกครบก่อนส่ง
  @override
  String? get submitBlocker {
    if (_selected == 'แก้ไขประเภทอ้อย') {
      if (_caneMode == null) return 'กรุณาเลือกประเภทอ้อยหลักใหม่';
      if (_caneTypeNew == null) {
        return 'กรุณาเลือกประเภทอ้อย$_caneMode';
      }
    }
    if (_selected == 'แก้ไขชาวไร') {
      if (_plotCodeCtrl.text.trim().isEmpty) {
        return 'กรุณากรอกรหัสแปลงใหม่';
      }
      if (_newFarmer == null) return 'กรุณาเลือกชาวไร่คนใหม่';
    }
    return null;
  }

  /// เปลี่ยนประเภทคำขอ → ล้างค่าการ์ดย่อยที่เคยกรอก
  void _resetSub() {
    _caneMode = null;
    _caneTypeNew = null;
    _newFarmer = null;
    _plotCodeCtrl.clear();
  }

  /// การ์ดย่อยสีขาวกรอบทอง — หัวข้อใหญ่ + children (หัวข้อย่อย/ช่อง)
  Widget _subCard(String title, List<Widget> children) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.gold),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        ...children,
      ],
    ),
  );

  Widget _subLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
  );

  /// ช่องเลือกชาวไร่คนใหม่ — popup ค้นหาได้ ข้อมูลจาก backend
  Widget _farmerField() => InkWell(
    borderRadius: BorderRadius.circular(10),
    onTap: () async {
      List<FarmerRef> farmers;
      try {
        farmers = _farmers ??= await widget.vm.loadFarmers();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('$e')));
        }
        return;
      }
      if (!mounted) return;
      final i = await showOptionPopup(
        context,
        title: 'เลือกชาวไร่คนใหม่',
        labels: [for (final f in farmers) f.name],
        selectedIndex: _newFarmer == null
            ? null
            : () {
                final i = farmers.indexWhere((f) => f.id == _newFarmer!.id);
                return i < 0 ? null : i;
              }(),
        searchHint: 'ค้นหาชาวไร่',
      );
      if (i != null) setState(() => _newFarmer = farmers[i]);
    },
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black26),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _newFarmer?.name ?? 'ค้นหา/เลือกชาวไร่คนใหม่',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                color: _newFarmer == null ? Colors.black45 : Colors.black87,
              ),
            ),
          ),
          const Icon(Iconsax.search_normal, size: 18, color: Colors.black45),
        ],
      ),
    ),
  );

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
    return [
      // การ์ดเทา ข้อมูลแปลงปัจจุบัน — ละเอียดกว่าหน้าแรกตาม ref
      Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(
                  Iconsax.document_text,
                  size: 20,
                  color: Colors.black54,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'ข้อมูลแปลงปัจจุบัน',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
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
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.gold),
                    ),
                    child: Text(
                      'ปีการผลิต ${ctx.metaStr('productionYear')}',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Colors.black87,
                      ),
                    ),
                  ),
              ],
            ),
            const Divider(height: 18, color: Colors.black12),
            line('ชื่อแปลง', ctx.landNo),
            line('รหัสแปลง (Land No.)', ctx.plotCode),
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
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              dropdown(
                opts,
                display: [
                  for (var i = 0; i < opts.length; i++) '${i + 1}. ${opts[i]}',
                ],
                onChanged: (v) => setState(() {
                  _selected = v;
                  _resetSub();
                }),
              ),
              if (_selected == 'แก้ไขประเภทอ้อย') ...[
                const SizedBox(height: 14),
                _subCard('กรอกข้อมูลประเภทอ้อยใหม่', [
                  _subLabel('ประเภทอ้อยหลักใหม่'),
                  dropdown(
                    snap.data?.canePlantModes ?? const [],
                    value: _caneMode,
                    bindSelected: false,
                    hint: 'เลือกประเภทอ้อยหลักใหม่',
                    onChanged: (v) => setState(() {
                      _caneMode = v;
                      _caneTypeNew = null;
                    }),
                  ),
                  if (_caneMode != null) ...[
                    const SizedBox(height: 12),
                    _subLabel('ประเภทอ้อย$_caneMode'),
                    dropdown(
                      snap.data?.caneTypesByMode[_caneMode] ??
                          snap.data?.caneTypes ??
                          const [],
                      value: _caneTypeNew,
                      bindSelected: false,
                      hint: 'เลือกประเภทอ้อย$_caneMode',
                      onChanged: (v) => setState(() => _caneTypeNew = v),
                    ),
                  ],
                ]),
              ],
              if (_selected == 'แก้ไขชาวไร') ...[
                const SizedBox(height: 14),
                _subCard('แก้ไขข้อมูลชาวไร่และแปลง', [
                  _subLabel('รหัสแปลงใหม่'),
                  TextField(
                    textAlign: TextAlign.center,
                    controller: _plotCodeCtrl,
                    decoration: InputDecoration(
                      hintText: 'กรอกรหัสแปลงใหม่',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _subLabel('ชาวไร่คนใหม่'),
                  _farmerField(),
                ]),
              ],
            ],
          );
        },
      ),
      const SizedBox(height: 14),
      // การ์ดเตือน — เฉพาะคำขอยกเลิกแปลง (ผลกระทบหนักสุด)
      if (_selected == 'ยกเลิกแปลง')
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
              const Icon(Iconsax.warning_2, color: Color(0xFFD6336C), size: 22),
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
        style: FilledButton.styleFrom(backgroundColor: AppColors.green),
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

/// หน้า "กลุ่มบำรุง / ตัด" — header card เหมือนคำขอ1 + dropdown 2 ชุด
/// (กลุ่มสร้างอ้อย(บำรุง) / กลุ่มตัด) + ปุ่มส่งคำขอ
/// ตัวเลือกแยกจาก caneGroups ของ backend ตามคำในชื่อกลุ่ม
/// ("บำรุง"/"ตัด" — convention เดียวกับ seed/filter)
class GroupRequestView extends _RequestViewBase {
  const GroupRequestView({super.key, required super.vm})
    : super(title: 'กลุ่มบำรุง / ตัด');

  @override
  State<GroupRequestView> createState() => _GroupRequestViewState();
}

class _GroupRequestViewState extends _RequestViewBaseState<GroupRequestView> {
  String? _maintain;
  String? _harvest;

  @override
  String get requestKind => 'group';

  /// ส่งทั้ง 2 ฟิลด์ใน request เดียว — เลือกอย่างน้อย 1 กลุ่ม
  Future<void> _submitGroup() async {
    if ((_maintain == null && _harvest == null) || _sending) return;
    setState(() => _sending = true);
    try {
      final status = await widget.vm.submitRequest(
        kind: requestKind,
        fields: {'maintainGroup': _maintain, 'harvestGroup': _harvest},
      );
      if (mounted) {
        Navigator.of(context).pop('ส่งคำขอสำเร็จ — สถานะ: $status');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  List<Widget> body(_ParcelCtx ctx) => [
    _HeaderCard(ctx: ctx),
    const SizedBox(height: 14),
    FutureBuilder<FormOptions>(
      future: _options,
      builder: (context, snap) {
        final groups = snap.data?.caneGroups ?? const <String>[];
        final maintain = [
          for (final g in groups)
            if (g.contains('บำรุง')) g,
        ];
        final harvest = [
          for (final g in groups)
            if (g.contains('ตัด')) g,
        ];
        // ค่าเดิมจาก backend — meta.maintainGroup/harvestGroup
        // (อนาคต) ไม่งั้นเดาจาก caneGroup ตามคำ
        _maintain ??= _pick(
          maintain,
          ctx.metaStr('maintainGroup') ??
              _matchKind(ctx.metaStr('caneGroup'), 'บำรุง'),
        );
        _harvest ??= _pick(
          harvest,
          ctx.metaStr('harvestGroup') ??
              _matchKind(ctx.metaStr('caneGroup'), 'ตัด'),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'กลุ่มสร้างอ้อย (กลุ่มบำรุง)',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            dropdown(
              maintain,
              value: _maintain,
              onChanged: (v) => setState(() => _maintain = v),
            ),
            const SizedBox(height: 14),
            const Text(
              'กลุ่มตัด',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            dropdown(
              harvest,
              value: _harvest,
              onChanged: (v) => setState(() => _harvest = v),
            ),
          ],
        );
      },
    ),
    const SizedBox(height: 16),
    FilledButton.icon(
      style: FilledButton.styleFrom(backgroundColor: AppColors.green),
      onPressed: _sending ? null : _submitGroup,
      icon: const Icon(Iconsax.send_2, size: 20),
      label: const Text(
        'ส่งคำขอ',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    ),
  ];

  /// caneGroup เดิมที่มีคำ kw → ใช้ prefill
  static String? _matchKind(String? group, String kw) =>
      group != null && group.contains(kw) ? group : null;

  /// เลือกเฉพาะค่าที่อยู่ใน options เท่านั้น (กันค่าเดิมไม่ตรง list)
  static String? _pick(List<String> options, String? want) =>
      want != null && options.contains(want) ? want : null;
}

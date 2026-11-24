import 'dart:io';

import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import 'package:brr/core/theme/app_theme.dart';
import 'package:brr/core/widgets/brr_app_bar.dart';
import 'package:brr/core/widgets/digit_formatter.dart';
import 'package:brr/core/widgets/discard_guard.dart';
import 'package:brr/core/widgets/image_source_sheet.dart';
import 'package:brr/core/widgets/option_popup.dart';
import 'package:brr/core/widgets/thai_date_picker.dart';
import 'package:brr/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:brr/features/map/models/activity_calc.dart';
import 'package:brr/features/map/models/parcel.dart';
import 'package:brr/features/map/viewmodels/parcel_detail_viewmodel.dart';
import 'package:brr/features/map/widgets/fert_round_dialog.dart';
import 'package:brr/features/map/widgets/unit_field.dart';
import 'package:brr/core/utils/json_safe.dart';

part 'activity_detail_sections.dart';

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
    this.draft,
  });

  final ParcelDetailViewModel vm;
  final List<String> photoPaths;
  final int activityNo;

  /// ร่างที่บันทึกไว้ในเครื่อง — มีค่าเมื่อเปิดมาแก้ไขจาก
  /// หน้า "นำส่งกิจกรรม" (prefill ทุกช่อง + บันทึกทับรายการเดิม)
  final Map<String, dynamic>? draft;

  @override
  State<ActivityDetailView> createState() => _ActivityDetailViewState();
}

class _ActivityDetailViewState extends State<ActivityDetailView> {
  final _dateCtrl = TextEditingController();
  final _rateCtrl = TextEditingController();
  final _nCtrl = TextEditingController();
  final _pCtrl = TextEditingController();
  final _kCtrl = TextEditingController();
  DateTime? _plantedAt;
  String? _caneGroup;
  String? _herbicide;
  bool? _mpiApplied;
  final _rounds = <FertRound>[];
  String? _organicType;
  final _organicRateCtrl = TextEditingController();
  DateTime? _organicDate;
  final _dolomiteRateCtrl = TextEditingController();
  DateTime? _dolomiteDate;
  bool? _weedPresent;
  bool? _subsoiled;
  final _subsoilDepthCtrl = TextEditingController();
  bool? _diseasePresent;
  String? _diseaseType;
  final _diseaseSpreadCtrl = TextEditingController();
  bool? _diseaseManaged;
  bool? _pestPresent;
  String? _pestType;
  final _pestSpreadCtrl = TextEditingController();
  final _pestDamageCtrl = TextEditingController();
  bool? _pestManaged;
  bool? _hilled;
  final _germCtrl = TextEditingController();
  FarmerRef? _harvestGroupFarmer;
  List<FarmerRef>? _farmers;
  String? _lossReason;
  final _lossAreaCtrl = TextEditingController();
  final _yieldEstimateCtrl = TextEditingController();
  final _cutVarietyCtrl = TextEditingController();
  final _cutLossKgCtrl = TextEditingController();
  final _cutLossTonCtrl = TextEditingController();
  String? _cutLossReason;
  bool _seedCane = false;
  final _seedNoteCtrl = TextEditingController();
  final _suggestionCtrl = TextEditingController();
  // รูปแนบกิจกรรม — seed จากรูปที่ถ่ายมาก่อนเข้าหน้า เพิ่ม/ลบได้ถึง 3 ใบ
  final _photos = <String>[];
  double _areaRai = 0;
  bool _saving = false;
  late final Future<FormOptions> _optionsFut = widget.vm.loadOptions();

  @override
  void initState() {
    super.initState();
    // prefill กลุ่มอ้อยจากข้อมูลแปลงถ้ามี
    _caneGroup = widget.vm.parcel.meta?['caneGroup']?.toString();
    _photos.addAll(widget.photoPaths.take(3));
    _prefillDraft();
    _recoverLostPhoto();
    // baseline หลัง prefill — เทียบตอนกดย้อน ต่าง = มีการแก้ไขค้าง
    _baseline = _formSig();
  }

  /// signature ของข้อมูลในฟอร์มทั้งหมด — ใช้เทียบว่าผู้ใช้แก้อะไร
  /// หลังเปิดหน้าไหม (พิมพ์ใน TextField ไม่ trigger rebuild เลย
  /// ต้องคำนวณสดตอน pop ไม่ใช้ค่า canPop ที่ snapshot ตอน build)
  String _formSig() => [
    for (final c in [
      _dateCtrl,
      _rateCtrl,
      _nCtrl,
      _pCtrl,
      _kCtrl,
      _organicRateCtrl,
      _dolomiteRateCtrl,
      _subsoilDepthCtrl,
      _diseaseSpreadCtrl,
      _pestSpreadCtrl,
      _pestDamageCtrl,
      _germCtrl,
      _lossAreaCtrl,
      _yieldEstimateCtrl,
      _cutVarietyCtrl,
      _cutLossKgCtrl,
      _cutLossTonCtrl,
      _seedNoteCtrl,
      _suggestionCtrl,
    ])
      c.text,
    '$_caneGroup',
    '$_herbicide',
    '$_mpiApplied',
    '$_organicType',
    '$_organicDate',
    '$_dolomiteDate',
    '$_weedPresent',
    '$_subsoiled',
    '$_diseasePresent',
    '$_diseaseType',
    '$_diseaseManaged',
    '$_pestPresent',
    '$_pestType',
    '$_pestManaged',
    '$_hilled',
    '${_harvestGroupFarmer?.id}',
    '$_lossReason',
    '$_cutLossReason',
    '$_seedCane',
    '$_plantedAt',
    _photos.join(','),
    _rounds
        .map((r) => '${r.date}|${r.rate}|${r.npk}|${r.n}|${r.p}|${r.k}')
        .join(';'),
  ].join('|');
  late final String _baseline;

  /// เปิดมาแก้ไขร่าง — เติมค่าที่เคยบันทึกกลับทุกช่อง
  /// (ร่างจากเวอร์ชันเก่า/ข้อมูลเสีย → ข้ามไปเปิดฟอร์มว่างแทนที่จะพัง)
  void _prefillDraft() {
    final d = widget.draft;
    if (d == null) return;
    try {
      _fillDraft(d);
    } catch (_) {}
  }

  void _fillDraft(Map<String, dynamic> d) {
    String s(String k) => '${d[k] ?? ''}';
    void fill(TextEditingController c, String k) {
      final v = s(k);
      if (v.isNotEmpty) c.text = v;
    }

    String? e(String k) {
      final v = s(k);
      return v.isEmpty ? null : v;
    }

    // bool จากข้อมูลเครื่อง — ผิดชนิด (เช่น ร่างเวอร์ชันเก่าเก็บเป็น
    // "true" string) → null แทนที่จะ throw ลาก prefill ทั้งชุดหาย
    bool? b(String k) => d[k] is bool ? d[k] as bool : null;

    final planted = DateTime.tryParse(s('plantedAt'));
    if (planted != null) {
      _plantedAt = planted;
      _dateCtrl.text = _fmtThai(planted);
    }
    _caneGroup = e('caneGroup') ?? _caneGroup;
    _herbicide = e('herbicideUsed');
    fill(_rateCtrl, 'fertilizerRate');
    fill(_nCtrl, 'npkN');
    fill(_pCtrl, 'npkP');
    fill(_kCtrl, 'npkK');
    _mpiApplied = b('mpiApplied');
    final roundsRaw = d['fertilizerRounds'];
    if (roundsRaw is List) {
      for (final r in roundsRaw) {
        if (r is! Map) continue;
        final m = Map<String, dynamic>.from(r);
        _rounds.add(
          FertRound(
            date: DateTime.tryParse('${m['date']}'),
            rate: '${m['rate'] ?? ''}',
            npk: '${m['npk'] ?? ''}',
            n: '${m['npkN'] ?? ''}',
            p: '${m['npkP'] ?? ''}',
            k: '${m['npkK'] ?? ''}',
          ),
        );
      }
    }
    _organicType = e('organicFertilizerType');
    fill(_organicRateCtrl, 'organicRate');
    _organicDate = DateTime.tryParse(s('organicDate'));
    fill(_dolomiteRateCtrl, 'dolomiteRate');
    _dolomiteDate = DateTime.tryParse(s('dolomiteDate'));
    _weedPresent = b('weedPresent');
    _subsoiled = b('subsoiled');
    fill(_subsoilDepthCtrl, 'subsoilDepth');
    _diseasePresent = b('diseasePresent');
    _diseaseType = e('diseaseType');
    fill(_diseaseSpreadCtrl, 'diseaseSpread');
    _diseaseManaged = b('diseaseManaged');
    _pestPresent = b('pestPresent');
    _pestType = e('pestType');
    fill(_pestSpreadCtrl, 'pestSpread');
    fill(_pestDamageCtrl, 'pestDamage');
    _pestManaged = b('pestManaged');
    _hilled = b('hilled');
    // ช่องพิมพ์เก็บเฉพาะตัวเลข — ตัด '%' ท้ายค่าเก่าที่เลือกจาก popup
    _germCtrl.text = (e('germinationPercent') ?? '').replaceAll('%', '');
    final farmerName = e('harvestGroupFarmer');
    if (farmerName != null) {
      _harvestGroupFarmer = FarmerRef(
        id: e('harvestGroupFarmerId') ?? '',
        name: farmerName,
      );
    }
    _lossReason = e('lossReason');
    fill(_lossAreaCtrl, 'lossAreaRai');
    fill(_yieldEstimateCtrl, 'yieldEstimate');
    fill(_cutVarietyCtrl, 'cutVarietyDeduction');
    fill(_cutLossKgCtrl, 'cutLossKgPerRai');
    fill(_cutLossTonCtrl, 'cutLossTons');
    _cutLossReason = e('cutLossReason');
    _seedCane = d['seedCane'] == true;
    fill(_seedNoteCtrl, 'seedCaneNote');
    fill(_suggestionCtrl, 'suggestion');
    // รูปที่ persist ไว้ตอนบันทึกร่าง — ใช้ของร่างแทน photoPaths
    final draftPhotos = d['photos'];
    if (draftPhotos is List && draftPhotos.isNotEmpty) {
      _photos
        ..clear()
        ..addAll([for (final p in draftPhotos) '$p'].take(3));
    }
  }

  @override
  void dispose() {
    _dateCtrl.dispose();
    _rateCtrl.dispose();
    _nCtrl.dispose();
    _pCtrl.dispose();
    _kCtrl.dispose();
    _organicRateCtrl.dispose();
    _dolomiteRateCtrl.dispose();
    _subsoilDepthCtrl.dispose();
    _diseaseSpreadCtrl.dispose();
    _pestSpreadCtrl.dispose();
    _pestDamageCtrl.dispose();
    _germCtrl.dispose();
    _lossAreaCtrl.dispose();
    _yieldEstimateCtrl.dispose();
    _cutVarietyCtrl.dispose();
    _cutLossKgCtrl.dispose();
    _cutLossTonCtrl.dispose();
    _seedNoteCtrl.dispose();
    _suggestionCtrl.dispose();
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
    final picked = await showThaiDatePicker(
      context,
      initialDate: _plantedAt ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        _plantedAt = picked;
        _dateCtrl.text = _fmtThai(picked);
      });
    }
  }

  /// เลือกวันที่เก็บลงตัวแปรที่ส่งมา — ใช้ร่วมกับช่องวันที่ของการ์ดต่างๆ
  Future<void> _pickAnyDate(
    DateTime? current,
    ValueChanged<DateTime> set,
  ) async {
    final picked = await showThaiDatePicker(
      context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => set(picked));
  }

  /// เลือก/ถ่ายรูปเพิ่ม (สูงสุด 3 ใบ) — image_picker throw ได้บาง
  /// เครื่อง กัน unhandled error แล้วแจ้งผู้ใช้แทนที่จะเงียบ
  Future<void> _pickPhoto() async {
    if (_photos.length >= 3) return;
    final source = await showImageSourceSheet(context);
    if (source == null) return;
    try {
      final x = await ImagePicker().pickImage(source: source, maxWidth: 1600);
      if (x != null) setState(() => _photos.add(x.path));
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
      if (file != null && mounted && _photos.length < 3) {
        setState(() => _photos.add(file.path));
      }
    } catch (_) {}
  }

  /// แถว label (ชิดขวา) + ช่องเทาแบบ dropdown ในการ์ด —
  /// [icon] ใช้วงกลมลูกศรลงสำหรับเลือก / ปฏิทินสำหรับวันที่
  /// label อยู่บน ช่องอยู่ล่างเต็มความกว้าง (สไตล์เดียวกับ
  /// _fieldCard ในหน้าวัดแปลง)
  /// setState ผ่าน helper — การ์ดใน part file เป็น extension
  /// บน state นี้ เรียก setState (@protected) ตรงๆ ไม่ได้
  void _set(VoidCallback fn) => setState(fn);

  static const _fieldLabelStyle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: Colors.black87,
  );

  /// หัวการ์ด — ตัวหนา + เส้นใต้แยกกับเนื้อหา
  Widget _cardHeader(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Divider(height: 1, thickness: 1, color: Colors.grey.shade300),
      ],
    ),
  );

  Widget _optRow(
    String label,
    String? value,
    String hint,
    VoidCallback onTap, {
    IconData icon = Iconsax.arrow_circle_down,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: _fieldLabelStyle),
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
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      color: value == null ? Colors.black38 : Colors.black87,
                    ),
                  ),
                ),
                Icon(icon, size: 26, color: Colors.black87),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  /// ปริมาณตันรวม = ประเมิน(ตัน/ไร่) × พื้นที่ไร่ของแปลง
  /// (ตรรก์อยู่ models/activity_calc.dart — view แค่ส่งค่า)
  double _totalTons() => totalTons(_yieldEstimateCtrl.text, _areaRai);

  /// อ้อยเข้าหีบจริง = ตันรวม − หักตัดพันธุ์ − หักสูญเสียจากการตัด
  double _actualTons() => actualTons(
    _yieldEstimateCtrl.text,
    _areaRai,
    cutVarietyTons: _cutVarietyCtrl.text,
    cutLossTons: _cutLossTonCtrl.text,
  );

  /// แถว label-บน + ค่าคำนวณในกรอบ (ตัวหนาน้ำเงินชิดขวา) — readonly
  Widget _calcRow(String label, double value, {String? unit}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: _fieldLabelStyle),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: value.toStringAsFixed(3),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1565C0),
                  ),
                ),
                if (unit != null)
                  TextSpan(
                    text: '  $unit',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1565C0),
                    ),
                  ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    ),
  );

  /// decoration กรอบเทาเดียวกันของช่องพิมพ์ในฟอร์มนี้ —
  /// [filled]=กรอกข้อมูลแล้ว → กรอบเขียว
  static InputDecoration _boxDeco(String hint, {bool filled = false}) =>
      InputDecoration(
        hintText: hint,
        isDense: true,
        filled: true,
        fillColor: Colors.grey.shade100,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: filled ? AppColors.green : Colors.grey.shade300,
            width: filled ? 1.5 : 1,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.gold, width: 2),
        ),
      );

  /// แถว label-บน + ช่องพิมพ์ในกรอบเต็มความกว้าง
  /// ([numeric]=ช่องตัวเลขทศนิยม) — กรอบเขียวเมื่อมีข้อมูล
  Widget _inputRow(
    String label,
    TextEditingController c, {
    bool numeric = true,
    int maxLines = 1,
    String? hint,
    String? unit,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: _fieldLabelStyle),
        const SizedBox(height: 6),
        if (unit != null && numeric)
          UnitField(
            controller: c,
            unit: unit,
            hint: hint ?? '0.0',
            onChanged: () => setState(() {}),
          )
        else
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: c,
            builder: (_, v, _) => TextField(
              controller: c,
              textAlign: TextAlign.start,
              keyboardType: numeric
                  ? const TextInputType.numberWithOptions(decimal: true)
                  : TextInputType.text,
              inputFormatters: numeric
                  ? const [DigitFormatter(decimal: true)]
                  : null,
              maxLines: maxLines,
              style: const TextStyle(fontSize: 18),
              decoration: _boxDeco(
                hint ?? (numeric ? '0.0' : 'กรอกข้อมูล'),
                filled: v.text.trim().isNotEmpty,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
      ],
    ),
  );

  /// เปิด dialog กรอกรอบใส่ปุ๋ยใหม่ — บันทึกแล้วเพิ่มเข้า list
  Future<void> _addRound() async {
    FormOptions opts;
    try {
      opts = await _optionsFut;
    } catch (_) {
      opts = const FormOptions();
    }
    if (!mounted) return;
    final r = await showDialog<FertRound>(
      context: context,
      builder: (_) => FertRoundDialog(
        roundNo: _rounds.length + 1,
        formulas: opts.fertilizerFormulas,
      ),
    );
    if (r != null) setState(() => _rounds.add(r));
  }

  /// แจ้งเตือนกลางจอเมื่อวันที่ไม่ถูกต้อง
  Future<void> _warnDate() => showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
              style: FilledButton.styleFrom(backgroundColor: AppColors.green),
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('ตกลง', style: TextStyle(fontSize: 16)),
            ),
          ),
        ],
      ),
    ),
  );

  /// [draft] = บันทึกลงเครื่องแบบฉบับร่าง — เก็บเท่าที่กรอก
  /// (วันที่ผิดรูปปล่อยเป็น null) และคง detailPending ไว้ให้
  /// กลับมากรอกต่อจากรายการรอ; ปุ่มหลัก = บันทึกสมบูรณ์
  Future<void> _save({bool draft = false}) async {
    if (_saving) return;
    var planted = _plantedAt;
    if (planted == null && _dateCtrl.text.trim().isNotEmpty) {
      planted = _parseThai(_dateCtrl.text);
      if (planted == null && !draft) {
        _warnDate();
        return;
      }
    }
    // ช่องเปอร์เซ็นต์ต้องอยู่ 0-100 — ร่างข้ามได้ (งานค้างยังไม่สมบูรณ์)
    if (!draft) {
      bool badPct(TextEditingController c) {
        final v = double.tryParse(c.text.trim());
        return v != null && (v < 0 || v > 100);
      }

      final bad = [
        if (badPct(_germCtrl)) 'เปอร์เซ็นต์งอก',
        if (badPct(_diseaseSpreadCtrl)) 'เปอร์เซ็นต์ระบาดโรค',
        if (badPct(_pestSpreadCtrl)) 'เปอร์เซ็นต์ระบาดแมลง',
        if (badPct(_pestDamageCtrl)) 'เปอร์เซ็นต์ความเสียหายแมลง',
      ];
      if (bad.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${bad.join(', ')} ต้องอยู่ระหว่าง 0-100')),
        );
        return;
      }
    }
    setState(() => _saving = true);
    String? num(TextEditingController c) {
      final t = c.text.trim();
      return t.isEmpty ? null : t;
    }

    String? iso(DateTime? d) => d == null
        ? null
        : '${d.year.toString().padLeft(4, '0')}-'
              '${d.month.toString().padLeft(2, '0')}-'
              '${d.day.toString().padLeft(2, '0')}';

    // รอบใส่ปุ๋ย — เพิ่มผ่าน dialog แล้วเก็บเป็นค่า string/date
    final rounds = [
      for (final r in _rounds)
        {
          'date': ?iso(r.date),
          'rate': ?r.rate,
          'npk': ?r.npk,
          'npkN': ?r.n,
          'npkP': ?r.p,
          'npkK': ?r.k,
        },
    ];

    try {
      final user = context.read<AuthViewModel>().user;
      await widget.vm.saveActivityDraft(
        photoPaths: _photos,
        detailPending: draft,
        caneGroup: _caneGroup,
        herbicideUsed: _herbicide,
        fertilizerRate: num(_rateCtrl),
        npkN: num(_nCtrl),
        npkP: num(_pCtrl),
        npkK: num(_kCtrl),
        mpiApplied: _mpiApplied,
        fertilizerRounds: rounds.isEmpty ? null : rounds,
        organicFertilizerType: _organicType,
        organicRate: num(_organicRateCtrl),
        organicDate: iso(_organicDate),
        dolomiteRate: num(_dolomiteRateCtrl),
        dolomiteDate: iso(_dolomiteDate),
        weedPresent: _weedPresent,
        subsoiled: _subsoiled,
        subsoilDepth: num(_subsoilDepthCtrl),
        diseasePresent: _diseasePresent,
        diseaseType: _diseaseType,
        diseaseSpread: num(_diseaseSpreadCtrl),
        diseaseManaged: _diseaseManaged,
        pestPresent: _pestPresent,
        pestType: _pestType,
        pestSpread: num(_pestSpreadCtrl),
        pestDamage: num(_pestDamageCtrl),
        pestManaged: _pestManaged,
        hilled: _hilled,
        germinationPercent: _germCtrl.text.trim().isEmpty
            ? null
            : '${_germCtrl.text.trim()}%',
        harvestGroupFarmerId: _harvestGroupFarmer?.id,
        harvestGroupFarmer: _harvestGroupFarmer?.name,
        lossReason: _lossReason,
        lossAreaRai: num(_lossAreaCtrl),
        yieldEstimate: num(_yieldEstimateCtrl),
        totalTons: _totalTons().toStringAsFixed(3),
        cutVarietyDeduction: num(_cutVarietyCtrl),
        cutLossKgPerRai: num(_cutLossKgCtrl),
        cutLossTons: num(_cutLossTonCtrl),
        cutLossReason: _cutLossReason,
        actualHarvestTons: _actualTons().toStringAsFixed(3),
        seedCane: _seedCane,
        seedCaneNote: num(_seedNoteCtrl),
        suggestion: num(_suggestionCtrl),
        activityId: widget.draft?['id']?.toString(),
        recordedBy: user?.displayName,
        recordedByRole: user?.role,
        plantedAt: iso(planted),
      );
      if (mounted) {
        Navigator.of(context)
            .pop(draft ? 'บันทึกฉบับร่างไว้แล้ว' : 'บันทึกกิจกรรมเรียบร้อย');
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

  /// ช่องสูตรปุ๋ย NPK — label ลอยบนขอบกรอบแบบการ์ดอ้างอิง
  /// กรอบเขียวเมื่อมีข้อมูล
  Widget _npk(String label, TextEditingController c) =>
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: c,
        builder: (_, v, _) => TextField(
          textAlign: TextAlign.start,
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: const [DigitFormatter(decimal: true)],
          style: const TextStyle(fontSize: 17),
          decoration: InputDecoration(
            labelText: label,
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: v.text.trim().isNotEmpty
                    ? AppColors.green
                    : Colors.grey.shade400,
                width: v.text.trim().isNotEmpty ? 1.5 : 1,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 12,
            ),
          ),
        ),
      );

  /// ปุ่ม toggle ทำ/ไม่ทำ ของค่าปุ๋ย MPI
  Widget _mpiButton(String label, bool selected, VoidCallback onTap) => InkWell(
    borderRadius: BorderRadius.circular(10),
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: selected ? AppColors.green : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          // ปุ่มที่เลือกกรอบทองแบบปุ่มหน้า Home
          color: selected ? AppColors.gold : Colors.grey.shade300,
          width: selected ? 2.5 : 1,
        ),
      ),
      child: Center(
        // ฟอนต์คงที่ทั้งสองปุ่ม — กรอบเล็กไปให้ตัดบรรทัด/ขยายกรอบแทนการย่อ
        child: Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.visible,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : Colors.black87,
          ),
        ),
      ),
    ),
  );

  /// แถว label-บน + ปุ่ม toggle 2 ตัวเต็มความกว้าง (สไตล์เดียวกับการ์ดคุมวัชพืช)
  /// [label] ว่าง = ไม่แสดงหัวข้อย่อย (กรณีซ้ำกับชื่อการ์ด)
  /// [reversed] = แสดงปุ่ม false ก่อน (เช่น ยังไม่จัดการ | จัดการแล้ว)
  Widget _toggleRow(
    String label,
    String trueLabel,
    String falseLabel,
    bool? value,
    ValueChanged<bool> onSet, {
    bool reversed = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label.isNotEmpty) ...[
          Text(label, style: _fieldLabelStyle),
          const SizedBox(height: 6),
        ],
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final e
                  in reversed
                      ? [(false, falseLabel), (true, trueLabel)]
                      : [(true, trueLabel), (false, falseLabel)]) ...[
                Expanded(
                  child: _mpiButton(e.$2, value == e.$1, () => onSet(e.$1)),
                ),
                if (e.$1 != (reversed ? true : false)) const SizedBox(width: 8),
              ],
            ],
          ),
        ),
      ],
    ),
  );

  /// การ์ดรอบการใส่ปุ๋ย — แสดงข้อมูลอย่างเดียว + ปุ่มลบ
  /// (กรอกผ่าน dialog "เพิ่มปุ๋ยครั้งที่ N")
  Widget _roundCard(int index, FertRound r) => Container(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
    decoration: BoxDecoration(
      color: Colors.grey.shade50,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: Colors.grey.shade300),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'รอบที่ ${index + 1}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => setState(() => _rounds.removeAt(index)),
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.red, width: 1.5),
                ),
                child: const Icon(Icons.close, size: 18, color: Colors.red),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        _roundLine('วันที่ใส่', r.date == null ? '—' : _fmtThai(r.date!)),
        _roundLine('อัตรา (กก./ไร่)', r.rate ?? '—'),
        _roundLine('สูตรปุ๋ย NPK', r.npk ?? '—'),
      ],
    ),
  );

  Widget _roundLine(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label :',
          style: const TextStyle(fontSize: 16, color: Colors.black54),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
        ),
      ],
    ),
  );

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
    return PopScope(
      // เช็กสดตอน pop (canPop ที่ snapshot ตอน build จะ stale
      // เพราะพิมพ์ใน TextField ไม่ rebuild) — ต่างจาก baseline
      // = แก้ไขค้าง → ยืนยันก่อนทิ้ง
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final dirty = _formSig() != _baseline;
        if (!dirty) {
          if (context.mounted) Navigator.of(context).pop();
          return;
        }
        if (await confirmDiscardChanges(context) && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F4F4),
        appBar: brrAppBar('บันทึกกิจกรรม ครั้งที่ ${widget.activityNo}'),
        body: FutureBuilder<Map<String, dynamic>?>(
          future: widget.vm.detail,
          builder: (context, snap) {
            final meta = asStringMap(snap.data?['meta']) ?? p.meta ?? const {};
            final rawArea = snap.data?['area'];
            final areaMap = rawArea is Map<String, dynamic> ? rawArea : null;
            final rai = _areaRai =
                toDoubleOrNull(areaMap?['raiDecimal']) ?? p.areaRai;
            final cards = <Widget>[
              _summaryCard(meta, rai),
              const SizedBox(height: 14),
              _plantedDateCard(),
              const SizedBox(height: 14),
              _caneGroupCard(),
              const SizedBox(height: 14),
              _herbicideCard(),
              const SizedBox(height: 14),
              _baseFertilizerCard(),
              const SizedBox(height: 14),
              _mpiFertilizerCard(),
              const SizedBox(height: 14),
              _organicCard(),
              const SizedBox(height: 14),
              _dolomiteCard(),
              const SizedBox(height: 14),
              _weedCard(),
              const SizedBox(height: 14),
              _subsoilCard(),
              const SizedBox(height: 14),
              _diseaseCard(),
              const SizedBox(height: 14),
              _pestCard(),
              const SizedBox(height: 14),
              _hillCard(),
              const SizedBox(height: 14),
              _germCard(),
              const SizedBox(height: 14),
              _harvestGroupCard(),
              const SizedBox(height: 14),
              _lossCard(),
              const SizedBox(height: 14),
              _cutLossCard(),
              const SizedBox(height: 16),
              _seedCaneCard(),
              const SizedBox(height: 12),
              _suggestionCard(),
              const SizedBox(height: 12),
              _photosCard(),
              const SizedBox(height: 16),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.green,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
                onPressed: _saving ? null : _save,
                child: Text(
                  _saving ? 'กำลังบันทึก…' : 'บันทึกกิจกรรม',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: _saving ? null : () => _save(draft: true),
                  icon: const Icon(Iconsax.save_2),
                  label: const Text(
                    'บันทึกลงเครื่อง (ฉบับร่าง)',
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              ),
            ];
            return ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
              children: cards,
            );
          },
        ),
      ),
    );
  }
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:image_picker/image_picker.dart';

import 'package:brr/core/theme/app_theme.dart';
import 'package:brr/core/widgets/brr_app_bar.dart';
import 'package:brr/core/widgets/digit_formatter.dart';
import 'package:brr/core/widgets/discard_guard.dart';
import 'package:brr/core/widgets/image_source_sheet.dart';
import 'package:brr/core/widgets/option_popup.dart';
import 'package:brr/core/widgets/thai_date_picker.dart';
import 'package:brr/features/map/models/activity_calc.dart';
import 'package:brr/features/map/models/parcel.dart';
import 'package:brr/features/map/viewmodels/parcel_detail_viewmodel.dart';
import 'package:brr/features/map/widgets/fert_round_dialog.dart';
import 'package:brr/features/map/widgets/unit_field.dart';
import 'package:brr/core/utils/json_safe.dart';

part 'activity_detail_sections.dart';
part 'activity_detail_widgets.dart';

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
                child: OutlinedButton(
                  onPressed: _saving ? null : () => _save(draft: true),
                  child: const Text(
                    'บันทึกลงเครื่อง (ฉบับร่าง)',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
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

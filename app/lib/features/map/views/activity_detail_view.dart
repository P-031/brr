import 'dart:io';

import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import 'package:brr/core/theme/app_theme.dart';
import 'package:brr/core/widgets/digit_formatter.dart';
import 'package:brr/core/widgets/image_source_sheet.dart';
import 'package:brr/core/widgets/option_popup.dart';
import 'package:brr/core/widgets/thai_date_picker.dart';
import 'package:brr/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:brr/features/map/models/activity_calc.dart';
import 'package:brr/features/map/models/parcel.dart';
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
  final _rounds = <_FertRound>[];
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
  String? _germPercent;
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
    _caneGroup = widget.vm.parcel.meta?['caneGroup'] as String?;
    _photos.addAll(widget.photoPaths.take(3));
    _prefillDraft();
    _recoverLostPhoto();
  }

  /// เปิดมาแก้ไขร่าง — เติมค่าที่เคยบันทึกกลับทุกช่อง
  void _prefillDraft() {
    final d = widget.draft;
    if (d == null) return;
    String s(String k) => '${d[k] ?? ''}';
    void fill(TextEditingController c, String k) {
      final v = s(k);
      if (v.isNotEmpty) c.text = v;
    }

    String? e(String k) {
      final v = s(k);
      return v.isEmpty ? null : v;
    }

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
    _mpiApplied = d['mpiApplied'] as bool?;
    for (final r in d['fertilizerRounds'] as List? ?? const []) {
      final m = Map<String, dynamic>.from(r as Map);
      _rounds.add(
        _FertRound(
          date: DateTime.tryParse('${m['date']}'),
          rate: '${m['rate'] ?? ''}',
          npk: '${m['npk'] ?? ''}',
          n: '${m['npkN'] ?? ''}',
          p: '${m['npkP'] ?? ''}',
          k: '${m['npkK'] ?? ''}',
        ),
      );
    }
    _organicType = e('organicFertilizerType');
    fill(_organicRateCtrl, 'organicRate');
    _organicDate = DateTime.tryParse(s('organicDate'));
    fill(_dolomiteRateCtrl, 'dolomiteRate');
    _dolomiteDate = DateTime.tryParse(s('dolomiteDate'));
    _weedPresent = d['weedPresent'] as bool?;
    _subsoiled = d['subsoiled'] as bool?;
    fill(_subsoilDepthCtrl, 'subsoilDepth');
    _diseasePresent = d['diseasePresent'] as bool?;
    _diseaseType = e('diseaseType');
    fill(_diseaseSpreadCtrl, 'diseaseSpread');
    _diseaseManaged = d['diseaseManaged'] as bool?;
    _pestPresent = d['pestPresent'] as bool?;
    _pestType = e('pestType');
    fill(_pestSpreadCtrl, 'pestSpread');
    fill(_pestDamageCtrl, 'pestDamage');
    _pestManaged = d['pestManaged'] as bool?;
    _hilled = d['hilled'] as bool?;
    _germPercent = e('germinationPercent');
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
    if ((d['photos'] as List? ?? const []).isNotEmpty) {
      _photos
        ..clear()
        ..addAll([for (final p in d['photos'] as List) '$p'].take(3));
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
  static const _fieldLabelStyle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: Colors.black87,
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
  Widget _calcRow(String label, double value) => Padding(
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
          child: Text(
            value.toStringAsFixed(3),
            textAlign: TextAlign.end,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1565C0),
            ),
          ),
        ),
      ],
    ),
  );

  /// decoration กรอบเทาเดียวกันของช่องพิมพ์ในฟอร์มนี้
  static InputDecoration _boxDeco(String hint) => InputDecoration(
    hintText: hint,
    isDense: true,
    filled: true,
    fillColor: Colors.grey.shade100,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: Colors.grey.shade300),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: Colors.grey.shade300),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: AppColors.gold, width: 2),
    ),
  );

  /// แถว label-บน + ช่องพิมพ์ในกรอบเต็มความกว้าง
  /// ([numeric]=ช่องตัวเลขทศนิยม ค่าชิดขวา)
  Widget _inputRow(
    String label,
    TextEditingController c, {
    bool numeric = true,
    int maxLines = 1,
    String? hint,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: _fieldLabelStyle),
        const SizedBox(height: 6),
        TextField(
          controller: c,
          textAlign: numeric ? TextAlign.end : TextAlign.start,
          keyboardType: numeric
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          inputFormatters: numeric
              ? const [DigitFormatter(decimal: true)]
              : null,
          maxLines: maxLines,
          style: const TextStyle(fontSize: 18),
          decoration: _boxDeco(hint ?? (numeric ? '0.0' : 'กรอกข้อมูล')),
          onChanged: (_) => setState(() {}),
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
    final r = await showDialog<_FertRound>(
      context: context,
      builder: (_) => _FertRoundDialog(
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
        germinationPercent: _germPercent,
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
        activityId: widget.draft?['id'] as String?,
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
  Widget _npk(String label, TextEditingController c) => TextField(
    controller: c,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    inputFormatters: const [DigitFormatter(decimal: true)],
    style: const TextStyle(fontSize: 17),
    decoration: InputDecoration(
      labelText: label,
      isDense: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
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

  /// แถว label ชิดขวา + ปุ่ม toggle 2 ตัว (สไตล์เดียวกับ MPI)
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
    child: Row(
      children: [
        Expanded(
          flex: 4,
          child: Text(
            '$label :',
            textAlign: TextAlign.end,
            style: const TextStyle(fontSize: 16, color: Colors.black87),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 7,
          child: IntrinsicHeight(
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
                  if (e.$1 != (reversed ? true : false))
                    const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        ),
      ],
    ),
  );

  /// การ์ดรอบการใส่ปุ๋ย — แสดงข้อมูลอย่างเดียว + ปุ่มลบ
  /// (กรอกผ่าน dialog "เพิ่มปุ๋ยครั้งที่ N")
  Widget _roundCard(int index, _FertRound r) => Container(
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
          final rai = _areaRai =
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
                    const SizedBox(height: 4),
                    const Text(
                      'พิมพ์ตัวเลข วัน เดือน ปี (พ.ศ.) ติดกัน\n'
                      'เช่น 01022569 → 01/02/2569 (ขีด / ใส่ให้อัตโนมัติ)',
                      style: TextStyle(fontSize: 14, color: Colors.black54),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _dateCtrl,
                      keyboardType: TextInputType.datetime,
                      inputFormatters: [ThaiDateSlashFormatter()],
                      style: const TextStyle(fontSize: 17),
                      decoration: InputDecoration(
                        hintText: 'วว/ดด/ปปปป',
                        hintStyle: const TextStyle(
                          fontSize: 16,
                          color: Colors.black38,
                        ),
                        suffixIcon: IconButton(
                          icon: const Icon(
                            Icons.calendar_today,
                            color: AppColors.green,
                            size: 30,
                          ),
                          onPressed: _pickDate,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.grey.shade300),
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
              const SizedBox(height: 14),
              // การ์ดกลุ่มสร้างอ้อย — ตัวเลือกจาก /meta/options
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
                      'กลุ่มสร้างอ้อย (กลุ่มบำรุง)',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () async {
                        // loadOptions พังตอนออฟไลน์ — ต้อง catch ไม่งั้น
                        // แตะแล้วเงียบเหมือนปุ่มตาย (unhandled error)
                        FormOptions opts;
                        try {
                          opts = await _optionsFut;
                        } catch (_) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('โหลดตัวเลือกไม่สำเร็จ'),
                            ),
                          );
                          return;
                        }
                        if (!context.mounted) return;
                        final idx = await showOptionPopup(
                          context,
                          title: 'กลุ่มสร้างอ้อย (กลุ่มบำรุง)',
                          labels: opts.caneGroups,
                          selectedIndex: _caneGroup == null
                              ? null
                              : opts.caneGroups.indexOf(_caneGroup!),
                          searchHint: 'ค้นหากลุ่มอ้อย',
                        );
                        if (idx != null) {
                          setState(() => _caneGroup = opts.caneGroups[idx]);
                        }
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _caneGroup == null
                                ? Colors.grey.shade300
                                : AppColors.green,
                            width: _caneGroup == null ? 1 : 1.5,
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _caneGroup ?? 'แตะเพื่อเลือก',
                                style: TextStyle(
                                  fontSize: 17,
                                  color: _caneGroup == null
                                      ? Colors.black38
                                      : Colors.black87,
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
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              // การ์ดการใช้ยาคุม — ใช้/ไม่ใช้
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
                      'การใช้ยาคุม',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () async {
                        final idx = await showOptionPopup(
                          context,
                          title: 'การใช้ยาคุม',
                          labels: const ['ใช้', 'ไม่ใช้'],
                          selectedIndex: _herbicide == null
                              ? null
                              : _herbicide == 'ใช้'
                              ? 0
                              : 1,
                        );
                        if (idx != null) {
                          setState(
                            () => _herbicide = idx == 0 ? 'ใช้' : 'ไม่ใช้',
                          );
                        }
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _herbicide == null
                                ? Colors.grey.shade300
                                : AppColors.green,
                            width: _herbicide == null ? 1 : 1.5,
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _herbicide ?? 'แตะเพื่อเลือก',
                                style: TextStyle(
                                  fontSize: 17,
                                  color: _herbicide == null
                                      ? Colors.black38
                                      : Colors.black87,
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
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              // การ์ดฝ่ากอ — อัตราปุ๋ย + สูตร NPK + ยอดรวม
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
                      'ฝ่ากอ',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    _inputRow('อัตราการใส่ปุ๋ย(กก./ไร่)', _rateCtrl),
                    const SizedBox(height: 4),
                    const Text(
                      'กรุณากรอกสูตรปุ๋ย NPK',
                      style: TextStyle(fontSize: 14, color: Colors.black45),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: _npk('N', _nCtrl)),
                        const SizedBox(width: 8),
                        Expanded(child: _npk('P', _pCtrl)),
                        const SizedBox(width: 8),
                        Expanded(child: _npk('K', _kCtrl)),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'รวม อัตรา(กก./ไร่)',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          // อัตราฝ่ากอ + รวมอัตราทุกรอบใส่ปุ๋ย
                          totalFertilizerRate(
                            _rateCtrl.text,
                            _rounds.map((r) => r.rate),
                          ).toStringAsFixed(1),
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1565C0),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              // การ์ดใช้ปุ๋ยตามปริมาณผลผลิตที่ต้องการ — MPI + หลายรอบใส่ปุ๋ย
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
                      'ใช้ปุ๋ยตามปริมาณผลผลิตที่ต้องการ',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'ค่าปุ๋ย MPI',
                      style: TextStyle(fontSize: 16, color: Colors.black54),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _mpiButton('ทำ', _mpiApplied == true, () {
                            setState(() => _mpiApplied = true);
                          }),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _mpiButton('ไม่ทำ', _mpiApplied == false, () {
                            setState(() => _mpiApplied = false);
                          }),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    for (var i = 0; i < _rounds.length; i++) ...[
                      _roundCard(i, _rounds[i]),
                      const SizedBox(height: 10),
                    ],
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.black87,
                        side: BorderSide(color: Colors.grey.shade300),
                        backgroundColor: Colors.grey.shade50,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        minimumSize: const Size.fromHeight(0),
                      ),
                      onPressed: _addRound,
                      icon: const Icon(Icons.add, size: 20),
                      label: const Text(
                        'เพิ่มรอบการใส่ปุ๋ย',
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'รวม อัตรา(กก./ไร่)',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          _rounds
                              .fold<double>(
                                0,
                                (s, r) =>
                                    s + (double.tryParse(r.rate ?? '') ?? 0),
                              )
                              .toStringAsFixed(1),
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1565C0),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              // การ์ดใส่ปุ๋ยอินทรีย์ — ชนิดปุ๋ยจาก /meta/options + อัตรา + วันที่
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
                      'ใส่ปุ๋ยอินทรีย์ (>500 กก/ไร่)',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _optRow('ชนิดปุ๋ย', _organicType, 'เลือก', () async {
                      // ตัวเลือกจาก backend — โหลดไม่สำเร็จ/ว่างแจ้งเตือน
                      FormOptions opts;
                      try {
                        opts = await _optionsFut;
                      } catch (_) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('โหลดตัวเลือกไม่สำเร็จ'),
                          ),
                        );
                        return;
                      }
                      if (opts.organicFertilizerTypes.isEmpty) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('ยังไม่มีตัวเลือกชนิดปุ๋ย'),
                          ),
                        );
                        return;
                      }
                      if (!context.mounted) return;
                      final idx = await showOptionPopup(
                        context,
                        title: 'ชนิดปุ๋ย',
                        labels: opts.organicFertilizerTypes,
                        selectedIndex: _organicType == null
                            ? null
                            : opts.organicFertilizerTypes.indexOf(
                                _organicType!,
                              ),
                      );
                      if (idx != null) {
                        setState(
                          () => _organicType = opts.organicFertilizerTypes[idx],
                        );
                      }
                    }),
                    _inputRow('อัตรา(กก./ไร่)', _organicRateCtrl),
                    _optRow(
                      'วันที่ใส่',
                      _organicDate == null ? null : _fmtThai(_organicDate!),
                      'เลือกวันที่',
                      () => _pickAnyDate(_organicDate, (d) => _organicDate = d),
                      icon: Icons.calendar_today,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              // การ์ดใส่โดโลไมท์ — อัตรา + วันที่
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
                      'ใส่โดโลไมท์ (50 - 100 กก/ไร่)',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _inputRow('อัตรา(กก./ไร่)', _dolomiteRateCtrl),
                    _optRow(
                      'วันที่ใส่',
                      _dolomiteDate == null ? null : _fmtThai(_dolomiteDate!),
                      'เลือกวันที่',
                      () =>
                          _pickAnyDate(_dolomiteDate, (d) => _dolomiteDate = d),
                      icon: Icons.calendar_today,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              // การ์ดคุมวัชพืช — มี/ไม่มีวัชพืช
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
                      'คุมวัชพืช ต้องไม่มีวัชพืช',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _mpiButton(
                            'มีวัชพืช',
                            _weedPresent == true,
                            () => setState(() => _weedPresent = true),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _mpiButton(
                            'ไม่มีวัชพืช',
                            _weedPresent == false,
                            () => setState(() => _weedPresent = false),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              // การ์ดไถระเบิดดินดาน — ทำแล้ว/ยังไม่ทำ + ความลึก
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
                      'ไถระเบิดดินดาน (ลึก > 40 ซม.)',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _toggleRow(
                      'ไถระเบิดดินดาน',
                      'ทำแล้ว',
                      'ยังไม่ทำ',
                      _subsoiled,
                      (v) => setState(() => _subsoiled = v),
                    ),
                    _inputRow('ความลึก(ซม.)', _subsoilDepthCtrl),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              // การ์ดโรค — มี/ไม่มี + ชนิดโรค + ระบาด% + จัดการแล้ว/ยัง
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
                      'โรค',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _toggleRow(
                      'โรค',
                      'มีโรค',
                      'ไม่มีโรค',
                      _diseasePresent,
                      (v) => setState(() => _diseasePresent = v),
                    ),
                    _optRow('เลือกชนิดโรค', _diseaseType, 'เลือก', () async {
                      // ชนิดโรคจาก backend — โหลดไม่สำเร็จ/ว่างแจ้งเตือน
                      FormOptions opts;
                      try {
                        opts = await _optionsFut;
                      } catch (_) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('โหลดตัวเลือกไม่สำเร็จ'),
                          ),
                        );
                        return;
                      }
                      if (opts.diseaseTypes.isEmpty) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('ยังไม่มีตัวเลือกชนิดโรค'),
                          ),
                        );
                        return;
                      }
                      if (!context.mounted) return;
                      final idx = await showOptionPopup(
                        context,
                        title: 'เลือกชนิดโรค',
                        labels: opts.diseaseTypes,
                        selectedIndex: _diseaseType == null
                            ? null
                            : opts.diseaseTypes.indexOf(_diseaseType!),
                      );
                      if (idx != null) {
                        setState(() => _diseaseType = opts.diseaseTypes[idx]);
                      }
                    }),
                    _inputRow('ระบาด (%)', _diseaseSpreadCtrl),
                    _toggleRow(
                      'การจัดการโรค',
                      'จัดการแล้ว',
                      'ยังไม่จัดการ',
                      _diseaseManaged,
                      (v) => setState(() => _diseaseManaged = v),
                      reversed: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              // การ์ดแมลง — มี/ไม่มี + ชนิดแมลง + ระบาด% + เบียน% + จัดการ
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
                      'แมลง',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _toggleRow(
                      'แมลง',
                      'มีแมลง',
                      'ไม่มีแมลง',
                      _pestPresent,
                      (v) => setState(() => _pestPresent = v),
                    ),
                    _optRow(
                      'เลือกชนิดแมลง',
                      _pestType,
                      'เลือกรายการ',
                      () async {
                        FormOptions opts;
                        try {
                          opts = await _optionsFut;
                        } catch (_) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('โหลดตัวเลือกไม่สำเร็จ'),
                            ),
                          );
                          return;
                        }
                        if (opts.pestTypes.isEmpty) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('ยังไม่มีตัวเลือกชนิดแมลง'),
                            ),
                          );
                          return;
                        }
                        if (!context.mounted) return;
                        final idx = await showOptionPopup(
                          context,
                          title: 'เลือกชนิดแมลง',
                          labels: opts.pestTypes,
                          selectedIndex: _pestType == null
                              ? null
                              : opts.pestTypes.indexOf(_pestType!),
                        );
                        if (idx != null) {
                          setState(() => _pestType = opts.pestTypes[idx]);
                        }
                      },
                    ),
                    _inputRow('ระบาด (%)', _pestSpreadCtrl),
                    _inputRow('เบียน (%)', _pestDamageCtrl),
                    _toggleRow(
                      'การจัดการแมลง',
                      'จัดการแล้ว',
                      'ยังไม่จัดการ',
                      _pestManaged,
                      (v) => setState(() => _pestManaged = v),
                      reversed: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              // การ์ดพูนโคน — ทำ/ไม่ทำ
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
                      'พูนโคน',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _toggleRow(
                      'พูนโคน',
                      'ทำ',
                      'ไม่ทำ',
                      _hilled,
                      (v) => setState(() => _hilled = v),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              // การ์ดการงอก — เลือกเปอร์เซ็นต์งอก
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
                      'การงอก',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _optRow('เปอร์เซ็นต์งอก', _germPercent, 'เลือก', () async {
                      final percents = [
                        for (var p = 0; p <= 100; p += 5) '$p%',
                      ];
                      final idx = await showOptionPopup(
                        context,
                        title: 'เปอร์เซ็นต์งอก',
                        labels: percents,
                        selectedIndex: _germPercent == null
                            ? null
                            : percents.indexOf(_germPercent!),
                      );
                      if (idx != null) {
                        setState(() => _germPercent = percents[idx]);
                      }
                    }),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              // การ์ดเลือกกลุ่มตัดอ้อย — เลือกชาวไร่จาก backend
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
                      'เลือกกลุ่มตัดอ้อย',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () async {
                        List<FarmerRef> farmers;
                        try {
                          farmers = _farmers ??= await widget.vm.loadFarmers();
                        } catch (_) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('โหลดรายชื่อไม่สำเร็จ'),
                            ),
                          );
                          return;
                        }
                        if (farmers.isEmpty) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('ไม่มีรายชื่อชาวไร่')),
                          );
                          return;
                        }
                        if (!context.mounted) return;
                        final idx = await showOptionPopup(
                          context,
                          title: 'เลือกกลุ่มตัดอ้อย',
                          labels: [
                            for (final f in farmers) '[${f.id}] ${f.name}',
                          ],
                          selectedIndex: _harvestGroupFarmer == null
                              ? null
                              : farmers.indexWhere(
                                  (f) => f.id == _harvestGroupFarmer!.id,
                                ),
                          searchHint: 'ค้นหาชาวไร่',
                        );
                        if (idx != null) {
                          setState(() => _harvestGroupFarmer = farmers[idx]);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 13,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _harvestGroupFarmer == null
                                ? Colors.grey.shade300
                                : AppColors.green,
                            width: _harvestGroupFarmer == null ? 1 : 1.5,
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Iconsax.people,
                              size: 24,
                              color: Colors.black45,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _harvestGroupFarmer == null
                                    ? 'แตะเพื่อเลือก'
                                    : '[${_harvestGroupFarmer!.id}] '
                                          '${_harvestGroupFarmer!.name}',
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 16,
                                  color: _harvestGroupFarmer == null
                                      ? Colors.black38
                                      : Colors.black87,
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
              ),
              const SizedBox(height: 14),
              // การ์ดสูญเสียในแปลง — สาเหตุ + ไร่ + ประเมิน + ตันรวม(คำนวณ)
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
                      'สูญเสียในแปลง',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _optRow(
                      'เลือกสาเหตุ',
                      _lossReason,
                      'เลือกรายการ',
                      () async {
                        FormOptions opts;
                        try {
                          opts = await _optionsFut;
                        } catch (_) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('โหลดตัวเลือกไม่สำเร็จ'),
                            ),
                          );
                          return;
                        }
                        if (opts.lossOptions.isEmpty) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('ยังไม่มีตัวเลือกสาเหตุ'),
                            ),
                          );
                          return;
                        }
                        if (!context.mounted) return;
                        final idx = await showOptionPopup(
                          context,
                          title: 'เลือกสาเหตุ',
                          labels: opts.lossOptions,
                          selectedIndex: _lossReason == null
                              ? null
                              : opts.lossOptions.indexOf(_lossReason!),
                        );
                        if (idx != null) {
                          setState(() => _lossReason = opts.lossOptions[idx]);
                        }
                      },
                    ),
                    _inputRow('สูญเสียรวม(ไร่)', _lossAreaCtrl),
                    _inputRow('ประเมิน(ตัน/ไร่)', _yieldEstimateCtrl),
                    _calcRow('ปริมาณตันรวม(ตัน)', _totalTons()),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              // การ์ดสูญเสียจากการตัดและหักพันธุ์ — หักหลายช่อง +
              // สาเหตุ + อ้อยเข้าหีบจริง(คำนวณ)
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
                      'สูญเสียจากการตัด และหักพันธุ์',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _inputRow('หักตัดพันธุ์รวม\n(ตัน)', _cutVarietyCtrl),
                    _inputRow(
                      'หักสูญเสีย จากการตัด\n(กก./ไร่)',
                      _cutLossKgCtrl,
                    ),
                    _inputRow('หักสูญเสีย จากการตัด\n(ตัน)', _cutLossTonCtrl),
                    _optRow(
                      'เลือกสาเหตุ หักสูญเสีย',
                      _cutLossReason,
                      'เลือกรายการ',
                      () async {
                        FormOptions opts;
                        try {
                          opts = await _optionsFut;
                        } catch (_) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('โหลดตัวเลือกไม่สำเร็จ'),
                            ),
                          );
                          return;
                        }
                        if (opts.lossOptions.isEmpty) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('ยังไม่มีตัวเลือกสาเหตุ'),
                            ),
                          );
                          return;
                        }
                        if (!context.mounted) return;
                        final idx = await showOptionPopup(
                          context,
                          title: 'เลือกสาเหตุ หักสูญเสีย',
                          labels: opts.lossOptions,
                          selectedIndex: _cutLossReason == null
                              ? null
                              : opts.lossOptions.indexOf(_cutLossReason!),
                        );
                        if (idx != null) {
                          setState(
                            () => _cutLossReason = opts.lossOptions[idx],
                          );
                        }
                      },
                    ),
                    _calcRow(
                      'ปริมาณอ้อยเข้าหีบจริง(ตัน)\n(ตันรวม−หักสูญเสียรวม)',
                      _actualTons(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // อ้อยพันธุ์ — checkbox + รายละเอียด
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
                      'อ้อยพันธุ์',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => setState(() => _seedCane = !_seedCane),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Checkbox(
                            value: _seedCane,
                            activeColor: AppColors.green,
                            visualDensity: VisualDensity.compact,
                            onChanged: (v) =>
                                setState(() => _seedCane = v ?? false),
                          ),
                          const Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(top: 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'อ้อยพันธุ์',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.green,
                                    ),
                                  ),
                                  Text(
                                    'เลือกหากแปลงนี้เหมาะสมเป็นอ้อยพันธุ์',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.black54,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    _inputRow(
                      'รายละเอียดอ้อยพันธุ์',
                      _seedNoteCtrl,
                      numeric: false,
                      hint: 'ระบุรายละเอียด',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // ข้อเสนอแนะ / ตรวจสอบ — พิมพ์อิสระหลายบรรทัด
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
                      'ข้อเสนอแนะ / ตรวจสอบ',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _suggestionCtrl,
                      maxLines: 3,
                      style: const TextStyle(fontSize: 16),
                      decoration: _boxDeco('พิมพ์ข้อเสนอแนะ'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // ภาพถ่าย — รูปที่ถ่ายมา + เพิ่ม/ลบได้สูงสุด 3 ใบ
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
                          '${_photos.length}/3',
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
                          separatorBuilder: (_, _) => const SizedBox(width: 10),
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
                        onPressed: _photos.length < 3 ? _pickPhoto : null,
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
            ],
          );
        },
      ),
    );
  }
}

/// รอบการใส่ปุ๋ยหนึ่งรอบ — ค่าที่กรอกจาก [ _FertRoundDialog ]
/// `npk` = ข้อความสูตรปุ๋ยที่แสดง (ชื่อสินค้า หรือ N-P-K)
class _FertRound {
  _FertRound({this.date, this.rate, this.npk, this.n, this.p, this.k});

  final DateTime? date;
  final String? rate;
  final String? npk;
  final String? n;
  final String? p;
  final String? k;
}

/// Dialog กรอกรอบใส่ปุ๋ย — วันที่ใส่ / อัตรา / สูตรปุ๋ย (เลือกจาก
/// `/meta/options → fertilizerFormulas` + "อื่น ๆ") + ช่อง N-P-K
/// เลือกสูตรที่มีรูปแบบ 15-5-30 ในชื่อจะเติม N/P/K ให้อัตโนมัติ
class _FertRoundDialog extends StatefulWidget {
  const _FertRoundDialog({required this.roundNo, required this.formulas});

  final int roundNo;

  /// รายการสูตรปุ๋ยจาก backend — ว่างได้ถ้า /meta/options ยังไม่ส่ง
  final List<String> formulas;

  @override
  State<_FertRoundDialog> createState() => _FertRoundDialogState();
}

class _FertRoundDialogState extends State<_FertRoundDialog> {
  static const _other = 'อื่น ๆ';
  static final _npkRe = RegExp(r'(\d+)\s*-\s*(\d+)\s*-\s*(\d+)');

  final _rateCtrl = TextEditingController();
  final _nCtrl = TextEditingController();
  final _pCtrl = TextEditingController();
  final _kCtrl = TextEditingController();
  DateTime? _date;
  String? _formula;

  @override
  void dispose() {
    _rateCtrl.dispose();
    _nCtrl.dispose();
    _pCtrl.dispose();
    _kCtrl.dispose();
    super.dispose();
  }

  String _fmtThai(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/'
      '${d.year + 543}';

  Future<void> _pickDate() async {
    final picked = await showThaiDatePicker(
      context,
      initialDate: _date ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickFormula() async {
    final labels = [...widget.formulas, _other];
    final idx = await showOptionPopup(
      context,
      title: 'เลือกสูตรปุ๋ย',
      labels: labels,
      selectedIndex: _formula == null ? null : labels.indexOf(_formula!),
    );
    if (idx == null) return;
    setState(() {
      _formula = labels[idx];
      // ชื่อสูตรที่มี N-P-K ในตัว เช่น "สูตร 15-5-30" → เติมช่องให้เลย
      final m = _npkRe.firstMatch(_formula!);
      if (m != null) {
        _nCtrl.text = m.group(1)!;
        _pCtrl.text = m.group(2)!;
        _kCtrl.text = m.group(3)!;
      }
    });
  }

  void _save() {
    String? nn(TextEditingController c) {
      final t = c.text.trim();
      return t.isEmpty ? null : t;
    }

    // ข้อความสูตรปุ๋ยที่แสดง: ชื่อสินค้าที่เลือก หรือ N-P-K จากช่อง
    // (ตัวเลือก "อื่น ๆ" → แสดงเป็นค่า N-P-K ที่กรอก)
    final npkCombo = [
      _nCtrl.text.trim(),
      _pCtrl.text.trim(),
      _kCtrl.text.trim(),
    ].join('-');
    String? npk;
    if (_formula == _other) {
      npk = npkCombo == '--' ? null : npkCombo;
    } else {
      npk = _formula ?? (npkCombo == '--' ? null : npkCombo);
    }
    Navigator.of(context).pop(
      _FertRound(
        date: _date,
        rate: nn(_rateCtrl),
        npk: npk,
        n: nn(_nCtrl),
        p: nn(_pCtrl),
        k: nn(_kCtrl),
      ),
    );
  }

  /// ช่องแบบ dropdown ของ dialog — แตะแล้วเปิด picker
  Widget _pickerField(String hint, String? value, VoidCallback onTap) =>
      InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  value ?? hint,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 17,
                    color: value == null ? Colors.black45 : Colors.black87,
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

  Widget _npkBox(String label, TextEditingController c) => TextField(
    controller: c,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    inputFormatters: const [DigitFormatter(decimal: true)],
    style: const TextStyle(fontSize: 19),
    decoration: InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontSize: 17),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
    ),
  );

  /// label อยู่บนช่อง (สไตล์เดียวกับฟอร์มหลัก)
  static const _dlgLabel = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: Colors.black87,
  );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      title: Text(
        'เพิ่มปุ๋ยครั้งที่ ${widget.roundNo}',
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
      ),
      content: SingleChildScrollView(
        child: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('วันที่ใส่', style: _dlgLabel),
              const SizedBox(height: 6),
              _pickerField(
                'เลือกวันที่',
                _date == null ? null : _fmtThai(_date!),
                _pickDate,
              ),
              const SizedBox(height: 12),
              const Text('อัตรา(กก./ไร่)', style: _dlgLabel),
              const SizedBox(height: 6),
              TextField(
                controller: _rateCtrl,
                textAlign: TextAlign.end,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: const [DigitFormatter(decimal: true)],
                style: const TextStyle(fontSize: 18),
                decoration: InputDecoration(
                  hintText: '0.0',
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
                    borderSide: BorderSide(color: Colors.grey.shade300),
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
              const SizedBox(height: 12),
              const Text('สูตรปุ๋ย', style: _dlgLabel),
              const SizedBox(height: 6),
              _pickerField('เลือก', _formula, _pickFormula),
              const SizedBox(height: 14),
              const Text(
                'สูตรปุ๋ย NPK',
                style: TextStyle(fontSize: 17, color: Colors.black87),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _npkBox('N', _nCtrl)),
                  const SizedBox(width: 8),
                  Expanded(child: _npkBox('P', _pCtrl)),
                  const SizedBox(width: 8),
                  Expanded(child: _npkBox('K', _kCtrl)),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(
            'ยกเลิก',
            style: TextStyle(fontSize: 17, color: Colors.black54),
          ),
        ),
        TextButton(
          onPressed: _save,
          child: const Text(
            'บันทึก',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: AppColors.green,
            ),
          ),
        ),
      ],
    );
  }
}

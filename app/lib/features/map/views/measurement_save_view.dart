import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax/iconsax.dart';
import 'package:image_picker/image_picker.dart';

import 'package:brr/features/map/models/measurement_result.dart';
import 'package:brr/features/map/models/parcel.dart';
import 'package:brr/core/theme/app_theme.dart';
import 'package:brr/core/widgets/brr_app_bar.dart';
import 'package:brr/core/utils/fuzzy_search.dart';
import 'package:brr/core/widgets/digit_formatter.dart';
import 'package:brr/core/widgets/discard_guard.dart';
import 'package:brr/core/widgets/image_source_sheet.dart';

part 'measurement_save_fields.dart';
part 'measurement_save_dialogs.dart';

/// One row in the searchable picker — backend will supply real
/// `{code, name}` pairs later.
class PickerItem {
  const PickerItem({required this.code, required this.name});

  final String code;
  final String name;
}

/// แป้นพิมพ์ไทยกดตำแหน่งเลขได้อักขระไทย/สัญลักษณ์ (เช่น / -) —
/// บันทึกข้อมูลการวัด — shows the measured area (ไร่/งาน/ตร.วา)
/// plus a form for plot name, production year and caretaker
/// officer. Backend-ready fields collected now.
class MeasurementSaveView extends StatefulWidget {
  const MeasurementSaveView({
    required this.areaSquareMeters,
    required this.officers,
    required this.farmers,
    required this.options,
    required this.isOfficer,
    this.initial,
    super.key,
  });

  final double areaSquareMeters;

  /// Fetchers (not futures) — every dialog open re-calls them so a
  /// failed load retries instead of staying empty forever.
  final Future<List<String>> Function() officers;
  final Future<List<FarmerRef>> Function() farmers;
  final Future<FormOptions> Function() options;

  /// Officers must pick which farmer the plot belongs to; farmers
  /// own their plots so the picker is hidden for them.
  final bool isOfficer;

  /// ร่างที่กำลังแก้ไข — prefill ทุกช่องจาก meta ที่บันทึกไว้
  /// (หน้าฉบับร่าง → แก้ไข; เส้นขอบแปลงคงเดิม แก้ได้เฉพาะข้อมูล)
  final Parcel? initial;

  @override
  State<MeasurementSaveView> createState() => _MeasurementSaveState();
}

class _MeasurementSaveState extends State<MeasurementSaveView> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _yearCtrl = TextEditingController();
  final _rootCtrl = TextEditingController();
  final _seqCtrl = TextEditingController();
  final _lossCtrl = TextEditingController();
  final _targetCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final List<XFile> _photos = [];
  String? _project;
  String? _zone;
  String? _province;
  String? _district;
  String? _subdistrict;
  String? _village;
  String? _prevPlot;
  String? _officer;
  String? _farmer;
  String? _farmerId;
  String? _caneGroup;
  String? _caneType;
  String? _caneVariety;
  String? _ownership;
  String? _terrain;
  // พื้นที่สูญเสียเลือกได้หลายสาเหตุพร้อมกัน (เช่น ต้นไม้ + สระน้ำ).
  final Set<String> _losses = {};
  // เคยกดบันทึกแล้วยังขาดข้อมูล → ช่องว่างขึ้นกรอบแดงไว้เตือน
  bool _showErrors = false;
  // ช่องที่ผู้ใช้เคยพิมพ์แล้ว — autovalidate ขึ้น error หลัง
  // onChanged แรก ถึงไม่กดบันทึกก็ต้องแดงให้ตรงกัน
  final Set<TextEditingController> _touched = {};
  // cache master data ต่อหน้า — ใช้โดย fields part file
  Future<FormOptions>? _optionsCache;
  Future<List<FarmerRef>>? _farmersCache;

  /// setState ที่ extension part files เรียกได้ — setState ตรงๆ
  /// เป็น @protected เรียกจาก extension ไม่ได้ (เหมือน _MapBodyState)
  void _set(VoidCallback fn) => setState(fn);

  @override
  void initState() {
    super.initState();
    _recoverLostPhoto();
    // prefill จากร่างที่บันทึกไว้ — meta เก็บ payload ฟอร์มครบ
    final p = widget.initial;
    if (p != null) {
      String s(String k) => '${p.meta?[k] ?? ''}';
      String? e(String k) {
        final v = s(k);
        return v.isEmpty ? null : v;
      }

      _nameCtrl.text = p.name.replaceAll(RegExp(r'\s*#\d+\s*$'), '');
      _yearCtrl.text = p.productionYear ?? s('productionYear');
      _rootCtrl.text = s('rootNo');
      _seqCtrl.text = s('sequenceNo');
      _lossCtrl.text = s('lossRai');
      _targetCtrl.text = s('targetYield');
      _noteCtrl.text = s('note');
      _project = e('project');
      _zone = e('zone');
      _province = e('province');
      _district = e('district');
      _subdistrict = e('subdistrict');
      _village = e('village');
      _prevPlot = e('prevPlotNo');
      _officer = e('officerName');
      _farmer = e('farmerName');
      _farmerId = e('farmerId');
      _caneGroup = e('caneGroup');
      _caneType = e('caneType');
      _caneVariety = e('caneVariety');
      _ownership = e('ownership');
      _terrain = e('terrain');
      final loss = s('hasLoss');
      if (loss.isNotEmpty) _losses.addAll(loss.split(', '));
      // รูปที่ถ่ายไว้ตอนบันทึกร่าง — prefill กลับกันรูปหายตอนแก้ไข
      // (meta['photos'] อาจไม่ใช่ List เสมอ — เช็กชนิดก่อนเสมอ)
      final metaPhotos = p.meta?['photos'];
      for (final path in metaPhotos is List ? metaPhotos : const []) {
        if (_photos.length >= 3) break;
        _photos.add(XFile('$path'));
      }
    }
    // baseline หลัง prefill (หรือฟอร์มว่าง) — ต้องตั้งเสมอ
    // ไม่งั้น late throw เงียบตอน onPopInvoked → กดย้อนไม่ได้
    _baseline = _formSig();
  }

  /// signature ข้อมูลในฟอร์มทั้งหมด — เช็กสดตอน pop (พิมพ์ใน
  /// TextField ไม่ rebuild ค่า canPop ที่ snapshot ตอน build จะ stale)
  String _formSig() => [
    for (final c in [
      _nameCtrl,
      _yearCtrl,
      _rootCtrl,
      _seqCtrl,
      _lossCtrl,
      _targetCtrl,
      _noteCtrl,
    ])
      c.text,
    '$_project',
    '$_zone',
    '$_province',
    '$_district',
    '$_subdistrict',
    '$_village',
    '$_prevPlot',
    '$_officer',
    '$_farmer',
    '$_farmerId',
    '$_caneGroup',
    '$_caneType',
    '$_caneVariety',
    '$_ownership',
    '$_terrain',
    (_losses.toList()..sort()).join(','),
    _photos.map((p) => p.path).join(','),
  ].join('|');
  // ไม่ใช้ late — hot reload ไม่รัน initState ใหม่ทำ field ว่างแล้ว
  // pop ไม่ได้ (crash ใน onPopInvoked) — fallback '' ให้ถามยืนยันแทน
  String _baseline = '';

  @override
  void dispose() {
    _nameCtrl.dispose();
    _yearCtrl.dispose();
    _rootCtrl.dispose();
    _seqCtrl.dispose();
    _lossCtrl.dispose();
    _targetCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  /// picker ที่ยังไม่ได้เลือก — Form validator จับได้เฉพาะ
  /// TextFormField เลยเช็กช่องเลือกเองแล้วขึ้นกรอบแดงผ่าน
  /// `_showErrors` (ทุกช่องบังคับ ยกเว้นข้อเสนอแนะ)
  List<String> get _missing => [
    if (_officer == null) 'นักส่งเสริมผู้ดูแล',
    if (_project == null) 'โครงการส่งเสริม',
    if (widget.isOfficer && _farmerId == null) 'ชาวไร่',
    if (_caneGroup == null) 'กลุ่มสร้างอ้อย',
    if (_zone == null) 'เขต',
    if (_province == null) 'จังหวัด',
    if (_district == null) 'อำเภอ',
    if (_subdistrict == null) 'ตำบล',
    if (_village == null) 'หมู่บ้าน',
    if (_caneType == null) 'ประเภทอ้อย',
    if (_caneVariety == null) 'พันธุ์อ้อย',
    if (_ownership == null) 'การถือครอง',
    if (_terrain == null) 'ระดับพื้นที่',
    if (_losses.isEmpty) 'มีพื้นที่สูญเสีย',
  ];

  void _save({bool draft = false}) {
    // ฉบับร่างเก็บลงเครื่อง — กรอกเท่าที่มีได้ (เช่น วัดเสร็จแล้ว
    // อยากกลับมากรอกต่อภายหลัง) บังคับเฉพาะตอนส่งขึ้นระบบจริง
    // กรอบแดงเตือนก็แสดงเฉพาะเส้นทางส่งจริงเช่นกัน
    if (!draft) {
      setState(() => _showErrors = true);
      final formOk = _formKey.currentState!.validate();
      final missing = _missing;
      if (!formOk || missing.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('กรุณากรอกข้อมูลให้ครบทุกช่อง (ยกเว้นข้อเสนอแนะ)'),
          ),
        );
        return;
      }
    }
    final yearText = _yearCtrl.text.trim();
    var name = _nameCtrl.text.trim();
    // ร่างที่ยังไม่ตั้งชื่อ — ตั้งให้อัตโนมัติจากเวลาบันทึก
    // ไม่งั้นการ์ดในหน้าฉบับร่างจะว่างเปล่าจำไม่ได้
    if (name.isEmpty && draft) {
      final t = DateTime.now();
      name =
          'แปลงร่าง ${t.day}/${t.month} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    }
    Navigator.pop(
      context,
      MeasurementResult(
        name: name,
        // '' ต้องไม่หลุดเป็น productionYear — backend/meta นับ
        // เป็นปีที่ไม่ระบุ ไม่ใช่สตริงว่าง
        productionYear: yearText.isEmpty ? null : yearText,
        officerName: _officer == 'ไม่ระบุ' ? null : _officer,
        project: _project,
        farmerName: _farmer == 'ไม่ระบุ' ? null : _farmer,
        farmerId: _farmerId,
        caneGroup: _caneGroup == 'ไม่ระบุ' ? null : _caneGroup,
        zone: _zone,
        province: _province,
        district: _district,
        subdistrict: _subdistrict,
        village: _village,
        rootNo: _t(_rootCtrl),
        sequenceNo: _t(_seqCtrl),
        prevPlotNo: _prevPlot,
        caneType: _none(_caneType),
        caneVariety: _none(_caneVariety),
        ownership: _none(_ownership),
        terrain: _none(_terrain),
        hasLoss: _losses.isEmpty ? null : _losses.join(', '),
        lossRai: _t(_lossCtrl),
        targetYield: _t(_targetCtrl),
        note: _t(_noteCtrl),
        photos: [for (final p in _photos) p.path],
        draft: draft,
      ),
    );
  }

  /// เป้าหมายผลผลิตรวม = ตัน/ไร่ × พื้นที่(ไร่).
  String get _totalYield {
    final t = double.tryParse(_targetCtrl.text.trim());
    if (t == null) return '0.00';
    return (t * widget.areaSquareMeters / 1600).toStringAsFixed(2);
  }

  Future<void> _pickPhoto() async {
    if (_photos.length >= 3) return;
    final source = await showImageSourceSheet(context);
    if (source == null) return;
    // pickImage throw ได้บางเครื่อง (already_active / camera busy)
    // กัน unhandled error แล้วแจ้งผู้ใช้แทนที่จะเงียบ
    try {
      final x = await ImagePicker().pickImage(source: source, maxWidth: 1600);
      if (x != null && mounted) setState(() => _photos.add(x));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('เปิดกล้องไม่สำเร็จ')));
    }
  }

  /// Android ฆ่าแอประหว่างเปิดกล้อง (เครื่อง RAM น้อย) — image_picker
  /// เก็บรูปที่ถ่ายไว้ใน pending state ดึงกลับมาตอนเปิดหน้าอีกครั้ง
  Future<void> _recoverLostPhoto() async {
    try {
      final lost = await ImagePicker().retrieveLostData();
      final file = lost.file;
      if (file != null && mounted && _photos.length < 3) {
        setState(() => _photos.add(file));
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
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
        appBar: brrAppBar('บันทึกข้อมูลการวัด'),
        body: Form(
          key: _formKey,
          child: Builder(
            builder: (_) {
              final fields = <Widget>[
                Card(
                  color: Colors.grey.shade200,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        const Text(
                          'พื้นที่ที่วัดได้',
                          style: TextStyle(color: Colors.black54, fontSize: 15),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          Parcel.formatThaiArea(widget.areaSquareMeters),
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: AppColors.green,
                          ),
                        ),
                        Text(
                          '${widget.areaSquareMeters.toStringAsFixed(0)} ตร.ม.',
                          style: const TextStyle(
                            color: Colors.black54,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                _tf(_nameCtrl, 'ชื่อแปลง', Iconsax.edit, required: true),
                const SizedBox(height: 16),
                _tf(
                  _yearCtrl,
                  'ปีการผลิต',
                  Icons.calendar_today,
                  required: true,
                  keyboard: TextInputType.number,
                  formatters: const [DigitFormatter()],
                ),
                const SizedBox(height: 16),
                _picker(
                  'นักส่งเสริมผู้ดูแล',
                  Iconsax.profile_2user,
                  () => _items(widget.officers()),
                  _officer,
                  (v) => setState(() => _officer = v),
                ),
                const SizedBox(height: 16),
                _picker(
                  'โครงการส่งเสริม',
                  Iconsax.folder,
                  () => _items(_pick((o) => o.projects)),
                  _project,
                  (v) => setState(() => _project = v),
                ),
                if (widget.isOfficer) ...[
                  const SizedBox(height: 16),
                  _farmerPicker(),
                ],
                const SizedBox(height: 16),
                _picker(
                  'กลุ่มสร้างอ้อย (กลุ่มบำรุง)',
                  Iconsax.people,
                  () => _items(_pick((o) => o.caneGroups)),
                  _caneGroup,
                  (v) => setState(() => _caneGroup = v),
                ),
                const SizedBox(height: 24),
                const Text(
                  'สถานที่',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.green,
                  ),
                ),
                const SizedBox(height: 12),
                _picker(
                  'เขต',
                  Iconsax.location,
                  () => _items(_pick((o) => o.zones)),
                  _zone,
                  (v) => setState(() => _zone = v),
                ),
                const SizedBox(height: 16),
                _picker(
                  'จังหวัด',
                  Iconsax.location,
                  () => _items(_pick((o) => o.provinces)),
                  _province,
                  // เปลี่ยนจังหวัด → เคลียร์ อำเภอ/ตำบล/หมู่บ้าน ที่เลือกไว้
                  (v) => setState(() {
                    _province = v;
                    _district = _subdistrict = _village = null;
                  }),
                ),
                const SizedBox(height: 16),
                _picker(
                  'อำเภอ',
                  Iconsax.location,
                  () => _items(_pick((o) => o.districtsOf(_province))),
                  _district,
                  (v) => setState(() {
                    _district = v;
                    _subdistrict = _village = null;
                  }),
                ),
                const SizedBox(height: 16),
                _picker(
                  'ตำบล',
                  Iconsax.location,
                  () => _items(
                    _pick((o) => o.subdistrictsOf(_province, _district)),
                  ),
                  _subdistrict,
                  (v) => setState(() {
                    _subdistrict = v;
                    _village = null;
                  }),
                ),
                const SizedBox(height: 16),
                _picker(
                  'หมู่บ้าน',
                  Iconsax.location,
                  () => _items(
                    _pick(
                      (o) => o.villagesOf(_province, _district, _subdistrict),
                    ),
                  ),
                  _village,
                  (v) => setState(() => _village = v),
                ),
                const SizedBox(height: 16),
                const SizedBox(height: 24),
                const Text(
                  'เลขแปลงปีก่อน',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.green,
                  ),
                ),
                const SizedBox(height: 12),
                _picker(
                  'เลขแปลงปีก่อน',
                  Iconsax.clock,
                  _prevPlotItems,
                  _prevPlot,
                  (v) => setState(() => _prevPlot = v),
                  required: false,
                ),
                const SizedBox(height: 16),
                _tf(
                  _rootCtrl,
                  'รูท',
                  Iconsax.hashtag,
                  keyboard: TextInputType.number,
                  formatters: const [DigitFormatter()],
                ),
                const SizedBox(height: 16),
                _tf(
                  _seqCtrl,
                  'ลำดับ',
                  Iconsax.task_square,
                  keyboard: TextInputType.number,
                  formatters: const [DigitFormatter()],
                ),
                const SizedBox(height: 24),
                const Text(
                  'ข้อมูลพื้นฐานแปลง (1)',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.green,
                  ),
                ),
                const SizedBox(height: 12),
                _picker(
                  'ประเภทอ้อย',
                  Iconsax.hierarchy,
                  () => _items(_pick((o) => o.caneTypes)),
                  _caneType,
                  (v) => setState(() => _caneType = v),
                ),
                const SizedBox(height: 16),
                _picker(
                  'เลือกพันธุ์อ้อย',
                  Iconsax.tree,
                  () => _items(_pick((o) => o.caneVarieties)),
                  _caneVariety,
                  (v) => setState(() => _caneVariety = v),
                ),
                const SizedBox(height: 16),
                _picker(
                  'การถือครอง',
                  Iconsax.map_1,
                  () => _items(_pick((o) => o.ownerships)),
                  _ownership,
                  (v) => setState(() => _ownership = v),
                ),
                const SizedBox(height: 16),
                _picker(
                  'ระดับพื้นที่',
                  Iconsax.convert_3d_cube,
                  () => _items(_pick((o) => o.terrains)),
                  _terrain,
                  (v) => setState(() => _terrain = v),
                ),
                const SizedBox(height: 24),
                const Text(
                  'ข้อมูลพื้นฐานแปลง (2)',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.green,
                  ),
                ),
                const SizedBox(height: 12),
                _multiPicker(
                  'มีพื้นที่สูญเสีย',
                  Iconsax.danger,
                  () => _items(_pick((o) => o.lossOptions)),
                  _losses,
                  (v) => setState(() {
                    _losses
                      ..clear()
                      ..addAll(v);
                  }),
                ),
                const SizedBox(height: 16),
                _tf(
                  _lossCtrl,
                  'พื้นที่สูญเสีย (ไร่)',
                  Iconsax.ruler,
                  // เลือก "ไม่มี" ในช่องสาเหตุ → เว้นว่างได้
                  required: !_losses.contains(_noneName),
                  keyboard: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  formatters: const [DigitFormatter(decimal: true)],
                ),
                const SizedBox(height: 24),
                const Text(
                  'ข้อมูลพื้นฐานแปลง (3)',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.green,
                  ),
                ),
                const SizedBox(height: 12),
                _tf(
                  _targetCtrl,
                  'เป้าหมายผลผลิต (ตัน/ไร่)',
                  Iconsax.flag,
                  required: true,
                  keyboard: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  formatters: const [DigitFormatter(decimal: true)],
                  helper: 'ไม่ควรใส่เกิน 30 ตัน/ไร่',
                  validator: (v) {
                    final t = double.tryParse(v?.trim() ?? '');
                    if (t != null && t > 30) {
                      return 'เป้าหมายผลผลิตไม่ควรเกิน 30 ตัน/ไร่';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _targetCtrl,
                  builder: (_, _, _) => _fieldCard(
                    'เป้าหมายผลผลิต (ตันรวม)',
                    Iconsax.calculator,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      decoration: _innerBoxDeco,
                      child: Text(
                        _totalYield,
                        style: const TextStyle(fontSize: 19),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _tf(_noteCtrl, 'ข้อเสนอแนะ', null, maxLines: 3, center: true),
                const SizedBox(height: 24),
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: const BorderSide(color: Colors.black12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'ภาพถ่าย',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                            Text(
                              '${_photos.length}/3',
                              style: const TextStyle(color: Colors.black54),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (_photos.isNotEmpty)
                          SizedBox(
                            height: 88,
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
                        if (_photos.isNotEmpty) const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          height: 46,
                          child: OutlinedButton.icon(
                            onPressed: _photos.length < 3 ? _pickPhoto : null,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF1B5E20),
                              side: const BorderSide(color: Color(0xFF1B5E20)),
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
                ),
                const SizedBox(height: 32),
                SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: () => _save(),
                    icon: const Icon(Icons.cloud_upload_outlined),
                    label: const Text(
                      'ส่งข้อมูลขึ้นระบบ (ออนไลน์)',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: () => _save(draft: true),
                    icon: const Icon(Iconsax.save_2),
                    label: const Text(
                      'บันทึกข้อมูลลงเครื่อง (ฉบับร่าง)',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ),
              ];
              return ListView.builder(
                padding: const EdgeInsets.all(20),
                itemCount: fields.length,
                itemBuilder: (_, i) => fields[i],
              );
            },
          ),
        ),
      ),
    );
  }
}

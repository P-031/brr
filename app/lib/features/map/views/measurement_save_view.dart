import 'dart:io';

import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:image_picker/image_picker.dart';

import 'package:brr/features/map/models/parcel.dart';
import 'package:brr/core/theme/app_theme.dart';

/// One row in the searchable picker — backend will supply real
/// `{code, name}` pairs later.
class PickerItem {
  const PickerItem({required this.code, required this.name});

  final String code;
  final String name;
}

/// Result returned when the measurement form is saved.
class MeasurementResult {
  const MeasurementResult({
    required this.name,
    this.productionYear,
    this.officerName,
    this.project,
    this.farmerName,
    this.farmerId,
    this.caneGroup,
    this.zone,
    this.province,
    this.district,
    this.subdistrict,
    this.village,
    this.rootNo,
    this.sequenceNo,
    this.prevPlotNo,
    this.caneType,
    this.caneVariety,
    this.ownership,
    this.terrain,
    this.hasLoss,
    this.lossRai,
    this.targetYield,
    this.note,
    this.photos = const [],
    this.draft = false,
  });

  final String name;
  final String? productionYear;
  final String? officerName;
  final String? project;
  final String? farmerName;
  final String? farmerId;
  final String? caneGroup;
  final String? zone;
  final String? province;
  final String? district;
  final String? subdistrict;
  final String? village;
  final String? rootNo;
  final String? sequenceNo;
  final String? prevPlotNo;
  final String? caneType;
  final String? caneVariety;
  final String? ownership;
  final String? terrain;
  final String? hasLoss;
  final String? lossRai;
  final String? targetYield;
  final String? note;
  final List<String> photos;
  final bool draft;
}

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

  void _save({bool draft = false}) {
    if (!_formKey.currentState!.validate()) return;
    if (widget.isOfficer && _farmerId == null && !draft) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('เลือกชาวไร่เจ้าของแปลง')),
      );
      return;
    }
    final year = _yearCtrl.text.trim().isEmpty ? null : _yearCtrl.text.trim();
    Navigator.pop(
      context,
      MeasurementResult(
        name: _nameCtrl.text.trim(),
        productionYear: year,
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
    final x = await ImagePicker().pickImage(
      source: ImageSource.camera,
      maxWidth: 1600,
    );
    if (x != null) setState(() => _photos.add(x));
  }

  String? _none(String? v) => (v == null || v == 'ไม่ระบุ') ? null : v;

  String? _t(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  /// Opens the searchable picker sheet (like the reference app) and
  /// returns the chosen item name to [onPick].
  Widget _picker(
    String label,
    IconData icon,
    Future<List<PickerItem>> Function() source,
    String? selected,
    void Function(String) onPick,
  ) {
    return InkWell(
      onTap: () async {
        final item = await showDialog<PickerItem>(
          context: context,
          builder: (_) => _PickerSheet(title: label, source: source),
        );
        if (item != null) onPick(item.name);
      },
      child: InputDecorator(
        decoration: _deco(label, icon, filled: selected != null).copyWith(
          suffixIcon: const Icon(Iconsax.arrow_down),
        ),
        child: Text(
          selected ?? 'แตะเพื่อเลือก',
          style: const TextStyle(fontSize: 16),
        ),
      ),
    );
  }

  Future<List<PickerItem>> _items(Future<List<String>> src) async =>
      [for (final s in await src) PickerItem(code: s, name: s)];

  Future<List<PickerItem>> _farmerItems() async =>
      [for (final f in await widget.farmers()) PickerItem(code: f.id, name: f.name)];

  /// Multi-select version of [_picker] — for fields like
  /// พื้นที่สูญเสีย where a plot can have several causes at once.
  Widget _multiPicker(
    String label,
    IconData icon,
    Future<List<PickerItem>> Function() source,
    Set<String> selected,
    void Function(Set<String>) onPick,
  ) {
    return InkWell(
      onTap: () async {
        final picked = await showDialog<Set<String>>(
          context: context,
          builder: (_) => _MultiPickerSheet(
            title: label,
            source: source,
            initial: selected,
          ),
        );
        if (picked != null) onPick(picked);
      },
      child: InputDecorator(
        decoration: _deco(label, icon, filled: selected.isNotEmpty).copyWith(
          suffixIcon: const Icon(Iconsax.arrow_down),
        ),
        child: Text(
          selected.isEmpty ? 'แตะเพื่อเลือก' : selected.join(', '),
          style: const TextStyle(fontSize: 16),
        ),
      ),
    );
  }

  /// ชาวไร่ picker — like [_picker] but keeps the account id so the
  /// backend knows which farmer owns the plot.
  Widget _farmerPicker() {
    return InkWell(
      onTap: () async {
        final item = await showDialog<PickerItem>(
          context: context,
          builder: (_) => _PickerSheet(title: 'ชาวไร่', source: _farmerItems),
        );
        if (item != null) {
          setState(() {
            _farmer = item.name;
            _farmerId = item.code;
          });
        }
      },
      child: InputDecorator(
        decoration: _deco('ชาวไร่', Iconsax.user, filled: _farmer != null)
            .copyWith(suffixIcon: const Icon(Iconsax.arrow_down)),
        child: Text(_farmer ?? 'แตะเพื่อเลือก', style: const TextStyle(fontSize: 16)),
      ),
    );
  }

  /// Pulls one option list out of the backend-supplied [FormOptions].
  Future<List<String>> _pick(List<String> Function(FormOptions) f) =>
      widget.options().then(f);

  /// เลขแปลงปีก่อน — existing plots from the backend (code = plot id).
  Future<List<PickerItem>> _prevPlotItems() async => [
    for (final p in (await widget.options()).prevPlots)
      PickerItem(code: p.code, name: p.name),
  ];

  /// [filled] → green border + soft gold tint once data is set.
  InputDecoration _deco(
    String label,
    IconData? icon, {
    bool filled = false,
    String? helper,
  }) => InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(fontSize: 16),
    helperText: helper,
    prefixIcon: icon != null ? Icon(icon, color: AppColors.green) : null,
    filled: filled,
    fillColor: filled ? AppColors.goldLight : null,
    border: const OutlineInputBorder(),
    enabledBorder: filled
        ? const OutlineInputBorder(
            borderSide: BorderSide(color: AppColors.green, width: 2),
          )
        : const OutlineInputBorder(),
  );

  /// Text field with the filled-state green border + soft gold fill.
  Widget _tf(
    TextEditingController ctrl,
    String label,
    IconData? icon, {
    TextInputType? keyboard,
    int maxLines = 1,
    String? helper,
    String? Function(String?)? validator,
  }) => ValueListenableBuilder<TextEditingValue>(
    valueListenable: ctrl,
    builder: (_, value, _) => TextFormField(
      controller: ctrl,
      style: const TextStyle(fontSize: 17),
      keyboardType: keyboard,
      maxLines: maxLines,
      validator: validator,
      decoration: _deco(
        label,
        icon,
        filled: value.text.trim().isNotEmpty,
        helper: helper,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('บันทึกข้อมูลการวัด')),
      body: Form(
        key: _formKey,
        child: Builder(
          builder: (_) {
            final fields = <Widget>[
            Card(
              color: AppColors.goldLight,
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
            _tf(
              _nameCtrl,
              'ชื่อแปลง',
              Iconsax.edit,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'กรุณากรอกชื่อแปลง' : null,
            ),
            const SizedBox(height: 16),
            _tf(
              _yearCtrl,
              'ปีการผลิต',
              Iconsax.calendar,
              keyboard: TextInputType.number,
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
                  (o) =>
                      o.villagesOf(_province, _district, _subdistrict),
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
            ),
            const SizedBox(height: 16),
            _tf(
              _rootCtrl,
              'รูท',
              Iconsax.hashtag,
              keyboard: TextInputType.number,
            ),
            const SizedBox(height: 16),
            _tf(
              _seqCtrl,
              'ลำดับ',
              Iconsax.task_square,
              keyboard: TextInputType.number,
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
              keyboard: TextInputType.number,
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
              keyboard: const TextInputType.numberWithOptions(
                decimal: true,
              ),
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
              builder: (_, _, _) => InputDecorator(
                decoration: _deco(
                  'เป้าหมายผลผลิต (ตันรวม)',
                  Iconsax.calculator,
                ),
                child: Text(
                  _totalYield,
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _tf(
              _noteCtrl,
              'ข้อเสนอแนะ',
              null,
              maxLines: 3,
            ),
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
                                ),
                              ),
                              Positioned(
                                top: -4,
                                right: -4,
                                child: GestureDetector(
                                  onTap: () => setState(
                                    () => _photos.removeAt(i),
                                  ),
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
                        onPressed:
                            _photos.length < 3 ? _pickPhoto : null,
                        icon: const Icon(Iconsax.camera),
                        label: const Text(
                          'ถ่ายภาพ',
                          style: TextStyle(fontSize: 15),
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
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
    );
  }
}

/// Centered dialog picker with search, list rows and a cancel
/// link — same pattern as the reference app.
class _PickerSheet extends StatefulWidget {
  const _PickerSheet({required this.title, required this.source});

  final String title;

  /// Invoked on open and on retry — a failed load never stays
  /// stale, and nothing is fetched until the dialog opens.
  final Future<List<PickerItem>> Function() source;

  @override
  State<_PickerSheet> createState() => _PickerSheetState();
}

class _PickerSheetState extends State<_PickerSheet> {
  String _q = '';
  late Future<List<PickerItem>> _future = widget.source();

  void _retry() => setState(() => _future = widget.source());

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 520),
        child: Padding(
          padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'เลือก${widget.title}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              autofocus: true,
              style: const TextStyle(fontSize: 16),
              onChanged: (v) => setState(() => _q = v),
              decoration: InputDecoration(
                hintText: 'ค้นหาด้วย รหัส หรือ ชื่อ ได้ที่นี่',
                hintStyle: const TextStyle(fontSize: 15),
                prefixIcon: const Icon(Iconsax.search_normal),
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: FutureBuilder<List<PickerItem>>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snap.hasError) {
                    return _SheetError(onRetry: _retry);
                  }
                  final items = (snap.data ?? const <PickerItem>[])
                      .where(
                        (i) => i.name.contains(_q) || i.code.contains(_q),
                      )
                      .toList();
                  if (items.isEmpty) {
                    return const Center(child: Text('ยังไม่มีข้อมูล'));
                  }
                  return ListView.builder(
                    shrinkWrap: true,
                    itemCount: items.length,
                    itemBuilder: (context, i) {
                      final it = items[i];
                      return Card(
                        child: ListTile(
                          leading: const CircleAvatar(
                            child: Icon(Iconsax.user),
                          ),
                          title: Text(
                            'ชื่อ: ${it.name}',
                            style: const TextStyle(fontSize: 16),
                          ),
                          subtitle: Text(
                            'รหัส: ${it.code}',
                            style: const TextStyle(fontSize: 14),
                          ),
                          onTap: () => Navigator.pop(context, it),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('ยกเลิก', style: TextStyle(fontSize: 15)),
              ),
            ),
          ],
        ),
          ),
        ),
    );
  }
}

/// Checkbox variant of [_PickerSheet] — returns the whole selected
/// set on ตกลง. 'ไม่มี' is exclusive: picking it clears the rest,
/// and picking anything else un-picks it.
class _MultiPickerSheet extends StatefulWidget {
  const _MultiPickerSheet({
    required this.title,
    required this.source,
    required this.initial,
  });

  final String title;
  final Future<List<PickerItem>> Function() source;
  final Set<String> initial;

  @override
  State<_MultiPickerSheet> createState() => _MultiPickerSheetState();
}

class _MultiPickerSheetState extends State<_MultiPickerSheet> {
  static const _noneName = 'ไม่มี';
  String _q = '';
  late final Set<String> _selected = {...widget.initial};
  late Future<List<PickerItem>> _future = widget.source();

  void _retry() => setState(() => _future = widget.source());

  void _toggle(String name, bool on) {
    setState(() {
      if (name == _noneName) {
        _selected.clear();
        if (on) _selected.add(name);
      } else {
        _selected.remove(_noneName);
        on ? _selected.add(name) : _selected.remove(name);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 520),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'เลือก${widget.title}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                autofocus: true,
                style: const TextStyle(fontSize: 16),
                onChanged: (v) => setState(() => _q = v),
                decoration: InputDecoration(
                  hintText: 'ค้นหาได้ที่นี่',
                  hintStyle: const TextStyle(fontSize: 15),
                  prefixIcon: const Icon(Iconsax.search_normal),
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: FutureBuilder<List<PickerItem>>(
                  future: _future,
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snap.hasError) {
                      return _SheetError(onRetry: _retry);
                    }
                    final items = (snap.data ?? const <PickerItem>[])
                        .where(
                          (i) => i.name.contains(_q) || i.code.contains(_q),
                        )
                        .toList();
                    if (items.isEmpty) {
                      return const Center(child: Text('ยังไม่มีข้อมูล'));
                    }
                    return ListView.builder(
                      shrinkWrap: true,
                      itemCount: items.length,
                      itemBuilder: (context, i) {
                        final it = items[i];
                        return Card(
                          child: CheckboxListTile(
                            value: _selected.contains(it.name),
                            onChanged: (v) => _toggle(it.name, v ?? false),
                            title: Text(
                              it.name,
                              style: const TextStyle(fontSize: 16),
                            ),
                            controlAffinity: ListTileControlAffinity.leading,
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('ยกเลิก', style: TextStyle(fontSize: 15)),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, _selected),
                    child: const Text('ตกลง', style: TextStyle(fontSize: 15)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown inside picker dialogs when the fetch throws — gives a
/// retry instead of silently looking like "no data".
class _SheetError extends StatelessWidget {
  const _SheetError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Iconsax.warning_2, color: Colors.red, size: 32),
          const SizedBox(height: 8),
          const Text('โหลดข้อมูลไม่สำเร็จ', style: TextStyle(fontSize: 15)),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Iconsax.refresh, size: 18),
            label: const Text('ลองใหม่'),
          ),
        ],
      ),
    );
  }
}

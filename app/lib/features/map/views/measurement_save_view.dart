import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax/iconsax.dart';
import 'package:image_picker/image_picker.dart';

import 'package:brr/features/map/models/parcel.dart';
import 'package:brr/core/theme/app_theme.dart';
import 'package:brr/core/utils/fuzzy_search.dart';
import 'package:brr/core/widgets/image_source_sheet.dart';

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

/// แป้นพิมพ์ไทยกดตำแหน่งเลขได้อักขระไทย/สัญลักษณ์ (เช่น / -) —
/// แปลงเลขไทย ๐-๙ เป็นอารบิกแล้วตัดตัวอื่นทิ้ง ทำให้ช่องตัวเลข
/// พิมพ์ได้ไม่ว่าแป้นจะอยู่โหมดไหน
class _DigitFormatter extends TextInputFormatter {
  const _DigitFormatter({this.decimal = false});

  /// true = อนุญาตจุดทศนิยม 1 จุด (ไร่สูญเสีย/เป้าผลผลิต)
  final bool decimal;

  static const _thai = '๐๑๒๓๔๕๖๗๘๙';

  /// แป้นไทย Kedmanee — อักขระที่แถวตัวเลขพิมพ์ออกมาโดยไม่กด Shift
  /// จับคู่กับเลขตาม "ตำแหน่งปุ่ม" (กดปุ่ม 4 ได้ ภ = ตั้งใจพิมพ์ 4)
  static const _kedmanee = {
    'ๅ': '1',
    '/': '2',
    '-': '3',
    'ภ': '4',
    'ถ': '5',
    'ุ': '6',
    'ึ': '7',
    'ค': '8',
    'ต': '9',
    'จ': '0',
  };

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final sb = StringBuffer();
    var hasDot = false;
    for (final r in newValue.text.runes) {
      final ch = String.fromCharCode(r);
      final ti = _thai.indexOf(ch);
      if (ti >= 0) {
        sb.write(ti);
        continue;
      }
      final kd = _kedmanee[ch];
      if (kd != null) {
        sb.write(kd);
        continue;
      }
      if (r >= 0x30 && r <= 0x39) {
        sb.write(ch);
        continue;
      }
      if (decimal && !hasDot && ch == '.') {
        hasDot = true;
        sb.write('.');
      }
    }
    final text = sb.toString();
    // ข้อความผ่าน filter แล้วเหมือนเดิม (เช่น พิมพ์เลขอารบิกกลาง
    // ประโยค) → คืน newValue เลย cursor ไม่ดีดไปท้ายทุกครั้ง
    if (text == newValue.text) return newValue;
    // มีตัวที่ถูกตัด/แปลง — วาง cursor หลังตัวสุดท้ายที่ผ่าน filter
    // ก่อนจุด cursor เดิม (run substring เดิมผ่าน formatter เดียวกัน)
    final cursorEnd = newValue.selection.end.clamp(
      0,
      newValue.text.length,
    );
    final keptLen = formatEditUpdate(
      oldValue,
      TextEditingValue(text: newValue.text.substring(0, cursorEnd)),
    ).text.length;
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(
        offset: keptLen.clamp(0, text.length),
      ),
    );
  }
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

  @override
  void initState() {
    super.initState();
    _recoverLostPhoto();
    // prefill จากร่างที่บันทึกไว้ — meta เก็บ payload ฟอร์มครบ
    final p = widget.initial;
    if (p == null) return;
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
    for (final path in p.meta?['photos'] as List? ?? const []) {
      if (_photos.length >= 3) break;
      _photos.add(XFile('$path'));
    }
  }

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
            content: Text(
              'กรุณากรอกข้อมูลให้ครบทุกช่อง (ยกเว้นข้อเสนอแนะ)',
            ),
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
      final x = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1600,
      );
      if (x != null) setState(() => _photos.add(x));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('เปิดกล้องไม่สำเร็จ')));
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
    void Function(String) onPick, {
    bool required = true,
  }) {
    final invalid = required && _showErrors && selected == null;
    return InkWell(
      onTap: () async {
        final item = await showDialog<PickerItem>(
          context: context,
          builder: (_) => _PickerSheet(title: label, source: source),
        );
        if (item != null) onPick(item.name);
      },
      child: _fieldCard(
        label,
        icon,
        filled: selected != null,
        invalid: invalid,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: _innerBoxDeco,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  selected ?? 'แตะเพื่อเลือก',
                  style: TextStyle(
                    fontSize: 19,
                    color: invalid
                        ? Colors.redAccent
                        : selected == null
                        ? Colors.black38
                        : null,
                  ),
                ),
              ),
              Icon(
                Iconsax.arrow_circle_down,
                size: 28,
                color: invalid ? Colors.redAccent : Colors.black87,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<List<PickerItem>> _items(Future<List<String>> src) async => [
    for (final s in await src) PickerItem(code: s, name: s),
  ];

  Future<List<PickerItem>> _farmerItems() async => [
    for (final f in await widget.farmers())
      PickerItem(code: f.id, name: f.name),
  ];

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
      child: _fieldCard(
        label,
        icon,
        filled: selected.isNotEmpty,
        invalid: _showErrors && selected.isEmpty,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: _innerBoxDeco,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  selected.isEmpty ? 'แตะเพื่อเลือก' : selected.join(', '),
                  style: TextStyle(
                    fontSize: 19,
                    color: _showErrors && selected.isEmpty
                        ? Colors.redAccent
                        : selected.isEmpty
                        ? Colors.black38
                        : null,
                  ),
                ),
              ),
              Icon(
                Iconsax.arrow_circle_down,
                size: 28,
                color: _showErrors && selected.isEmpty
                    ? Colors.redAccent
                    : Colors.black87,
              ),
            ],
          ),
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
      child: _fieldCard(
        'ชาวไร่',
        Iconsax.user,
        filled: _farmer != null,
        invalid: _showErrors && _farmerId == null,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: _innerBoxDeco,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _farmer ?? 'แตะเพื่อเลือก',
                  style: TextStyle(
                    fontSize: 19,
                    color: _showErrors && _farmerId == null
                        ? Colors.redAccent
                        : _farmer == null
                        ? Colors.black38
                        : null,
                  ),
                ),
              ),
              Icon(
                Iconsax.arrow_circle_down,
                size: 28,
                color: _showErrors && _farmerId == null
                    ? Colors.redAccent
                    : Colors.black87,
              ),
            ],
          ),
        ),
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

  /// การ์ดช่องข้อมูล — หัวข้อ (icon+label) อยู่ในการ์ด ตามด้วย
  /// ตัวกรอก/เลือกของแต่ละช่อง
  /// [filled] → กรอบเขียวเมื่อมีข้อมูล
  /// [invalid] → กรอบแดงตอนกดบันทึกแล้วยังว่าง
  Widget _fieldCard(
    String label,
    IconData? icon, {
    bool filled = false,
    bool invalid = false,
    String? helper,
    required Widget child,
  }) => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: invalid
            ? Colors.redAccent
            : filled
            ? AppColors.green
            : Colors.black26,
        width: invalid || filled ? 1.5 : 1,
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 22,
                color: invalid ? Colors.redAccent : AppColors.green,
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: invalid ? Colors.redAccent : Colors.black87,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        child,
        if (helper != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              helper,
              style: const TextStyle(fontSize: 13, color: Colors.black54),
            ),
          ),
      ],
    ),
  );

  /// กรอบช่องย่อยในการ์ด — ช่องพิมพ์/ช่องเลือกดูเป็น "ช่อง" ชัด
  /// พื้นเทาอ่อน + ขอบมน เหมือน input ทั่วไป
  static final BoxDecoration _innerBoxDeco = BoxDecoration(
    color: Colors.grey.shade50,
    borderRadius: BorderRadius.circular(10),
    border: Border.all(color: Colors.black12),
  );

  /// decoration ของช่องพิมพ์ในการ์ด — กรอบเดียวกับ _innerBox
  static const _innerDeco = InputDecoration(
    isDense: true,
    filled: true,
    fillColor: Color(0xFFFAFAFA), // grey.shade50 (const)
    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    hintText: 'กรอกข้อมูล',
    hintStyle: TextStyle(fontSize: 17, color: Colors.black38),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(10)),
      borderSide: BorderSide(color: Colors.black12),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(10)),
      borderSide: BorderSide(color: Colors.black12),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(10)),
      borderSide: BorderSide(color: AppColors.green, width: 2),
    ),
  );

  /// Text field — มีข้อมูล = กรอบเขียว, [required] = ห้ามว่าง
  /// (validate สดตอนพิมพ์ กรอบแดงหายทันทีที่กรอก)
  Widget _tf(
    TextEditingController ctrl,
    String label,
    IconData? icon, {
    TextInputType? keyboard,
    int maxLines = 1,
    bool required = false,
    String? helper,
    String? Function(String?)? validator,
    List<TextInputFormatter>? formatters,
  }) => ValueListenableBuilder<TextEditingValue>(
    valueListenable: ctrl,
    builder: (_, value, _) => _fieldCard(
      label,
      icon,
      filled: value.text.trim().isNotEmpty,
      // ช่องบังคับที่ว่าง — แดงหลังกดบันทึก หรือหลังเคยพิมพ์
      // (autovalidate ขึ้นกรอบแดงตั้งแต่ onChanged แรก ให้
      // ไอคอน/label แดงตามไม่ให้มั่วกัน)
      invalid:
          required &&
          value.text.trim().isEmpty &&
          (_showErrors || _touched.contains(ctrl)),
      helper: helper,
      child: TextFormField(
        controller: ctrl,
        style: const TextStyle(fontSize: 19),
        keyboardType: keyboard,
        maxLines: maxLines,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        validator: (v) {
          if (required && (v == null || v.trim().isEmpty)) {
            return 'กรุณากรอกข้อมูล';
          }
          return validator?.call(v);
        },
        inputFormatters: formatters,
        onChanged: (_) => _touched.add(ctrl),
        decoration: _innerDeco,
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
                formatters: const [_DigitFormatter()],
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
                formatters: const [_DigitFormatter()],
              ),
              const SizedBox(height: 16),
              _tf(
                _seqCtrl,
                'ลำดับ',
                Iconsax.task_square,
                keyboard: TextInputType.number,
                formatters: const [_DigitFormatter()],
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
                keyboard: const TextInputType.numberWithOptions(decimal: true),
                formatters: const [_DigitFormatter(decimal: true)],
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
                keyboard: const TextInputType.numberWithOptions(decimal: true),
                formatters: const [_DigitFormatter(decimal: true)],
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
              _tf(_noteCtrl, 'ข้อเสนอแนะ', null, maxLines: 3),
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
                    fontSize: 21,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                autofocus: true,
                style: const TextStyle(fontSize: 18),
                onChanged: (v) => setState(() => _q = v),
                decoration: InputDecoration(
                  hintText: 'ค้นหาด้วย รหัส หรือ ชื่อ ได้ที่นี่',
                  hintStyle: const TextStyle(fontSize: 17),
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
                    final items = fuzzySearch(
                      snap.data ?? const <PickerItem>[],
                      _q,
                      (i) => '${i.name} ${i.code}',
                    );
                    if (items.isEmpty) {
                      return const Center(
                        child: Text(
                          'ยังไม่มีข้อมูล',
                          style: TextStyle(fontSize: 17),
                        ),
                      );
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
                              style: const TextStyle(fontSize: 18),
                            ),
                            subtitle: Text(
                              'รหัส: ${it.code}',
                              style: const TextStyle(fontSize: 16),
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
                  child: const Text('ยกเลิก', style: TextStyle(fontSize: 17)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Backend loss-option that means "no cause" — exclusive inside
/// [_MultiPickerSheet] and skips the loss-area field requirement.
const _noneName = 'ไม่มี';

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
  String _q = '';
  List<PickerItem> _items = const [];
  // Selection keyed by code, not name — two options sharing a
  // display name don't collide. Initial names resolve once items
  // load; names no longer in the list stay in [_extra] so a
  // restored draft doesn't silently drop a removed option.
  Set<String>? _selected;
  final Set<String> _extra = {};
  late Future<List<PickerItem>> _future = widget.source();

  void _retry() => setState(() => _future = widget.source());

  void _init(List<PickerItem> items) {
    if (_selected != null) return;
    _items = items;
    _selected = {
      for (final it in items)
        if (widget.initial.contains(it.name)) it.code,
    };
    _extra.addAll(
      widget.initial.difference({for (final it in items) it.name}),
    );
  }

  void _toggle(PickerItem it, bool on) {
    setState(() {
      final sel = _selected!;
      if (it.name == _noneName) {
        sel.clear();
        _extra.clear();
        if (on) sel.add(it.code);
      } else {
        for (final n in _items) {
          if (n.name == _noneName) sel.remove(n.code);
        }
        _extra.remove(_noneName);
        on ? sel.add(it.code) : sel.remove(it.code);
      }
    });
  }

  Set<String> _pickedNames() => {
    ..._extra,
    for (final it in _items)
      if (_selected!.contains(it.code)) it.name,
  };

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
                    fontSize: 21,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                autofocus: true,
                style: const TextStyle(fontSize: 18),
                onChanged: (v) => setState(() => _q = v),
                decoration: InputDecoration(
                  hintText: 'ค้นหาได้ที่นี่',
                  hintStyle: const TextStyle(fontSize: 17),
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
                    _init(snap.data ?? const <PickerItem>[]);
                    final items = fuzzySearch(
                      snap.data ?? const <PickerItem>[],
                      _q,
                      (i) => '${i.name} ${i.code}',
                    );
                    if (items.isEmpty) {
                      return const Center(
                        child: Text(
                          'ยังไม่มีข้อมูล',
                          style: TextStyle(fontSize: 17),
                        ),
                      );
                    }
                    return ListView.builder(
                      shrinkWrap: true,
                      itemCount: items.length,
                      itemBuilder: (context, i) {
                        final it = items[i];
                        return Card(
                          child: CheckboxListTile(
                            value: _selected!.contains(it.code),
                            onChanged: (v) => _toggle(it, v ?? false),
                            title: Text(
                              it.name,
                              style: const TextStyle(fontSize: 18),
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
                    child: const Text('ยกเลิก', style: TextStyle(fontSize: 17)),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.pop(
                      context,
                      _selected == null ? widget.initial : _pickedNames(),
                    ),
                    child: const Text('ตกลง', style: TextStyle(fontSize: 17)),
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
          const Text('โหลดข้อมูลไม่สำเร็จ', style: TextStyle(fontSize: 17)),
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

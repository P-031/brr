import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import 'package:brr/core/theme/app_theme.dart';
import 'package:brr/core/widgets/digit_formatter.dart';
import 'package:brr/core/widgets/option_popup.dart';
import 'package:brr/core/widgets/thai_date_picker.dart';
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
  });

  final ParcelDetailViewModel vm;
  final List<String> photoPaths;
  final int activityNo;

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
  bool _saving = false;
  late final Future<FormOptions> _optionsFut = widget.vm.loadOptions();

  @override
  void initState() {
    super.initState();
    // prefill กลุ่มอ้อยจากข้อมูลแปลงถ้ามี
    _caneGroup = widget.vm.parcel.meta?['caneGroup'] as String?;
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

  /// แถว label (ชิดขวา) + ช่องเทาแบบ dropdown ในการ์ด —
  /// [icon] ใช้วงกลมลูกศรลงสำหรับเลือก / ปฏิทินสำหรับวันที่
  Widget _optRow(
    String label,
    String? value,
    String hint,
    VoidCallback onTap, {
    IconData icon = Iconsax.arrow_circle_down,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        SizedBox(
          width: 132,
          child: Text(
            '$label :',
            textAlign: TextAlign.end,
            softWrap: false,
            style: const TextStyle(fontSize: 16, color: Colors.black87),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: Container(
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
                      textAlign: TextAlign.center,
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
        ),
      ],
    ),
  );

  /// แถว label + ช่องตัวเลขเส้นใต้ (อัตรา กก./ไร่)
  Widget _rateRow(String label, TextEditingController c) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        SizedBox(
          width: 132,
          child: Text(
            '$label :',
            textAlign: TextAlign.end,
            softWrap: false,
            style: const TextStyle(fontSize: 16, color: Colors.black87),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: c,
            textAlign: TextAlign.end,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: const [DigitFormatter(decimal: true)],
            style: const TextStyle(fontSize: 20),
            decoration: const InputDecoration(
              hintText: '0.0',
              hintStyle: TextStyle(fontSize: 18),
              isDense: true,
              border: UnderlineInputBorder(),
            ),
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
      await widget.vm.saveActivityDraft(
        photoPaths: widget.photoPaths,
        detailPending: false,
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
        plantedAt: iso(planted),
      );
      if (mounted) Navigator.of(context).pop('บันทึกกิจกรรมเรียบร้อย');
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
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: selected ? AppColors.green : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          // ปุ่มที่เลือกกรอบทองแบบปุ่มหน้า Home
          color: selected ? AppColors.gold : Colors.grey.shade300,
          width: selected ? 4.5 : 1,
        ),
      ),
      child: Center(
        child: Text(
          label,
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
        SizedBox(
          width: 132,
          child: Text(
            '$label :',
            textAlign: TextAlign.end,
            style: const TextStyle(fontSize: 16, color: Colors.black87),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Row(
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
          final rai = (areaMap?['raiDecimal'] as num?)?.toDouble() ?? p.areaRai;
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
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Text(
                          'อัตราการใส่ปุ๋ย(กก./ไร่) :',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _rateCtrl,
                            textAlign: TextAlign.end,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: const [
                              DigitFormatter(decimal: true),
                            ],
                            style: const TextStyle(fontSize: 17),
                            decoration: const InputDecoration(
                              hintText: '0.0',
                              isDense: true,
                              border: UnderlineInputBorder(),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
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
                          ((double.tryParse(_rateCtrl.text) ?? 0) +
                                  _rounds.fold<double>(
                                    0,
                                    (s, r) =>
                                        s +
                                        (double.tryParse(r.rate ?? '') ?? 0),
                                  ))
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
                    _rateRow('อัตรา(กก./ไร่)', _organicRateCtrl),
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
                    _rateRow('อัตรา(กก./ไร่)', _dolomiteRateCtrl),
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
                    _rateRow('ความลึก(ซม.)', _subsoilDepthCtrl),
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
                    _rateRow('ระบาด (%)', _diseaseSpreadCtrl),
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

  Widget _label(String t) => Text(
    t,
    style: const TextStyle(fontSize: 17, color: Colors.black87),
    textAlign: TextAlign.end,
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
              Row(
                children: [
                  _label('วันที่ใส่ :'),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _pickerField(
                      'เลือกวันที่',
                      _date == null ? null : _fmtThai(_date!),
                      _pickDate,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _label('อัตรา(กก./ไร่) :'),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _rateCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: const [DigitFormatter(decimal: true)],
                      style: const TextStyle(fontSize: 18),
                      decoration: const InputDecoration(
                        isDense: true,
                        border: UnderlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: _label('สูตรปุ๋ย :'),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _pickerField('เลือก', _formula, _pickFormula),
                  ),
                ],
              ),
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

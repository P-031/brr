part of 'activity_detail_view.dart';

/// helper + widget builder ย่อยของ _ActivityDetailViewState —
/// แยกออกจาก activity_detail_view.dart เพราะไฟล์เดิมยาวกว่า
/// พันบรรทัด; extension เข้าถึง private ได้เหมือนเดิม
extension _ActivityDetailWidgets on _ActivityDetailViewState {
  Future<void> _pickDate() async {
    final picked = await showThaiDatePicker(
      context,
      initialDate: _plantedAt ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      _set(() {
        _plantedAt = picked;
        _dateCtrl.text = _ActivityDetailViewState._fmtThai(picked);
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
    if (picked != null) _set(() => set(picked));
  }

  /// เลือก/ถ่ายรูปเพิ่ม (สูงสุด 3 ใบ) — image_picker throw ได้บาง
  /// เครื่อง กัน unhandled error แล้วแจ้งผู้ใช้แทนที่จะเงียบ
  Future<void> _pickPhoto() async {
    if (_photos.length >= 3) return;
    final source = await showImageSourceSheet(context);
    if (source == null) return;
    try {
      final x = await ImagePicker().pickImage(source: source, maxWidth: 1600);
      if (x != null) _set(() => _photos.add(x.path));
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
        _set(() => _photos.add(file.path));
      }
    } catch (_) {}
  }

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
        Text(label, style: _ActivityDetailViewState._fieldLabelStyle),
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
        Text(label, style: _ActivityDetailViewState._fieldLabelStyle),
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
        Text(label, style: _ActivityDetailViewState._fieldLabelStyle),
        const SizedBox(height: 6),
        if (unit != null && numeric)
          UnitField(
            controller: c,
            unit: unit,
            hint: hint ?? '0.0',
            onChanged: () => _set(() {}),
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
              decoration: _ActivityDetailViewState._boxDeco(
                hint ?? (numeric ? '0.0' : 'กรอกข้อมูล'),
                filled: v.text.trim().isNotEmpty,
              ),
              onChanged: (_) => _set(() {}),
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
    if (r != null) _set(() => _rounds.add(r));
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
      planted = _ActivityDetailViewState._parseThai(_dateCtrl.text);
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
    _set(() => _saving = true);
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
        plantedAt: iso(planted),
      );
      if (mounted) {
        Navigator.of(context)
            .pop(draft ? 'บันทึกฉบับร่างไว้แล้ว' : 'บันทึกกิจกรรมเรียบร้อย');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'.replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) _set(() => _saving = false);
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
          Text(label, style: _ActivityDetailViewState._fieldLabelStyle),
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
              onTap: () => _set(() => _rounds.removeAt(index)),
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
        _roundLine(
          'วันที่ใส่',
          r.date == null ? '—' : _ActivityDetailViewState._fmtThai(r.date!),
        ),
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
}

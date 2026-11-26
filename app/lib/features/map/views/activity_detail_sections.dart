part of 'activity_detail_view.dart';

/// การ์ดแต่ละ section ของฟอร์มกิจกรรม — แยกออกจาก
/// activity_detail_view.dart เพราะ build เดิมยาวกว่าพันบรรทัด
/// extension บน state เดิม = เข้าถึง controller/field private
/// ได้เหมือนเดิมทุกอย่าง (part ไฟล์เดียวกัน library เดียวกัน)
extension _ActivityDetailSections on _ActivityDetailViewState {
  /// การ์ดสรุปแปลง — ชุดเดียวกับหน้าถ่ายรูป
  Widget _summaryCard(Map meta, double rai) {
    final p = widget.vm.parcel;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade400, width: 1.5),
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
    );
  }

  /// การ์ดวันที่ปลูก — พิมพ์เองหรือเลือกจากปฏิทิน
  Widget _plantedDateCard() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.grey.shade400, width: 1.5),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _cardHeader('วันที่ปลูก'),
        const Text(
          'พิมพ์ตัวเลข วัน เดือน ปี (พ.ศ.) ติดกัน\n'
          'เช่น 01022569 → 01/02/2569 (ขีด / ใส่ให้อัตโนมัติ)',
          style: TextStyle(fontSize: 14, color: Colors.black54),
        ),
        const SizedBox(height: 12),
        TextField(
          textAlign: TextAlign.start,
          controller: _dateCtrl,
          keyboardType: TextInputType.datetime,
          inputFormatters: [ThaiDateSlashFormatter()],
          style: const TextStyle(fontSize: 17),
          decoration: InputDecoration(
            hintText: 'วว/ดด/ปปปป',
            hintStyle: const TextStyle(fontSize: 16, color: Colors.black38),
            suffixIcon: IconButton(
              icon: const Icon(
                Icons.calendar_today,
                color: AppColors.green,
                size: 30,
              ),
              onPressed: _pickDate,
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.green, width: 1.5),
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
  );

  /// การ์ดกลุ่มสร้างอ้อย — ตัวเลือกจาก /meta/options
  Widget _caneGroupCard() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.grey.shade400, width: 1.5),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _cardHeader('กลุ่มสร้างอ้อย (กลุ่มบำรุง)'),
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () async {
            // loadOptions พังตอนออฟไลน์ — ต้อง catch ไม่งั้น
            // แตะแล้วเงียบเหมือนปุ่มตาย (unhandled error)
            FormOptions opts;
            try {
              opts = await _optionsFut;
            } catch (_) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('โหลดตัวเลือกไม่สำเร็จ')),
              );
              return;
            }
            if (!mounted) return;
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
              _set(() => _caneGroup = opts.caneGroups[idx]);
            }
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
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
  );

  /// การ์ดการใช้ยาคุม — ใช้/ไม่ใช้
  Widget _herbicideCard() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.grey.shade400, width: 1.5),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _cardHeader('การใช้ยาคุม'),
        Row(
          children: [
            Expanded(
              child: _mpiButton(
                'ใช้',
                _herbicide == 'ใช้',
                () => _set(() => _herbicide = 'ใช้'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _mpiButton(
                'ไม่ใช้',
                _herbicide == 'ไม่ใช้',
                () => _set(() => _herbicide = 'ไม่ใช้'),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  /// การ์ดฝ่ากอ — อัตราปุ๋ย + สูตร NPK + ยอดรวม
  Widget _baseFertilizerCard() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.grey.shade400, width: 1.5),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _cardHeader('ฝ่ากอ'),
        _inputRow('อัตราการใส่ปุ๋ย(กก./ไร่)', _rateCtrl, unit: 'กก./ไร่'),
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
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
  );

  /// การ์ดใช้ปุ๋ยตามปริมาณผลผลิตที่ต้องการ — MPI + หลายรอบใส่ปุ๋ย
  Widget _mpiFertilizerCard() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.grey.shade400, width: 1.5),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _cardHeader('ใช้ปุ๋ยตามปริมาณผลผลิตที่ต้องการ'),
        const Text(
          'ค่าปุ๋ย MPI',
          style: TextStyle(fontSize: 16, color: Colors.black54),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _mpiButton('ทำ', _mpiApplied == true, () {
                _set(() => _mpiApplied = true);
              }),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _mpiButton('ไม่ทำ', _mpiApplied == false, () {
                _set(() => _mpiApplied = false);
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
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(
              // รวมเฉพาะรอบใส่ปุ๋ย — base=null ให้ rateOf นับเป็น 0
              totalFertilizerRate(
                null,
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
  );

  /// การ์ดใส่ปุ๋ยอินทรีย์ — ชนิดปุ๋ยจาก /meta/options + อัตรา + วันที่
  Widget _organicCard() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.grey.shade400, width: 1.5),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _cardHeader('ใส่ปุ๋ยอินทรีย์ (>500 กก/ไร่)'),
        _optRow('ชนิดปุ๋ย', _organicType, 'เลือก', () async {
          // ตัวเลือกจาก backend — โหลดไม่สำเร็จ/ว่างแจ้งเตือน
          FormOptions opts;
          try {
            opts = await _optionsFut;
          } catch (_) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('โหลดตัวเลือกไม่สำเร็จ')),
            );
            return;
          }
          if (opts.organicFertilizerTypes.isEmpty) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('ยังไม่มีตัวเลือกชนิดปุ๋ย')),
            );
            return;
          }
          if (!mounted) return;
          final idx = await showOptionPopup(
            context,
            title: 'ชนิดปุ๋ย',
            labels: opts.organicFertilizerTypes,
            selectedIndex: _organicType == null
                ? null
                : opts.organicFertilizerTypes.indexOf(_organicType!),
            searchHint: 'ค้นหาชนิดปุ๋ย',
          );
          if (idx != null) {
            _set(() => _organicType = opts.organicFertilizerTypes[idx]);
          }
        }),
        _inputRow('อัตรา(กก./ไร่)', _organicRateCtrl, unit: 'กก./ไร่'),
        _optRow(
          'วันที่ใส่',
          _organicDate == null
              ? null
              : _ActivityDetailViewState._fmtThai(_organicDate!),
          'เลือกวันที่',
          () => _pickAnyDate(_organicDate, (d) => _organicDate = d),
          icon: Icons.calendar_today,
        ),
      ],
    ),
  );

  /// การ์ดใส่โดโลไมท์ — อัตรา + วันที่
  Widget _dolomiteCard() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.grey.shade400, width: 1.5),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _cardHeader('ใส่โดโลไมท์ (50 - 100 กก/ไร่)'),
        _inputRow('อัตรา(กก./ไร่)', _dolomiteRateCtrl, unit: 'กก./ไร่'),
        _optRow(
          'วันที่ใส่',
          _dolomiteDate == null
              ? null
              : _ActivityDetailViewState._fmtThai(_dolomiteDate!),
          'เลือกวันที่',
          () => _pickAnyDate(_dolomiteDate, (d) => _dolomiteDate = d),
          icon: Icons.calendar_today,
        ),
      ],
    ),
  );

  /// การ์ดคุมวัชพืช — มี/ไม่มีวัชพืช
  Widget _weedCard() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.grey.shade400, width: 1.5),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _cardHeader('คุมวัชพืช ต้องไม่มีวัชพืช'),
        Row(
          children: [
            Expanded(
              child: _mpiButton(
                'มีวัชพืช',
                _weedPresent == true,
                () => _set(() => _weedPresent = true),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _mpiButton(
                'ไม่มีวัชพืช',
                _weedPresent == false,
                () => _set(() => _weedPresent = false),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  /// การ์ดไถระเบิดดินดาน — ทำแล้ว/ยังไม่ทำ + ความลึก
  Widget _subsoilCard() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.grey.shade400, width: 1.5),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _cardHeader('ไถระเบิดดินดาน (ลึก > 40 ซม.)'),
        _toggleRow(
          'ไถระเบิดดินดาน',
          'ทำแล้ว',
          'ยังไม่ทำ',
          _subsoiled,
          (v) => _set(() => _subsoiled = v),
        ),
        _inputRow('ความลึก(ซม.)', _subsoilDepthCtrl, unit: 'ซม.'),
      ],
    ),
  );

  /// การ์ดโรค — มี/ไม่มี + ชนิดโรค + ระบาด% + จัดการแล้ว/ยัง
  Widget _diseaseCard() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.grey.shade400, width: 1.5),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _cardHeader('โรค'),
        _toggleRow(
          'โรค',
          'มีโรค',
          'ไม่มีโรค',
          _diseasePresent,
          (v) => _set(() => _diseasePresent = v),
        ),
        _optRow('เลือกชนิดโรค', _diseaseType, 'เลือก', () async {
          // ชนิดโรคจาก backend — โหลดไม่สำเร็จ/ว่างแจ้งเตือน
          FormOptions opts;
          try {
            opts = await _optionsFut;
          } catch (_) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('โหลดตัวเลือกไม่สำเร็จ')),
            );
            return;
          }
          if (opts.diseaseTypes.isEmpty) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('ยังไม่มีตัวเลือกชนิดโรค')),
            );
            return;
          }
          if (!mounted) return;
          final idx = await showOptionPopup(
            context,
            title: 'เลือกชนิดโรค',
            labels: opts.diseaseTypes,
            selectedIndex: _diseaseType == null
                ? null
                : opts.diseaseTypes.indexOf(_diseaseType!),
            searchHint: 'ค้นหาชนิดโรค',
          );
          if (idx != null) {
            _set(() => _diseaseType = opts.diseaseTypes[idx]);
          }
        }),
        _inputRow('ระบาด (%)', _diseaseSpreadCtrl, unit: '%'),
        _toggleRow(
          'การจัดการโรค',
          'จัดการแล้ว',
          'ยังไม่จัดการ',
          _diseaseManaged,
          (v) => _set(() => _diseaseManaged = v),
          reversed: true,
        ),
      ],
    ),
  );

  /// การ์ดแมลง — มี/ไม่มี + ชนิดแมลง + ระบาด% + เบียน% + จัดการ
  Widget _pestCard() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.grey.shade400, width: 1.5),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _cardHeader('แมลง'),
        _toggleRow(
          'แมลง',
          'มีแมลง',
          'ไม่มีแมลง',
          _pestPresent,
          (v) => _set(() => _pestPresent = v),
        ),
        _optRow('เลือกชนิดแมลง', _pestType, 'เลือกรายการ', () async {
          FormOptions opts;
          try {
            opts = await _optionsFut;
          } catch (_) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('โหลดตัวเลือกไม่สำเร็จ')),
            );
            return;
          }
          if (opts.pestTypes.isEmpty) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('ยังไม่มีตัวเลือกชนิดแมลง')),
            );
            return;
          }
          if (!mounted) return;
          final idx = await showOptionPopup(
            context,
            title: 'เลือกชนิดแมลง',
            labels: opts.pestTypes,
            selectedIndex: _pestType == null
                ? null
                : opts.pestTypes.indexOf(_pestType!),
            searchHint: 'ค้นหาชนิดแมลง',
          );
          if (idx != null) {
            _set(() => _pestType = opts.pestTypes[idx]);
          }
        }),
        _inputRow('ระบาด (%)', _pestSpreadCtrl, unit: '%'),
        _inputRow('เบียน (%)', _pestDamageCtrl, unit: '%'),
        _toggleRow(
          'การจัดการแมลง',
          'จัดการแล้ว',
          'ยังไม่จัดการ',
          _pestManaged,
          (v) => _set(() => _pestManaged = v),
          reversed: true,
        ),
      ],
    ),
  );

  /// การ์ดพูนโคน — ทำ/ไม่ทำ
  Widget _hillCard() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.grey.shade400, width: 1.5),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _cardHeader('พูนโคน'),
        _toggleRow(
          'พูนโคน',
          'ทำ',
          'ไม่ทำ',
          _hilled,
          (v) => _set(() => _hilled = v),
        ),
      ],
    ),
  );

  /// การ์ดการงอก — เลือกเปอร์เซ็นต์งอก
  Widget _germCard() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.grey.shade400, width: 1.5),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _cardHeader('การงอก'),
        // ช่องตัวเลข+หน่วยแบบเดียวกับฟิลด์อื่นในหน้านี้
        _inputRow('เปอร์เซ็นต์งอก', _germCtrl, unit: '%'),
      ],
    ),
  );

  /// การ์ดเลือกกลุ่มตัดอ้อย — เลือกชาวไร่จาก backend
  Widget _harvestGroupCard() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.grey.shade400, width: 1.5),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _cardHeader('เลือกกลุ่มตัดอ้อย'),
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () async {
            List<FarmerRef> farmers;
            try {
              farmers = _farmers ??= await widget.vm.loadFarmers();
            } catch (_) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('โหลดรายชื่อไม่สำเร็จ')),
              );
              return;
            }
            if (farmers.isEmpty) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('ไม่มีรายชื่อชาวไร่')),
              );
              return;
            }
            if (!mounted) return;
            final idx = await showOptionPopup(
              context,
              title: 'เลือกกลุ่มตัดอ้อย',
              labels: [for (final f in farmers) '[${f.id}] ${f.name}'],
              // indexWhere คืน -1 เมื่อชาวไร่ที่เลือกไม่อยู่ใน list
              // (ตกหล่น/เปลี่ยนรายชื่อ) — ส่ง null ไม่ใช่ -1
              selectedIndex: _harvestGroupFarmer == null
                  ? null
                  : () {
                      final i = farmers.indexWhere(
                        (f) => f.id == _harvestGroupFarmer!.id,
                      );
                      return i < 0 ? null : i;
                    }(),
              searchHint: 'ค้นหาชาวไร่',
            );
            if (idx != null) {
              _set(() => _harvestGroupFarmer = farmers[idx]);
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
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
                const Icon(Iconsax.people, size: 24, color: Colors.black45),
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
  );

  /// การ์ดสูญเสียในแปลง — สาเหตุ + ไร่ + ประเมิน + ตันรวม(คำนวณ)
  Widget _lossCard() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.grey.shade400, width: 1.5),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _cardHeader('สูญเสียในแปลง'),
        _optRow('เลือกสาเหตุ', _lossReason, 'เลือกรายการ', () async {
          FormOptions opts;
          try {
            opts = await _optionsFut;
          } catch (_) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('โหลดตัวเลือกไม่สำเร็จ')),
            );
            return;
          }
          if (opts.lossOptions.isEmpty) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('ยังไม่มีตัวเลือกสาเหตุ')),
            );
            return;
          }
          if (!mounted) return;
          final idx = await showOptionPopup(
            context,
            title: 'เลือกสาเหตุ',
            labels: opts.lossOptions,
            selectedIndex: _lossReason == null
                ? null
                : opts.lossOptions.indexOf(_lossReason!),
            searchHint: 'ค้นหาสาเหตุ',
          );
          if (idx != null) {
            _set(() => _lossReason = opts.lossOptions[idx]);
          }
        }),
        _inputRow('สูญเสียรวม(ไร่)', _lossAreaCtrl, unit: 'ไร่'),
        _inputRow('ประเมิน(ตัน/ไร่)', _yieldEstimateCtrl, unit: 'ตัน/ไร่'),
        _calcRow('ปริมาณตันรวม(ตัน)', _totalTons(), unit: 'ตัน'),
      ],
    ),
  );

  /// การ์ดสูญเสียจากการตัดและหักพันธุ์ — หักหลายช่อง +
  /// สาเหตุ + อ้อยเข้าหีบจริง(คำนวณ)
  Widget _cutLossCard() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.grey.shade400, width: 1.5),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _cardHeader('สูญเสียจากการตัด และหักพันธุ์'),
        _inputRow('หักตัดพันธุ์รวม (ตัน)', _cutVarietyCtrl, unit: 'ตัน'),
        _inputRow(
          'หักสูญเสียจากการตัด (กก./ไร่)',
          _cutLossKgCtrl,
          unit: 'กก./ไร่',
        ),
        _inputRow('หักสูญเสียจากการตัด (ตัน)', _cutLossTonCtrl, unit: 'ตัน'),
        _optRow(
          'เลือกสาเหตุ หักสูญเสีย',
          _cutLossReason,
          'เลือกรายการ',
          () async {
            FormOptions opts;
            try {
              opts = await _optionsFut;
            } catch (_) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('โหลดตัวเลือกไม่สำเร็จ')),
              );
              return;
            }
            if (opts.lossOptions.isEmpty) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('ยังไม่มีตัวเลือกสาเหตุ')),
              );
              return;
            }
            if (!mounted) return;
            final idx = await showOptionPopup(
              context,
              title: 'เลือกสาเหตุ หักสูญเสีย',
              labels: opts.lossOptions,
              selectedIndex: _cutLossReason == null
                  ? null
                  : opts.lossOptions.indexOf(_cutLossReason!),
              searchHint: 'ค้นหาสาเหตุ',
            );
            if (idx != null) {
              _set(() => _cutLossReason = opts.lossOptions[idx]);
            }
          },
        ),
        _calcRow(
          'ปริมาณอ้อยเข้าหีบจริง(ตัน)\n(ตันรวม−หักสูญเสียรวม)',
          _actualTons(),
          unit: 'ตัน',
        ),
      ],
    ),
  );

  /// อ้อยพันธุ์ — checkbox + รายละเอียด
  Widget _seedCaneCard() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.grey.shade400, width: 1.5),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _cardHeader('อ้อยพันธุ์'),
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _set(() => _seedCane = !_seedCane),
          child: Row(
            children: [
              Checkbox(
                value: _seedCane,
                activeColor: AppColors.green,
                visualDensity: VisualDensity.compact,
                onChanged: (v) => _set(() => _seedCane = v ?? false),
              ),
              const Expanded(
                child: Text(
                  'อ้อยพันธุ์',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.green,
                  ),
                ),
              ),
            ],
          ),
        ),
        const Text(
          'เลือกหากแปลงนี้เหมาะสมเป็นอ้อยพันธุ์',
          style: TextStyle(fontSize: 15, color: Colors.black54),
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
  );

  /// ข้อเสนอแนะ / ตรวจสอบ — พิมพ์อิสระหลายบรรทัด
  Widget _suggestionCard() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.grey.shade400, width: 1.5),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _cardHeader('ข้อเสนอแนะ / ตรวจสอบ'),
        SizedBox(
          height: 96,
          child: ValueListenableBuilder<TextEditingValue>(
            valueListenable: _suggestionCtrl,
            // hint วาดเองตรงกลาง — hintText ของ multiline ติดบนเสมอ
            builder: (_, v, _) => Stack(
              alignment: Alignment.center,
              children: [
                TextField(
                  textAlign: TextAlign.start,
                  textAlignVertical: TextAlignVertical.top,
                  controller: _suggestionCtrl,
                  expands: true,
                  maxLines: null,
                  style: const TextStyle(fontSize: 16),
                  decoration: _ActivityDetailViewState._boxDeco(
                    '',
                    filled: v.text.trim().isNotEmpty,
                  ),
                ),
                if (v.text.isEmpty)
                  const IgnorePointer(
                    child: Text(
                      'กรุณากรอกข้อเสนอแนะ',
                      style: TextStyle(fontSize: 16, color: Colors.black38),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  /// ภาพถ่าย — รูปที่ถ่ายมา + เพิ่ม/ลบได้สูงสุด 3 ใบ
  Widget _photosCard() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.grey.shade400, width: 1.5),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _cardHeader('ภาพถ่าย')),
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
                      onTap: () => _set(() => _photos.removeAt(i)),
                      child: const CircleAvatar(
                        radius: 13,
                        backgroundColor: Colors.white,
                        child: Icon(Icons.close, size: 18, color: Colors.red),
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
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    ),
  );
}

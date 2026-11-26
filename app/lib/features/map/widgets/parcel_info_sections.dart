part of 'parcel_info_sheet.dart';

/// section ย่อยของ _ParcelInfoSheetState — แยกออกจาก
/// parcel_info_sheet.dart เพราะไฟล์เดิมยาวกว่าพันบรรทัด;
/// extension เข้าถึง field/method private ได้เหมือนเดิม
extension _ParcelInfoSheetSections on _ParcelInfoSheetState {
  /// โหลด list + badge ใหม่หลังกลับจากหน้ากิจกรรม
  void _reloadActivities() => _set(() {
    _acts = widget.vm.activityDrafts();
    _unseen = widget.vm.unseenActivityCount();
  });

  /// stub ชั่วคราว — แตะแล้วบอกว่าปุ่มไหนถูกกด รอผู้ใช้นิยามการทำงานจริง
  void _todo(String label) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$label — ยังไม่เปิดใช้งาน')));
  }

  /// push หน้าเต็มจอ (รายละเอียด/เมนูแก้ไข) — บอกหน้าแผนที่พัก
  /// platform view ระหว่างเปิด แล้วรายงาน extent จริงคืนหลัง pop
  void _pushFullScreen(Widget page, {VoidCallback? onReturn}) {
    widget.onCovered?.call(true);
    Navigator.of(context)
        .push(MaterialPageRoute<Object>(builder: (_) => page))
        .then((saved) {
          if (!mounted) return;
          widget.onCovered?.call(_extent >= 0.99);
          if (saved != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(saved is String ? saved : 'บันทึกสำเร็จ')),
            );
          }
          onReturn?.call();
        });
  }

  /// เพิ่มเติม → push หน้ารายละเอียดเต็มจอ (แชร์ VM เดียวกัน —
  /// PATCH จากหน้าลูกแล้ว sheet/detail เห็นค่าใหม่ทันที)
  void _openDetail() => _pushFullScreen(ParcelDetailView(vm: widget.vm));

  /// นำทาง — เปิด Google Maps เส้นทางไปยังพิกัดกึ่งกลางแปลงที่บันทึกไว้
  /// google.navigation = turn-by-turn ในแอป Maps โดยตรง (Android);
  /// ไม่มีแอป → fallback https เปิดใน browser/chooser
  Future<void> _navigate() async {
    final c = widget.vm.parcel.center;
    final latLng = '${c.latitude},${c.longitude}';
    for (final raw in [
      'google.navigation:q=$latLng',
      'https://www.google.com/maps/dir/?api=1&destination=$latLng',
    ]) {
      try {
        if (await launchUrl(
          Uri.parse(raw),
          mode: LaunchMode.externalApplication,
        )) {
          return;
        }
      } catch (_) {
        // plugin channel ยังไม่ขึ้น (hot reload หลังเพิ่ม package)
        // → ลอง fallback ถัดไป
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ไม่สามารถเปิด Google Maps ได้')),
      );
    }
  }

  /// บ้านชาวไร่ — dialog ข้อมูลที่อยู่ที่เกี่ยวข้องจาก backend
  /// (หมู่บ้าน/ตำบล/อำเภอ/จังหวัด) เฉพาะฟิลด์ที่มีค่าจริง
  void _farmerHome() {
    final name = _ParcelInfoSheetState._str(_farmer?['displayName']);
    final rows = <(String, String)>[
      if (name != null) ('ชาวไร่', name),
      for (final (k, label) in const [
        ('village', 'หมู่บ้าน'),
        ('subdistrict', 'ตำบล'),
        ('district', 'อำเภอ'),
        ('province', 'จังหวัด'),
      ])
        if (_ParcelInfoSheetState._str(_meta[k]) != null) (label, _ParcelInfoSheetState._str(_meta[k])!),
    ];
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        icon: const Icon(Iconsax.home_2, color: AppColors.gold, size: 28),
        title: const Text('บ้านชาวไร่'),
        content: rows.isEmpty
            ? const Text('ยังไม่มีข้อมูลที่อยู่')
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final (label, value) in rows)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Text.rich(
                        TextSpan(
                          text: '$label : ',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                          children: [
                            TextSpan(
                              text: value,
                              style: const TextStyle(
                                fontWeight: FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
        // ปุ่มเต็มกว้างให้กดง่าย สไตล์เดียวกับ dialog แจ้งเตือนตัวอื่น
        actions: [
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('ปิด', style: TextStyle(fontSize: 17)),
            ),
          ),
        ],
      ),
    );
  }

  /// เบอร์โทร — เด้ง dialer พร้อมเบอร์ที่บันทึกไว้ (farmer.phone /
  /// meta.phone… — schema ยังไม่มีฟิลด์นี้ แสดงข้อความแทนจนกว่า
  /// backend จะมี)
  Future<void> _call() async {
    final phone =
        _ParcelInfoSheetState._str(_farmer?['phone']) ??
        _ParcelInfoSheetState._str(_meta['phone']) ??
        _ParcelInfoSheetState._str(_meta['farmerPhone']) ??
        _ParcelInfoSheetState._str(_meta['tel']);
    if (phone == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ไม่มีเบอร์โทรที่บันทึกไว้')),
      );
      return;
    }
    var ok = false;
    try {
      ok = await launchUrl(
        Uri.parse('tel:$phone'),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {}
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ไม่สามารถเปิดแอปโทรศัพท์ได้')),
      );
    }
  }

  /// แถวข้อมูลในตาราง — label ซ้ายเทา / value ขวา (highlight = ฟ้า)
  Widget _infoRow((String, String?, bool) row, bool shaded) {
    return Container(
      color: shaded ? const Color(0xFFF6F6F6) : Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Text(
              row.$1,
              style: const TextStyle(fontSize: 16, color: Colors.black87),
            ),
          ),
          Expanded(
            flex: 7,
            child: Text(
              row.$2 == null || row.$2!.isEmpty ? '—' : row.$2!,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: row.$3 ? AppColors.sky : Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// กระเบื้องเมนู — สี่เหลี่ยมขาวมน + icon สี + label ใต้
  Widget _menuTile(
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.grey.shade200),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Icon(icon, color: color, size: 34),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }

  /// การ์ดกิจกรรมแถวเดียว — leading icon + title/subtitle + trailing
  Widget _actionCard({
    required Color color,
    required Widget leading,
    required String title,
    String? subtitle,
    Color titleColor = Colors.black87,
    Color subtitleColor = Colors.black45,
    Widget? trailing,
    Widget? titleTrailing,
    BoxBorder? border,
    VoidCallback? onTap,
    int? badgeCount,
  }) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          decoration: BoxDecoration(
            border: border,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              if (badgeCount != null && badgeCount > 0)
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    leading,
                    Positioned(top: -6, right: -6, child: _badge(badgeCount)),
                  ],
                )
              else
                leading,
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: titleColor,
                            ),
                          ),
                        ),
                        // widget ท้ายแถว title (เช่น badge สถานะ —
                        // อยู่บรรทัดเดียวกับ title subtitle ยืดเต็ม)
                        ?titleTrailing,
                      ],
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle,
                        style: TextStyle(fontSize: 15, color: subtitleColor),
                      ),
                  ],
                ),
              ),
              // trailing เอาเท่าขนาดจริง — title ได้พื้นที่เหลือ
              // ทั้งหมด (widget trailing ที่ยาวต้อง cap ขนาดเอง)
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }

  /// กล่อง icon มุมมนพื้นสี — leading ของการ์ดขาว
  /// วงกลมแดงบอกจำนวนรายการ (ติดมุมขวาบนของไอคอน)
  Widget _badge(int count) => Container(
    constraints: const BoxConstraints(minWidth: 20),
    padding: const EdgeInsets.all(4),
    decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
    child: Text(
      '$count',
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.bold,
        color: Colors.white,
        height: 1,
      ),
    ),
  );

  Widget _iconBox(Color bg, IconData icon) {
    return Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: Colors.white, size: 28),
    );
  }

  /// เปิด sheet ฟอร์มจุดเสี่ยง — บันทึกสำเร็จ refresh preview +
  /// แจ้ง snackbar; [type] = ประเภทที่เลือกมาจาก chip บนการ์ด
  Future<void> _openRiskSheet({String? type}) async {
    final saved = await showRiskPointSheet(
      context,
      vm: widget.vm,
      initialType: type,
    );
    if (!mounted) return;
    _set(() {
      _riskPoint = widget.vm.riskPoint();
    });
    if (saved != null) {
      showResultDialog(
        context,
        success: true,
        title: 'บันทึกจุดเสี่ยงภัยแล้ว',
      );
    }
  }

  /// เปิด sheet อัปเดตสถานะแปลงตัด — บันทึกสำเร็จขึ้น snackbar
  Future<void> _openCutSheet() async {
    final saved = await showCutStatusSheet(context, vm: widget.vm);
    if (!mounted) return;
    if (saved == true) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('บันทึกสถานะแปลงตัดแล้ว')));
    }
  }

  /// เปิด sheet โครงการส่งเสริม — บันทึกสำเร็จขึ้น snackbar
  Future<void> _openProjectSheet() async {
    final saved = await showPlotProjectSheet(context, vm: widget.vm);
    if (!mounted) return;
    if (saved == true) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('บันทึกข้อมูลโครงการแล้ว')));
    }
  }

  /// chip preview ในการ์ด — แตะเลือกประเภทแล้วเปิด sheet ฟอร์ม
  /// พร้อมประเภทนั้น; ตัวที่บันทึกไว้ = พื้นเข้ม + ขอบสีชัด
  Widget _riskPreviewChip(String label, bool selected) {
    final (icon, bg, fg) = riskChipStyle(label);
    // ตัวที่ไม่ได้เลือก = เทาหมด ไอคอนยังตามประเภทเดิม
    final effBg = selected ? bg : Colors.grey.shade100;
    final effFg = selected ? fg : Colors.black38;
    return Expanded(
      child: GestureDetector(
        onTap: () => _openRiskSheet(type: label),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            color: effBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? fg : Colors.grey.shade300,
              width: selected ? 2.2 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 21, color: effFg),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: effFg,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

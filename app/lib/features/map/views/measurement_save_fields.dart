part of 'measurement_save_view.dart';

/// Widget ช่องฟอร์มทั้งหมดของหน้าบันทึกแปลง — แยกออกจาก
/// measurement_save_view.dart เพราะไฟล์เดิมยาว ~1,500 บรรทัด;
/// extension บน state เดิม เข้าถึง controller/field private
/// ได้เหมือนเดิมทุกอย่าง (part ไฟล์เดียวกัน library เดียวกัน)
/// กรอบช่องย่อยในการ์ด — ช่องพิมพ์/ช่องเลือกดูเป็น "ช่อง" ชัด
/// พื้นเทาอ่อน + ขอบมน เหมือน input ทั่วไป (library-level เพราะ
/// ใช้ทั้งใน fields part และ build ของไฟล์หลัก)
final BoxDecoration _innerBoxDeco = BoxDecoration(
  color: Colors.grey.shade50,
  borderRadius: BorderRadius.circular(10),
  border: Border.all(color: Colors.black12),
);

extension _MeasurementSaveFields on _MeasurementSaveState {
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
    for (final f in await _farmers()) PickerItem(code: f.id, name: f.name),
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
          _set(() {
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



  /// master data — fetch ครั้งเดียวต่อหน้า แชร์ให้ทุก dropdown
  /// (เดิมทุกครั้งที่แตะ picker ยิง /meta/options ใหม่ทั้ง request);
  /// ล้มเหลวเคลียร์ cache ให้แตะ retry ได้ ไม่ค้างเป็น error ตลอดหน้า
  Future<FormOptions> _options() {
    final c = _optionsCache;
    if (c != null) return c;
    final f = widget.options();
    f.catchError((_) {
      _optionsCache = null;
      return const FormOptions();
    });
    return _optionsCache = f;
  }

  Future<List<FarmerRef>> _farmers() {
    final c = _farmersCache;
    if (c != null) return c;
    final f = widget.farmers();
    f.catchError((_) {
      _farmersCache = null;
      return const <FarmerRef>[];
    });
    return _farmersCache = f;
  }

  /// Pulls one option list out of the backend-supplied [FormOptions].
  Future<List<String>> _pick(List<String> Function(FormOptions) f) =>
      _options().then(f);

  /// เลขแปลงปีก่อน — existing plots from the backend (code = plot id).
  Future<List<PickerItem>> _prevPlotItems() async => [
    for (final p in (await _options()).prevPlots)
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
              style: const TextStyle(fontSize: 16, color: Colors.black54),
            ),
          ),
      ],
    ),
  );


  /// decoration ของช่องพิมพ์ในการ์ด — กรอบเดียวกับ _innerBox
  // hint บอกชื่อช่องเสมอ — เดิมทุกช่อง "กรอกข้อมูล" เหมือนกัน
  // หมด มองไม่ออกว่าช่องไหนคืออะไร
  static InputDecoration _innerDeco(String label, {bool hideHint = false}) =>
      InputDecoration(
        isDense: true,
        filled: true,
        fillColor: const Color(0xFFFAFAFA), // grey.shade50 (const)
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        hintText: hideHint ? null : 'กรอก$label',
        hintStyle: const TextStyle(fontSize: 17, color: Colors.black38),
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
    bool center = false,
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
      // center → hint ตัวเองวาดตรงกลางเป็น overlay (hintText ของ
      // multiline ติดบนเสมอ textAlignVertical ขยับไม่ได้) แสดงเฉพาะ
      // ตอนช่องว่าง — ตัวพิมพ์จริงชิดซ้ายเหมือนช่องอื่น
      child: Stack(
        alignment: Alignment.center,
        children: [
          TextFormField(
            textAlign: TextAlign.start,
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
            decoration: _innerDeco(label, hideHint: center),
          ),
          // ต้องวางหลัง TextField — พื้นเทาของช่องทึบ ถ้าอยู่ล่าง
          // จะโดนทับจนมองไม่เห็น
          if (center && value.text.isEmpty)
            const IgnorePointer(
              child: Text(
                'กรุณากรอกข้อเสนอแนะ',
                style: TextStyle(fontSize: 17, color: Colors.black38),
              ),
            ),
        ],
      ),
    ),
  );
}

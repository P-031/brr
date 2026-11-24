import 'package:flutter/material.dart';

import 'package:brr/core/theme/app_theme.dart';
import 'package:brr/core/widgets/digit_formatter.dart';

/// ช่องตัวเลข + หน่วยติดกับตัวเลข — คู่ตัวเลข+หน่วยอยู่กลางช่อง
/// (กรอบเทา→เขียวเมื่อมีข้อมูล / ทองตอนโฟกัส เหมือน _boxDeco)
class UnitField extends StatefulWidget {
  const UnitField({
    super.key,
    required this.controller,
    required this.unit,
    this.hint = '0.0',
    this.onChanged,
  });

  final TextEditingController controller;
  final String unit;
  final String hint;
  final VoidCallback? onChanged;

  @override
  State<UnitField> createState() => _UnitFieldState();
}

class _UnitFieldState extends State<UnitField> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_refresh);
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filled = widget.controller.text.trim().isNotEmpty;
    final borderColor = _focus.hasFocus
        ? AppColors.gold
        : filled
        ? AppColors.green
        : Colors.grey.shade300;
    // แตะที่ไหนในกรอบก็โฟกัสช่องพิมพ์ (พื้นที่แตะจริงของช่อง
    // หดตามความกว้างข้อความเพื่อจัดกลาง)
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _focus.requestFocus,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: borderColor,
            width: _focus.hasFocus ? 2 : (filled ? 1.5 : 1),
          ),
        ),
        child: _centeredPair(context),
      ),
    );
  }

  Widget _centeredPair(BuildContext context) => LayoutBuilder(
    builder: (context, cst) {
      // วัดความกว้างข้อความ+หน่วยจริง → คู่นี้อยู่กลางช่องเสมอ
      const textStyle = TextStyle(fontSize: 18);
      const unitStyle = TextStyle(fontSize: 15, color: Colors.black87);
      final hasText = widget.controller.text.isNotEmpty;
      final display = hasText ? widget.controller.text : widget.hint;
      final textW =
          (TextPainter(
            text: TextSpan(text: display, style: textStyle),
            textDirection: TextDirection.ltr,
            maxLines: 1,
          )..layout()).width +
          8;
      // หน่วยโชว์เฉพาะตอนมีข้อความ — ช่องว่างเหลือแค่ hint
      final unitW = hasText
          ? (TextPainter(
              text: TextSpan(text: ' ${widget.unit}', style: unitStyle),
              textDirection: TextDirection.ltr,
              maxLines: 1,
            )..layout()).width
          : 0.0;
      // เผื่อ 2px กัน overflow จากการปัดความกว้างตัวหนังสือ
      final maxFieldW = (cst.maxWidth - unitW - 2).clamp(0.0, double.infinity);
      return Align(
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxFieldW),
              child: SizedBox(
                // ช่องว่างเอากว้างเต็ม — hint ภาษาไทย render กว้างกว่าที่
                // TextPainter วัดไว้ ล็อกกว้างตาม hint แล้วถูกตัด
                width: widget.controller.text.isEmpty ? maxFieldW : textW,
                child: TextField(
                  controller: widget.controller,
                  focusNode: _focus,
                  // ชิดซ้ายทั้งแอป — หน่วยตามหลังตัวเลขอยู่แล้ว
                  textAlign: TextAlign.start,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: const [DigitFormatter(decimal: true)],
                  style: textStyle,
                  decoration: InputDecoration.collapsed(
                    hintText: widget.hint,
                    // fontSize ต้องตรง textStyle ที่ใช้วัดความกว้าง
                    // ไม่งั้น hint ยาวกว่ากล่องที่เผื่อไว้แล้วถูกตัด
                    hintStyle: const TextStyle(
                      fontSize: 15,
                      color: Colors.black38,
                    ),
                  ),
                  onChanged: (_) {
                    _refresh();
                    widget.onChanged?.call();
                  },
                ),
              ),
            ),
            if (hasText) Text(' ${widget.unit}', style: unitStyle),
          ],
        ),
      );
    },
  );
}

import 'package:flutter/material.dart';

/// ปุ่มปิดมุมขวาบนของ bottom sheet — วงกลมเทาเป้าแตะ ~48dp มองเห็น
/// ชัดว่าเป็นปุ่ม (IconButton เดาๆ icon เล็ก+ชิดขอบจอ นิ้วแตะพลาดบ่อย)
class SheetCloseButton extends StatelessWidget {
  const SheetCloseButton({super.key, this.onTap});

  /// default = pop route ปัจจุบัน (ปิด sheet)
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.06),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap ?? () => Navigator.of(context).pop(),
        child: const Padding(
          padding: EdgeInsets.all(11),
          child: Icon(Icons.close, size: 26, color: Colors.black54),
        ),
      ),
    );
  }
}

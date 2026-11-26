import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'package:brr/core/theme/app_theme.dart';

/// AppBar มาตรฐานของแอป — พื้นเขียว ชิดซ้าย (titleSpacing 0)
/// หัวข้อหนา 19; `subtitle` ใส่ widget บรรทัดรองใต้หัวข้อได้
/// (เช่น caneType ในหน้าบันทึกกิจกรรม)
PreferredSizeWidget brrAppBar(
  String title, {
  List<Widget>? actions,
  Widget? subtitle,
}) => AppBar(
  backgroundColor: AppColors.green,
  // รูปไร่อ้อยเต็มแถบ — เบลอเบา + ทับดำบาง ให้หัวข้อขาวอ่าน
  // ง่ายแต่ยังเห็นลายใบอ้อย (Pexels free photo)
  flexibleSpace: const _AppBarBackdrop(child: SizedBox.expand()),
  titleSpacing: 0,
  title: subtitle == null
      ? Text(
          title,
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
        )
      : Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
            ),
            DefaultTextStyle(
              style: const TextStyle(fontSize: 14, color: Colors.white70),
              child: subtitle,
            ),
          ],
        ),
  actions: actions,
);

/// พื้นหลังรูป app bar (เบลอ + ทับดำบาง) — ใช้กับหน้าที่สร้าง
/// header เองไม่ผ่าน AppBar เช่น ParcelStatusView; [child]
/// คือเนื้อหาที่วางเหนือรูป (ไม่ถูกเบลอ)
class _AppBarBackdrop extends StatelessWidget {
  const _AppBarBackdrop({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned.fill(
        child: ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 2.2, sigmaY: 2.2),
          child: Container(
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: AssetImage(
                  'assets/images/appbar_new_18780840.jpg',
                ),
                fit: BoxFit.cover,
                // มุมโดรนเห็นแปลงเป็นบล็อกเรขาคณิต — กลางรูป
                // เขียวเข้มพอดี
                alignment: Alignment(0, 0.1),
              ),
            ),
            child: Container(
              color: Colors.black.withValues(alpha: 0.28),
            ),
          ),
        ),
      ),
      child,
    ],
  );
}

/// หน้าที่มี header สร้างเอง (ไม่ใช้ AppBar) — wrap เนื้อหา
/// header ด้วยตัวนี้ให้ได้พื้นหลังรูปชุดเดียวกับ app bar
/// ทั้งแอป
Widget brrHeaderBackdrop({required Widget child}) =>
    _AppBarBackdrop(child: child);

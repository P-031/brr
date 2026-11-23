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

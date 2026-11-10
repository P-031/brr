import 'dart:io';

import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';

import 'package:brr/core/theme/app_theme.dart';
import 'package:brr/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:brr/features/menu/views/change_password_view.dart';
import 'package:brr/features/menu/views/edit_profile_view.dart';

/// เมนู — profile header, settings list, and the only place with a
/// sign-out action. Items are backend-ready placeholders for now.
class MenuView extends StatelessWidget {
  const MenuView({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<AuthViewModel>();
    final user = vm.user;
    return SafeArea(
      child: Column(
        children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 34,
                backgroundColor: AppColors.gold,
                child: CircleAvatar(
                  radius: 32,
                  backgroundColor: Colors.white,
                backgroundImage: user?.photoPath != null
                    ? FileImage(File(user!.photoPath!))
                    : null,
                child: user?.photoPath == null
                    ? Text(
                        (user?.displayName.isNotEmpty == true
                                ? user!.displayName[0]
                                : '?')
                            .toUpperCase(),
                        style: const TextStyle(
                          color: AppColors.green,
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                    : null,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user?.displayName ?? 'ผู้ใช้',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _badge(user?.email ?? '-'),
                        const SizedBox(width: 6),
                        _badge('Zone: -'),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Card(
            child: Column(
              children: [
                _item(
                  context,
                  Iconsax.user,
                  'แก้ไขโปรไฟล์',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const EditProfileView(),
                    ),
                  ),
                ),
                _item(context, Iconsax.setting_2, 'ตั้งค่า'),
                _item(
                  context,
                  Iconsax.lock,
                  'เปลี่ยนรหัสผ่าน',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ChangePasswordView(),
                    ),
                  ),
                ),
                _item(
                  context,
                  Iconsax.message,
                  'เชื่อมต่อ Line',
                  iconColor: AppColors.greenLight,
                  divider: false,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Card(
            child: ListTile(
              leading: const Icon(Iconsax.logout, color: Colors.red),
              title: const Text(
                'ออกจากระบบ',
                style: TextStyle(color: Colors.red, fontSize: 16),
              ),
              onTap: vm.signOut,
            ),
          ),
        ),
        const Spacer(),
        const Padding(
          padding: EdgeInsets.only(bottom: 16),
          child: Text(
            'BRR เวอร์ชั่น 1.0.0',
            style: TextStyle(color: Colors.black38, fontSize: 13),
          ),
        ),
        ],
      ),
    );
  }

  Widget _badge(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: AppColors.goldLight,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      text,
      style: const TextStyle(fontSize: 12, color: Colors.black54),
    ),
  );

  Widget _item(
    BuildContext context,
    IconData icon,
    String label, {
    Color iconColor = AppColors.green,
    bool divider = true,
    VoidCallback? onTap,
  }) {
    return Column(
      children: [
        ListTile(
          leading: Icon(icon, color: iconColor),
          title: Text(label, style: const TextStyle(fontSize: 15)),
          onTap:
              onTap ??
              () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('ยังไม่เปิดใช้งาน')),
              ),
        ),
        if (divider) const Divider(height: 1, indent: 16, endIndent: 16),
      ],
    );
  }
}

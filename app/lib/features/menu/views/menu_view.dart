import 'dart:io';

import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';

import 'package:brr/core/config/app_info.dart';
import 'package:brr/core/theme/app_theme.dart';
import 'package:brr/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:brr/features/map/viewmodels/failed_edits_viewmodel.dart';
import 'package:brr/features/map/views/failed_edits_view.dart';
import 'package:brr/features/menu/views/change_password_view.dart';
import 'package:brr/features/menu/views/edit_profile_view.dart';
import 'package:brr/features/settings/views/settings_view.dart';

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
                    onBackgroundImageError: user?.photoPath != null
                        ? (_, _) {}
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
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          _badge(user?.email ?? '-'),
                          // เขตจาก claim ของ token — แสดงเฉพาะตอน
                          // backend/Keycloak ส่งมาจริง
                          if (user?.zone != null) ...[
                            const SizedBox(width: 6),
                            _badge('Zone: ${user!.zone}'),
                          ],
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
                  _item(
                    context,
                    Iconsax.setting_2,
                    'ตั้งค่า',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SettingsView()),
                    ),
                  ),
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
                  ),
                  const _FailedEditsTile(),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              child: ListTile(
                leading: const Icon(Icons.logout, color: Colors.red),
                title: const Text(
                  'ออกจากระบบ',
                  style: TextStyle(color: Colors.red, fontSize: 18),
                ),
                onTap: () async {
                  final ok = await _confirmSignOut(context);
                  if (ok == true) vm.signOut();
                },
              ),
            ),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              'BRR เวอร์ชั่น ${AppInfo.version}',
              style: const TextStyle(color: Colors.black38, fontSize: 14),
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
      style: const TextStyle(fontSize: 14, color: Colors.black54),
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
          title: Text(label, style: const TextStyle(fontSize: 18)),
          onTap:
              onTap ??
              () => ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('ยังไม่เปิดใช้งาน'))),
        ),
        if (divider) const Divider(height: 1, indent: 16, endIndent: 16),
      ],
    );
  }
}

/// เมนู "การแก้ไขที่ส่งไม่สำเร็จ" — badge นับรายการ PATCH ที่
/// server ปฏิเสธค้างในเครื่อง; stateful เพื่อ refresh count
/// หลังผู้ใช้กลับจากหน้ารายการ (retry/discard เปลี่ยนจำนวน)
class _FailedEditsTile extends StatefulWidget {
  const _FailedEditsTile();

  @override
  State<_FailedEditsTile> createState() => _FailedEditsTileState();
}

class _FailedEditsTileState extends State<_FailedEditsTile> {
  @override
  void initState() {
    super.initState();
    _seed();
  }

  /// seed จำนวนจาก prefs เข้า notifier (ค่า persist ข้ามรอบแอป)
  /// — failedCountFor เขียนกลับเข้า countListenable เอง
  Future<void> _seed() async {
    if (!mounted) return;
    await FailedEditsViewModel.failedCountFor(context);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: FailedEditsViewModel.countListenable,
      builder: (context, count, _) => ListTile(
        leading: Icon(
          Iconsax.warning_2,
          color: count > 0 ? Colors.orange : AppColors.green,
        ),
        title: const Text(
          'การแก้ไขที่ส่งไม่สำเร็จ',
          style: TextStyle(fontSize: 18),
        ),
        trailing: count > 0
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            : null,
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const FailedEditsView())),
      ),
    );
  }
}

/// ยืนยันก่อนออกจากระบบ — กันแตะผิดแล้วหลุดทันที
Future<bool?> _confirmSignOut(BuildContext context) => showDialog<bool>(
  context: context,
  builder: (ctx) => AlertDialog(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    // ลดระยะห่างขอบจอ → กรอบกว้างขึ้น (default 40 แคบไปบนจอเล็ก)
    insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
    title: const Text(
      'ออกจากระบบ?',
      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
      textAlign: TextAlign.center,
    ),
    titlePadding: const EdgeInsets.fromLTRB(24, 28, 24, 8),
    contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
    // ปุ่มกว้างเท่ากันเต็มแถว — actions row เดิมปุ่มไปชิดขอบขวา
    // บนจอแคบ ดูเบียด/ล้น; AlertDialog หดตามเนื้อหา เลยบังคับ
    // content กว้างเต็มที่กรอบจะยืดได้
    content: SizedBox(
      width: double.maxFinite,
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text(
                'ยกเลิก',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text(
                'ออกจากระบบ',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    ),
  ),
);

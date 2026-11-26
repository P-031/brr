import 'dart:io';

import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import 'package:brr/core/theme/app_theme.dart';
import 'package:brr/core/widgets/brr_app_bar.dart';
import 'package:brr/core/widgets/image_source_sheet.dart';
import 'package:brr/features/auth/viewmodels/auth_viewmodel.dart';

/// แก้ไขโปรไฟล์ — avatar, email, phone. Values are collected and
/// passed to [AuthViewModel.updateProfile]; the backend call is a
/// TODO once the API endpoint exists.
class EditProfileView extends StatefulWidget {
  const EditProfileView({super.key});

  @override
  State<EditProfileView> createState() => _EditProfileViewState();
}

class _EditProfileViewState extends State<EditProfileView> {
  late final TextEditingController _emailCtrl;
  late final TextEditingController _phoneCtrl;
  XFile? _photo;

  @override
  void initState() {
    super.initState();
    final u = context.read<AuthViewModel>().user;
    _emailCtrl = TextEditingController(text: u?.email ?? '');
    _phoneCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final source = await showImageSourceSheet(context);
    if (source == null) return;
    // pickImage throw ได้ (already_active / camera busy บนบางเครื่อง)
    try {
      final x = await ImagePicker().pickImage(source: source, maxWidth: 1024);
      if (x != null && mounted) setState(() => _photo = x);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('เลือกรูปไม่สำเร็จ')));
    }
  }

  Future<void> _save() async {
    await context.read<AuthViewModel>().updateProfile(
      email: _emailCtrl.text.trim(),
      phone: _phoneCtrl.text.trim(),
      photoPath: _photo?.path,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('บันทึกโปรไฟล์ในเครื่องแล้ว')));
    Navigator.pop(context);
  }

  /// ช่องกรอก — label แยกเหนือช่อง (pattern เดียวกับหน้า
  /// เปลี่ยนรหัสผ่าน) + icon นำหน้าในช่อง
  Widget _field(
    String label,
    TextEditingController ctrl, {
    required IconData icon,
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: ctrl,
          keyboardType: keyboardType,
          textAlign: TextAlign.start,
          style: const TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
          cursorColor: AppColors.gold,
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.grey.shade100,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 13,
            ),
            prefixIcon: Icon(icon),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(
                color: AppColors.gold,
                width: 2,
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthViewModel>().user;
    return Scaffold(
      appBar: brrAppBar('แก้ไขโปรไฟล์'),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: GestureDetector(
              onTap: _pickPhoto,
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 56,
                    backgroundColor: AppColors.gold,
                    child: CircleAvatar(
                      radius: 52,
                      backgroundColor: Colors.white,
                      backgroundImage: _photo != null
                          ? FileImage(File(_photo!.path))
                          : (user?.photoPath != null
                                ? FileImage(File(user!.photoPath!))
                                : null),
                      onBackgroundImageError:
                          _photo != null || user?.photoPath != null
                          ? (_, _) {}
                          : null,
                      child: _photo == null && user?.photoPath == null
                          ? Text(
                              (user?.displayName.isNotEmpty == true
                                      ? user!.displayName[0]
                                      : '?')
                                  .toUpperCase(),
                              style: const TextStyle(
                                color: AppColors.green,
                                fontSize: 38,
                                fontWeight: FontWeight.bold,
                              ),
                            )
                          : null,
                    ),
                  ),
                  const Positioned(
                    bottom: 0,
                    right: 0,
                    child: CircleAvatar(
                      radius: 16,
                      backgroundColor: AppColors.gold,
                      child: Icon(
                        Iconsax.camera,
                        size: 16,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Center(
            child: Text(
              'แตะเพื่อเปลี่ยนรูปโปรไฟล์',
              style: TextStyle(color: Colors.black45, fontSize: 13),
            ),
          ),
          const SizedBox(height: 28),
          _field(
            'อีเมล',
            _emailCtrl,
            icon: Iconsax.sms,
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 16),
          _field(
            'เบอร์โทร',
            _phoneCtrl,
            icon: Iconsax.call,
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 32),
          SizedBox(
            height: 50,
            child: FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Iconsax.save_2),
              label: const Text(
                'บันทึก',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

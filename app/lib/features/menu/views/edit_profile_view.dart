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
          TextFormField(
            textAlign: TextAlign.center,
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'อีเมล',
              prefixIcon: Icon(Iconsax.sms),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            textAlign: TextAlign.center,
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'เบอร์โทร',
              prefixIcon: Icon(Iconsax.call),
              border: OutlineInputBorder(),
            ),
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

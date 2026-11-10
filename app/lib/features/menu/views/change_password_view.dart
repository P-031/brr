import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';

import 'package:brr/core/theme/app_theme.dart';
import 'package:brr/features/auth/viewmodels/auth_viewmodel.dart';

/// เปลี่ยนรหัสผ่าน — old / new / confirm with per-field visibility
/// toggles. Backend-ready: posts to Keycloak once the flow is wired.
class ChangePasswordView extends StatefulWidget {
  const ChangePasswordView({super.key});

  @override
  State<ChangePasswordView> createState() => _ChangePasswordState();
}

class _ChangePasswordState extends State<ChangePasswordView> {
  final _formKey = GlobalKey<FormState>();
  final _oldCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _showOld = false;
  bool _showNew = false;
  bool _showConfirm = false;
  bool _busy = false;

  @override
  void dispose() {
    _oldCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  InputDecoration _deco(
    String label,
    bool show,
    VoidCallback toggle,
  ) => InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(fontSize: 16),
    prefixIcon: const Icon(Iconsax.lock, color: AppColors.green),
    suffixIcon: IconButton(
      icon: Icon(show ? Icons.visibility : Iconsax.eye_slash),
      onPressed: toggle,
    ),
    border: const OutlineInputBorder(),
  );

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    final err = await context.read<AuthViewModel>().changePassword(
      oldPassword: _oldCtrl.text,
      newPassword: _newCtrl.text,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(err ?? 'เปลี่ยนรหัสผ่านแล้ว')),
    );
    if (err == null) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('เปลี่ยนรหัสผ่าน')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextFormField(
              controller: _oldCtrl,
              obscureText: !_showOld,
              style: const TextStyle(fontSize: 17),
              decoration: _deco(
                'รหัสผ่านเดิม',
                _showOld,
                () => setState(() => _showOld = !_showOld),
              ),
              validator: (v) =>
                  (v == null || v.isEmpty) ? 'กรุณากรอกรหัสผ่านเดิม' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _newCtrl,
              obscureText: !_showNew,
              style: const TextStyle(fontSize: 17),
              decoration: _deco(
                'รหัสผ่านใหม่',
                _showNew,
                () => setState(() => _showNew = !_showNew),
              ),
              validator: (v) => (v == null || v.length < 6)
                  ? 'รหัสผ่านใหม่ต้องยาวอย่างน้อย 6 ตัว'
                  : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _confirmCtrl,
              obscureText: !_showConfirm,
              style: const TextStyle(fontSize: 17),
              decoration: _deco(
                'ยืนยันรหัสผ่านใหม่',
                _showConfirm,
                () => setState(() => _showConfirm = !_showConfirm),
              ),
              validator: (v) =>
                  v != _newCtrl.text ? 'รหัสผ่านใหม่ไม่ตรงกัน' : null,
            ),
            const SizedBox(height: 32),
            SizedBox(
              height: 50,
              child: FilledButton.icon(
                onPressed: _busy ? null : _save,
                icon: const Icon(Iconsax.refresh),
                label: Text(
                  _busy ? 'กำลังบันทึก…' : 'เปลี่ยนรหัสผ่าน',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

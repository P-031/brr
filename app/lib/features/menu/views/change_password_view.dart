import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';

import 'package:brr/core/theme/app_theme.dart';
import 'package:brr/core/widgets/brr_app_bar.dart';
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

  /// ช่องกรอกรหัส — label แยกเหนือช่อง (pattern เดียวกับฟอร์ม
  /// แก้ไขแปลง) + ปุ่มตา toggle ท้ายช่อง
  Widget _field(
    String label,
    TextEditingController ctrl, {
    required bool show,
    required VoidCallback toggle,
    required String? Function(String?) validator,
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
          obscureText: !show,
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
            suffixIcon: IconButton(
              icon: Icon(show ? Icons.visibility : Iconsax.eye_slash),
              onPressed: toggle,
            ),
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
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(
                color: AppColors.gold,
                width: 2,
              ),
            ),
          ),
          validator: validator,
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    final err = await context.read<AuthViewModel>().changePassword(
      oldPassword: _oldCtrl.text,
      newPassword: _newCtrl.text,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(err ?? 'เปลี่ยนรหัสผ่านแล้ว')));
    if (err == null) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: brrAppBar('เปลี่ยนรหัสผ่าน'),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _field(
              'รหัสผ่านเดิม',
              _oldCtrl,
              show: _showOld,
              toggle: () => setState(() => _showOld = !_showOld),
              validator: (v) =>
                  (v == null || v.isEmpty) ? 'กรุณากรอกรหัสผ่านเดิม' : null,
            ),
            const SizedBox(height: 16),
            _field(
              'รหัสผ่านใหม่',
              _newCtrl,
              show: _showNew,
              toggle: () => setState(() => _showNew = !_showNew),
              validator: (v) => (v == null || v.length < 6)
                  ? 'รหัสผ่านใหม่ต้องยาวอย่างน้อย 6 ตัว'
                  : null,
            ),
            const SizedBox(height: 16),
            _field(
              'ยืนยันรหัสผ่านใหม่',
              _confirmCtrl,
              show: _showConfirm,
              toggle: () => setState(() => _showConfirm = !_showConfirm),
              validator: (v) =>
                  v != _newCtrl.text ? 'รหัสผ่านใหม่ไม่ตรงกัน' : null,
            ),
            const SizedBox(height: 32),
            SizedBox(
              height: 50,
              child: FilledButton(
                onPressed: _busy ? null : _save,
                child: Text(
                  _busy ? 'กำลังบันทึก…' : 'เปลี่ยนรหัสผ่าน',
                  style: const TextStyle(
                    fontSize: 18,
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

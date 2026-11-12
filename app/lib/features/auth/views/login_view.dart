import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';

import 'package:brr/features/auth/models/saved_account.dart';
import 'package:brr/core/theme/app_theme.dart';
import 'package:brr/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:brr/features/auth/views/auth_scaffold.dart';

class LoginView extends StatefulWidget {
  const LoginView({super.key});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  final _formKey = GlobalKey<FormState>();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _userFocus = FocusNode();
  final _passFocus = FocusNode();
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    for (final node in [_userFocus, _passFocus]) {
      node.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    _userFocus.dispose();
    _passFocus.dispose();
    super.dispose();
  }

  Widget _animatedField({required bool focused, required Widget child}) {
    return AnimatedScale(
      scale: focused ? 1.04 : 1.0,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      child: child,
    );
  }

  InputDecoration _decoration({
    required String label,
    required IconData icon,
    Widget? suffix,
    bool hasError = false,
  }) {
    final error = Theme.of(context).colorScheme.error;
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      suffixIcon: suffix,
      filled: true,
      fillColor: Colors.white,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: hasError ? error : Colors.black26,
          width: hasError ? 2 : 1,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.gold, width: 2.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.gold, width: 2.5),
      ),
    );
  }

  void _submit(AuthViewModel vm) {
    if (_formKey.currentState?.validate() ?? false) {
      vm.signIn(_userCtrl.text.trim(), _passCtrl.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<AuthViewModel>();
    final scheme = Theme.of(context).colorScheme;
    return AuthScaffold(
      child: Card(
        elevation: 4,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.gold, width: 3),
                  ),
                  child: const CircleAvatar(
                    radius: 40,
                    backgroundColor: Colors.white,
                    child: Icon(
                      Iconsax.lock,
                      size: 40,
                      color: AppColors.green,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'BRR',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.green,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'เข้าสู่ระบบเพื่อใช้งานแอปพลิเคชัน',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                if (vm.savedAccounts.isNotEmpty) ...[
                  DropdownButtonFormField<SavedAccount>(
                    decoration: _decoration(
                      label:
                          'เลือกบัญชีที่บันทึกไว้ (${vm.savedAccounts.length})',
                      icon: Iconsax.people,
                    ),
                    items: [
                      for (final a in vm.savedAccounts)
                        DropdownMenuItem(
                          value: a,
                          child: Text('${a.displayName} (${a.username})'),
                        ),
                    ],
                    onChanged: vm.isBusy
                        ? null
                        : (a) {
                            if (a != null) vm.signInWithSaved(a);
                          },
                  ),
                  const SizedBox(height: 16),
                ],
                _animatedField(
                  focused: _userFocus.hasFocus,
                  child: TextFormField(
                    controller: _userCtrl,
                    focusNode: _userFocus,
                    enabled: !vm.isBusy,
                    keyboardType: TextInputType.text,
                    textInputAction: TextInputAction.next,
                    decoration: _decoration(
                      label: 'บัญชีผู้ใช้',
                      icon: Iconsax.user,
                      hasError: vm.errorField == 'username',
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'กรุณากรอกบัญชีผู้ใช้'
                        : null,
                  ),
                ),
                const SizedBox(height: 16),
                _animatedField(
                  focused: _passFocus.hasFocus,
                  child: TextFormField(
                    controller: _passCtrl,
                    focusNode: _passFocus,
                    enabled: !vm.isBusy,
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _submit(vm),
                    decoration: _decoration(
                      label: 'รหัสผ่าน',
                      icon: Iconsax.lock,
                      hasError: vm.errorField == 'password',
                      suffix: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                      ),
                    ),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'กรุณากรอกรหัสผ่าน' : null,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: _PopButton(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      onPressed: vm.isBusy ? null : () => _submit(vm),
                      icon: vm.isBusy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Iconsax.login, size: 22),
                      label: Text(
                        vm.isBusy ? 'กำลังเข้าสู่ระบบ...' : 'เข้าสู่ระบบ',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Row(
                  children: [
                    Expanded(child: Divider()),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text('หรือ'),
                    ),
                    Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: vm.isBusy ? null : vm.signInWithBrowser,
                    icon: Image.asset(
                      'assets/images/google_logo.png',
                      width: 22,
                      height: 22,
                    ),
                    label: const Text(
                      'เข้าสู่ระบบด้วย Google',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                if (vm.error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    vm.error!,
                    style: TextStyle(color: scheme.error),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Lifts its child slightly on mouse hover / press.
class _PopButton extends StatefulWidget {
  const _PopButton({required this.child});

  final Widget child;

  @override
  State<_PopButton> createState() => _PopButtonState();
}

class _PopButtonState extends State<_PopButton> {
  bool _hover = false;
  bool _pressed = false;

  bool get _up => _hover || _pressed;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => setState(() => _pressed = true),
      onPointerUp: (_) => setState(() => _pressed = false),
      onPointerCancel: (_) => setState(() => _pressed = false),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          transform: Matrix4.translationValues(0, _up ? -4 : 0, 0),
          child: widget.child,
        ),
      ),
    );
  }
}

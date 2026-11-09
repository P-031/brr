import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/keycloak_config.dart';
import '../../theme/app_theme.dart';
import '../../viewmodels/auth_viewmodel.dart';

class LoginView extends StatelessWidget {
  const LoginView({super.key});

  Future<void> _openRegistration() async {
    await launchUrl(
      Uri.parse(KeycloakConfig.registrationUrl),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<AuthViewModel>();
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.green, AppColors.greenLight, AppColors.gold],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Card(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 40,
                  ),
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
                          backgroundColor: AppColors.green,
                          child: Icon(
                            Icons.lock_outline,
                            size: 40,
                            color: AppColors.gold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'BRR',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
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
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: vm.isBusy ? null : vm.signIn,
                          icon: vm.isBusy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.login),
                          label: Text(
                            vm.isBusy
                                ? 'กำลังเข้าสู่ระบบ...'
                                : 'เข้าสู่ระบบด้วย Keycloak',
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: vm.isBusy ? null : _openRegistration,
                        child: const Text('สร้างบัญชีใหม่'),
                      ),
                      if (vm.error != null) ...[
                        const SizedBox(height: 16),
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
          ),
        ),
      ),
    );
  }
}

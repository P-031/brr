import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../viewmodels/auth_viewmodel.dart';
import 'login/login_view.dart';
import 'main/main_view.dart';

/// Root view — switches between login and home purely on auth state.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<AuthViewModel>();
    return switch (vm.status) {
      AuthStatus.restoring => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      AuthStatus.authenticated => const MainView(),
      _ => const LoginView(),
    };
  }
}

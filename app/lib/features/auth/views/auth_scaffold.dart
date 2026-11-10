import 'package:flutter/material.dart';

import 'package:brr/core/theme/app_theme.dart';

/// Shared layout for auth screens — green/gold gradient background
/// with the [child] card centered.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
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
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

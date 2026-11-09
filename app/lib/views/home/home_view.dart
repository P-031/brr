import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../theme/app_theme.dart';
import '../../viewmodels/auth_viewmodel.dart';

class HomeView extends StatelessWidget {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<AuthViewModel>();
    final name = vm.user?.displayName ?? 'ผู้ใช้';
    final email = vm.user?.email;
    return Scaffold(
      appBar: AppBar(
        title: const Text('BRR'),
        actions: [
          IconButton(
            onPressed: vm.signOut,
            icon: const Icon(Icons.logout),
            tooltip: 'ออกจากระบบ',
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.gold, width: 3),
              ),
              child: CircleAvatar(
                radius: 40,
                backgroundColor: AppColors.green,
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: const TextStyle(fontSize: 32, color: Colors.white),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(name, style: Theme.of(context).textTheme.titleLarge),
            if (email != null) ...[
              const SizedBox(height: 4),
              Text(email, style: Theme.of(context).textTheme.bodyMedium),
            ],
            const SizedBox(height: 32),
            OutlinedButton.icon(
              onPressed: vm.signOut,
              icon: const Icon(Icons.logout),
              label: const Text('ออกจากระบบ'),
            ),
          ],
        ),
      ),
    );
  }
}

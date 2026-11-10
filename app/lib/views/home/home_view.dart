import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';

import '../../theme/app_theme.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../map/map_view.dart';
import '../notifications/notifications_view.dart';

class HomeView extends StatelessWidget {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<AuthViewModel>();
    final name = vm.user?.displayName ?? 'ผู้ใช้';
    final email = vm.user?.email;
    return Scaffold(
      body: Column(
        children: [
          // green header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(24, 56, 24, 32),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [AppColors.green, AppColors.greenLight],
              ),
              borderRadius: BorderRadius.vertical(
                bottom: Radius.circular(28),
              ),
            ),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: InkWell(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const NotificationsView(),
                      ),
                    ),
                    customBorder: const CircleBorder(),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: ValueListenableBuilder<int>(
                        valueListenable: unreadNotifications,
                        builder: (_, count, _) => Badge(
                          isLabelVisible: count > 0,
                          backgroundColor: Colors.red,
                          child: const Icon(
                            Iconsax.notification,
                            color: Colors.white,
                            size: 26,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.gold, width: 3),
                  ),
                  child: CircleAvatar(
                    radius: 40,
                    backgroundColor: Colors.white,
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: const TextStyle(
                        fontSize: 32,
                        color: AppColors.green,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                if (email != null)
                  Text(
                    email,
                    style: const TextStyle(color: Colors.white70),
                  ),
              ],
            ),
          ),
          // offline banner
          if (vm.isOffline)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: AppColors.goldLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Iconsax.wifi_square, size: 16, color: AppColors.green),
                  SizedBox(width: 8),
                  Text('ออฟไลน์ — แสดงข้อมูลที่บันทึกไว้'),
                ],
              ),
            ),
          // menu
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _MenuCard(
                  icon: Iconsax.rulerpen,
                  title: 'วัดพื้นที่',
                  subtitle: 'ดูแปลงและคำนวณพื้นที่จากพิกัด',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => MapView(api: vm.api),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  const _MenuCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 8,
        ),
        leading: Icon(icon, size: 40, color: AppColors.green),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle),
        trailing: const Icon(Iconsax.arrow_right_3, color: AppColors.gold),
        onTap: onTap,
      ),
    );
  }
}

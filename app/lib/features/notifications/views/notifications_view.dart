import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import 'package:brr/core/theme/app_theme.dart';
import 'package:brr/core/widgets/brr_app_bar.dart';
import 'package:brr/features/notifications/data/notification_store.dart';

/// การแจ้งเตือน — list page; currently no data source.
class NotificationsView extends StatelessWidget {
  const NotificationsView({super.key});

  // Placeholder — backend will supply real notification items.
  static const _items = <({String title, String body, String time})>[];

  @override
  Widget build(BuildContext context) {
    // อัปเดท badge หลังเฟรม — setValue ระหว่าง build กระทบ listener
    // ที่กำลัง build อยู่ (setState during build)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unreadNotifications.value = _items.length;
    });
    return Scaffold(
      appBar: brrAppBar('การแจ้งเตือน'),
      body: _items.isEmpty
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Iconsax.notification, size: 64, color: Colors.black26),
                  SizedBox(height: 12),
                  Text(
                    'ยังไม่มีการแจ้งเตือน',
                    style: TextStyle(color: Colors.black45, fontSize: 16),
                  ),
                ],
              ),
            )
          : ListView.separated(
              itemCount: _items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final n = _items[i];
                return ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: AppColors.goldLight,
                    child: Icon(Iconsax.notification, color: AppColors.green),
                  ),
                  title: Text(n.title),
                  subtitle: Text(n.body),
                  trailing: Text(
                    n.time,
                    style: const TextStyle(fontSize: 12, color: Colors.black45),
                  ),
                );
              },
            ),
    );
  }
}

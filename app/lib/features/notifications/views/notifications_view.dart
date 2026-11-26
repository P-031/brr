import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';

import 'package:brr/core/theme/app_theme.dart';
import 'package:brr/core/widgets/brr_app_bar.dart';
import 'package:brr/features/map/viewmodels/failed_edits_viewmodel.dart';
import 'package:brr/features/map/views/failed_edits_view.dart';
import 'package:brr/features/notifications/models/notification_item.dart';
import 'package:brr/features/notifications/viewmodels/notifications_viewmodel.dart';

/// การแจ้งเตือน — list page ดึงจาก `GET /notifications`
/// (เปิดหน้า = อ่านแล้ว badge เคลียร์)
class NotificationsView extends StatelessWidget {
  const NotificationsView({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: NotificationsViewModel.forContext,
      child: const _Body(),
    );
  }
}

class _Body extends StatefulWidget {
  const _Body();

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  @override
  void initState() {
    super.initState();
    // รีเฟรชจำนวนงานค้างจาก prefs — persist ข้ามรอบแอปและ
    // เขียนกลับเข้า countListenable ให้แถวปักหัวอัปเดตเอง
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<NotificationsViewModel>().refreshFailedCount();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<NotificationsViewModel>();
    final items = vm.items;
    return Scaffold(
      appBar: brrAppBar('การแจ้งเตือน'),
      body: vm.loading
          ? const Center(child: CircularProgressIndicator())
          : ValueListenableBuilder<int>(
              valueListenable: FailedEditsViewModel.countListenable,
              builder: (context, failed, _) {
                final banner = failed > 0 ? 1 : 0;
                if (items.isEmpty && banner == 0) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Iconsax.notification,
                          size: 64,
                          color: Colors.black26,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          vm.error ?? 'ยังไม่มีการแจ้งเตือน',
                          style: const TextStyle(
                            color: Colors.black45,
                            fontSize: 16,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  itemCount: items.length + banner,
                  itemBuilder: (context, i) {
                    if (banner == 1 && i == 0) {
                      return _FailedEditsBanner(count: failed);
                    }
                    final n = items[i - banner];
                    return _NotificationTile(n: n);
                  },
                );
              },
            ),
    );
  }
}

/// แถวปักหัว "การแก้ไขที่ส่งไม่สำเร็จ" — งานค้างบนเครื่องที่
/// ต้องตัดสินใจ (ส่งใหม่/ทิ้ง) แยกจากข่าว server; แตะไปหน้าจัดการ
class _FailedEditsBanner extends StatelessWidget {
  const _FailedEditsBanner({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Material(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const FailedEditsView()),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 14,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.orange.shade300, width: 1.5),
            ),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 26,
                  backgroundColor: Colors.orange,
                  child: Icon(
                    Iconsax.warning_2,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'มีการแก้ไขที่ส่งไม่สำเร็จ',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$count รายการ — ต้องจัดการ',
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  color: Colors.black54,
                  size: 30,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// การ์ดแจ้งเตือน 1 ใบ — ยังไม่อ่านเด่นด้วยกรอบ/จุดสีทอง +
/// พื้นทองจาง (สไตล์เดียวกับการ์ดคำขอในหน้าอนุมัติ)
class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.n});

  final NotificationItem n;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: n.unread ? AppColors.goldLight : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: n.unread ? AppColors.gold : Colors.grey.shade300,
          width: 1.5,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: n.unread ? Colors.white : Colors.black12,
            child: Icon(
              Iconsax.notification,
              size: 28,
              color: n.unread ? AppColors.green : Colors.black45,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  n.title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: n.unread
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  n.body,
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  n.time,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.black45,
                  ),
                ),
              ],
            ),
          ),
          if (n.unread)
            const Padding(
              padding: EdgeInsets.only(left: 8, top: 4),
              child: CircleAvatar(radius: 5, backgroundColor: AppColors.gold),
            ),
        ],
      ),
    );
  }
}

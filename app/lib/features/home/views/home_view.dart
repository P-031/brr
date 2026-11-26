import 'dart:io';

import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';

import 'package:brr/core/theme/app_theme.dart';
import 'package:brr/features/home/viewmodels/home_viewmodel.dart';
import 'package:brr/features/map/viewmodels/drafts_viewmodel.dart';
import 'package:brr/features/map/viewmodels/failed_edits_viewmodel.dart';
import 'package:brr/features/map/viewmodels/map_viewmodel.dart';
import 'package:brr/features/map/views/drafts_view.dart';
import 'package:brr/features/map/views/map_view.dart';
import 'package:brr/features/notifications/viewmodels/notifications_viewmodel.dart';
import 'package:brr/features/notifications/views/notifications_view.dart';
import 'package:brr/features/parcel_status/views/request_approval_view.dart';
import 'package:brr/features/plot_activities/views/plot_activities_view.dart';

class HomeView extends StatelessWidget {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: HomeViewModel.forContext,
      child: const _HomeBody(),
    );
  }
}

class _HomeBody extends StatelessWidget {
  const _HomeBody();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<HomeViewModel>();
    final user = vm.user;
    final name = user?.displayName ?? 'ผู้ใช้';
    final email = user?.email;
    return Scaffold(
      body: Column(
        children: [
          // sugarcane header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(24, 40, 24, 20),
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/images/home_header.jpg'),
                fit: BoxFit.cover,
                colorFilter: ColorFilter.mode(
                  Color(0x66000000),
                  BlendMode.darken,
                ),
              ),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
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
                    // ปุ่มกระดิ่งวงกลมขาวจาง — ดูเป็นปุ่มกดชัดกว่า icon ลอย
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white24,
                      ),
                      child: ValueListenableBuilder<int>(
                        valueListenable:
                            NotificationsViewModel.unreadListenable,
                        builder: (_, count, _) => ValueListenableBuilder<int>(
                          valueListenable: FailedEditsViewModel.countListenable,
                          // จุดแดง/เลขขึ้นเมื่อมีแจ้งเตือนยังไม่อ่าน
                          // หรือมีการแก้ไขที่ส่งไม่สำเร็จค้างอยู่
                          builder: (_, failed, _) => Badge(
                            isLabelVisible: count > 0 || failed > 0,
                            label: count > 0 ? Text('$count') : null,
                            backgroundColor: Colors.red,
                            smallSize: 10,
                            child: const Icon(
                              Iconsax.notification,
                              color: Colors.white,
                              size: 30,
                            ),
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
                    backgroundImage: user?.photoPath != null
                        ? FileImage(File(user!.photoPath!))
                        : null,
                    // ไฟล์รูปถูกลบภายนอก → provider throw; กัน error
                    // spam แล้ว fallback เป็นวงกลมว่างเหมือนเดิม
                    onBackgroundImageError: user?.photoPath != null
                        ? (_, _) {}
                        : null,
                    child: user?.photoPath == null
                        ? Text(
                            name.isNotEmpty ? name[0].toUpperCase() : '?',
                            style: const TextStyle(
                              fontSize: 32,
                              color: AppColors.green,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        : null,
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
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                  ),
              ],
            ),
          ),
          // offline banner
          if (vm.isOffline)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                const Text(
                  'เมนูหลัก',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                // การ์ดเทาครอบเมนูหลัก — ข้างในเป็นเมนู launcher คู่
                Card(
                  elevation: 1,
                  color: Colors.grey.shade200,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    // เมนูแบบ launcher — icon กรอบมนสีจาง + ชื่อใต้ icon
                    // ไหลเรียงทีละ 2 ช่อง เพิ่มเมนูอนาคตแค่ใส่ใน list;
                    // อนุมัติคำขอเฉพาะ officer (backend กัน 403 อีกชั้น)
                    child: Column(
                      children: _menuRows([
                        if (vm.isOfficer) _approvalTile(context),
                        _measureTile(context, vm),
                        _mapTile(context, vm),
                      ]),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _MenuCard(
                  image: 'assets/images/menu_activities.jpg',
                  title: 'กิจกรรมแปลง',
                  subtitle: 'รายการแปลงพร้อมตัวกรอง — ปี เขต ประเภทอ้อย สถานะ',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const PlotActivitiesView(),
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

  /// จัด tile เป็นแถวละ 2 ช่อง — ช่องค้างท้ายแถวสุดท้ายเติมว่าง
  /// ให้ tile กว้างเท่ากันทุกใบ
  List<Widget> _menuRows(List<Widget> tiles) => [
    for (var i = 0; i < tiles.length; i += 2)
      Row(
        children: [
          Expanded(child: tiles[i]),
          i + 1 < tiles.length
              ? Expanded(child: tiles[i + 1])
              : const Expanded(child: SizedBox()),
        ],
      ),
  ];

  Widget _approvalTile(BuildContext context) => _MenuTile(
    image: 'assets/icons/emoji_u1f4cb.png',
    title: 'อนุมัติคำขอแปลง',
    color: Colors.blueGrey,
    onTap: () => Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const RequestApprovalView())),
  );

  Widget _measureTile(BuildContext context, HomeViewModel vm) => _MenuTile(
    image: 'assets/icons/emoji_u1f4cf.png',
    title: 'วัดพื้นที่',
    color: Colors.amber,
    // คั่นหน้าฉบับร่างก่อน — ร่างค้างอยู่จัดการ
    // ต่อได้ (แก้ไข/ยืนยัน/ลบ) หรือกดเริ่มวัดใหม่
    onTap: () => Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DraftsView(
          vm: DraftsViewModel.forContext(context),
          isOfficer: vm.isOfficer,
          onStartMeasure: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => MapView(
                createViewModel: () => MapViewModel.forContext(
                  context,
                  canDrawManually: vm.isOfficer,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _mapTile(BuildContext context, HomeViewModel vm) => _MenuTile(
    image: 'assets/icons/emoji_u1f5fa.png',
    title: 'แผนที่แปลงทั้งหมด',
    color: Colors.blue,
    onTap: () => Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MapView(
          parcelBrowser: true,
          createViewModel: () => MapViewModel.forContext(
            context,
            canDrawManually: vm.isOfficer,
          ),
        ),
      ),
    ),
  );
}

/// เมนูหลักแบบ launcher — ไอคอนภาพสีในกรอบมน + ชื่อใต้ icon
/// (ไม่ใช่การ์ด กดได้ทั้งก้อน) สำหรับวางคู่กันในกรอบเทา
class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.image,
    required this.title,
    required this.color,
    required this.onTap,
  });

  final String image;
  final String title;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Column(
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: color.withValues(alpha: 0.45),
                  width: 1.5,
                ),
              ),
              padding: const EdgeInsets.all(14),
              child: Image.asset(image, fit: BoxFit.contain),
            ),
            const SizedBox(height: 8),
            // จองที่ 2 บรรทัด — "แผนที่แปลงทั้งหมด" wrap ก็ยัง
            // เริ่มบรรทัดเดียวกันกับใบสั้น ปุ่มไม่เบี้ยว
            SizedBox(
              height: 46,
              child: Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  const _MenuCard({
    required this.image,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String image;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            image: DecorationImage(image: AssetImage(image), fit: BoxFit.cover),
          ),
          // overlay ดำจาง — ให้ตัวหนังสือขาวอ่านได้บนภาพ
          child: Container(
            constraints: const BoxConstraints(minHeight: 160),
            color: Colors.black.withValues(alpha: 0.35),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Iconsax.arrow_right_3,
                  color: Colors.white,
                  size: 28,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

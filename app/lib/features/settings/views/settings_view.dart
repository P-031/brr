import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';

import 'package:brr/core/theme/app_theme.dart';
import 'package:brr/core/widgets/brr_app_bar.dart';
import 'package:brr/features/settings/viewmodels/settings_viewmodel.dart';

/// หน้าตั้งค่า — เวอร์ชั่นแอป (กดเปิด Play Store) + สำรองข้อมูล
/// ในเครื่องออกเป็นไฟล์
class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => SettingsViewModel(),
    child: const _SettingsBody(),
  );
}

class _SettingsBody extends StatelessWidget {
  const _SettingsBody();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SettingsViewModel>();
    return Scaffold(
      appBar: brrAppBar('ตั้งค่า'),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Card(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(
                  Iconsax.info_circle,
                  color: AppColors.green,
                ),
                title: const Text(
                  'เวอร์ชั่น',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  'เวอร์ชั่นปัจจุบัน ${vm.version}',
                  style: const TextStyle(fontSize: 14),
                ),
                trailing: const Icon(
                  Iconsax.arrow_right_3,
                  color: Colors.black38,
                ),
                onTap: () => _openStore(context),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                leading: const Icon(
                  Iconsax.cloud_change,
                  color: AppColors.green,
                ),
                title: const Text(
                  'สำรองข้อมูล',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  'ส่งออกข้อมูลในเครื่องเป็นไฟล์',
                  style: TextStyle(fontSize: 14),
                ),
                trailing: vm.backingUp
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Iconsax.arrow_right_3, color: Colors.black38),
                onTap: vm.backingUp ? null : () => _backup(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openStore(BuildContext context) async {
    final vm = context.read<SettingsViewModel>();
    final ok = await vm.openPlayStore();
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('เปิด Play Store ไม่ได้')));
    }
  }

  Future<void> _backup(BuildContext context) async {
    final vm = context.read<SettingsViewModel>();
    try {
      final path = await vm.backup();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 5),
          content: Text('สำรองข้อมูลแล้ว\n$path'),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'สำรองข้อมูลไม่สำเร็จ — '
            '${'$e'.replaceFirst('Exception: ', '')}',
          ),
        ),
      );
    }
  }
}

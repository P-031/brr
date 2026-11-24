import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';

import 'package:brr/core/theme/app_theme.dart';
import 'package:brr/core/widgets/brr_app_bar.dart';
import 'package:brr/features/map/viewmodels/failed_edits_viewmodel.dart';

/// หน้า "การแก้ไขที่ส่งไม่สำเร็จ" — รายการ PATCH ที่ server ปฏิเสธ
/// ตอนส่งคิว offline (ข้อมูลถูกแก้จากเครื่องอื่น/แปลงถูกลบ ฯลฯ)
/// ผู้ใช้เลือกส่งใหม่หรือทิ้งได้ต่อรายการ — ไม่ให้ข้อมูลหายเงียบ
class FailedEditsView extends StatelessWidget {
  const FailedEditsView({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: FailedEditsViewModel.forContext,
      child: const _Body(),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body();

  static String _fmt(String? iso) {
    final d = DateTime.tryParse('$iso');
    if (d == null) return '—';
    return '${d.day}/${d.month}/${d.year + 543} '
        '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
  }

  /// ฟิลด์ที่แก้ในรายการนี้ — body เก็บ version ด้วยตัดออก
  static String _fields(Map<String, dynamic> e) {
    final body = e['body'];
    if (body is! Map) return '—';
    final names = body.keys.where((k) => k != 'version').join(', ');
    return names.isEmpty ? '—' : names;
  }

  /// สาเหตุที่ server ปฏิเสธ ให้ผู้ใช้เข้าใจทันที
  static String _reason(Map<String, dynamic> e) => switch (e['status']) {
    409 => 'ข้อมูลถูกแก้จากที่อื่นแล้ว (ขัดแย้งเวอร์ชัน)',
    404 || 410 => 'ไม่พบแปลงบนเซิร์ฟเวอร์ (อาจถูกลบ)',
    401 || 403 => 'ไม่มีสิทธิ์แก้ไขแปลงนี้',
    final s => 'เซิร์ฟเวอร์ตอบ $s',
  };

  Future<void> _retry(BuildContext context, Map<String, dynamic> e) async {
    final vm = context.read<FailedEditsViewModel>();
    final err = await vm.retry(e);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          err == null
              ? 'ส่งใหม่แล้ว — ตรวจสอบผลอีกครั้ง'
              : 'ส่งไม่สำเร็จ: $err',
        ),
      ),
    );
  }

  Future<void> _discard(BuildContext context, Map<String, dynamic> e) async {
    final vm = context.read<FailedEditsViewModel>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'ลบรายการนี้?',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'ค่าที่แก้ไว้จะถูกลบออกจากเครื่องถาวร ไม่สามารถกู้คืนได้',
          style: TextStyle(fontSize: 15),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('ยกเลิก', style: TextStyle(fontSize: 16)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'ลบ',
              style: TextStyle(fontSize: 16, color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (ok == true) await vm.discard(e);
  }

  Future<void> _clearAll(BuildContext context) async {
    final vm = context.read<FailedEditsViewModel>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'ล้างรายการทั้งหมด?',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'ค่าที่แก้ไว้ทุกรายการจะถูกลบออกจากเครื่องถาวร',
          style: TextStyle(fontSize: 15),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('ยกเลิก', style: TextStyle(fontSize: 16)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'ล้างทั้งหมด',
              style: TextStyle(fontSize: 16, color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (ok == true) await vm.discardAll();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<FailedEditsViewModel>();
    return Scaffold(
      appBar: brrAppBar(
        'การแก้ไขที่ส่งไม่สำเร็จ',
        actions: [
          if (vm.items.isNotEmpty)
            IconButton(
              icon: const Icon(Iconsax.trash, color: Colors.red),
              tooltip: 'ล้างรายการ',
              onPressed: () => _clearAll(context),
            ),
        ],
      ),
      body: vm.loading
          ? const Center(child: CircularProgressIndicator())
          : vm.items.isEmpty
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Iconsax.tick_circle, size: 56, color: Colors.green),
                  SizedBox(height: 12),
                  Text(
                    'ไม่มีรายการค้างส่ง',
                    style: TextStyle(fontSize: 16, color: Colors.black54),
                  ),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: vm.items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final e = vm.items[i];
                final busy = vm.busyId == FailedEditsViewModel.keyOf(e);
                return Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: const BorderSide(color: Colors.black12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Iconsax.warning_2,
                              color: Colors.orange,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'แปลง ${e['plotId']}',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _reason(e),
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.red,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'ฟิลด์ที่แก้: ${_fields(e)}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.black54,
                          ),
                        ),
                        Text(
                          'บันทึกคิว: ${_fmt('${e['queuedAt']}')}  •  '
                          'ปฏิเสธ: ${_fmt('${e['failedAt']}')}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black45,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: busy
                                  ? null
                                  : () => _discard(context, e),
                              child: const Text(
                                'ลบทิ้ง',
                                style: TextStyle(color: Colors.red),
                              ),
                            ),
                            const SizedBox(width: 8),
                            FilledButton.icon(
                              onPressed: busy ? null : () => _retry(context, e),
                              icon: busy
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Iconsax.send_2, size: 16),
                              label: const Text('ส่งใหม่'),
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.green,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

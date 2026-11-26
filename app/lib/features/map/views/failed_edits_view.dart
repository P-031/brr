import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  /// คัดลอกค่า + snackbar ยืนยัน
  static void _copy(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('คัดลอก $text แล้ว')));
  }

  /// แถวข้อมูล label : value — label ความกว้างคงที่ให้ตรงกัน
  static Widget _infoRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(fontSize: 16, color: Colors.black87),
            ),
          ),
          const Text(
            ' :  ',
            style: TextStyle(fontSize: 16, color: Colors.black87),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: color ?? Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
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
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'ค่าที่แก้ไว้จะถูกลบออกจากเครื่องถาวร ไม่สามารถกู้คืนได้',
          style: TextStyle(fontSize: 17),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('ยกเลิก', style: TextStyle(fontSize: 17)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'ลบ',
              style: TextStyle(fontSize: 17, color: Colors.red),
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
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'ค่าที่แก้ไว้ทุกรายการจะถูกลบออกจากเครื่องถาวร',
          style: TextStyle(fontSize: 17),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('ยกเลิก', style: TextStyle(fontSize: 17)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'ล้างทั้งหมด',
              style: TextStyle(fontSize: 17, color: Colors.red),
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
      appBar: brrAppBar('การแก้ไขที่ส่งไม่สำเร็จ'),
      body: Column(
        children: [
          // แถบเครื่องมือเหนือ list — เรียง/รีเฟรช/ล้างทั้งหมด
          if (!vm.loading && vm.items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 6, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // ป้ายตัวหนังสือบอกโหมดเรียงชัดๆ แทนไอคอน
                  TextButton.icon(
                    onPressed: vm.toggleSort,
                    icon: const Icon(Iconsax.sort, size: 24),
                    label: Text(
                      vm.newestFirst ? 'ใหม่สุด' : 'เก่าสุด',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.black87,
                    ),
                  ),
                  IconButton(
                    iconSize: 32,
                    padding: const EdgeInsets.all(12),
                    icon: const Icon(Icons.autorenew),
                    tooltip: 'รีเฟรช',
                    onPressed: vm.load,
                  ),
                  IconButton(
                    iconSize: 32,
                    padding: const EdgeInsets.all(12),
                    icon: const Icon(Iconsax.trash, color: Colors.redAccent),
                    tooltip: 'ล้างรายการทั้งหมด',
                    onPressed: () => _clearAll(context),
                  ),
                ],
              ),
            ),
          Expanded(child: _buildBody(context, vm)),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, FailedEditsViewModel vm) {
    return vm.loading
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
                color: const Color(0xFFF2F2F2),
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
                            color: Colors.deepOrange,
                            size: 28,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'แปลง ${e['plotName'] ?? e['plotId']}',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          // status code ที่ server ตอบ — ป้ายแดงเล็ก
                          if (e['status'] != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.red.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${e['status']}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red,
                                ),
                              ),
                            ),
                        ],
                      ),
                      // เลขแปลงใต้ชื่อ + ปุ่มคัดลอก — ตอนรายงานปัญหา
                      // ให้ support เอาเลขไปหาแปลงได้เลย
                      if (e['plotNo'] != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 30, top: 2),
                          child: Row(
                            children: [
                              Text(
                                'เลขแปลง ${e['plotNo']}',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(width: 4),
                              InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: () => _copy(context, '${e['plotNo']}'),
                                child: const Padding(
                                  padding: EdgeInsets.all(8),
                                  child: Icon(
                                    Iconsax.copy,
                                    size: 26,
                                    color: AppColors.green,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      const Divider(height: 18, color: Colors.black12),
                      _infoRow('เหตุผล', _reason(e), color: Colors.red),
                      // ข้อความ error จริงจาก server — แสดงเมื่อมี
                      // (entry เก่าก่อน feature นี้จะไม่มี detail)
                      if (e['detail'] != null)
                        _infoRow(
                          'รายละเอียด',
                          '${e['detail']}',
                          color: Colors.red.shade700,
                        ),
                      _infoRow('ฟิลด์ที่แก้', _fields(e)),
                      _infoRow('บันทึกคิว', _fmt('${e['queuedAt']}')),
                      _infoRow('ปฏิเสธ', _fmt('${e['failedAt']}')),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: busy ? null : () => _discard(context, e),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.red,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                            ),
                            child: const Text(
                              'ลบทิ้ง',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            onPressed: busy ? null : () => _retry(context, e),
                            icon: busy
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Iconsax.send_2, size: 20),
                            label: const Text(
                              'ส่งใหม่',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.green,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
  }
}

import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';

import 'package:brr/core/theme/app_theme.dart';
import 'package:brr/features/map/data/parcel_service.dart' show ParcelPage;
import 'package:brr/features/map/viewmodels/plot_download_viewmodel.dart';
import 'package:brr/features/map/widgets/map_skeleton.dart';

/// หน้าเลือกดาวน์โหลดข้อมูลแปลง (push ทับหน้าแผนที่) — ดึงรายการปี
/// แบบเบา (`GET /plots/years`) ให้ผู้ใช้ติ๊กเลือก แล้วปุ่มดาวน์โหลด
/// ค่อยดึงขอบแปลงจริง (`GET /plots/map`) พร้อมแสดง % ตาม bytes ที่
/// รับมา เสร็จแล้ว pop [PlotDownloadResult] กลับให้หน้าแผนที่เอา
/// ไปแสดง — ไม่เปิด route ใหม่
class PlotDownloadView extends StatelessWidget {
  const PlotDownloadView({required this.viewModel, super.key});

  /// VM จาก MapViewModel.createDownloadVm() — แชร์ service/token
  /// เดียวกับหน้าแผนที่ ไม่สร้างใหม่
  final PlotDownloadViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: viewModel,
      child: const _DownloadBody(),
    );
  }
}

class _DownloadBody extends StatelessWidget {
  const _DownloadBody();

  static const _noYear = 'ไม่ระบุปี';

  Future<void> _run(
    BuildContext context,
    PlotDownloadViewModel vm,
    Future<ParcelPage?> Function() action,
  ) async {
    final page = await action();
    if (page != null && context.mounted) {
      Navigator.of(context).pop(
        (page: page, selected: {...vm.selected}),
      );
    }
  }

  String _kb(int bytes) => bytes < 1024 * 1024
      ? '${(bytes / 1024).toStringAsFixed(0)} KB'
      : '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<PlotDownloadViewModel>();
    final years = vm.serverYears;
    return Scaffold(
      appBar: AppBar(title: const Text('ดาวน์โหลดข้อมูลแปลง')),
      body: vm.downloading || vm.downloadError != null
          ? vm.downloadError != null
              ? _errorView(
                  'ดาวน์โหลดไม่สำเร็จ',
                  () => _run(context, vm, vm.download),
                  cacheFallback: () => _run(context, vm, vm.useCache),
                )
              // รับ bytes ครบแล้วกำลัง parse+เปิดแผนที่ — skeleton
              // รูปแผนที่ดูเป็นธรรมชาติกว่าวงหมุนค้างที่ 100%
              : vm.processing
              ? const MapSkeleton(parcelBrowser: true)
              : _progressView(vm)
          : years == null
          ? vm.error != null
              ? _errorView('โหลดข้อมูลไม่สำเร็จ', vm.loadIndex)
              : const Center(child: CircularProgressIndicator())
          : _content(vm),
      bottomNavigationBar:
          years == null || vm.error != null || vm.downloading
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  onPressed: () => _run(context, vm, vm.download),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  icon: const Icon(Iconsax.import),
                  label: Text(
                    'ดาวน์โหลด ${vm.selectedCount} แปลง',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _progressView(PlotDownloadViewModel vm) {
    final progress = vm.processing ? null : vm.progress;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 140,
              height: 140,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox.expand(
                    child: CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 10,
                      strokeCap: StrokeCap.round,
                      backgroundColor: Colors.black12,
                      valueColor: const AlwaysStoppedAnimation(
                        AppColors.green,
                      ),
                    ),
                  ),
                  Text(
                    progress == null
                        ? '...'
                        : '${(progress * 100).round()}%',
                    style: const TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.bold,
                      color: AppColors.green,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              vm.processing
                  ? 'กำลังเตรียมข้อมูลแปลง...'
                  : 'กำลังดาวน์โหลดข้อมูลแปลง',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              vm.processing
                  ? 'ดาวน์โหลดครบแล้ว กำลังจัดข้อมูลลงแผนที่'
                  : vm.total == null
                  ? 'รับข้อมูลแล้ว ${_kb(vm.received)}'
                  : '${_kb(vm.received)} / ${_kb(vm.total!)}',
              style: const TextStyle(color: Colors.black54, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorView(
    String title,
    VoidCallback retry, {
    VoidCallback? cacheFallback,
  }) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Iconsax.warning_2, color: Colors.red, size: 40),
        const SizedBox(height: 8),
        Text(title),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: retry,
          icon: const Icon(Iconsax.refresh, size: 18),
          label: const Text('ลองใหม่'),
        ),
        if (cacheFallback != null)
          TextButton.icon(
            onPressed: cacheFallback,
            icon: const Icon(Iconsax.archive, size: 18),
            label: const Text('ใช้ข้อมูลที่บันทึกไว้'),
          ),
      ],
    ),
  );

  Widget _content(PlotDownloadViewModel vm) {
    final years = vm.sortedYears;
    if (years.isEmpty) {
      return const Center(child: Text('ยังไม่มีแปลงให้ดาวน์โหลด'));
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'เลือกปีการผลิตที่ต้องการดาวน์โหลด',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'พบ ${years.fold<int>(0, (s, e) => s + e.value)} แปลง — ข้อมูลจะถูกเก็บไว้แสดงบนแผนที่',
          style: const TextStyle(color: Colors.black54, fontSize: 14),
        ),
        const SizedBox(height: 12),
        CheckboxListTile(
          value: vm.selected.length == years.length,
          tristate: true,
          onChanged: (on) => vm.toggleAll(on ?? false),
          title: const Text(
            'เลือกทั้งหมด',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          secondary: const Icon(Iconsax.tick_square),
        ),
        const Divider(),
        for (final e in years)
          CheckboxListTile(
            value: vm.selected.contains(e.key),
            onChanged: (on) => vm.toggleYear(e.key, on ?? false),
            title: Text(e.key ?? _noYear),
            subtitle: Text('${e.value} แปลง'),
            secondary: const Icon(Icons.calendar_month),
          ),
      ],
    );
  }
}

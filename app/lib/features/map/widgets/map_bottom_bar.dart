import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax/iconsax.dart';

import 'package:brr/core/theme/app_theme.dart';
import 'package:brr/features/map/models/measurement_result.dart';
import 'package:brr/features/map/viewmodels/map_viewmodel.dart';
import 'package:brr/features/map/views/measurement_save_view.dart';

/// Walk-measure status line — point count plus a color-coded GPS
/// accuracy badge so the farmer knows the signal quality.
class _WalkStatus extends StatelessWidget {
  const _WalkStatus({required this.vm});

  final MapViewModel vm;

  @override
  Widget build(BuildContext context) {
    final acc = vm.gpsAccuracy;
    final color = acc == null
        ? Colors.grey
        : acc <= 6
        ? AppColors.green
        : acc <= 15
        ? Colors.orange
        : Colors.red;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          vm.walkPaused
              ? vm.autoPaused
                    ? 'GPS แย่ — พักอัตโนมัติ (${vm.draft.length} จุด)'
                    : 'หยุดพักชั่วคราว (${vm.draft.length} จุด)'
              : 'เดินวัดอยู่… ${vm.draft.length} จุด',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color),
          ),
          child: Text(
            acc == null ? 'GPS รอสัญญาณ' : 'GPS ±${acc.toStringAsFixed(0)} ม.',
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}

/// แผงข้อมูล GPS จริง — พิกัดล่าสุด + ค่าความคลาดเคลื่อน
/// แสดงเมื่อลากแถบล่างขึ้น คัดลอกพิกัดได้ด้วยปุ่ม copy
class _GpsInfo extends StatelessWidget {
  const _GpsInfo({required this.vm, super.key});

  final MapViewModel vm;

  @override
  Widget build(BuildContext context) {
    final fix = vm.lastFix ?? vm.userPos;
    final acc = vm.gpsAccuracy;
    // โหมดแตะวาดไม่โชว์คลาดเคลื่อน — จุดมาจากนิ้วแตะไม่ใช่ GPS
    final showAcc = vm.walking || !vm.drawing;
    final coordText = fix == null
        ? 'รอสัญญาณ GPS…'
        : '${fix.latitude.toStringAsFixed(6)}, ${fix.longitude.toStringAsFixed(6)}';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Iconsax.gps, size: 20, color: AppColors.green),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'พิกัดปัจจุบัน',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                    Text(
                      coordText,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (fix != null)
                IconButton(
                  icon: const Icon(Iconsax.copy, size: 20),
                  tooltip: 'คัดลอกพิกัด',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: coordText));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('คัดลอกพิกัดแล้ว'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                ),
            ],
          ),
          if (showAcc) const SizedBox(height: 8),
          if (showAcc)
            Row(
              children: [
                const Icon(Iconsax.radar, size: 20, color: AppColors.green),
                const SizedBox(width: 8),
                const Text(
                  'ความคลาดเคลื่อน',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(width: 8),
                Text(
                  acc == null
                      ? 'รอสัญญาณ GPS…'
                      : '±${acc.toStringAsFixed(1)} เมตร',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// ปุ่มลูกศรย้อนกลับออกจากโหมดวัด — วงกลมเรียบๆ สไตล์เดียว
/// กับปุ่มลอยบนแผนที่ กลับไปหน้าเลือกเดินวัด/แตะวาด
class _BackButton extends StatelessWidget {
  const _BackButton({required this.onCancel});

  final Future<void> Function() onCancel;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onCancel,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.green),
        ),
        child: const Icon(Iconsax.arrow_left, size: 20, color: AppColors.green),
      ),
    );
  }
}

/// แถบปุ่มล่าง — เดินวัด/แตะวาด หรือชุดเครื่องมือขณะกำลังวัด
/// ลากขึ้นเพื่อดูพิกัด GPS ปัจจุบัน + ค่าความคลาดเคลื่อนจริง
class MapBottomBar extends StatefulWidget {
  const MapBottomBar({
    required this.vm,
    required this.movingIndex,
    this.onFormOpen,
    super.key,
  });

  final MapViewModel vm;

  /// Draft pin armed for tap-to-move (0-based), or null.
  final int? movingIndex;

  /// Tells the map when the save form covers it — used to pause
  /// the my-location dot animation while the form is open.
  final void Function(bool open)? onFormOpen;

  @override
  State<MapBottomBar> createState() => _MapBottomBarState();
}

class _MapBottomBarState extends State<MapBottomBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );
  final GlobalKey _panelKey = GlobalKey();

  double get _panelHeight => _panelKey.currentContext?.size?.height ?? 140.0;

  void _togglePanel() {
    _ctrl.animateTo(_ctrl.value < 0.5 ? 1.0 : 0.0, curve: Curves.easeOut);
  }

  void _dragPanel(DragUpdateDetails d) {
    _ctrl.value = (_ctrl.value - d.delta.dy / _panelHeight).clamp(0.0, 1.0);
  }

  void _grabPanel(DragStartDetails _) => _ctrl.stop();

  void _snapPanel(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    if (v.abs() > 200) {
      _ctrl.fling(velocity: v < 0 ? 3.0 : -3.0);
    } else {
      _ctrl.animateTo(_ctrl.value > 0.5 ? 1.0 : 0.0, curve: Curves.easeOut);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.vm;
    final movingIndex = widget.movingIndex;
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _togglePanel,
            onVerticalDragStart: _grabPanel,
            onVerticalDragUpdate: _dragPanel,
            onVerticalDragEnd: _snapPanel,
            child: SizedBox(
              height: 34,
              child: Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
          AnimatedBuilder(
            animation: _ctrl,
            builder: (context, _) {
              final t = _ctrl.value;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRect(
                    child: Align(
                      alignment: Alignment.topCenter,
                      heightFactor: t,
                      child: IgnorePointer(
                        ignoring: t == 0,
                        // แยก layer — ลากทีละเฟรมไม่ repaint ชนแผนที่
                        child: RepaintBoundary(
                          // ลากที่ตัวแผงลงเพื่อหุบได้ด้วย ไม่จำเป็น
                          // ต้องมาโดนขีดจับอย่างเดียว
                          child: GestureDetector(
                            onVerticalDragStart: _grabPanel,
                            onVerticalDragUpdate: _dragPanel,
                            onVerticalDragEnd: _snapPanel,
                            child: _GpsInfo(key: _panelKey, vm: vm),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: 10 * t),
                ],
              );
            },
          ),
          widget.vm.drawing
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        _BackButton(onCancel: () => _cancel(context)),
                        Expanded(
                          child: widget.vm.walking
                              ? _WalkStatus(vm: vm)
                              : Text(
                                  movingIndex != null
                                      ? 'แตะจุดใหม่เพื่อย้ายหมุด #${movingIndex + 1}'
                                      : 'แตะแผนที่เพื่อปักจุด (${widget.vm.draft.length} จุด)',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                        // ดันเนื้อหาให้อยู่กลางจริงๆ หลังมีปุ่มซ้าย
                        const SizedBox(width: 38),
                      ],
                    ),
                    if (widget.vm.walking) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: Builder(
                          builder: (context) {
                            final acc = widget.vm.gpsAccuracy;
                            final ok = acc != null && acc <= 6;
                            return FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: ok
                                    ? AppColors.green
                                    : Colors.red,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                              ),
                              onPressed: () => _pinPoint(context),
                              icon: const Icon(Iconsax.add_circle, size: 24),
                              label: Text(
                                acc == null
                                    ? 'เพิ่มพิกัด (รอสัญญาณ GPS…)'
                                    : 'เพิ่มพิกัด (±${acc.toStringAsFixed(1)} ม.)',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                vertical: 14,
                                horizontal: 8,
                              ),
                            ),
                            onPressed: widget.vm.walking
                                ? widget.vm.toggleWalkPause
                                : (widget.vm.draft.isEmpty
                                      ? null
                                      : widget.vm.clearDraft),
                            icon: Icon(
                              widget.vm.walking
                                  ? (widget.vm.walkPaused
                                        ? Iconsax.play
                                        : Iconsax.pause)
                                  : Iconsax.refresh,
                              size: 24,
                            ),
                            label: Text(
                              widget.vm.walking
                                  ? (widget.vm.walkPaused ? 'เดินต่อ' : 'พัก')
                                  : 'เริ่มใหม่',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                vertical: 14,
                                horizontal: 8,
                              ),
                            ),
                            onPressed: widget.vm.draft.isEmpty
                                ? null
                                : widget.vm.undoDraftPoint,
                            icon: const Icon(Iconsax.undo, size: 24),
                            label: const Text(
                              'ย้อนกลับ',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                vertical: 14,
                                horizontal: 8,
                              ),
                            ),
                            onPressed: () => _finish(context),
                            child: const Text(
                              'เสร็จสิ้น',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                )
              : widget.vm.canDrawManually
              ? Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        onPressed: () => _startWalk(context),
                        icon: const Icon(Icons.directions_walk, size: 24),
                        label: const Text(
                          'เดินวัด',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        onPressed: widget.vm.startDrawing,
                        icon: const Icon(Iconsax.location_add, size: 24),
                        label: const Text(
                          'แตะวาด',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              : SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    onPressed: () => _startWalk(context),
                    icon: const Icon(Icons.directions_walk, size: 24),
                    label: const Text(
                      'เดินวัด',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  Future<void> _startWalk(BuildContext context) async {
    final err = await widget.vm.startWalk();
    if (err != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }

  /// ออกจากโหมดวัดกลับไปหน้าเลือกโหมด — เตือนก่อนถ้ามีจุดค้างอยู่
  Future<void> _cancel(BuildContext context) async {
    final vm = widget.vm;
    if (vm.draft.isNotEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          // กรอบกว้างขึ้น + ฟอนต์ใหญ่ขึ้น — อ่านง่ายกลางแจ้ง
          insetPadding: const EdgeInsets.symmetric(horizontal: 20),
          title: const Text(
            'ยกเลิกการวัด?',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          content: Text(
            'จุดที่ปักไว้ ${vm.draft.length} จุดจะถูกลบทั้งหมด',
            style: const TextStyle(fontSize: 16),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('วัดต่อ', style: TextStyle(fontSize: 16)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('ยกเลิกการวัด', style: TextStyle(fontSize: 16)),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    if (!context.mounted) return;
    vm.cancelDrawing();
  }

  void _pinPoint(BuildContext context) {
    final err = widget.vm.pinWalkPoint();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(err ?? 'ปักพิกัดแล้ว (${widget.vm.draft.length} จุด)'),
        duration: Duration(seconds: err == null ? 1 : 2),
      ),
    );
  }

  Future<void> _finish(BuildContext context) async {
    if (widget.vm.draft.length < 3) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('ต้องปักอย่างน้อย 3 จุด')));
      return;
    }
    widget.onFormOpen?.call(true);
    final result = await Navigator.of(context).push<MeasurementResult>(
      MaterialPageRoute(
        builder: (_) => MeasurementSaveView(
          areaSquareMeters: widget.vm.draftAreaSqm,
          officers: widget.vm.fetchOfficers,
          farmers: widget.vm.fetchFarmers,
          options: widget.vm.fetchOptions,
          isOfficer: widget.vm.canDrawManually,
        ),
      ),
    );
    widget.onFormOpen?.call(false);
    if (result == null) return;
    final err = await widget.vm.finishDrawing(
      result.name,
      productionYear: result.productionYear,
      officerName: result.officerName,
      project: result.project,
      farmerName: result.farmerName,
      farmerId: result.farmerId,
      caneGroup: result.caneGroup,
      zone: result.zone,
      province: result.province,
      district: result.district,
      subdistrict: result.subdistrict,
      village: result.village,
      rootNo: result.rootNo,
      sequenceNo: result.sequenceNo,
      prevPlotNo: result.prevPlotNo,
      caneType: result.caneType,
      caneVariety: result.caneVariety,
      ownership: result.ownership,
      terrain: result.terrain,
      hasLoss: result.hasLoss,
      lossRai: result.lossRai,
      targetYield: result.targetYield,
      note: result.note,
      photos: result.photos,
      draft: result.draft,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          err ?? (result.draft ? 'บันทึกฉบับร่างแล้ว' : 'บันทึกแปลงสำเร็จ'),
        ),
      ),
    );
  }
}

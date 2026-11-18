import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';

import 'package:brr/core/services/api_client.dart';
import 'package:brr/core/theme/app_theme.dart';
import 'package:brr/core/widgets/skeleton.dart';
import 'package:brr/features/map/widgets/parcel_outline.dart';
import 'package:brr/features/map/widgets/satellite_thumb.dart';
import 'package:brr/features/parcel_status/models/plot_request.dart';
import 'package:brr/features/parcel_status/viewmodels/parcel_status_viewmodel.dart';

/// สถานะแปลง — scrollable status tabs + filtered parcel list.
/// ชื่อ tab มาจาก backend (/meta/options → parcelStatuses) เสมอ;
/// รายการแปลงจะต่อเมื่อมี endpoint (ดู ParcelStatusViewModel)
class ParcelStatusView extends StatelessWidget {
  const ParcelStatusView({super.key, this.api});

  /// ApiClient เดียวกับ session — null = โหมดออฟไลน์ (แสดงว่าง)
  final ApiClient? api;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ParcelStatusViewModel.forApi(api),
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
  int _tab = 0;
  List<GlobalKey> _keys = const [];

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ParcelStatusViewModel>();
    final tabs = vm.statuses;
    if (_tab >= tabs.length) _tab = 0;
    if (_keys.length != tabs.length) {
      _keys = List.generate(tabs.length, (_) => GlobalKey());
    }
    final items = tabs.isEmpty
        ? const <PlotRequestEntry>[]
        : vm.requestsOf(tabs[_tab]);
    return Column(
      children: [
        Container(
          width: double.infinity,
          color: Colors.white,
          padding: const EdgeInsets.only(top: 48, bottom: 12),
          child: const Text(
            'สถานะแปลง',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ),
        Container(
          color: Colors.white,
          child: Column(
            children: [
              if (vm.loading)
                // skeleton แถว tab — เส้นข้อความเทาแนวนอน ตัวแรก
                // มีเส้นใต้เหมือน tab ที่กำลังเลือก
                const SkeletonPulse(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 10),
                    child: Row(
                      children: [
                        _TabSkeleton(selected: true, width: 86),
                        SizedBox(width: 22),
                        _TabSkeleton(width: 64),
                        SizedBox(width: 22),
                        _TabSkeleton(width: 74),
                        SizedBox(width: 22),
                        _TabSkeleton(width: 58),
                      ],
                    ),
                  ),
                )
              else if (vm.error != null)
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: TextButton.icon(
                    onPressed: vm.load,
                    icon: const Icon(Iconsax.refresh, size: 18),
                    label: const Text('โหลดสถานะไม่สำเร็จ — ลองใหม่'),
                  ),
                )
              else
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Row(
                    children: [
                      for (var i = 0; i < tabs.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(right: 14),
                          child: _chip(i, tabs[i]),
                        ),
                    ],
                  ),
                ),
              const Divider(height: 1, color: Colors.black12),
            ],
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? const Center(
                  child: Text(
                    'ไม่มีข้อมูล',
                    style: TextStyle(fontSize: 16),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length,
                  itemBuilder: (context, i) =>
                      _RequestCard(r: items[i], status: tabs[_tab]),
                ),
        ),
      ],
    );
  }

  Widget _inner(int i, String label) {
    final selected = _tab == i;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: selected ? 16 : 12,
        vertical: selected ? 10 : 8,
      ),
      decoration: BoxDecoration(
        color: Colors.transparent,
        border: Border(
          bottom: BorderSide(
            color: selected
                ? const Color(0xFFFFD54F)
                : Colors.transparent,
            width: 3,
          ),
        ),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: selected ? 20 : 16,
          fontWeight: selected ? FontWeight.bold : FontWeight.w600,
          color: selected ? AppColors.green : Colors.black87,
        ),
      ),
    );
  }

  Widget _chip(int i, String label) {
    final selected = _tab == i;
    return GestureDetector(
      key: _keys[i],
      onTap: () {
        setState(() => _tab = i);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final ctx = _keys[i].currentContext;
          if (ctx != null) {
            Scrollable.ensureVisible(
              ctx,
              alignment: 0.5,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
            );
          }
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        transform: Matrix4.translationValues(0, selected ? -8 : 0, 0),
        child: _inner(i, label),
      ),
    );
  }
}

/// การ์ดคำขอแปลง 1 รายการ — ชื่อแปลง + ประเภทคำขอ + ค่าที่ขอ +
/// ผู้ส่ง/วันที่ + chip สถานะ (ตรง tab ที่เลือก)
class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.r, required this.status});

  final PlotRequestEntry r;
  final String status;

  String _thaiDate(DateTime? d) {
    if (d == null) return '';
    final l = d.toLocal();
    return '${l.day}/${l.month}/${l.year + 543} '
        '${l.hour.toString().padLeft(2, '0')}:'
        '${l.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // รูปแปลงดาวเทียมกรอบมน — outline จาก backend จริง;
            // โหลด tile ไม่ได้ fallback เป็น polygon วาดเอง
            // (เหมือนการ์ดกิจกรรมแปลง)
            SatelliteThumb(
              points: r.points,
              cacheKey: 'req-${r.id}',
              fallback: ParcelOutline(points: r.points),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r.plotName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${r.kindLabel}${r.detail.isEmpty ? '' : ' — ${r.detail}'}',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (r.requester != null) 'โดย ${r.requester}',
                      if (r.productionYear != null)
                        'ปีการผลิต ${r.productionYear}',
                      _thaiDate(r.createdAt),
                    ].where((s) => s.isNotEmpty).join('  •  '),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Chip(
              label: Text(status, style: const TextStyle(fontSize: 12)),
              backgroundColor: AppColors.goldLight,
            ),
          ],
        ),
      ),
    );
  }
}

/// เส้นเทาเลียน tab สถานะ — [selected] = มีเส้นใต้ทองเหมือน
/// tab ที่กำลังเลือกอยู่จริง
class _TabSkeleton extends StatelessWidget {
  const _TabSkeleton({this.selected = false, required this.width});

  final bool selected;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: selected
                ? const Color(0xFFFFD54F)
                : Colors.transparent,
            width: 3,
          ),
        ),
      ),
      child: SkelLine(width: width, height: selected ? 18 : 15),
    );
  }
}

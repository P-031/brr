import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';

import 'package:brr/core/theme/app_theme.dart';
import 'package:brr/core/widgets/brr_app_bar.dart';
import 'package:brr/core/widgets/skeleton.dart';
import 'package:brr/features/map/models/sat_thumb.dart';
import 'package:brr/features/map/widgets/parcel_outline.dart';
import 'package:brr/features/map/widgets/satellite_thumb.dart';
import 'package:brr/features/parcel_status/models/plot_request.dart';
import 'package:brr/features/parcel_status/viewmodels/parcel_status_viewmodel.dart';
import 'package:brr/core/widgets/error_retry_view.dart';

/// สถานะแปลง — scrollable status tabs + filtered parcel list.
/// ชื่อ tab มาจาก backend (/meta/options → parcelStatuses) เสมอ;
/// รายการแปลงจะต่อเมื่อมี endpoint (ดู ParcelStatusViewModel)
class ParcelStatusView extends StatelessWidget {
  const ParcelStatusView({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      // VM หยิบ ApiClient จาก Provider root เอง (forContext)
      create: (ctx) => ParcelStatusViewModel.forContext(ctx),
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
  bool _newestFirst = true;
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
        : (vm.requestsOf(tabs[_tab]).toList()..sort((a, b) {
            // เรียงตามเวลาส่งคำขอ — ไม่มีเวลาถือว่าเก่าสุด
            final ta = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            final tb = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            return _newestFirst ? tb.compareTo(ta) : ta.compareTo(tb);
          }));
    return Column(
      children: [
        brrHeaderBackdrop(
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.only(top: 48, bottom: 12),
                child: const Text(
                  'สถานะแปลง',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
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
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    ),
                    onPressed: vm.load,
                    icon: const Icon(Icons.autorenew, size: 26),
                    label: const Text(
                      'โหลดสถานะไม่สำเร็จ — ลองใหม่',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
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
              const Divider(height: 1, color: Colors.white38),
            ],
          ),
        ),
        // แถบเครื่องมือเหนือ list — เรียงใหม่/เก่า + รีเฟรช
        // (ชุดเดียวกับหน้าการแก้ไขที่ส่งไม่สำเร็จ) ใช้ได้ทุก
        // tab แม้ tab ว่าง — รีเฟรชยังจำเป็น
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 6, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: () => setState(() => _newestFirst = !_newestFirst),
                icon: const Icon(Iconsax.sort, size: 24),
                label: Text(
                  _newestFirst ? 'ใหม่สุด' : 'เก่าสุด',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: TextButton.styleFrom(foregroundColor: Colors.black87),
              ),
              IconButton(
                iconSize: 32,
                padding: const EdgeInsets.all(12),
                icon: const Icon(Icons.autorenew),
                tooltip: 'รีเฟรช',
                onPressed: vm.load,
              ),
            ],
          ),
        ),
        Expanded(
          child: vm.requestsError != null
              // แถบ tab โหลดได้แต่ list ล้ม — แจ้ง + ให้ retry เฉพาะ
              // ส่วน list ไม่ทำทั้งหน้าเสีย
              ? ErrorRetryView('โหลดรายการไม่สำเร็จ', onRetry: vm.load)
              : vm.loading
              ? const Center(child: CircularProgressIndicator())
              : vm.error != null
              // แถบสถานะมาไม่ได้เลย — บอกสาเหตุกลางจอ ไม่ใช่โชว์
              // "ไม่มีข้อมูล" ทั้งที่ปัญหาคือติดต่อ server ไม่ได้
              ? ErrorRetryView(
                  vm.error!.replaceFirst('Exception: ', ''),
                  onRetry: vm.load,
                )
              : items.isEmpty
              ? const Center(
                  child: Text('ไม่มีข้อมูล', style: TextStyle(fontSize: 19)),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length,
                  itemBuilder: (context, i) => _RequestCard(
                    r: items[i],
                    status: tabs[_tab],
                    loader: vm.satThumb,
                  ),
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
            color: selected ? const Color(0xFFFFD54F) : Colors.transparent,
            width: 3,
          ),
        ),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: selected ? 22 : 19,
          fontWeight: selected ? FontWeight.bold : FontWeight.w600,
          color: Colors.white,
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
  const _RequestCard({
    required this.r,
    required this.status,
    required this.loader,
  });

  final PlotRequestEntry r;
  final String status;
  final SatThumbLoader loader;

  String _thaiDate(DateTime? d) {
    if (d == null) return '';
    final l = d.toLocal();
    // \u2060 = word joiner — กันคำไทยแตกกลางคำ "วัน|ที่" คนละ
    // บรรทัด (ไทยตัดบรรทัดได้ทุกพจน์ ไม่ใช่แค่ช่องว่าง)
    // \u00A0 = NBSP กัน "วันที่" แยกจากตัวเลข
    return 'วัน\u2060ที่\u00A0${l.day}/${l.month}/${l.year + 543}'
        '\u00A0${l.hour.toString().padLeft(2, '0')}:'
        '${l.minute.toString().padLeft(2, '0')}';
  }

  /// ชื่อแปลงล้วน / เลขแปลง — ตัด `#NNN` ท้ายชื่อแยกเป็น 2 ฟิลด์
  /// (regex เดียวกับ Parcel.landNo/plotCode)
  String get _landNo => r.plotName.replaceAll(RegExp(r'\s*#\d+\s*$'), '');
  String get _plotCode =>
      RegExp(r'#\s*(\d+)\s*$').firstMatch(r.plotName)?.group(1) ?? '';

  /// สี+ไอคอนป้ายสถานะ — อ่านสถานะได้จากสีทันที
  /// (เขียว=อนุมัติ เหลือง=รอ แดง=ไม่ผ่าน/ยกเลิก)
  ({Color bg, IconData icon}) get _statusStyle => switch (status) {
    'อนุมัติ' => (bg: AppColors.green, icon: Iconsax.tick_circle),
    'รออนุมัติ' => (bg: const Color(0xFFE8960C), icon: Iconsax.clock),
    _ => (bg: const Color(0xFFC62828), icon: Iconsax.close_circle),
  };

  @override
  Widget build(BuildContext context) {
    final st = _statusStyle;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // รูปแปลงดาวเทียมแบนเนอร์เต็มกว้าง — outline จาก
          // backend จริง; โหลด tile ไม่ได้ fallback เป็น polygon
          // วาดเอง (เหมือนการ์ดกิจกรรมแปลง)
          // width ต้องเป็นตัวเลขจริง (loader เอาไป round() ขอ tile)
          // — LayoutBuilder เอากว้างการ์ดจริง
          LayoutBuilder(
            builder: (context, c) => SatelliteThumb(
              points: r.points,
              cacheKey: 'req-${r.id}',
              loader: loader,
              fallback: ParcelOutline(points: r.points),
              width: c.maxWidth,
              height: 120,
              radius: 0,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ชื่อแปลง + เลขแปลง (# จากท้ายชื่อ)
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          text: _landNo,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                          children: [
                            if (_plotCode.isNotEmpty)
                              TextSpan(
                                text: '  #$_plotCode',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.green,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // ป้ายสถานะ — บรรทัดเดียวกับชื่อ
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: st.bg,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(st.icon, size: 17, color: Colors.white),
                          const SizedBox(width: 5),
                          Text(
                            status,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (r.productionYear != null)
                  Text(
                    'ปีการผลิต ${r.productionYear}',
                    style: TextStyle(fontSize: 16, color: Colors.grey.shade700),
                  ),
                const SizedBox(height: 4),
                Text(
                  [
                    if (r.requester != null) 'โดย ${r.requester}',
                    _thaiDate(r.createdAt),
                  ].where((s) => s.isNotEmpty).join('  •  '),
                  style: TextStyle(fontSize: 16, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 6),
                Text(
                  r.kindLabel,
                  style: TextStyle(fontSize: 16, color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
        ],
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
            color: selected ? const Color(0xFFFFD54F) : Colors.transparent,
            width: 3,
          ),
        ),
      ),
      child: SkelLine(width: width, height: selected ? 18 : 15),
    );
  }
}

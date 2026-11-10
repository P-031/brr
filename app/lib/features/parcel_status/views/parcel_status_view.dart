import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import 'package:brr/features/map/models/parcel.dart';
import 'package:brr/core/theme/app_theme.dart';

/// สถานะแปลง — scrollable status tabs + filtered parcel list.
///
/// Backend-ready: not wired yet — swap [_parcels] for a
/// ParcelService/MapViewModel fetch when the endpoint is ready.
class ParcelStatusView extends StatefulWidget {
  const ParcelStatusView({super.key});

  @override
  State<ParcelStatusView> createState() => _ParcelStatusState();
}

class _ParcelStatusState extends State<ParcelStatusView> {
  int _tab = 0;
  late final List<GlobalKey> _keys = List.generate(
    _tabs.length,
    (_) => GlobalKey(),
  );

  static const _tabs = [
    'รออนุมัติ',
    'อนุมัติ',
    'ไม่อนุมัติ',
    'ยกเลิก',
    'แปลงที่ลบแล้ว',
    'แปลงรอยืนยัน',
    'ยกเลิกแบบมีหนี้ค้าง',
  ];

  // TODO(backend): replace with vm.parcels from ParcelService.
  static const _parcels = <Parcel>[];

  String _statusOf(Parcel p) => p.status ?? 'รออนุมัติ';

  @override
  Widget build(BuildContext context) {
    final items = _parcels
        .where((p) => _statusOf(p) == _tabs[_tab])
        .toList();
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
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(
                  children: [
                    for (var i = 0; i < _tabs.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(right: 14),
                        child: _chip(i),
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
                  itemBuilder: (context, i) {
                    final p = items[i];
                    return Card(
                      child: ListTile(
                        leading: const Icon(
                          Iconsax.map_1,
                          color: AppColors.green,
                        ),
                        title: Text(p.name),
                        subtitle: Text(p.areaThai),
                        trailing: Chip(
                          label: Text(
                            _statusOf(p),
                            style: const TextStyle(fontSize: 12),
                          ),
                          backgroundColor: AppColors.goldLight,
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _inner(int i) {
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
        _tabs[i],
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

  Widget _chip(int i) {
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
        child: _inner(i),
      ),
    );
  }
}

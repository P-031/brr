import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';

import 'package:brr/core/services/api_client.dart';
import 'package:brr/core/theme/app_theme.dart';
import 'package:brr/features/map/data/parcel_service.dart';
import 'package:brr/features/map/models/parcel.dart';
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
      create: (_) =>
          ParcelStatusViewModel(api == null ? null : ParcelService(api)),
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
        ? const <Parcel>[]
        : vm.parcelsOf(tabs[_tab]);
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
                const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.green,
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
                            tabs[_tab],
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

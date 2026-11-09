import 'package:flutter/material.dart';

import '../../models/parcel.dart';
import '../../services/parcel_service.dart';
import '../../theme/app_theme.dart';

/// สถานะแปลง — parcel list with status chips.
/// Status is mocked until the backend provides it.
class ParcelStatusView extends StatelessWidget {
  const ParcelStatusView({super.key});

  static const _statuses = ['กำลังเติบโต', 'พร้อมเก็บเกี่ยว'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('สถานะแปลง')),
      body: FutureBuilder<List<Parcel>>(
        future: ParcelService().fetchParcels(),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final parcels = snap.data ?? const <Parcel>[];
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: parcels.length,
            itemBuilder: (context, i) {
              final p = parcels[i];
              final status = _statuses[i % _statuses.length];
              return Card(
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: AppColors.green,
                    child: Icon(Icons.grass, color: AppColors.gold),
                  ),
                  title: Text(
                    p.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    '≈ ${p.areaRai.toStringAsFixed(2)} ไร่',
                  ),
                  trailing: Chip(
                    label: Text(
                      status,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.green,
                      ),
                    ),
                    backgroundColor: AppColors.goldLight,
                    side: const BorderSide(color: AppColors.gold),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

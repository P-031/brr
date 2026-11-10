import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../services/api_client.dart';
import '../../theme/app_theme.dart';
import '../../viewmodels/map_viewmodel.dart';
import 'measurement_save_view.dart';

/// Area-measurement screen — plots parcel boundaries from the backend
/// as polygons + pins, and supports drafting a new parcel by tapping
/// points on the map (เพิ่มพิกัด / ย้อนกลับ / เสร็จสิ้น).
class MapView extends StatelessWidget {
  const MapView({super.key, this.api});

  /// Pass the authenticated ApiClient so parcels go to the backend.
  final ApiClient? api;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => MapViewModel(api: api),
      child: const _MapBody(),
    );
  }
}

class _MapBody extends StatelessWidget {
  const _MapBody();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<MapViewModel>();
    return Scaffold(
      appBar: AppBar(title: const Text('วัดพื้นที่')),
      body: vm.loading
          ? const Center(child: CircularProgressIndicator())
          : vm.error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(vm.error!),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: vm.load,
                    child: const Text('ลองใหม่'),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: FlutterMap(
                    options: MapOptions(
                      initialCameraFit: CameraFit.bounds(
                        bounds: _boundsOf(vm.parcels),
                        padding: const EdgeInsets.all(40),
                      ),
                      onTap: (_, point) => vm.addDraftPoint(point),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.brr.brr',
                      ),
                      PolygonLayer(
                        polygons: [
                          for (final p in vm.parcels)
                            Polygon(
                              points: p.points,
                              color: AppColors.green.withValues(alpha: 0.25),
                              borderColor: AppColors.gold,
                              borderStrokeWidth: 3,
                            ),
                          if (vm.draft.length >= 3)
                            Polygon(
                              points: vm.draft,
                              color: AppColors.gold.withValues(alpha: 0.3),
                              borderColor: AppColors.gold,
                              borderStrokeWidth: 3,
                            ),
                        ],
                      ),
                      MarkerLayer(
                        markers: [
                          for (final p in vm.parcels)
                            Marker(
                              point: p.center,
                              width: 40,
                              height: 40,
                              child: const Icon(
                                Iconsax.location_tick,
                                color: AppColors.green,
                                size: 40,
                              ),
                            ),
                          for (var i = 0; i < vm.draft.length; i++)
                            Marker(
                              point: vm.draft[i],
                              width: 24,
                              height: 24,
                              child: const Icon(
                                Iconsax.record_circle,
                                color: AppColors.gold,
                                size: 16,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                _BottomBar(vm: vm),
              ],
            ),
    );
  }

  LatLngBounds _boundsOf(List<dynamic> parcels) {
    final all = <LatLng>[
      for (final p in parcels) ...p.points,
    ];
    if (all.isEmpty) {
      return LatLngBounds(LatLng(14.99, 103.11), LatLng(15.0, 103.12));
    }
    return LatLngBounds.fromPoints(all);
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.vm});

  final MapViewModel vm;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      child: vm.drawing
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'แตะแผนที่เพื่อปักจุด (${vm.draft.length} จุด)',
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: vm.draft.isEmpty
                            ? null
                            : vm.undoDraftPoint,
                        icon: const Icon(Iconsax.undo),
                        label: const Text('ย้อนกลับ'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _finish(context),
                        icon: const Icon(Iconsax.tick_circle),
                        label: const Text('เสร็จสิ้น'),
                      ),
                    ),
                  ],
                ),
              ],
            )
          : SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: vm.startDrawing,
                icon: const Icon(Iconsax.location_add),
                label: const Text('เพิ่มพิกัด'),
              ),
            ),
    );
  }

  Future<void> _finish(BuildContext context) async {
    if (vm.draft.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ต้องปักอย่างน้อย 3 จุด')),
      );
      return;
    }
    final result = await Navigator.of(context).push<MeasurementResult>(
      MaterialPageRoute(
        builder: (_) => MeasurementSaveView(
          areaSquareMeters: vm.draftAreaSqm,
          officers: vm.service.fetchOfficers(),
          farmers: vm.service.fetchFarmers(),
          caneGroups: vm.service.fetchCaneGroups(),
        ),
      ),
    );
    if (result == null) return;
    final err = await vm.finishDrawing(
      result.name,
      productionYear: result.productionYear,
      officerName: result.officerName,
      project: result.project,
      farmerName: result.farmerName,
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
    if (context.mounted && err != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err)),
      );
    }
  }
}

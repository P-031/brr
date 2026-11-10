import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import 'package:brr/core/services/api_client.dart';
import 'package:brr/core/theme/app_theme.dart';
import 'package:brr/features/map/viewmodels/map_viewmodel.dart';
import 'package:brr/features/map/views/measurement_save_view.dart';

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

class _MapBody extends StatefulWidget {
  const _MapBody();

  @override
  State<_MapBody> createState() => _MapBodyState();
}

class _MapBodyState extends State<_MapBody> {
  final _mapController = MapController();
  bool _locating = false;

  /// Map layer style — backend/config can drive this later.
  /// TODO: persist per user or load tile templates from config API.
  static const _tileUrls = {
    'แผนที่': 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    'ดาวเทียม':
        'https://server.arcgisonline.com/ArcGIS/rest/services/'
        'World_Imagery/MapServer/tile/{z}/{y}/{x}',
  };
  String _mapType = 'แผนที่';

  Future<void> _locate() async {
    setState(() => _locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw 'เปิด GPS ก่อนใช้งาน';
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        throw 'ไม่ได้รับอนุญาตตำแหน่ง';
      }
      final pos = await Geolocator.getCurrentPosition();
      _mapController.move(LatLng(pos.latitude, pos.longitude), 16);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

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
                  child: Stack(
                    children: [
                      FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                      initialCameraFit: CameraFit.bounds(
                        bounds: _boundsOf(vm.parcels),
                        padding: const EdgeInsets.all(40),
                      ),
                      onTap: (_, point) => vm.addDraftPoint(point),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: _tileUrls[_mapType]!,
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
                      // ประเภทแผนที่ + เข็มทิศ + GPS — Google-Maps-style
                      // controls; wired to tile template & rotation, and
                      // structured so a backend-driven config can replace
                      // the local state later.
                      Positioned(
                        right: 16,
                        bottom: 16,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            PopupMenuButton<String>(
                              tooltip: 'ประเภทแผนที่',
                              color: Colors.white,
                              onSelected: (v) =>
                                  setState(() => _mapType = v),
                              itemBuilder: (_) => [
                                for (final t in _tileUrls.keys)
                                  PopupMenuItem(
                                    value: t,
                                    child: Text(t),
                                  ),
                              ],
                              child: _MapButton(
                                icon: Iconsax.layer,
                                loading: false,
                              ),
                            ),
                            const SizedBox(height: 10),
                            GestureDetector(
                              onTap: () => _mapController.rotate(0),
                              child: const _MapButton(
                                icon: Iconsax.discover,
                                loading: false,
                              ),
                            ),
                            const SizedBox(height: 10),
                            GestureDetector(
                              onTap: _locating ? null : _locate,
                              child: _MapButton(
                                icon: Iconsax.gps,
                                loading: _locating,
                              ),
                            ),
                          ],
                        ),
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

/// White circular map-control button (map type / compass / GPS).
class _MapButton extends StatelessWidget {
  const _MapButton({required this.icon, required this.loading});

  final IconData icon;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black12),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 6),
        ],
      ),
      child: loading
          ? const Padding(
              padding: EdgeInsets.all(14),
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.green,
              ),
            )
          : Icon(icon, color: AppColors.green, size: 24),
    );
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
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            vertical: 14,
                          ),
                        ),
                        onPressed: vm.draft.isEmpty
                            ? null
                            : vm.undoDraftPoint,
                        icon: const Icon(Iconsax.undo, size: 22),
                        label: const Text(
                          'ย้อนกลับ',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            vertical: 14,
                          ),
                        ),
                        onPressed: () => _finish(context),
                        icon: const Icon(Iconsax.tick_circle, size: 22),
                        label: const Text(
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
          : SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: vm.startDrawing,
                icon: const Icon(Iconsax.location_add, size: 24),
                label: const Text(
                  'เพิ่มพิกัด',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
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

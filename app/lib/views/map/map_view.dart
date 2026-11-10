import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../services/api_client.dart';
import '../../theme/app_theme.dart';
import '../../viewmodels/map_viewmodel.dart';

/// Area-measurement screen — plots parcel boundaries from the backend
/// as polygons + centroid pins on an OpenStreetMap layer.
class MapView extends StatelessWidget {
  const MapView({super.key, this.api});

  /// Pass the authenticated ApiClient so parcels can come from the
  /// backend when enabled. Null = mock data.
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
                                Icons.location_pin,
                                color: AppColors.green,
                                size: 40,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: 120,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.all(12),
                    children: [
                      for (final p in vm.parcels)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text('≈ ${p.areaRai.toStringAsFixed(2)} ไร่'),
                                Text(
                                  '${p.areaSquareMeters.toStringAsFixed(0)} ตร.ม.',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.black54,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
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

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax/iconsax.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:provider/provider.dart';

import 'package:brr/core/theme/app_theme.dart';
import 'package:brr/features/map/viewmodels/map_viewmodel.dart';
import 'package:brr/features/map/views/measurement_save_view.dart';

/// Area-measurement screen — plots parcel boundaries from the backend
/// as polygons + pins, and supports drafting a new parcel by tapping
/// points on the map (เพิ่มพิกัด / ย้อนกลับ / เสร็จสิ้น).
class MapView extends StatelessWidget {
  const MapView({super.key, this.createViewModel});

  /// Factory for the screen's ViewModel — the caller (usually a parent
  /// view) wires in an authenticated service when backend access is
  /// needed. The view itself never touches services directly.
  final MapViewModel Function()? createViewModel;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => createViewModel?.call() ?? MapViewModel(),
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
  GoogleMapController? _controller;
  CameraPosition _camera = _initialCamera;
  bool _locating = false;
  bool _locationGranted = false;

  /// Numbered gold-pin bitmaps for draft points, keyed by 1-based index.
  final _pinIcons = <int, BitmapDescriptor>{};

  /// Green-ringed variants shown while a pin is selected for moving.
  final _pinSelIcons = <int, BitmapDescriptor>{};

  /// Draft pin index currently armed for tap-to-move (0-based).
  int? _movingIndex;

  /// Renders a numbered gold pin (ring + white bold index) as a marker
  /// bitmap — draft pins show their tap order like survey stakes.
  static Future<BitmapDescriptor> _numberedPin(
    int n, {
    ui.Color ring = Colors.white,
  }) {
    // Drawn at 3x then scaled down — crisp edges on hi-dpi screens.
    const ratio = 3.0;
    const size = 35.0 * ratio;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    const c = ui.Offset(size / 2, size / 2);
    canvas
      ..drawCircle(
        c,
        size / 2 - 2 * ratio,
        ui.Paint()..color = AppColors.gold,
      )
      ..drawCircle(
        c,
        size / 2 - 2 * ratio,
        ui.Paint()
          ..color = ring
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = 3 * ratio,
      );
    final tp = TextPainter(
      text: TextSpan(
        text: '$n',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16 * ratio,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      ui.Offset(size / 2 - tp.width / 2, size / 2 - tp.height / 2),
    );
    final pic = recorder.endRecording();
    return pic.toImage(size.toInt(), size.toInt()).then((img) async {
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      return BitmapDescriptor.bytes(
        bytes!.buffer.asUint8List(),
        imagePixelRatio: ratio,
      );
    });
  }

  /// Lazily creates pin bitmaps for new draft indexes (async — markers
  /// fall back to a plain gold pin until their numbered icon is ready).
  void _ensurePinIcons(int count) {
    for (var i = _pinIcons.length + 1; i <= count; i++) {
      final n = i;
      _numberedPin(n).then((icon) {
        if (mounted) setState(() => _pinIcons[n] = icon);
      });
    }
  }

  /// Tap a draft pin to arm/disarm it for moving; the next map tap
  /// relocates it. A green ring marks the armed pin.
  void _toggleMovePin(int i) {
    setState(() {
      _movingIndex = _movingIndex == i ? null : i;
    });
    if (_movingIndex != null && _pinSelIcons[i + 1] == null) {
      final n = i + 1;
      _numberedPin(n, ring: AppColors.greenLight).then((icon) {
        if (mounted) setState(() => _pinSelIcons[n] = icon);
      });
    }
  }

  /// Map tap: relocate an armed pin, otherwise drop a new point.
  void _onMapTap(LatLng p, MapViewModel vm) {
    final point = ll.LatLng(p.latitude, p.longitude);
    final i = _movingIndex;
    if (i != null && i < vm.draft.length) {
      setState(() => _movingIndex = null);
      vm.moveDraftPoint(i, point);
    } else {
      _movingIndex = null;
      vm.addDraftPoint(point);
    }
  }

  /// Fallback camera — Surin area, matches the mock parcels' location.
  static const _initialCamera = CameraPosition(
    target: LatLng(14.995, 103.113),
    zoom: 17,
  );

  /// Map type — backend/config can drive the default later.
  static const _mapTypes = {
    'แผนที่': MapType.normal,
    'ดาวเทียม': MapType.satellite,
  };

  /// Real-map preview thumbnails for the type picker sheet.
  static const _mapTypeAssets = {
    'แผนที่': 'assets/images/maptype_normal.png',
    'ดาวเทียม': 'assets/images/maptype_satellite.jpg',
  };
  MapType _mapType = MapType.satellite;

  static LatLng _ll(ll.LatLng p) => LatLng(p.latitude, p.longitude);

  /// Moves the camera to the user's GPS position. [auto] is used when
  /// the page opens — it suppresses error toasts and returns false so
  /// the caller can fall back to fitting the parcels.
  Future<bool> _locate({bool auto = false}) async {
    if (mounted) setState(() => _locating = true);
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
      if (!mounted) return true;
      setState(() => _locationGranted = true);
      await _controller?.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(pos.latitude, pos.longitude),
          17,
        ),
      );
      return true;
    } catch (e) {
      if (mounted && !auto) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
      return false;
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  /// On page open: jump to the user's current position; if GPS /
  /// permission is unavailable, fit the camera around the parcels.
  Future<void> _initialLocate(MapViewModel vm) async {
    if (!await _locate(auto: true)) _fitParcels(vm);
  }

  /// Reset the camera bearing to north (compass button).
  void _resetNorth() {
    _controller?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: _camera.target, zoom: _camera.zoom),
      ),
    );
  }

  /// Map-type picker styled after the Google Maps layer sheet —
  /// thumbnail tiles with a gold ring on the selected one.
  void _pickMapType() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'ประเภทแผนที่',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final e in _mapTypes.entries)
                    _MapTypeThumb(
                      label: e.key,
                      asset: _mapTypeAssets[e.key]!,
                      selected: _mapType == e.value,
                      onTap: () {
                        setState(() => _mapType = e.value);
                        Navigator.of(sheetContext).pop();
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _fitParcels(MapViewModel vm) {
    final all = <ll.LatLng>[for (final p in vm.parcels) ...p.points];
    if (all.isEmpty) return;
    var south = all.first.latitude, north = all.first.latitude;
    var west = all.first.longitude, east = all.first.longitude;
    for (final p in all) {
      if (p.latitude < south) south = p.latitude;
      if (p.latitude > north) north = p.latitude;
      if (p.longitude < west) west = p.longitude;
      if (p.longitude > east) east = p.longitude;
    }
    _controller?.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(south, west),
          northeast: LatLng(north, east),
        ),
        60,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<MapViewModel>();
    _ensurePinIcons(vm.draft.length);
    // Edge-to-edge map: transparent status bar, light icons for the
    // satellite imagery behind it.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
      ),
      child: Scaffold(
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
                      GoogleMap(
                        initialCameraPosition: _initialCamera,
                        onMapCreated: (c) {
                          _controller = c;
                          _initialLocate(
                            context.read<MapViewModel>(),
                          );
                        },
                        onCameraMove: (pos) => _camera = pos,
                        onTap: (p) => _onMapTap(p, vm),
                        mapType: _mapType,
                        compassEnabled: true,
                        zoomControlsEnabled: false,
                        myLocationEnabled: _locationGranted,
                        myLocationButtonEnabled: false,
                        polygons: {
                          for (final p in vm.parcels)
                            Polygon(
                              polygonId: PolygonId(p.id),
                              points: [for (final x in p.points) _ll(x)],
                              fillColor:
                                  (p.isDraft ? AppColors.gold : AppColors.green)
                                      .withValues(alpha: 0.25),
                              strokeColor: AppColors.gold,
                              strokeWidth: 3,
                            ),
                          if (vm.draft.length >= 3)
                            Polygon(
                              polygonId: const PolygonId('draft'),
                              points: [for (final x in vm.draft) _ll(x)],
                              fillColor: AppColors.gold.withValues(
                                alpha: 0.3,
                              ),
                              strokeColor: AppColors.gold,
                              strokeWidth: 3,
                            ),
                        },
                        markers: {
                          for (final p in vm.parcels)
                            Marker(
                              markerId: MarkerId(p.id),
                              position: _ll(p.center),
                              infoWindow: InfoWindow(
                                title: p.isDraft ? '${p.name} (ร่าง)' : p.name,
                              ),
                              icon: BitmapDescriptor.defaultMarkerWithHue(
                                BitmapDescriptor.hueGreen,
                              ),
                            ),
                          for (var i = 0; i < vm.draft.length; i++)
                            Marker(
                              markerId: MarkerId('draft-$i'),
                              position: _ll(vm.draft[i]),
                              anchor: const Offset(0.5, 0.5),
                              zIndexInt: 2,
                              draggable: true,
                              consumeTapEvents: true,
                              onTap: () => _toggleMovePin(i),
                              onDragEnd: (pos) => vm.moveDraftPoint(
                                i,
                                ll.LatLng(pos.latitude, pos.longitude),
                              ),
                              icon:
                                  (_movingIndex == i
                                      ? _pinSelIcons[i + 1] ??
                                            _pinIcons[i + 1]
                                      : _pinIcons[i + 1]) ??
                                  BitmapDescriptor.defaultMarkerWithHue(
                                    BitmapDescriptor.hueYellow,
                                  ),
                            ),
                        },
                      ),
                      // Back button floats over the map (no AppBar —
                      // the map runs edge-to-edge under the status bar).
                      Positioned(
                        top: MediaQuery.of(context).padding.top + 12,
                        left: 16,
                        child: GestureDetector(
                          onTap: () => Navigator.of(context).pop(),
                          child: const _MapButton(
                            icon: Iconsax.arrow_left,
                            loading: false,
                          ),
                        ),
                      ),
                      // ประเภทแผนที่ + เข็มทิศ + GPS — Google-Maps-style
                      // controls; structured so a backend-driven config
                      // can replace the local state later.
                      Positioned(
                        right: 16,
                        bottom: 16,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            GestureDetector(
                              onTap: _pickMapType,
                              child: const _MapButton(
                                icon: Iconsax.layer,
                                loading: false,
                              ),
                            ),
                            const SizedBox(height: 10),
                            GestureDetector(
                              onTap: _resetNorth,
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
                _BottomBar(vm: vm, movingIndex: _movingIndex),
              ],
            ),
      ),
    );
  }
}

/// Thumbnail tile in the map-type sheet — Google-Maps-style preview
/// tile with a gold ring when selected.
class _MapTypeThumb extends StatelessWidget {
  const _MapTypeThumb({
    required this.label,
    required this.asset,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String asset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? AppColors.gold : Colors.black12,
                width: selected ? 3 : 1,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(
                selected ? 11 : 13,
              ),
              child: Image.asset(
                asset,
                fit: BoxFit.cover,
                width: 88,
                height: 88,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: selected ? FontWeight.bold : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
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
  const _BottomBar({required this.vm, required this.movingIndex});

  final MapViewModel vm;

  /// Draft pin armed for tap-to-move (0-based), or null.
  final int? movingIndex;

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
                  movingIndex != null
                      ? 'แตะจุดใหม่เพื่อย้ายหมุด #${movingIndex! + 1}'
                      : 'แตะแผนที่เพื่อปักจุด (${vm.draft.length} จุด)',
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
                            horizontal: 8,
                          ),
                        ),
                        onPressed: vm.draft.isEmpty
                            ? null
                            : vm.clearDraft,
                        icon: const Icon(Iconsax.refresh, size: 24),
                        label: const Text(
                          'เริ่มใหม่',
                          style: TextStyle(
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
                        onPressed: vm.draft.isEmpty
                            ? null
                            : vm.undoDraftPoint,
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
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            vertical: 14,
                            horizontal: 8,
                          ),
                        ),
                        onPressed: () => _finish(context),
                        icon: const Icon(Iconsax.tick_circle, size: 24),
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
          officers: vm.fetchOfficers(),
          farmers: vm.fetchFarmers(),
          caneGroups: vm.fetchCaneGroups(),
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

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax/iconsax.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:provider/provider.dart';

import 'package:brr/core/theme/app_theme.dart';
import 'package:brr/core/widgets/option_popup.dart';
import 'package:brr/features/map/models/parcel.dart';
import 'package:brr/features/map/viewmodels/map_viewmodel.dart';
import 'package:brr/features/map/viewmodels/plot_download_viewmodel.dart';
import 'package:brr/features/map/views/drafts_view.dart';
import 'package:brr/features/map/views/plot_download_view.dart';
import 'package:brr/features/map/widgets/map_bottom_bar.dart';
import 'package:brr/features/map/widgets/map_skeleton.dart';
import 'package:brr/features/map/widgets/map_widgets.dart';
import 'package:brr/features/map/widgets/parcel_info_sheet.dart';

/// Area-measurement screen — plots parcel boundaries from the backend
/// as polygons + pins, and supports drafting a new parcel by tapping
/// points on the map (เพิ่มพิกัด / ย้อนกลับ / เสร็จสิ้น).
class MapView extends StatelessWidget {
  const MapView({
    super.key,
    this.createViewModel,
    this.parcelBrowser = false,
    this.autoPromptDownload = true,
    this.focusParcel,
  });

  /// Factory for the screen's ViewModel — the caller (usually a parent
  /// view) wires in an authenticated service when backend access is
  /// needed. The view itself never touches services directly.
  final MapViewModel Function()? createViewModel;

  /// โหมด "แผนที่แปลง" — มีปุ่มดาวน์โหลดข้อมูลแปลง + auto-open
  /// หน้าเลือกปีตอนแผนที่ว่าง. false = โหมดวัดพื้นที่ล้วน
  final bool parcelBrowser;

  /// auto-open หน้าเลือกปีตอนแผนว่าง — ปิดได้เวลาเข้าจากหน้าอื่น
  /// (เช่นกิจกรรมแปลง) ที่อยากให้เห็นแผนที่ทันที
  final bool autoPromptDownload;

  /// แปลงที่เลือกมาจากหน้าก่อนหน้า — เปิดแผนที่บินไปแปลงนั้นแล้ว
  /// เด้ง sheet ข้อมูลทันที (เช่น กด "เลือก" จากกิจกรรมแปลง)
  final Parcel? focusParcel;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => createViewModel?.call() ?? MapViewModel(),
      child: _MapBody(
        parcelBrowser: parcelBrowser,
        autoPromptDownload: autoPromptDownload,
        focusParcel: focusParcel,
      ),
    );
  }
}

class _MapBody extends StatefulWidget {
  const _MapBody({
    required this.parcelBrowser,
    this.autoPromptDownload = true,
    this.focusParcel,
  });

  final bool parcelBrowser;
  final bool autoPromptDownload;
  final Parcel? focusParcel;

  @override
  State<_MapBody> createState() => _MapBodyState();
}

class _MapBodyState extends State<_MapBody> {
  GoogleMapController? _controller;
  CameraPosition _camera = _initialCamera;
  bool _locating = false;
  bool _locationGranted = false;

  @override
  void initState() {
    super.initState();
    // รอ locate ครั้งแรก (เริ่มไว้ใน VM ตอน skeleton แสดงอยู่) —
    // mount GoogleMap หลังจบเท่านั้น กล้องจะเริ่มที่ตำแหน่งจริง
    // ทันที ไม่เด้งจากจุด fallback แล้วค่อย animate กลับ
    context.read<MapViewModel>().initialLocate.then((_) {
      if (mounted) setState(() => _locateReady = true);
    });
    // Cap เวลารอ — GPS ไม่พร้อมภายใน 1.5วิ mount ไปก่อน
    // _initialLocate จะ animate ตำแหน่งตามมาเองเมื่อพร้อม
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted && !_locateReady) {
        setState(() => _locateReady = true);
      }
    });
    // โหมดแผนที่แปลง + แผนที่ว่าง → เปิดหน้าเลือกปีทับทันที
    // flow เดิม: เลือกปี → ดาวน์โหลด → กลับมาเห็นแปลงบนแผนที่เดิม
    if (widget.parcelBrowser && widget.autoPromptDownload) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final v = context.read<MapViewModel>();
        if (v.parcels.isEmpty && !v.loading) _openDownload(v);
      });
    }
  }

  /// Push หน้าเลือกปี/ดาวน์โหลดทับแผนที่ — unmount GoogleMap ระหว่าง
  /// ถูกคลุม (platform view กิน GPU หนัก) แล้วเอาผลลัพธ์มาแสดงต่อ
  Future<void> _openDownload(MapViewModel vm) async {
    setState(() => _formOpen = true);
    final result = await Navigator.of(context).push<PlotDownloadResult>(
      MaterialPageRoute(
        builder: (_) => PlotDownloadView(viewModel: vm.createDownloadVm()),
      ),
    );
    if (!mounted) return;
    setState(() => _formOpen = false);
    if (result == null) return;
    vm.applyDownload(result.page, result.selected);
    _fitParcels(vm);
  }

  /// Push หน้า "ข้อมูลฉบับร่าง" — unmount GoogleMap ระหว่างถูกคลุม;
  /// ถ้ามีร่างถูกลบ (pop คืน true) → refetch กรอบปัจจุบันให้
  /// แปลงร่างที่ถูกลบหายจากแผนที่ทันที
  Future<void> _openDrafts(MapViewModel vm) async {
    setState(() => _formOpen = true);
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => DraftsView(vm: vm.createDraftsVm()),
      ),
    );
    if (!mounted) return;
    setState(() => _formOpen = false);
    if (changed != true) return;
    final r = await _controller?.getVisibleRegion();
    if (r == null || !mounted) return;
    vm.loadViewport(
      r.southwest.longitude,
      r.southwest.latitude,
      r.northeast.longitude,
      r.northeast.latitude,
    );
  }

  /// Numbered sky-pin bitmaps for draft points — สีเดียวกับเส้น
  /// polygon ที่กำลังวาด (ฟ้า=กำลังวาด/ทอง=ร่าง/แดง=บันทึกแล้ว)
  final _pinIcons = <int, BitmapDescriptor>{};

  /// Green-ringed variants shown while a pin is selected for moving.
  final _pinSelIcons = <int, BitmapDescriptor>{};

  /// Draft pin index currently armed for tap-to-move (0-based).
  int? _movingIndex;

  /// ฟอร์ม/route ทับแผนที่เต็มจอ — แผนที่ยัง mount อยู่แต่ถูกคลุม
  /// ด้วยพื้นทึบ (ไม่ unmount: สร้าง platform view ใหม่ขณะ
  /// transition แล้ว render ดำค้างบน emulator)
  bool _formOpen = false;

  /// info sheet ลากขึ้นทับเต็มจอ — คลุมแผนที่แบบเดียวกับ [_formOpen]
  /// แล้วเปิดออกตอน sheet หด/ปิด
  bool _infoSheetCovered = false;

  /// GPS auto-locate runs only on the first map creation — a
  /// remount after the form closes keeps the user's last camera.
  bool _didInitialLocate = false;

  /// true เมื่อ locate ครั้งแรกจบแล้ว — GoogleMap mount หลังจาก
  /// นี้เท่านั้น เพื่อให้ initialCamera เป็นตำแหน่งจริงทันที
  /// (ไม่แสดงจุด fallback ก่อนแล้วค่อย animate กลับมา)
  bool _locateReady = false;

  /// Memoized saved-parcel polygons — rebuilt only when the
  /// renderable list instance changes (not on every GPS fix).
  List<Parcel>? _polySrc;
  Set<Polygon> _polyCache = const {};

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
      ..drawCircle(c, size / 2 - 2 * ratio, ui.Paint()..color = AppColors.sky)
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
  /// fall back to a plain blue pin until their numbered icon is ready).
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
  /// Ignored while walk-measuring — pins come from the GPS stream.
  void _onMapTap(LatLng p, MapViewModel vm) {
    if (vm.walking) return;
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

  /// Last GPS fix the camera already followed (walk mode).
  ll.LatLng? _followedFix;

  /// Moves the camera to the user's GPS position. [auto] is used when
  /// the page opens — it suppresses error toasts and returns false so
  /// the caller can fall back to fitting the parcels.
  Future<bool> _locate(MapViewModel vm, {bool auto = false}) async {
    if (mounted) setState(() => _locating = true);
    try {
      final pos = await vm.locate();
      if (pos == null) throw 'เปิด GPS แล้วอนุญาตตำแหน่ง';
      if (!mounted) return true;
      setState(() => _locationGranted = true);
      await _controller?.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(pos.latitude, pos.longitude), 17),
      );
      return true;
    } catch (e) {
      if (mounted && !auto) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
      return false;
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  /// On page open: jump to the user's current position; if GPS /
  /// permission is unavailable, fit the camera around the parcels.
  Future<void> _initialLocate(MapViewModel vm) async {
    if (!await _locate(vm, auto: true)) _fitParcels(vm);
  }

  /// เปิดแผนที่พร้อมแปลงเป้าหมาย (จากกิจกรรมแปลง) — บินไปกรอบแปลง
  /// นั้นแทน GPS ของตัวเอง แล้วเด้ง sheet ข้อมูลขึ้นมาทันที
  Future<void> _focusInitialParcel(MapViewModel vm) async {
    final p = widget.focusParcel!;
    if (p.points.length >= 2) {
      var s = p.points.first.latitude, n = s;
      var w = p.points.first.longitude, e = w;
      for (final x in p.points) {
        if (x.latitude < s) s = x.latitude;
        if (x.latitude > n) n = x.latitude;
        if (x.longitude < w) w = x.longitude;
        if (x.longitude > e) e = x.longitude;
      }
      // pad เล็กน้อยกันแปลงเล็กมาก zoom จนแตก
      const pad = 0.0005;
      await _controller?.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(s - pad, w - pad),
            northeast: LatLng(n + pad, e + pad),
          ),
          60,
        ),
      );
    } else {
      final c = p.centerOverride ?? (p.points.isNotEmpty ? p.points.first : null);
      if (c != null) {
        await _controller?.animateCamera(
          CameraUpdate.newLatLngZoom(_ll(c), 17),
        );
      }
    }
    if (mounted) _showParcelInfo(p, vm);
  }

  /// จุดกลางของ focusParcel — ใช้เป็น initialCamera ตั้งแต่เฟรมแรก
  /// จะได้ไม่กระโดดจากตำแหน่ง GPS ไปแปลงทีหลัง
  ll.LatLng? get _focusCenter {
    final p = widget.focusParcel;
    if (p == null) return null;
    if (p.centerOverride != null) return p.centerOverride;
    if (p.points.isEmpty) return null;
    var s = p.points.first.latitude, n = s;
    var w = p.points.first.longitude, e = w;
    for (final x in p.points) {
      if (x.latitude < s) s = x.latitude;
      if (x.latitude > n) n = x.latitude;
      if (x.longitude < w) w = x.longitude;
      if (x.longitude > e) e = x.longitude;
    }
    return ll.LatLng((s + n) / 2, (w + e) / 2);
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
                    MapTypeThumb(
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

  /// Saved-parcel polygon set — identical [renderableParcels] list
  /// instance หมายถึงข้อมูล/กรอบ/filter ไม่เปลี่ยน ใช้ชุดเดิมได้เลย
  /// (กัน allocate Polygon ใหม่หลายพันตัวทุก GPS fix)
  Set<Polygon> _polygons(MapViewModel vm) {
    final src = vm.renderableParcels;
    if (!identical(src, _polySrc)) {
      _polySrc = src;
      _polyCache = {
        for (final p in src)
          Polygon(
            polygonId: PolygonId(p.id),
            points: [for (final x in p.points) _ll(x)],
            fillColor: (p.isDraft ? AppColors.gold : Colors.red).withValues(
              alpha: 0.3,
            ),
            strokeColor: p.isDraft ? AppColors.gold : Colors.red,
            strokeWidth: 3,
            // โหมดแผนที่แปลง — แตะแปลงเด้งข้อมูลขึ้นมา
            consumeTapEvents: widget.parcelBrowser,
            onTap: widget.parcelBrowser
                ? () => _showParcelInfo(p, vm)
                : null,
          ),
      };
    }
    return {
      ..._polyCache,
      // ขอบที่กำลังวาด — สร้างใหม่ทุกครั้ง (ตัวเดียว ถูกมาก)
      if (vm.draft.length >= 3)
        Polygon(
          polygonId: const PolygonId('draft'),
          points: [for (final x in vm.draft) _ll(x)],
          fillColor: AppColors.sky.withValues(alpha: 0.3),
          strokeColor: AppColors.sky,
          strokeWidth: 3,
        ),
    };
  }

  /// แตะแปลง → sheet ข้อมูลจริงของแปลงนั้น — เปิดทันทีด้วยข้อมูลที่
  /// มีอยู่ แล้ว VM ดึง /plots/:id มาเติม meta (bulk payload ไม่ฝัง
  /// meta หนักๆ ทำให้ดาวน์โหลดเร็วขึ้นมาก) — UI อยู่ใน
  /// parcel_info_sheet.dart
  void _showParcelInfo(Parcel p, MapViewModel vm) {
    showParcelInfoSheet(
      context,
      vm: vm.detailVmFor(p),
      onCovered: (covered) {
        if (mounted && covered != _infoSheetCovered) {
          setState(() => _infoSheetCovered = covered);
        }
      },
    ).whenComplete(() {
      // sheet ถูกปิดทิ้งตอนทับอยู่ — mount แผนที่กลับ
      if (mounted && _infoSheetCovered) {
        setState(() => _infoSheetCovered = false);
      }
    });
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
    // Follow the walker — pan the camera onto each new GPS fix.
    final fix = vm.lastFix;
    if (!_formOpen && vm.walking && fix != null && fix != _followedFix) {
      _followedFix = fix;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _controller?.animateCamera(CameraUpdate.newLatLng(_ll(fix)));
      });
    }
    // Edge-to-edge map: transparent status bar, light icons for the
    // satellite imagery behind it.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
      ),
      child: Scaffold(
        // skeleton ค้างไว้จนกว่า locate ครั้งแรกจะจบ (max 1.5วิ) —
        // GoogleMap mount ช้ากว่านิดแต่กล้องอยู่ตำแหน่งจริงตั้งแต่เฟรมแรก
        // + crossfade ให้เปลี่ยนผ่านนุ่ม ไม่ตัดจอทีเดียว
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          child: vm.loading || !_locateReady
              ? MapSkeleton(
                  key: const ValueKey('skel'),
                  parcelBrowser: widget.parcelBrowser,
                )
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
              : Stack(
                  children: [
                    // GoogleMap อยู่ใน tree ตลอด — ตอนฟอร์ม/sheet ทับ
                    // ให้คลุมด้วยพื้นทึบแทน unmount: การทำลาย platform
                    // view แล้วสร้างใหม่ขณะ transition ทำให้บน
                    // emulator/เครื่องบางรุ่น render ดำค้าง
                    GoogleMap(
                        // ตำแหน่งจริงเฉพาะ mount แรกที่ locate() เสร็จ
                        // แล้ว — remount หลังปิดฟอร์มใช้ _camera เดิม
                        // เพื่อไม่กระโดดกลับจุดผู้ใช้ทิ้งตำแหน่งที่เลื่อนไว้
                        initialCameraPosition:
                            widget.focusParcel != null &&
                                _focusCenter != null
                            ? CameraPosition(target: _ll(_focusCenter!), zoom: 15)
                            : (!_didInitialLocate && vm.userPos != null
                                  ? CameraPosition(
                                      target: _ll(vm.userPos!),
                                      zoom: 17,
                                    )
                                  : _camera),
                        onMapCreated: (c) {
                          _controller = c;
                          if (!_didInitialLocate) {
                            _didInitialLocate = true;
                            final v = context.read<MapViewModel>();
                            if (widget.focusParcel != null) {
                              _focusInitialParcel(v);
                            } else {
                              _initialLocate(v);
                            }
                          }
                        },
                        onCameraMove: (pos) {
                          // rebuild เฉพาะตอนหมุนแผนที่ (bearing เปลี่ยน)
                          // เพื่อให้เข็มทิศหมุนตาม — pan ปกติไม่ setState
                          final rotated =
                              (pos.bearing - _camera.bearing).abs() > 0.5;
                          _camera = pos;
                          if (rotated) setState(() {});
                        },
                        // เลื่อน/ซูมเสร็จ → โหลดแปลงเฉพาะกรอบที่เห็น
                        // ใหม่ (แถบโหลดบางๆ ขึ้นด้านบนขณะรอ)
                        onCameraIdle: () async {
                          final r = await _controller?.getVisibleRegion();
                          if (r == null || !context.mounted) return;
                          context.read<MapViewModel>().loadViewport(
                            r.southwest.longitude,
                            r.southwest.latitude,
                            r.northeast.longitude,
                            r.northeast.latitude,
                          );
                        },
                        onTap: (p) => _onMapTap(p, vm),
                        mapType: _mapType,
                        // satellite/hybrid ไม่รองรับ indoor แล้ว — ปิดไว้
                        // กัน deprecation warning จาก Maps SDK
                        indoorViewEnabled: false,
                        compassEnabled: true,
                        zoomControlsEnabled: false,
                        // ดันเนื้อแผนที่ขึ้นเหนือแถบวัดที่ลอยทับ —
                        // หมุด/draft ใกล้ขอบล่างไม่จมใต้แถบขาว
                        padding: EdgeInsets.only(
                          bottom: widget.parcelBrowser
                              ? 0
                              : vm.drawing
                              ? (vm.walking ? 210 : 160)
                              : 110,
                        ),
                        myLocationEnabled: _locationGranted && !_formOpen,
                        myLocationButtonEnabled: false,
                        polygons: _polygons(vm),
                        markers: {
                          // Red pin marks the user's position — updated
                          // by the GPS button or live fixes while walking.
                          if (vm.userPos != null)
                            Marker(
                              markerId: const MarkerId('me'),
                              position: _ll(vm.userPos!),
                              icon: BitmapDescriptor.defaultMarkerWithHue(
                                BitmapDescriptor.hueRed,
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
                                      ? _pinSelIcons[i + 1] ?? _pinIcons[i + 1]
                                      : _pinIcons[i + 1]) ??
                                  BitmapDescriptor.defaultMarkerWithHue(
                                    BitmapDescriptor.hueAzure,
                                  ),
                            ),
                        },
                      ),
                    // พื้นทึบคลุมแผนที่ตอนฟอร์ม/sheet ทับอยู่ — กันแตะ
                    // แผนที่รอดผ่าน + หน้าจอไม่ดำตอน remount
                    if (_formOpen || _infoSheetCovered)
                      const Positioned.fill(
                        child: AbsorbPointer(
                          child: ColoredBox(color: Color(0xFFE8E6E1)),
                        ),
                      ),
                    // แถบโหลดบางๆ ขณะดึงแปลงของกรอบจอใหม่
                    if (vm.loadingViewport)
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: const LinearProgressIndicator(
                          minHeight: 3,
                          color: AppColors.green,
                          backgroundColor: Colors.transparent,
                        ),
                      ),
                    // Back button floats over the map (no AppBar —
                    // the map runs edge-to-edge under the status bar).
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 12,
                      left: 16,
                      child: GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: const MapButton(
                          icon: Iconsax.arrow_left,
                          loading: false,
                        ),
                      ),
                    ),
                    // ฟิลเตอร์ปีการผลิต — เลือกปีแล้วแผนที่แสดง
                    // เฉพาะแปลงของปีนั้น (draft แสดงเสมอ)
                    if (vm.years.isNotEmpty)
                      Positioned(
                        top: MediaQuery.of(context).padding.top + 12,
                        left: 76,
                        child: Container(
                          height: 48,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: const [
                              BoxShadow(color: Colors.black26, blurRadius: 6),
                            ],
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(24),
                            onTap: () async {
                              final labels = [
                                'ทุกปีการผลิต',
                                ...vm.years,
                              ];
                              final i = await showOptionPopup(
                                context,
                                title: 'ปีการผลิต',
                                labels: labels,
                                selectedIndex: vm.yearFilter == null
                                    ? 0
                                    : vm.years.indexOf(vm.yearFilter!) + 1,
                              );
                              if (i != null) {
                                vm.setYearFilter(
                                  i == 0 ? null : vm.years[i - 1],
                                );
                              }
                            },
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Iconsax.calendar_1,
                                  size: 18,
                                  color: AppColors.green,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  vm.yearFilter ?? 'ทุกปีการผลิต',
                                  style: const TextStyle(fontSize: 14),
                                ),
                                const SizedBox(width: 4),
                                const Icon(
                                  Iconsax.arrow_down_1,
                                  size: 18,
                                  color: AppColors.green,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    // ประเภทแผนที่ + เข็มทิศ + GPS — Google-Maps-style
                    // controls; structured so a backend-driven config
                    // can replace the local state later.
                    // โหมดวัดมีแถบล่างลอยทับ — ยกปุ่มขึ้นเหนือแถบ
                    Positioned(
                      right: 16,
                      bottom: widget.parcelBrowser
                          ? 16
                          : vm.drawing
                          ? (vm.walking ? 226 : 166)
                          : 116,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // เข็มทิศสไตล์ Google Maps — โผล่เฉพาะตอน
                          // แผนที่ถูกหมุน เข็มแดงชี้เหนือจริงตาม bearing
                          if (_camera.bearing.abs() > 0.5)
                            GestureDetector(
                              onTap: _resetNorth,
                              child: CompassButton(bearing: _camera.bearing),
                            ),
                          if (_camera.bearing.abs() > 0.5)
                            const SizedBox(height: 10),
                          GestureDetector(
                            onTap: _locating ? null : () => _locate(vm),
                            child: MapButton(
                              icon: Iconsax.gps,
                              loading: _locating,
                            ),
                          ),
                          const SizedBox(height: 10),
                          GestureDetector(
                            onTap: _pickMapType,
                            child: const MapButton(
                              icon: Iconsax.layer,
                              loading: false,
                            ),
                          ),
                          const SizedBox(height: 10),
                          // ดาวน์โหลดแปลง — เฉพาะโหมดแผนที่แปลง
                          if (widget.parcelBrowser) ...[
                            GestureDetector(
                              onTap: () => _openDownload(vm),
                              child: const MapButton(
                                icon: Iconsax.import,
                                loading: false,
                              ),
                            ),
                            const SizedBox(height: 10),
                          ],
                          // ร่างในเครื่อง — โชว์เฉพาะตอนมีร่างจริง
                          // (ไม่มีก็ไม่ต้องมีปุ่มให้กดเปล่า)
                          if (vm.parcels.any((p) => p.isDraft))
                            GestureDetector(
                              onTap: () => _openDrafts(vm),
                              child: const MapButton(
                                icon: Iconsax.document_text,
                                loading: false,
                              ),
                            ),
                        ],
                      ),
                    ),
                    // โหมดแผนที่แปลง + แผนที่ว่าง — ชวนกดดาวน์โหลด
                    // เฉพาะเข้าจากเมนูหลัก (autoPrompt) — เข้าจาก
                    // หน้าอื่น (กิจกรรมแปลง) ปุ่มนี้ไม่โชว์ มีไอคอน
                    // ดาวน์โหลดลอยอยู่แล้ว; รอจน fetch แรกจบก่อน
                    // ค่อยตัดสินว่าว่างจริง
                    if (widget.parcelBrowser &&
                        widget.autoPromptDownload &&
                        vm.parcels.isEmpty &&
                        !vm.loading &&
                        !vm.loadingViewport)
                      Center(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 14,
                            ),
                          ),
                          onPressed: () => _openDownload(vm),
                          icon: const Icon(Iconsax.import, size: 22),
                          label: const Text(
                            'ดาวน์โหลดข้อมูลแปลง',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    // Overlay กันกดซ้ำระหว่าง POST /plots — ครอบทั้ง
                    // แผนที่จนกว่าบันทึกจะเสร็จ
                    if (vm.saving)
                      Positioned.fill(
                        child: Container(
                          color: Colors.black38,
                          child: const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(color: Colors.white),
                                SizedBox(height: 12),
                                Text(
                                  'กำลังบันทึกแปลง...',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    // แถบวัดลอยทับขอบล่างแผนที่ — แผง GPS เลื่อนขึ้นมา
                    // ครอบบนแผนที่โดยไม่บีบ platform view (จุดหน่วง
                    // หลัก: resize GoogleMap ทุกเฟรมลาก)
                    if (!widget.parcelBrowser)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: MapBottomBar(
                          vm: vm,
                          movingIndex: _movingIndex,
                          onFormOpen: (v) => setState(() => _formOpen = v),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

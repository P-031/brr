import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax/iconsax.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:provider/provider.dart';

import 'package:brr/core/theme/app_theme.dart';
import 'package:brr/core/widgets/error_retry_view.dart';
import 'package:brr/core/widgets/plot_filter_sheet.dart';
import 'package:brr/features/map/models/parcel.dart';
import 'package:brr/features/map/viewmodels/map_viewmodel.dart';
import 'package:brr/features/map/viewmodels/plot_download_viewmodel.dart';
import 'package:brr/features/map/views/drafts_view.dart';
import 'package:brr/features/map/views/plot_download_view.dart';
import 'package:brr/features/map/widgets/map_bottom_bar.dart';
import 'package:brr/features/map/widgets/map_skeleton.dart';
import 'package:brr/features/map/widgets/map_widgets.dart';
import 'package:brr/features/map/widgets/parcel_info_sheet.dart';
import 'package:brr/features/map/widgets/risk_point_sheet.dart';
part 'map_view_interactions.dart';
part 'map_view_sections.dart';

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
    // rebuild ตอนโฟกัสช่องค้นหาเปลี่ยน — dropdown แนะนำ
    // โชว์เฉพาะตอนโฟกัสอยู่ (เลือกแปลงแล้วหลุดโฟกัส = ซ่อน)
    _searchFocus.addListener(() {
      if (mounted) setState(() {});
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
        if (v.parcels.isEmpty && !v.loading) {
          _openDownload(v, autoPrompt: true);
        }
      });
    }
  }

  /// Numbered green-pin bitmaps for draft points — สีเดียวกับเส้น
  /// polygon ที่กำลังวาด/ร่างไว้ (เขียว=ร่าง ฟ้า=บันทึกไม่มีสถานะ)
  final _pinIcons = <int, BitmapDescriptor>{};

  /// Gold-ringed variants shown while a pin is selected for moving.
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

  /// ช่องค้นหาแปลงบนแผนที่ + debounce กัน filter 30k ทุก keystroke
  /// focus node ใช้ซ่อน dropdown แนะนำตอนหลุดโฟกัส (เลือกแปลงแล้ว)
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  Timer? _searchDebounce;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// setState ผ่าน helper — method ใน part file เป็น extension
  /// บน state นี้ เรียก setState (@protected) ตรงๆ ไม่ได้
  void _set(VoidCallback fn) => setState(fn);

  /// Memoized saved-parcel polygons — rebuilt only when the
  /// renderable list instance changes (not on every GPS fix).
  List<Parcel>? _polySrc;
  Map<String, String>? _riskSrc;
  Set<Polygon> _polyCache = const {};

  /// Renders a numbered green pin (ring + white bold index) as a
  /// marker bitmap — draft pins show their tap order like stakes.
  static Future<BitmapDescriptor> _numberedPin(
    int n, {
    ui.Color ring = Colors.white,
    ui.Color color = AppColors.pink,
  }) {
    // Drawn at 3x then scaled down — crisp edges on hi-dpi screens.
    const ratio = 3.0;
    const size = 35.0 * ratio;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    const c = ui.Offset(size / 2, size / 2);
    canvas
      ..drawCircle(c, size / 2 - 2 * ratio, ui.Paint()..color = color)
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
      // encode ล้มเหลวได้ (เครื่องหน่วยความจำต่ำ) — คืนหมุดเขียว
      // fallback ตัวเดียวกับ marker แทนที่จะ throw ทิ้งทั้งชุด
      if (bytes == null) {
        return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen);
      }
      return BitmapDescriptor.bytes(
        bytes.buffer.asUint8List(),
        imagePixelRatio: ratio,
      );
    });
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
              ? ErrorRetryView(vm.error!, onRetry: vm.load)
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
                          widget.focusParcel != null && _focusCenter != null
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
                                  BitmapDescriptor.hueRose,
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
                    // โหลดแปลงของกรอบจอไม่สำเร็จ — เดิมเงียบทำให้เหมือน
                    // ไม่มีแปลง; แจ้งเตือน + แตะเพื่อลองใหม่
                    if (vm.viewportError != null && !vm.loadingViewport)
                      _viewportErrorBar(vm),
                    // Back button floats over the map (no AppBar —
                    // the map runs edge-to-edge under the status bar).
                    _backButton(),
                    // แถวบน: ช่องค้นหาแปลง + ปุ่มฟิลเตอร์ปีการผลิต
                    // (ค้นหากรอง polygon ที่แสดง / ปีกรองเหมือนเดิม)
                    _searchBar(vm),
                    // ประเภทแผนที่ + เข็มทิศ + GPS — Google-Maps-style
                    // controls; structured so a backend-driven config
                    // can replace the local state later.
                    // โหมดวัดมีแถบล่างลอยทับ — ยกปุ่มขึ้นเหนือแถบ
                    _controlButtons(vm),
                    // dropdown แนะนำใต้ช่องค้นหา — แปลงที่ match
                    // สูงสุด 8 รายการ (เห็น ~5 แถว เลื่อนดูได้) แตะ =
                    // zoom ไปแปลงนั้น; วางหลังคอลัมน์ปุ่มลอยเพื่อให้
                    // ทับเหนือปุ่มเสมอ
                    if (vm.searchQuery.isNotEmpty &&
                        vm.searchSuggestions.isNotEmpty &&
                        _searchFocus.hasFocus)
                      _searchSuggestions(vm),
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
                      _emptyDownloadPrompt(vm),
                    // Overlay กันกดซ้ำระหว่าง POST /plots — ครอบทั้ง
                    // แผนที่จนกว่าบันทึกจะเสร็จ
                    if (vm.saving) _savingOverlay(),
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

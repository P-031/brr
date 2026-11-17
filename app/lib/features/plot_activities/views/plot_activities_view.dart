import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax/iconsax.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:provider/provider.dart';

import 'package:brr/core/services/api_client.dart';
import 'package:brr/core/theme/app_theme.dart';
import 'package:brr/features/map/data/parcel_service.dart';
import 'package:brr/features/map/models/parcel.dart';
import 'package:brr/features/map/viewmodels/map_viewmodel.dart';
import 'package:brr/features/map/widgets/map_widgets.dart';
import 'package:brr/features/map/widgets/parcel_outline.dart';
import 'package:brr/features/map/views/map_view.dart';
import 'package:brr/features/plot_activities/models/plot_list_item.dart';
import 'package:brr/features/plot_activities/viewmodels/plot_activities_viewmodel.dart';

/// กิจกรรมแปลง — แผนที่ย่อ 1/3 จอ + การ์ดรายละเอียดแปลงทีละ 30
/// + ฟิลเตอร์จาก backend (ปีการผลิต/เขต/ประเภทอ้อย/สถานะปลูก/กลุ่ม)
class PlotActivitiesView extends StatelessWidget {
  const PlotActivitiesView({required this.api, super.key});

  final ApiClient? api;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => PlotActivitiesViewModel(ParcelService(api)),
    child: _Body(api: api),
  );
}

class _Body extends StatefulWidget {
  const _Body({required this.api});

  final ApiClient? api;

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  GoogleMapController? _mapCtrl;
  List<PlotListItem>? _fittedItems;
  String? _lastFocusedId;
  MapType _mapType = MapType.satellite;
  CameraPosition _miniCam = const CameraPosition(
    target: LatLng(15.2, 103.1),
    zoom: 10,
  );

  static const _mapTypes = {'แผนที่': MapType.normal, 'ดาวเทียม': MapType.satellite};
  static const _mapTypeAssets = {
    'แผนที่': 'assets/images/maptype_normal.png',
    'ดาวเทียม': 'assets/images/maptype_satellite.jpg',
  };

  void _resetNorth() => _mapCtrl?.animateCamera(
    CameraUpdate.newCameraPosition(
      CameraPosition(target: _miniCam.target, zoom: _miniCam.zoom),
    ),
  );

  /// sheet เลือกประเภทแผนที่ — สไตล์เดียวกับหน้าวัดพื้นที่
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

  /// เลือกการ์ด → กล้องแผนที่ย่อบินไปที่กลางแปลงนั้น
  void _maybeFocusSelected(PlotActivitiesViewModel vm) {
    final sel = vm.selected;
    if (sel == null ||
        sel.centerLat == null ||
        sel.centerLng == null ||
        _lastFocusedId == sel.id) {
      return;
    }
    _lastFocusedId = sel.id;
    final ctrl = _mapCtrl;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ctrl?.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(sel.centerLat!, sel.centerLng!),
          17,
        ),
      );
    });
  }

  /// ปรับกล้องให้เห็นแปลงที่โหลดมาทั้งหมด — refit เมื่อชุด items เปลี่ยน
  void _maybeFit(PlotActivitiesViewModel vm) {
    if (_mapCtrl == null || vm.items.isEmpty || identical(_fittedItems, vm.items)) {
      return;
    }
    _fittedItems = vm.items;
    final ctrl = _mapCtrl;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ctrl == null || !mounted) return;
      double minLat = 90, maxLat = -90, minLng = 180, maxLng = -180;
      var n = 0;
      for (final p in vm.items) {
        final lat = p.centerLat;
        final lng = p.centerLng;
        if (lat == null || lng == null) continue;
        n++;
        if (lat < minLat) minLat = lat;
        if (lat > maxLat) maxLat = lat;
        if (lng < minLng) minLng = lng;
        if (lng > maxLng) maxLng = lng;
      }
      if (n == 0) return;
      const pad = 0.005; // ~500 ม. กันจุดเดียว zoom ลึกเกิน
      ctrl.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(minLat - pad, minLng - pad),
            northeast: LatLng(maxLat + pad, maxLng + pad),
          ),
          30,
        ),
      );
    });
  }

  /// ปุ่ม "แสดงผลบนแผนที่" → MapView เต็มจอโหมดแผนที่แปลง
  /// (ไม่เด้งหน้าดาวน์โหลดซ้ำ; ฟิลเตอร์ปีส่งต่อให้ viewport fetch ด้วย)
  void _openFullMap(PlotActivitiesViewModel vm) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MapView(
          parcelBrowser: true,
          autoPromptDownload: false,
          createViewModel: () => MapViewModel(
            api: widget.api,
            canDrawManually: false,
            yearAllowlist: vm.years.isEmpty ? null : {...vm.years},
          ),
        ),
      ),
    );
  }

  /// ปุ่ม "เลือก" บนการ์ด — mark การ์ดไว้ + เด้งไปแผนที่เต็มจอบินไป
  /// แปลงนั้นและแสดง sheet ข้อมูลแปลงทันที (polygon แปลงถูก seed
  /// เข้าแผนที่ด้วย เห็นขอบแปลงแม้ยังไม่ได้ดาวน์โหลดชุดนั้น)
  void _openParcelMap(PlotListItem item, PlotActivitiesViewModel vm) {
    if (vm.selectedId != item.id) vm.select(item.id);
    final parcel = Parcel(
      id: item.id,
      name: item.name,
      owner: item.farmerName,
      productionYear: item.productionYear,
      points: item.points,
      centerOverride:
          item.centerLat != null && item.centerLng != null
          ? ll.LatLng(item.centerLat!, item.centerLng!)
          : null,
      meta: {
        if (item.sequenceNo != null) 'sequenceNo': item.sequenceNo,
        if (item.rootNo != null) 'rootNo': item.rootNo,
        if (item.village != null) 'village': item.village,
        if (item.subdistrict != null) 'subdistrict': item.subdistrict,
        if (item.district != null) 'district': item.district,
        if (item.province != null) 'province': item.province,
        if (item.caneType != null) 'caneType': item.caneType,
        if (item.caneVariety != null) 'caneVariety': item.caneVariety,
        if (item.caneGroup != null) 'caneGroup': item.caneGroup,
        if (item.zone != null) 'zone': item.zone,
      },
    );
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MapView(
          parcelBrowser: true,
          autoPromptDownload: false,
          focusParcel: parcel,
          createViewModel: () => MapViewModel(
            api: widget.api,
            canDrawManually: false,
            initialParcels: [parcel],
            yearAllowlist: vm.years.isEmpty ? null : {...vm.years},
          ),
        ),
      ),
    );
  }

  Future<void> _openFilters(PlotActivitiesViewModel vm) {
    // snapshot ค่าปัจจุบันเป็น Set — apply ทีเดียวตอนกด "ใช้ตัวกรอง"
    var years = {...vm.years};
    var zones = {...vm.zones};
    var caneTypes = {...vm.caneTypes};
    var planted = {...vm.planted};
    var groupKinds = {...vm.groupKinds};
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Iconsax.setting_4, color: AppColors.green),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'ตัวกรองแปลง',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => setS(() {
                        years.clear();
                        zones.clear();
                        caneTypes.clear();
                        planted.clear();
                        groupKinds.clear();
                      }),
                      child: const Text('ล้างทั้งหมด'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _filterMulti<String>(
                  label: 'ปีการผลิต',
                  selected: years,
                  options: {for (final y in vm.yearOptions) y: y},
                  onChanged: (s) => setS(() {}),
                ),
                const SizedBox(height: 12),
                _filterMulti<String>(
                  label: 'เขต',
                  selected: zones,
                  options: {for (final z in vm.zoneOptions) z: z},
                  onChanged: (s) => setS(() {}),
                ),
                const SizedBox(height: 12),
                _filterMulti<String>(
                  label: 'ประเภทของอ้อย',
                  selected: caneTypes,
                  options: {for (final t in vm.caneTypeOptions) t: t},
                  onChanged: (s) => setS(() {}),
                ),
                const SizedBox(height: 12),
                _filterMulti<bool>(
                  label: 'สถานะการปลูก',
                  selected: planted,
                  options: const {true: 'ปลูกแล้ว', false: 'ยังไม่ปลูก'},
                  onChanged: (s) => setS(() {}),
                ),
                const SizedBox(height: 12),
                _filterMulti<String>(
                  label: 'กลุ่มงาน',
                  selected: groupKinds,
                  options: const {
                    'harvest': 'กลุ่มตัด',
                    'maintain': 'กลุ่มบำรุง',
                  },
                  onChanged: (s) => setS(() {}),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    vm.applyFilters(
                      years: years,
                      zones: zones,
                      caneTypes: caneTypes,
                      planted: planted,
                      groupKinds: groupKinds,
                    );
                  },
                  icon: const Icon(Iconsax.tick_circle),
                  label: const Text('ใช้ตัวกรอง'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.green,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _filterMulti<T>({
    required String label,
    required Set<T> selected,
    required Map<T, String> options,
    required ValueChanged<Set<T>> onChanged,
  }) {
    final display = selected.isEmpty
        ? 'ทั้งหมด'
        : selected.length == 1
        ? (options[selected.first] ?? 'ทั้งหมด')
        : 'เลือกแล้ว ${selected.length}';
    final active = selected.isNotEmpty;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _pickMulti<T>(
        label: label,
        selected: selected,
        options: options,
        onChanged: onChanged,
      ),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(
            color: active ? AppColors.green : null,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
          ),
          border: const OutlineInputBorder(),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(
              color: active ? AppColors.green : const Color(0xFF9E9E9E),
              width: active ? 1.5 : 1,
            ),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          suffixIcon: Icon(
            Iconsax.arrow_down_1,
            size: 18,
            color: active ? AppColors.green : null,
          ),
        ),
        child: Text(
          display,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15),
        ),
      ),
    );
  }

  /// ตัวเลือกเด้งเป็น bottom sheet — เลือกได้หลายค่า (toggle)
  /// "ทั้งหมด" = ล้าง selection; กด "เสร็จ" หรือแตะพื้นหลังเพื่อปิด
  void _pickMulti<T>({
    required String label,
    required Set<T> selected,
    required Map<T, String> options,
    required ValueChanged<Set<T>> onChanged,
  }) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          void toggle(T key) {
            setSheet(() {
              if (selected.contains(key)) {
                selected.remove(key);
              } else {
                selected.add(key);
              }
            });
            onChanged(selected); // อัปเดตข้อความบนช่องใน filter sheet
          }

          Widget tile(String text, bool on, VoidCallback onTap) => Padding(
            padding: const EdgeInsets.fromLTRB(16, 5, 16, 5),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onTap, // toggle เฉยๆ ไม่ปิด sheet
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: on ? const Color(0xFFE8F5E9) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: on ? AppColors.green : const Color(0xFFDDDDDD),
                    width: on ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        text,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight:
                              on ? FontWeight.w700 : FontWeight.w400,
                          color: on ? AppColors.green : Colors.black87,
                        ),
                      ),
                    ),
                    if (on)
                      const Icon(
                        Iconsax.tick_circle,
                        color: AppColors.green,
                        size: 22,
                      ),
                  ],
                ),
              ),
            ),
          );
          return SafeArea(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            label,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: const Text('เสร็จ'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  tile('ทั้งหมด', selected.isEmpty, () {
                    setSheet(() => selected.clear());
                    onChanged(selected);
                  }),
                  for (final e in options.entries)
                    tile(
                      e.value,
                      selected.contains(e.key),
                      () => toggle(e.key),
                    ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<PlotActivitiesViewModel>();
    _maybeFit(vm);
    _maybeFocusSelected(vm);
    // ไม่มี AppBar เขียว — แผนที่ย่อขึ้นไปชิดขอบบนของจอทับ status bar
    // เหมือนหน้าวัดพื้นที่ ปุ่ม back/เข็มทิศ/ประเภทแผนที่/ซูม ลอยอยู่บนแผนที่
    final topPad = MediaQuery.of(context).padding.top;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
      ),
      child: Scaffold(
        body: Column(
          children: [
            SizedBox(
              height: MediaQuery.sizeOf(context).height / 3 + topPad,
              child: Stack(
                children: [
                  GoogleMap(
                    initialCameraPosition: const CameraPosition(
                      target: LatLng(15.2, 103.1),
                      zoom: 10,
                    ),
                    // แผนที่ถนน — ภาพดาวเทียมพื้นที่ไร่อ้อยเขียวล้วน
                    // ดูเหมือนพื้นสีเขียวเปล่าๆ ไม่ใช่แผนที่
                    mapType: _mapType,
                    markers: {
                      for (final p in vm.items)
                        if (p.centerLat != null && p.centerLng != null)
                          Marker(
                            markerId: MarkerId(p.id),
                            position: LatLng(p.centerLat!, p.centerLng!),
                            icon: vm.selectedId == p.id
                                ? BitmapDescriptor.defaultMarkerWithHue(
                                    BitmapDescriptor.hueAzure,
                                  )
                                : BitmapDescriptor.defaultMarker,
                            infoWindow: InfoWindow(title: p.name),
                          ),
                    },
                    // เลื่อนดู + ซูม + หมุนได้ตามปกติ
                    scrollGesturesEnabled: true,
                    zoomGesturesEnabled: true,
                    rotateGesturesEnabled: true,
                    tiltGesturesEnabled: false,
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: false,
                    compassEnabled: false,
                    mapToolbarEnabled: false,
                    onMapCreated: (c) {
                      _mapCtrl = c;
                      _fittedItems = null;
                      _maybeFit(vm);
                    },
                    onCameraMove: (pos) {
                      // rebuild เฉพาะตอนหมุน — เข็มทิศต้องขึ้น/หมุนตาม
                      final rotated =
                          (pos.bearing - _miniCam.bearing).abs() > 0.5;
                      _miniCam = pos;
                      if (rotated) setState(() {});
                    },
                  ),
                  // ปุ่ม back ลอยมุมซ้ายบน — แทน AppBar เดิม
                  Positioned(
                    top: topPad + 12,
                    left: 16,
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: const MapButton(
                        icon: Iconsax.arrow_left,
                        loading: false,
                      ),
                    ),
                  ),
                  // controls ขวาบน — เข็มทิศ / ประเภทแผนที่ / ซูม +-
                  Positioned(
                    top: topPad + 12,
                    right: 16,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_miniCam.bearing.abs() > 0.5)
                          GestureDetector(
                            onTap: _resetNorth,
                            child: CompassButton(bearing: _miniCam.bearing),
                          ),
                        if (_miniCam.bearing.abs() > 0.5)
                          const SizedBox(height: 10),
                        GestureDetector(
                          onTap: _pickMapType,
                          child: const MapButton(
                            icon: Iconsax.layer,
                            loading: false,
                          ),
                        ),
                        const SizedBox(height: 10),
                        GestureDetector(
                          onTap: () => _mapCtrl?.animateCamera(
                            CameraUpdate.zoomIn(),
                          ),
                          child: const MapButton(
                            icon: Iconsax.add,
                            loading: false,
                          ),
                        ),
                        const SizedBox(height: 10),
                        GestureDetector(
                          onTap: () => _mapCtrl?.animateCamera(
                            CameraUpdate.zoomOut(),
                          ),
                          child: const MapButton(
                            icon: Iconsax.minus,
                            loading: false,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    onChanged: vm.setSearch,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'ค้นหาจาก ชื่อ, รหัสพื้นที่, รหัสชาวไร่',
                      hintStyle: const TextStyle(
                        fontSize: 14,
                        color: Colors.black38,
                      ),
                      prefixIcon: const Icon(
                        Iconsax.search_normal_1,
                        size: 20,
                        color: Colors.black45,
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Color(0xFFDDDDDD),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Color(0xFFDDDDDD),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _FilterButton(
                  count: vm.activeFilterCount,
                  onPressed: () => _openFilters(vm),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _openFullMap(vm),
                icon: const Icon(Iconsax.global, size: 22),
                label: Text(
                  'แสดงผลบนแผนที่ จำนวน [${vm.total}] รายการ',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.green,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ),
            Expanded(child: _listBody(vm)),
          ],
        ),
      ),
    );
  }

  Widget _listBody(PlotActivitiesViewModel vm) {
    if (vm.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (vm.items.isEmpty) {
      if (vm.error != null) {
        return _ErrorState(message: vm.error!, onRetry: vm.refresh);
      }
      return const Center(
        child: Text(
          'ไม่พบแปลงตามเงื่อนไข',
          style: TextStyle(fontSize: 16),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: vm.refresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        itemCount: vm.items.length + 1,
        itemBuilder: (ctx, i) {
          if (i == vm.items.length) {
            if (vm.loadingMore) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (!vm.hasMore) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: Text(
                    'แสดงครบ ${vm.items.length} แปลงแล้ว',
                    style: const TextStyle(
                      color: Colors.black45,
                      fontSize: 14,
                    ),
                  ),
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: vm.loadMore,
                  icon: const Icon(Iconsax.arrow_down, size: 22),
                  label: const Text(
                    'โหลดเพิ่ม',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.green,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            );
          }
          final item = vm.items[i];
          return _PlotCard(
            item: item,
            selected: vm.selectedId == item.id,
            onSelect: () => _openParcelMap(item, vm),
          );
        },
      ),
    );
  }
}

/// ปุ่มฟิลเตอร์ข้างแถบแผนที่ — ขอบเขียว + badge นับฟิลเตอร์ที่ใช้
class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.count, required this.onPressed});

  final int count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      SizedBox(
        height: 46,
        width: 46,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.green,
            side: const BorderSide(color: AppColors.green, width: 1.5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: EdgeInsets.zero,
          ),
          child: const Icon(Iconsax.setting_4, size: 20),
        ),
      ),
      if (count > 0)
        Positioned(
          top: -2,
          right: -2,
          child: CircleAvatar(
            radius: 9,
            backgroundColor: AppColors.gold,
            child: Text(
              '$count',
              style: const TextStyle(
                fontSize: 11,
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
    ],
  );
}

class _PlotCard extends StatelessWidget {
  const _PlotCard({
    required this.item,
    required this.selected,
    required this.onSelect,
  });

  final PlotListItem item;
  final bool selected;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final p = item;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? AppColors.green : const Color(0xFFE0E0E0),
          width: selected ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // รูปแปลงกรอบมน กึ่งกลางแนวตั้งของการ์ด
            ParcelOutline(points: p.points),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 5),
                  if (p.sequenceNo != null)
                    Text(
                      'เลขแปลง ${p.sequenceNo}',
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 15,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (p.farmerCode != null)
                    Text(
                      'รหัสชาวไร่ ${p.farmerCode}',
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 15,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (p.farmerName != null)
                    Text(
                      'ชาวไร่ ${p.farmerName}',
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 15,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 8),
                  // พื้นที่ชิดขวา (ย่อตัวเองถ้าแคบ)
                  Align(
                    alignment: Alignment.centerRight,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        'พื้นที่ ${p.areaThai}',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.green,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            // ปุ่มเลือกกึ่งกลางขวา
            _SelectButton(onPressed: onSelect),
          ],
        ),
      ),
    );
  }
}

/// ปุ่มเลือก — นิ่งเดิมตลอด (ไม่มี animation) เขียวทึบ "เลือก"
/// กดแล้วเด้งไปแผนที่เต็มจอแสดงข้อมูลแปลงนั้น
class _SelectButton extends StatelessWidget {
  const _SelectButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.green,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
      child: const Text('เลือก'),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Iconsax.warning_2, size: 56, color: Colors.black38),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onRetry,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.green,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text(
                'ลองอีกครั้ง',
                style: TextStyle(fontSize: 18),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

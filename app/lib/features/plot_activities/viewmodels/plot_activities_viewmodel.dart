import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import 'package:brr/core/services/api_client.dart';
import 'package:brr/features/map/data/location_service.dart';
import 'package:brr/features/map/data/parcel_service.dart';
import 'package:brr/features/map/data/satellite_thumb_service.dart';
import 'package:brr/features/map/models/sat_thumb.dart';
import 'package:brr/features/plot_activities/models/plot_list_item.dart';

/// หน้ากิจกรรมแปลง — รายการแปลงแบบเพจ (30/ครั้ง) + ตัวกรองจาก backend
/// ตัวเลือกฟิลเตอร์ (ปี/เขต/ประเภทอ้อย) ดึงจาก /plots/years + /meta/options
/// ไม่ hardcode ค่าใน UI
class PlotActivitiesViewModel extends ChangeNotifier {
  PlotActivitiesViewModel(ParcelService service) : _service = service {
    unawaited(_loadFilterOptions());
    unawaited(refresh());
  }

  /// สร้างจาก session api — view ส่งแค่นี้ ไม่ต้องเห็น ParcelService
  PlotActivitiesViewModel.forApi(ApiClient? api) : this(ParcelService(api));

  /// หยิบ ApiClient จาก Provider ที่ root — view ไม่ต้องถือ
  /// type ของชั้น data ส่งต่อเอง (MVVM)
  factory PlotActivitiesViewModel.forContext(BuildContext context) =>
      PlotActivitiesViewModel.forApi(context.read<ApiClient>());

  final ParcelService _service;
  final LocationService _location = LocationService();

  /// loader รูปดาวเทียมให้ widget SatelliteThumb — view ไม่เห็น
  /// ชั้น data ตรงๆ
  SatThumbLoader get satThumb => SatelliteThumbService.load;

  /// ตำแหน่งผู้ใช้ปัจจุบัน (ปุ่มโฟกัส GPS บนแผนที่ย่อ)
  Future<LatLng?> currentPosition() => _location.currentPosition();

  // ---------- ตัวเลือกฟิลเตอร์ (จาก backend) ----------
  List<String> _yearOptions = const [];
  List<String> _zoneOptions = const [];
  List<String> _caneTypeOptions = const [];
  bool _optionsLoaded = false;

  List<String> get yearOptions => _yearOptions;
  List<String> get zoneOptions => _zoneOptions;
  List<String> get caneTypeOptions => _caneTypeOptions;
  bool get optionsLoaded => _optionsLoaded;

  // ---------- ฟิลเตอร์ที่เลือก (เลือกได้หลายค่า) ----------
  // null = "ไม่มีปีการผลิต" — backend รองรับ nullYear ตรงๆ
  final Set<String?> _years = {};
  final Set<String> _zones = {};
  final Set<String> _caneTypes = {};
  final Set<bool> _planted = {}; // true=ปลูกแล้ว false=ยังไม่ปลูก
  final Set<String> _groupKinds =
      {}; // 'harvest'=กลุ่มตัด 'maintain'=กลุ่มบำรุง
  String _search = '';
  Timer? _searchDebounce;
  // เลขรุ่น fetch — refresh ใหม่ทำให้ loadMore ที่ค้างอยู่เป็น stale
  // ทิ้งผลลัพธ์ของมัน ไม่ให้ย้อนไป merge ทับรายการล่าสุด
  int _fetchEpoch = 0;

  Set<String?> get years => _years;
  Set<String> get zones => _zones;
  Set<String> get caneTypes => _caneTypes;
  Set<bool> get planted => _planted;
  Set<String> get groupKinds => _groupKinds;

  /// จำนวนค่าฟิลเตอร์ที่เลือกทั้งหมด — badge บนปุ่มฟิลเตอร์
  int get activeFilterCount =>
      _years.length +
      _zones.length +
      _caneTypes.length +
      _planted.length +
      _groupKinds.length;

  // ---------- รายการ + เพจจิเนชัน ----------
  List<PlotListItem> _items = const [];
  String? _nextCursor;
  int _total = 0;
  bool _loading = false;
  bool _loadingMore = false;
  String? _error;

  List<PlotListItem> get items => _items;
  bool get loading => _loading;
  bool get loadingMore => _loadingMore;
  bool get hasMore => _nextCursor != null;
  String? get error => _error;

  /// จำนวนแปลงทั้งหมดตามฟิลเตอร์ (จาก backend ไม่ใช่แค่ที่โหลดมา)
  int get total => _total;

  // ---------- แปลงที่เลือก (โฟกัสบนแผนที่ย่อ) ----------
  String? _selectedId;
  String? get selectedId => _selectedId;

  void select(String id) {
    _selectedId = _selectedId == id ? null : id;
    _safeNotify();
  }

  PlotListItem? get selected {
    if (_selectedId == null) return null;
    for (final p in _items) {
      if (p.id == _selectedId) return p;
    }
    return null;
  }

  Future<void> _loadFilterOptions() async {
    try {
      final index = await _service.fetchYearIndex();
      _yearOptions = index.years.keys.whereType<String>().toList()
        ..sort((a, b) => b.compareTo(a));
      _optionsLoaded = true;
    } catch (_) {}
    try {
      final options = await _service.fetchOptions();
      _zoneOptions = options.zones;
      _caneTypeOptions = options.caneTypes;
    } catch (_) {}
    _safeNotify();
  }

  Future<void> refresh() async {
    final epoch = ++_fetchEpoch;
    _loading = true;
    _error = null;
    _items = const [];
    _nextCursor = null;
    _safeNotify();
    try {
      final page = await _fetch(cursor: null);
      if (epoch != _fetchEpoch) return;
      _items = page.items;
      _nextCursor = page.nextCursor;
      _total = page.total;
    } catch (e) {
      if (epoch == _fetchEpoch) {
        _error = '$e'.replaceFirst('Exception: ', '');
      }
    }
    // epoch stale → refresh ใหม่กำลังทำงาน เป็นคนเคลียร์ _loading เอง
    if (epoch != _fetchEpoch) return;
    _loading = false;
    _safeNotify();
  }

  Future<void> loadMore() async {
    if (_nextCursor == null || _loadingMore || _loading) return;
    final epoch = _fetchEpoch;
    _loadingMore = true;
    _safeNotify();
    try {
      final page = await _fetch(cursor: _nextCursor);
      // refresh มาแทรกระหว่างรอ → ผลของเพจเก่าไม่เอามาต่อ list ใหม่
      if (epoch != _fetchEpoch) return;
      _items = [..._items, ...page.items];
      _nextCursor = page.nextCursor;
      _total = page.total;
    } catch (e) {
      if (epoch == _fetchEpoch) {
        _error = '$e'.replaceFirst('Exception: ', '');
      }
    } finally {
      // finally ไม่ใช่ tail ปกติ — return ตอน epoch stale ข้างบน
      // ก็ต้องเคลียร์ flag ไม่งั้น _loadingMore ค้างตลอด (ปุ่มตาย)
      _loadingMore = false;
      _safeNotify();
    }
  }

  Future<PlotPage> _fetch({required String? cursor}) => _service.fetchPlots(
    limit: 30,
    cursor: cursor,
    years: _years.isEmpty ? null : {..._years},
    zones: _zones,
    caneTypes: _caneTypes,
    planted: _planted,
    groupKinds: _groupKinds,
    search: _search.isEmpty ? null : _search,
  );

  /// ช่องค้นหา — debounce 400ms กันยิง API ทุก keystroke
  void setSearch(String v) {
    _search = v.trim();
    _searchDebounce?.cancel();
    _searchDebounce = Timer(
      const Duration(milliseconds: 400),
      () => unawaited(refresh()),
    );
  }

  /// กดค้นบนคีย์บอร์ด/ไอคอนแว่นขยาย — ยิงทันทีไม่รอ debounce
  void submitSearch() {
    _searchDebounce?.cancel();
    unawaited(refresh());
  }

  // ---------- set ฟิลเตอร์แล้วรีเฟรช ----------
  /// apply ครั้งเดียวจาก filter sheet — refresh รอบเดียวไม่ยิงซ้ำ
  void applyFilters({
    required Set<String?> years,
    required Set<String> zones,
    required Set<String> caneTypes,
    required Set<bool> planted,
    required Set<String> groupKinds,
  }) => _apply(() {
    _years
      ..clear()
      ..addAll(years);
    _zones
      ..clear()
      ..addAll(zones);
    _caneTypes
      ..clear()
      ..addAll(caneTypes);
    _planted
      ..clear()
      ..addAll(planted);
    _groupKinds
      ..clear()
      ..addAll(groupKinds);
  });

  void clearFilters() => _apply(() {
    _years.clear();
    _zones.clear();
    _caneTypes.clear();
    _planted.clear();
    _groupKinds.clear();
  });

  void _apply(void Function() change) {
    change();
    _safeNotify();
    unawaited(refresh());
  }

  bool _disposed = false;

  /// fetch/timer ที่กลับมาหลังหน้าปิด — notify บน VM ที่ disposed
  /// แล้ว crash "used after disposed" ข้ามเงียบๆ แทน
  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _searchDebounce?.cancel();
    super.dispose();
  }
}

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import 'package:brr/features/map/models/parcel.dart';
import 'package:brr/core/services/api_client.dart';
import 'package:brr/features/map/data/location_service.dart';
import 'package:brr/features/map/data/parcel_service.dart';
import 'package:brr/features/map/viewmodels/drafts_viewmodel.dart';
import 'package:brr/features/map/viewmodels/parcel_detail_viewmodel.dart';
import 'package:brr/features/map/viewmodels/plot_download_viewmodel.dart';

/// ViewModel for the area-measurement map screen — parcel display
/// plus a drawing mode for marking a new boundary.
class MapViewModel extends ChangeNotifier {
  MapViewModel({
    ApiClient? api,
    ParcelService? service,
    LocationService? location,
    this.canDrawManually = true,
    List<Parcel>? initialParcels,
    this._yearAllowlist,
    bool initialCoverageComplete = false,
  }) : _service = service ?? ParcelService(api),
       _location = location ?? LocationService() {
    // ขอตำแหน่งตั้งแต่ต้น — ระหว่างที่ยังเป็น skeleton อยู่ userPos
    // จะพร้อมก่อน GoogleMap mount → initialCamera ชี้ตำแหน่งจริง
    // ได้เลยไม่ต้องรอ animate หลัง onMapCreated
    initialLocate = locate();
    // โหลดสถานะจุดเสี่ยงทันที — polygon ทาสีตามค่านี้
    unawaited(refreshRiskTypes());
    // Seeded from the download screen — skip the initial fetch.
    if (initialParcels != null) {
      _parcels = initialParcels;
      _loading = false;
      // Download ที่ไม่ truncated ครอบคลุมกรอบทั้งประเทศแล้ว —
      // ไม่ต้อง viewport fetch เลย แปลงที่โหลดมาเห็นครบ
      if (initialCoverageComplete) {
        _coverage = _parseBox(ParcelService.fullBox);
      }
    } else {
      // เปิดแผนที่ว่างๆ ก่อน — แปลงมาจากหน้าดาวน์โหลดในหน้านี้
      // (applyDownload) หรือ viewport fetch ตามกรอบที่เลื่อนไปดู
      _loading = false;
    }
  }

  /// สร้าง VM หยิบ ApiClient จาก Provider ที่ root — view ไม่ต้อง
  /// ถือ type ของชั้น data (ApiClient) ส่งต่อเอง (MVVM)
  factory MapViewModel.forContext(
    BuildContext context, {
    ParcelService? service,
    LocationService? location,
    bool canDrawManually = true,
    List<Parcel>? initialParcels,
    Set<String?>? yearAllowlist,
    bool initialCoverageComplete = false,
  }) => MapViewModel(
    api: context.read<ApiClient>(),
    service: service,
    location: location,
    canDrawManually: canDrawManually,
    initialParcels: initialParcels,
    yearAllowlist: yearAllowlist,
    initialCoverageComplete: initialCoverageComplete,
  );

  final ParcelService _service;
  final LocationService _location;

  /// Officers/admins may also draw boundaries by tapping; farmers
  /// only get walk-measure mode.
  final bool canDrawManually;

  List<Parcel> _parcels = const [];
  bool _loading = true;
  String? _error;

  /// ปีที่ผู้ใช้เลือกดาวน์โหลดจากหน้าเลือกข้อมูล — null = ทุกปี.
  /// กรองทั้ง seeded parcels และ viewport refetch (drafts แสดงเสมอ).
  /// เปลี่ยนค่าได้ผ่าน [applyDownload] เมื่อดาวน์โหลดชุดใหม่.
  Set<String?>? _yearAllowlist;
  Set<String?>? get yearAllowlist => _yearAllowlist;

  /// แปลงที่เพิ่งบันทึกขึ้น server จาก session นี้ — bypass year
  /// filter เสมอ ไม่งั้นเดินวัดปี 2570 ขณะดาวน์โหลดแค่ปี 2567 แล้ว
  /// polygon ที่เพิ่งวาดจะหายทันทีทั้งที่บันทึกสำเร็จ (viewport
  /// refetch ก็ไม่ได้ id นี้กลับมาเพราะ server กรองปีให้)
  final Set<String> _freshIds = {};
  final Map<String, Parcel> _fresh = {};

  // drawing state
  bool _drawing = false;
  final List<LatLng> _draft = [];
  final List<WalkCorner> _corners = [];
  DateTime? _walkStartedAt;
  String? _plotClientId;

  // walk-measure state
  StreamSubscription<Position>? _posSub;
  bool _walking = false;
  bool _walkPaused = false;
  double? _gpsAccuracy;

  /// นับ fix ที่ accuracy เกิน 15 ม. ต่อเนื่อง — ครบ 5 → auto-pause
  int _badFixStreak = 0;

  /// true เมื่อหยุดพักเพราะ GPS แย่ (ไม่ใช่ผู้ใช้กดพักเอง) —
  /// UI แสดงข้อความต่างกัน
  bool _autoPaused = false;
  LatLng? _lastFix;

  List<Parcel> get parcels => _parcels;

  /// ฟิลเตอร์แปลงบนแผนที่ (กรองฝั่ง client บนแปลงที่โหลดอยู่)
  /// เซตว่าง = ไม่กรองช่องนั้น; null ใน _filterYears = "ไม่มีปีการผลิต"
  final Set<String?> _filterYears = {};
  final Set<String> _filterZones = {};
  final Set<String> _filterCaneTypes = {};
  final Set<bool> _filterPlanted = {}; // true=ปลูกแล้ว false=ยังไม่ปลูก
  // ชื่อกลุ่มจริง (caneGroup) — แยก 2 เซตตามคำในชื่อกลุ่ม
  final Set<String> _filterCutGroups = {};
  final Set<String> _filterMaintainGroups = {};

  Set<String?> get filterYears => _filterYears;
  Set<String> get filterZones => _filterZones;
  Set<String> get filterCaneTypes => _filterCaneTypes;
  Set<bool> get filterPlanted => _filterPlanted;
  Set<String> get filterCutGroups => _filterCutGroups;
  Set<String> get filterMaintainGroups => _filterMaintainGroups;

  /// จำนวนค่าฟิลเตอร์ที่เลือก — จุด badge บนปุ่มฟิลเตอร์
  int get activeFilterCount =>
      _filterYears.length +
      _filterZones.length +
      _filterCaneTypes.length +
      _filterPlanted.length +
      _filterCutGroups.length +
      _filterMaintainGroups.length;

  /// ช่องค้นหาแปลงบนแผนที่ — ว่าง = ไม่กรอง; กรองเฉพาะแปลง
  /// จาก backend (draft ในเครื่องแสดงเสมอ)
  String _searchQuery = '';
  String get searchQuery => _searchQuery;

  /// ค้นหาใน ชื่อแปลง/#เลขแปลง/เจ้าของ/รหัส-ชื่อชาวไร่/รูท
  /// (ครอบชุดเดียวกับ `search` ของ backend)
  bool _matchesSearch(Parcel p) {
    final q = _searchQuery.toLowerCase();
    final farmer = p.meta?['farmer'];
    final hay =
        '${p.name} ${p.owner ?? ''} ${p.meta?['farmerName'] ?? ''} '
        '${p.meta?['farmerId'] ?? ''} ${p.meta?['rootNo'] ?? ''} '
        '${farmer is Map ? '${farmer['username'] ?? ''} ${farmer['displayName'] ?? ''}' : ''}';
    return hay.toLowerCase().contains(q);
  }

  /// ปีการผลิตที่มีในแปลงทั้งหมด — เรียงปีล่าสุดก่อน
  List<String> get years {
    final ys = <String>{
      for (final p in _parcels)
        if (p.productionYear != null) p.productionYear!,
    }.toList();
    ys.sort((a, b) => b.compareTo(a));
    return ys;
  }

  /// แปลงที่วาดบนแผนที่ตาม filter — draft แสดงเสมอจนกว่าจะถูกลบ
  /// หรือยืนยันขึ้น server (confirmed ซ่อน — แปลงจริงจาก backend
  /// มาวาดแทน ไม่งั้นซ้อนทับกัน)
  List<Parcel> get visibleParcels => [
    for (final p in _parcels)
      if (p.isDraft
          ? p.status != 'confirmed'
          : _freshIds.contains(p.id) ||
                ((yearAllowlist == null ||
                        yearAllowlist!.contains(p.productionYear)) &&
                    _matchesFilters(p) &&
                    (_searchQuery.isEmpty || _matchesSearch(p))))
        p,
  ];

  /// match ฟิลเตอร์ที่เลือก (ปี/เขต/ประเภทอ้อย/สถานะปลูก/กลุ่มงาน)
  /// เซตว่างของช่องไหน = ผ่านช่องนั้น — ตรรกะเดียวกับ
  /// fetchPlots ของ backend: ปลูกแล้ว = มี caneType,
  /// กลุ่มตัด/บำรุง = caneGroup มีคำ "ตัด"/"บำรุง"
  bool _matchesFilters(Parcel p) {
    final meta = p.meta ?? const {};
    if (_filterYears.isNotEmpty && !_filterYears.contains(p.productionYear)) {
      return false;
    }
    if (_filterZones.isNotEmpty &&
        !_filterZones.contains('${meta['zone'] ?? ''}')) {
      return false;
    }
    final caneType = '${meta['caneType'] ?? ''}';
    if (_filterCaneTypes.isNotEmpty && !_filterCaneTypes.contains(caneType)) {
      return false;
    }
    if (_filterPlanted.isNotEmpty &&
        !_filterPlanted.contains(caneType.isNotEmpty)) {
      return false;
    }
    if (_filterCutGroups.isNotEmpty || _filterMaintainGroups.isNotEmpty) {
      final group = '${meta['caneGroup'] ?? ''}';
      if (!(_filterCutGroups.contains(group) ||
          _filterMaintainGroups.contains(group))) {
        return false;
      }
    }
    return true;
  }

  /// ตัวเลือกเขต/ประเภทอ้อย/กลุ่มจาก meta ของแปลงที่โหลดอยู่
  /// (เรียงตามตัวอักษร ให้เลือกได้เฉพาะค่าที่มีจริง)
  /// กลุ่มแยก 2 list ด้วยคำในชื่อ — "ตัด"=กลุ่มตัด "บำรุง"=กลุ่มบำรุง
  List<String> get zoneOptions => _metaOptions('zone');
  List<String> get caneTypeOptions => _metaOptions('caneType');
  List<String> get cutGroupOptions =>
      _metaOptions('caneGroup', contains: 'ตัด');
  List<String> get maintainGroupOptions =>
      _metaOptions('caneGroup', contains: 'บำรุง');

  List<String> _metaOptions(String key, {String? contains}) {
    final out = <String>{
      for (final p in _parcels)
        if (!p.isDraft && '${p.meta?[key] ?? ''}'.isNotEmpty) '${p.meta![key]}',
    };
    final list = out.toList()..sort();
    return contains == null
        ? list
        : [
            for (final v in list)
              if (v.contains(contains)) v,
          ];
  }

  /// apply ครั้งเดียวจาก filter sheet — invalidate+notify รอบเดียว
  void applyFilters({
    required Set<String?> years,
    required Set<String> zones,
    required Set<String> caneTypes,
    required Set<bool> planted,
    required Set<String> cutGroups,
    required Set<String> maintainGroups,
  }) {
    _filterYears
      ..clear()
      ..addAll(years);
    _filterZones
      ..clear()
      ..addAll(zones);
    _filterCaneTypes
      ..clear()
      ..addAll(caneTypes);
    _filterPlanted
      ..clear()
      ..addAll(planted);
    _filterCutGroups
      ..clear()
      ..addAll(cutGroups);
    _filterMaintainGroups
      ..clear()
      ..addAll(maintainGroups);
    _invalidateRender();
    _safeNotify();
  }

  /// GoogleMap renders every polygon handed to it — คัดเฉพาะแปลงที่
  /// ทับกับกรอบที่กำลังดู (bbox overlap) แล้วจำกัดจำนวนอีกชั้น
  /// กันเครื่อง RAM 4GB หน่วง; drafts ไม่ถูกตัด
  static const _maxRenderedParcels = 1500;

  /// กรอบที่กำลังดูบนแผนที่ — อัพเดททุก onCameraIdle
  ({double w, double s, double e, double n})? _viewBox;

  /// Memoized renderable list — คืน instance เดิมจนกว่าข้อมูล/กรอบ/
  /// filter เปลี่ยนจริง (GPS fix ตอนเดินวัดไม่ต้อง filter 30k ซ้ำทุกเฟรม)
  List<Parcel>? _renderCache;

  void _invalidateRender() => _renderCache = null;

  List<Parcel> get renderableParcels => _renderCache ??= _computeRenderable();

  List<Parcel> _computeRenderable() {
    final vis = visibleParcels;
    final vb = _viewBox;
    final inView = vb == null
        ? vis
        : [
            for (final p in vis)
              if (p.isDraft || p.intersectsBox(vb.w, vb.s, vb.e, vb.n)) p,
          ];
    if (inView.length <= _maxRenderedParcels) return inView;
    final drafts = inView.where((p) => p.isDraft).toList();
    final rest = inView.where((p) => !p.isDraft).toList();
    if (vb != null) {
      // เลือกแปลงที่ใกล้กลางจอก่อน — เดิม take() ตัดตามลำดับข้อมูล
      // ทำให้แปลงที่มองเห็นชัดๆ หายก่อนแปลงที่อยู่ริมกรอบ
      final cy = (vb.n + vb.s) / 2;
      final cx = (vb.e + vb.w) / 2;
      double d2(Parcel p) {
        final c = p.center;
        final dy = c.latitude - cy;
        final dx = c.longitude - cx;
        return dy * dy + dx * dx;
      }

      rest.sort((a, b) => d2(a).compareTo(d2(b)));
    }
    return [...drafts, ...rest.take(_maxRenderedParcels)];
  }

  void setSearchQuery(String q) {
    final t = q.trim();
    if (t == _searchQuery) return;
    _searchQuery = t;
    _invalidateRender();
    _safeNotify();
  }

  /// dropdown แนะนำใต้ช่องค้นหา — แปลงที่ match 8 รายการแรก
  /// (ไม่รวม draft ในเครื่อง)
  List<Parcel> get searchSuggestions {
    if (_searchQuery.isEmpty) return const [];
    final out = <Parcel>[];
    for (final p in _parcels) {
      if (!p.isDraft && _matchesSearch(p)) out.add(p);
      if (out.length >= 8) break;
    }
    return out;
  }

  /// Viewport refetch in progress — drives the thin top progress bar.
  bool _loadingViewport = false;
  bool get loadingViewport => _loadingViewport;

  /// ประเภทจุดเสี่ยงล่าสุดต่อ plotId — แผนที่ทาสี polygon ตามค่านี้
  /// (มีสถานะ = สีตามชนิดภัย / บันทึกแล้วไม่มีสถานะ = ฟ้า / ร่าง = เขียว)
  Map<String, String> _riskTypes = const {};
  Map<String, String> get riskTypes => _riskTypes;

  /// โหลดจุดเสี่ยงจากเครื่องใหม่ — เรียกตอนเปิดแผนที่และหลัง sheet
  /// แปลงปิด (บันทึกจุดเสี่ยงใน info sheet → สี polygon เปลี่ยนทันที)
  Future<void> refreshRiskTypes() async {
    try {
      _riskTypes = await _service.riskPointTypes();
    } catch (_) {}
    _safeNotify();
  }

  /// ขอบเขตที่ _parcels ครอบคลุม "ครบ" — กรอบใหม่ที่อยู่ภายในครอบนี้
  /// ข้อมูลมีอยู่แล้ว ไม่ต้อง fetch (download เต็มก็นับ coverage)
  ({double w, double s, double e, double n})? _coverage;

  /// Plot save POST in progress — drives the blocking overlay.
  bool _saving = false;
  bool get saving => _saving;

  static ({double w, double s, double e, double n}) _parseBox(String box) {
    final q = Uri.splitQueryString(box);
    double n(String k) => double.tryParse(q[k] ?? '') ?? 0;
    return (w: n('west'), s: n('south'), e: n('east'), n: n('north'));
  }

  /// Reload parcels inside the visible map bounds — keeps local
  /// drafts, drops backend items that scrolled out of view.
  /// ข้ามเมื่อข้อมูลครอบคลุมกรอบใหม่ครบแล้ว (download เต็มหรือ
  /// fetch รอบก่อนไม่ truncated) — เลื่อนในบริเวณเดิมไม่ยิง API.
  /// error ของ viewport fetch ล่าสุด — map แสดงแถบเตือน + ปุ่ม retry
  /// (เดิม swallow เงียบ ผู้ใช้เข้าใจว่าบริเวณนั้นไม่มีแปลง)
  String? get viewportError => _viewportError;
  String? _viewportError;

  /// โหลดกรอบปัจจุบันใหม่โดยข้าม coverage cache — ใช้จากปุ่ม retry
  void retryViewport() {
    final b = _viewBox;
    if (b != null) loadViewport(b.w, b.s, b.e, b.n, force: true);
  }

  Future<void> loadViewport(
    double west,
    double south,
    double east,
    double north, {
    bool force = false,
  }) async {
    final b = (w: west, s: south, e: east, n: north);
    // อัพเดทกรอบมองเสมอ — renderableParcels คัด polygon ตามกรอบนี้
    final moved = _viewBox != b;
    _viewBox = b;
    if (moved) _invalidateRender();
    final cov = _coverage;
    if (_loadingViewport ||
        (!force &&
            cov != null &&
            b.w >= cov.w &&
            b.s >= cov.s &&
            b.e <= cov.e &&
            b.n <= cov.n)) {
      if (moved) _safeNotify();
      return;
    }
    _loadingViewport = true;
    _safeNotify();
    try {
      final page = await _service.fetchParcels(
        box: 'west=$west&south=$south&east=$east&north=$north&limit=2000',
        // กรองปีฝั่ง server ด้วย — ไม่ต้องรับข้อมูลที่จะทิ้ง
        years: yearAllowlist,
      );
      // ร่างเอาจาก page.items ที่ fetchParcels merge สดจาก storage
      // เสมอ — ห้าม reuse ของเดิมใน _parcels เพราะร่างที่ลบไปแล้ว
      // จะยังค้างวาดบนแผนที่ (drafts ต้องโชว์ตลอดจนกว่าจะลบจริง)
      _parcels = [
        for (final p in page.items)
          if (p.isDraft ||
              yearAllowlist == null ||
              yearAllowlist!.contains(p.productionYear))
            p,
        // แปลงที่เพิ่งสร้างใน session นี้ไม่กลับมาใน fetch ถ้าปีไม่
        // อยู่ใน allowlist — ผนวกกลับเองให้คงอยู่บนแผนที่
        for (final p in _fresh.values)
          if (!page.items.any((s) => s.id == p.id)) p,
      ];
      _invalidateRender();
      // server ส่งแปลง fresh กลับมาแล้ว → ถือตัว server เป็น authoritative
      for (final p in page.items) {
        _fresh.remove(p.id);
        _freshIds.remove(p.id);
      }
      // จำ coverage เฉพาะ fetch ที่ครบ — truncated มีหลุมในกรอบนี้
      // ห้ามข้าม fetch รอบต่อไปไม่งั้นแปลงหายรอบๆหมุด
      _coverage = page.truncated ? null : b;
      _viewportError = null;
    } catch (e) {
      _viewportError = '$e'.replaceFirst('Exception: ', '');
    }
    _loadingViewport = false;
    _safeNotify();
  }

  bool get loading => _loading;
  String? get error => _error;
  bool get drawing => _drawing;
  List<LatLng> get draft => List.unmodifiable(_draft);
  bool get walking => _walking;
  bool get walkPaused => _walkPaused;
  double? get gpsAccuracy => _gpsAccuracy;
  bool get autoPaused => _autoPaused;
  LatLng? get lastFix => _lastFix;

  bool _disposed = false;

  /// fetch ที่ค้างอยู่อาจกลับมาหลังหน้าปิดไปแล้ว — notify บน VM
  /// ที่ disposed แล้วจะ crash, ข้ามเงียบๆ แทน
  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _posSub?.cancel();
    super.dispose();
  }

  /// VM ของ flow ข้อมูลแปลง (info sheet → รายละเอียด → เมนูแก้ไข) —
  /// สร้างต่อแปลงที่แตะ แชร์ service/token เดียวกัน; รับ context
  /// ให้ VM ปลายทางอ่าน session user เอง (เติม recordedBy ตอนบันทึก)
  ParcelDetailViewModel detailVmFor(BuildContext context, Parcel p) =>
      ParcelDetailViewModel.forContext(context, parcel: p, service: _service);

  /// VM ของหน้าดาวน์โหลด — แชร์ service เดียวกัน ไม่สร้างใหม่
  PlotDownloadViewModel createDownloadVm() => PlotDownloadViewModel(_service);

  /// VM หน้า "ข้อมูลฉบับร่าง" — แปลงที่บันทึกลงเครื่องเท่านั้น
  DraftsViewModel createDraftsVm() => DraftsViewModel(_service);

  /// รับผลจากหน้าดาวน์โหลด — เก็บเฉพาะปีที่ติ๊ก + draft ทั้งหมด
  /// แล้วตั้ง coverage/allowlist ให้ viewport fetch กรองตามปีนั้นต่อ
  void applyDownload(ParcelPage page, Set<String?> years) {
    _yearAllowlist = years;
    _freshIds.clear();
    _fresh.clear();
    _parcels = [
      for (final p in page.items)
        if (p.isDraft || years.contains(p.productionYear)) p,
    ];
    _coverage = page.truncated ? null : _parseBox(ParcelService.fullBox);
    _filterYears.clear();
    _filterZones.clear();
    _filterCaneTypes.clear();
    _filterPlanted.clear();
    _filterCutGroups.clear();
    _filterMaintainGroups.clear();
    _loading = false;
    _error = null;
    _invalidateRender();
    _safeNotify();
  }

  /// Dropdown options for the save form — views never touch the
  /// service directly.
  Future<List<String>> fetchOfficers() => _service.fetchOfficers();
  Future<List<FarmerRef>> fetchFarmers() => _service.fetchFarmers();
  Future<FormOptions> fetchOptions() => _service.fetchOptions();

  /// Draft area in square meters for the save form preview.
  double get draftAreaSqm =>
      Parcel(id: 'draft', name: '', points: _draft).areaSquareMeters;

  Future<void> load() async {
    _loading = true;
    _error = null;
    _coverage = null;
    _safeNotify();
    try {
      final page = await _service.fetchParcels();
      _parcels = page.items;
      _invalidateRender();
      if (!page.truncated) _coverage = _parseBox(ParcelService.fullBox);
    } catch (e) {
      _error = '$e'.replaceFirst('Exception: ', '');
      // server ดึงไม่ได้ก็ยังโชว์ร่างในเครื่อง — ร่างต้องอยู่บน
      // แผนที่ตลอดจนกว่าจะลบหรือยืนยันขึ้น server
      _parcels = await _service.fetchDrafts();
      _invalidateRender();
    }
    _loading = false;
    _safeNotify();
  }

  /// เพิ่มพิกัด — enter drawing mode (officers/admins only).
  Future<void> startDrawing() async {
    if (!canDrawManually) return;
    _drawing = true;
    _draft.clear();
    _plotClientId = null;
    _dropWalkSurvey();
    _safeNotify();
    // subscribe position stream ด้วย — แผง GPS ในแถบล่างต้องมี
    // พิกัด/คลาดเคลื่อนจริงแม้โหมดแตะวาด (ไม่ได้เดินวัด)
    if (await _location.ensurePermission()) {
      _ensurePosSub();
    }
  }

  /// subscribe position stream จุดเดียว — stream ตายเงียบ (GPS ดับ/
  /// ถูกถอนสิทธิ์กลางทาง) ต้อง resub ใหม่ได้ ไม่งั้นตำแหน่งหยุด
  /// อัปเดตโดยไม่มีใครรู้ (`_posSub` ยัง non-null แต่ stream ตายแล้ว)
  void _ensurePosSub() {
    void revive() {
      final dead = _posSub;
      _posSub = null;
      dead?.cancel();
      unawaited(
        Future.delayed(const Duration(seconds: 3), () {
          if (!_disposed && (_walking || _drawing)) _ensurePosSub();
        }),
      );
    }

    _posSub ??= _location.positionStream().listen(
      _onPosition,
      onDone: revive,
      onError: (_) => revive(),
    );
  }

  /// Last known user position — set by [locate] (GPS button) or live
  /// fixes while walk-measuring.
  LatLng? get userPos => _lastFix ?? _userPos;
  LatLng? _userPos;

  /// Future ของการหาตำแหน่งครั้งแรก — view รอให้จบก่อน mount
  /// GoogleMap เพื่อให้ initialCamera อยู่ตำแหน่งจริงทันที
  /// (ไม่โชว์จุด fallback กะพริบแล้ว animate ตามทีหลัง)
  late final Future<LatLng?> initialLocate;

  /// One-shot locate — view animates the camera to the result.
  Future<LatLng?> locate() async {
    _userPos = await _location.currentPosition();
    if (_userPos != null) _safeNotify();
    return _userPos;
  }

  /// เดินวัด — starts GPS tracking; every good fix drops a pin.
  /// Returns an error message when location permission is missing.
  Future<String?> startWalk() async {
    if (!await _location.ensurePermission()) {
      return 'ไม่ได้รับสิทธิตำแหน่ง — เปิด GPS แล้วลองใหม่';
    }
    _drawing = true;
    _walking = true;
    _walkPaused = false;
    _autoPaused = false;
    _badFixStreak = 0;
    _draft.clear();
    _corners.clear();
    _plotClientId = null;
    _walkStartedAt = DateTime.now();
    _safeNotify();
    // sub เก่าอาจค้างจาก startDrawing — ต้องปิดก่อนไม่งั้น
    // 2 stream ยิง _onPosition ซ้อน → ลงจุดซ้ำทุก fix
    await _posSub?.cancel();
    _posSub = null;
    _ensurePosSub();
    return null;
  }

  /// Pause/resume walk tracking (draft is kept).
  void toggleWalkPause() {
    if (!_walking) return;
    _walkPaused = !_walkPaused;
    _autoPaused = false;
    _badFixStreak = 0;
    _safeNotify();
  }

  /// Stops tracking; the drawn boundary stays for review/saving.
  void stopWalk() {
    _posSub?.cancel();
    _posSub = null;
    _walking = false;
    _walkPaused = false;
    _autoPaused = false;
    _badFixStreak = 0;
    _safeNotify();
  }

  void _onPosition(Position p) {
    _gpsAccuracy = p.accuracy;
    _lastFix = LatLng(p.latitude, p.longitude);
    // โหมดแตะวาด — อัปเดตพิกัด/คลาดเคลื่อนให้แผง GPS อย่างเดียว
    if (!_walking) {
      _safeNotify();
      return;
    }
    // อัพเดท badge แม้ตอนพัก — ผู้วัดเห็นสัญญาณฟื้นตัวก่อนกดเดินต่อ
    if (_walkPaused) {
      _safeNotify();
      return;
    }
    // สัญญาณแย่เกิน — badge เปลี่ยนสีแต่ไม่ลงจุด
    if (p.accuracy > 15) {
      // GPS แย่ต่อเนื่อง — auto-pause กันเส้นกระโดด/จุดหลุด
      // ผู้ใช้กดเดินต่อเองเมื่อสัญญาณดีกลับมา
      _badFixStreak++;
      if (_badFixStreak >= 5) {
        _walkPaused = true;
        _autoPaused = true;
      }
      _safeNotify();
      return;
    }
    _badFixStreak = 0;
    // ลงจุดเฉพาะ fix ที่แม่นพอ (≤6ม.) — แย่กว่านั้น
    // เดินผ่านไปแต่ไม่ปัก เพื่อขอบแม่นสุด
    if (p.accuracy > 6) {
      _safeNotify();
      return;
    }
    if (_draft.isNotEmpty) {
      const dist = Distance();
      final d = dist.as(LengthUnit.Meter, _draft.last, _lastFix!);
      if (d < 2.5) {
        _safeNotify();
        return;
      }
      // เกณฑ์เดียวกับ backend: (ระยะห่าง - ความคลาดเคลื่อน)/เวลา > 3 ม./วิ
      // = เดินไม่ถึง → fix นี้เป็น spike ไม่ใช่จุดจริง ปฏิเสธไม่ลงขอบ
      // (ระยะไกลที่เกิดตอนสัญญาณขาดนานๆ ยังผ่าน — เวลาห่างพอ)
      if (_corners.isNotEmpty) {
        final last = _corners.last;
        final seconds =
            DateTime.now().difference(last.capturedAt).inMilliseconds / 1000;
        final walked = (d - last.accuracyM - p.accuracy).clamp(
          0.0,
          double.infinity,
        );
        if (seconds > 0 && walked / seconds > 3) {
          _safeNotify();
          return;
        }
      }
    }
    _addWalkPoint(_lastFix!, p.accuracy);
    _safeNotify();
  }

  void addDraftPoint(LatLng p) {
    if (!_drawing) return;
    _draft.add(p);
    // จุดที่แตะบนแผนที่ไม่ได้มาจาก GPS — เลิกใช้ชุดเดินวัด
    // ไม่งั้นจำนวนมุมไม่ตรง แล้วกฎความแม่นยำทั้งแปลงหาย
    // หรือส่งรูปเดินรอบก่อนแทนจุดที่เห็น
    _dropWalkSurvey();
    _safeNotify();
  }

  /// ปักพิกัดปัจจุบันด้วยมือระหว่างเดินวัด — คืนข้อความ error
  /// ถ้าสัญญาณไม่ผ่านเกณฑ์ (null = ปักสำเร็จ)
  String? pinWalkPoint() {
    if (!_walking) return 'ไม่ได้อยู่ในโหมดเดินวัด';
    if (_walkPaused) return 'กำลังพักอยู่ — กดเดินต่อก่อน';
    final fix = _lastFix;
    final acc = _gpsAccuracy;
    if (fix == null || acc == null) return 'รอสัญญาณ GPS…';
    if (acc > 6) {
      return 'พิกัดคลาดเคลื่อน ±${acc.toStringAsFixed(1)} ม. เกินกำหนด — ไม่สามารถบันทึกค่าได้';
    }
    if (_draft.isNotEmpty) {
      const dist = Distance();
      final d = dist.as(LengthUnit.Meter, _draft.last, fix);
      if (d < 2.5) return 'อยู่ใกล้จุดล่าสุดเกินไป — เดินออกไปอีก';
      // เกณฑ์เดียวกับ backend — จุดนี้ไกลเกินกว่าจะเดินถึงจากจุดก่อน
      // (3 ม./วิ) แปลว่าพิกัดกระโดด ไม่ใช่ตำแหน่งจริง
      if (_corners.isNotEmpty) {
        final last = _corners.last;
        final seconds =
            DateTime.now().difference(last.capturedAt).inMilliseconds / 1000;
        final walked = (d - last.accuracyM - acc).clamp(0.0, double.infinity);
        if (seconds > 0 && walked / seconds > 3) {
          return 'พิกัดกระโดดผิดปกติ — ไม่สามารถบันทึกค่าได้';
        }
      }
    }
    _addWalkPoint(fix, acc);
    _safeNotify();
    return null;
  }

  void _addWalkPoint(LatLng point, double accuracyM) {
    var capturedAt = DateTime.now();
    if (_corners.isNotEmpty && !capturedAt.isAfter(_corners.last.capturedAt)) {
      capturedAt = _corners.last.capturedAt.add(
        const Duration(milliseconds: 1),
      );
    }
    _draft.add(point);
    _corners.add(
      WalkCorner(
        point: point,
        accuracyM: accuracyM < 0.1 ? 0.1 : accuracyM,
        capturedAt: capturedAt,
      ),
    );
  }

  /// ส่งให้ backend ตรวจเกณฑ์เดินวัดได้เฉพาะเมื่อทุกมุมมาจาก GPS
  Map<String, Object?>? _surveyPayload() {
    final started = _walkStartedAt;
    if (started == null ||
        _corners.isEmpty ||
        _corners.length != _draft.length) {
      return null;
    }
    var finished = DateTime.now();
    if (!finished.isAfter(_corners.last.capturedAt)) {
      finished = _corners.last.capturedAt.add(const Duration(milliseconds: 1));
    }
    return {
      'startedAt': started.toUtc().toIso8601String(),
      'finishedAt': finished.toUtc().toIso8601String(),
      'corners': [for (final corner in _corners) corner.toJson()],
    };
  }

  /// ย้อนกลับ — remove the last drafted point.
  void undoDraftPoint() {
    if (_draft.isNotEmpty) _draft.removeLast();
    if (_corners.length > _draft.length) _corners.removeLast();
    _safeNotify();
  }

  /// ลากย้ายหมุด — จุดที่ย้ายไม่ใช่ค่า GPS เดิม จึงไม่ส่งความแม่นยำเดิม
  void moveDraftPoint(int index, LatLng p) {
    if (index < 0 || index >= _draft.length) return;
    _draft[index] = p;
    _dropWalkSurvey();
    _safeNotify();
  }

  /// เริ่มใหม่ — clear every drafted point, stay in drawing mode.
  void clearDraft() {
    if (_draft.isEmpty && _corners.isEmpty && _walkStartedAt == null) return;
    _draft.clear();
    _plotClientId = null;
    _dropWalkSurvey();
    _safeNotify();
  }

  /// รูปที่เห็นไม่ตรงกับการเดินวัดแล้ว — ห้ามส่งความแม่นยำของรอบเดินเดิม
  void _dropWalkSurvey() {
    _corners.clear();
    _walkStartedAt = null;
  }

  void cancelDrawing() {
    _posSub?.cancel();
    _posSub = null;
    _drawing = false;
    _walking = false;
    _walkPaused = false;
    _draft.clear();
    _corners.clear();
    _walkStartedAt = null;
    _plotClientId = null;
    _safeNotify();
  }

  /// เสร็จสิ้น — save the drafted boundary (backend or local).
  Future<String?> finishDrawing(
    String name, {
    String? productionYear,
    String? officerName,
    String? project,
    String? farmerName,
    String? farmerId,
    String? caneGroup,
    String? zone,
    String? province,
    String? district,
    String? subdistrict,
    String? village,
    String? rootNo,
    String? sequenceNo,
    String? prevPlotNo,
    String? caneType,
    String? caneVariety,
    String? ownership,
    String? terrain,
    String? hasLoss,
    String? lossRai,
    String? targetYield,
    String? note,
    List<String> photos = const [],
    bool draft = false,
  }) async {
    if (_draft.length < 3) return 'ต้องปักอย่างน้อย 3 จุด';
    // เกณฑ์เดียวกับ backend (surveyRules) — เตือนก่อนส่ง ไม่ให้
    // ผู้ใช้กรอกฟอร์มเสร็จแล้วค่อยเจอ reject ตอนบันทึก
    if (!draft && draftAreaSqm < 100) {
      return 'แปลงต้องใหญ่อย่างน้อย 100 ตารางเมตร';
    }
    // เดินวัดยาวเกิน 12 ชม. backend ปฏิเสธทั้งแปลง — บอกตั้งแต่ตรงนี้
    final walkStart = _walkStartedAt;
    if (!draft &&
        walkStart != null &&
        DateTime.now().difference(walkStart) > const Duration(hours: 12)) {
      return 'เดินวัดนานเกิน 12 ชั่วโมง — เริ่มวัดใหม่';
    }
    // กดซ้ำระหว่างบันทึก — คืนข้อความจริงแทน null (caller ตี null
    // เป็นสำเร็จแล้วขึ้น snackbar "บันทึกสำเร็จ" มั่ว)
    if (_saving) return 'กำลังบันทึกอยู่ กรุณารอสักครู่';
    _saving = true;
    _safeNotify();
    try {
      _plotClientId ??= newPlotId();
      final p = await _service.createParcel(
        id: _plotClientId!,
        name: name,
        productionYear: productionYear,
        officerName: officerName,
        project: project,
        farmerName: farmerName,
        farmerId: farmerId,
        caneGroup: caneGroup,
        zone: zone,
        province: province,
        district: district,
        subdistrict: subdistrict,
        village: village,
        rootNo: rootNo,
        sequenceNo: sequenceNo,
        prevPlotNo: prevPlotNo,
        caneType: caneType,
        caneVariety: caneVariety,
        ownership: ownership,
        terrain: terrain,
        hasLoss: hasLoss,
        lossRai: lossRai,
        targetYield: targetYield,
        note: note,
        photos: photos,
        draft: draft,
        points: List.of(_draft),
        survey: _surveyPayload(),
      );
      _parcels = [..._parcels, p];
      _invalidateRender();
      // จำ id ไว้ bypass year filter — แปลงที่เพิ่งวาดต้องไม่หาย
      // ทั้งที่ปีการผลิตไม่อยู่ในชุดที่ดาวน์โหลดไว้
      if (!p.isDraft) {
        _freshIds.add(p.id);
        _fresh[p.id] = p;
      }
      // รูปที่ถ่ายประกอบการวัดไม่มี endpoint อัปโหลด — เก็บเป็น
      // activity draft ผูกกับแปลงที่สร้าง กันรูปหายเงียบๆ
      if (!p.isDraft && photos.isNotEmpty) {
        try {
          await _service.saveActivityDraft(
            plotId: p.id,
            photoPaths: photos,
            detailPending: true,
          );
        } catch (_) {}
      }
      cancelDrawing();
      // POST หลุดกลางทาง → createParcel fallback เซฟเป็นร่าง —
      // ต้องบอกตรงๆ ไม่ใช่ "สำเร็จ" เดี๋ยว user คิดว่าขึ้นระบบแล้ว
      if (!draft && p.isDraft) {
        return 'ส่งขึ้นเซิร์ฟเวอร์ไม่ได้ — บันทึกเป็นฉบับร่างไว้แล้ว '
            'ยืนยันส่งใหม่ได้จากรายการร่างแปลง';
      }
      return null;
    } catch (e) {
      return '$e'.replaceFirst('Exception: ', '');
    } finally {
      _saving = false;
      _safeNotify();
    }
  }
}

/// มุมหนึ่งมุมจากการเดินวัด — backend ใช้ตรวจความแม่นยำไม่เกิน 15 เมตร
class WalkCorner {
  const WalkCorner({
    required this.point,
    required this.accuracyM,
    required this.capturedAt,
  });

  final LatLng point;
  final double accuracyM;
  final DateTime capturedAt;

  Map<String, Object> toJson() => {
    'latitude': point.latitude,
    'longitude': point.longitude,
    'accuracyM': accuracyM,
    'capturedAt': capturedAt.toUtc().toIso8601String(),
  };
}

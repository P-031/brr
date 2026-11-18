import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

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

  // drawing state
  bool _drawing = false;
  final List<LatLng> _draft = [];

  // walk-measure state
  StreamSubscription<Position>? _posSub;
  bool _walking = false;
  bool _walkPaused = false;
  double? _gpsAccuracy;

  /// นับ fix ที่ accuracy >20ม. ต่อเนื่อง — ครบ 5 → auto-pause
  int _badFixStreak = 0;

  /// true เมื่อหยุดพักเพราะ GPS แย่ (ไม่ใช่ผู้ใช้กดพักเอง) —
  /// UI แสดงข้อความต่างกัน
  bool _autoPaused = false;
  LatLng? _lastFix;

  List<Parcel> get parcels => _parcels;

  /// ฟิลเตอร์ปีการผลิต — null คือแสดงทุกปี
  String? _yearFilter;
  String? get yearFilter => _yearFilter;

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
          : (yearAllowlist == null ||
                  yearAllowlist!.contains(p.productionYear)) &&
              (_yearFilter == null || p.productionYear == _yearFilter))
        p,
  ];

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

  List<Parcel> get renderableParcels =>
      _renderCache ??= _computeRenderable();

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
    return [
      ...inView.where((p) => p.isDraft),
      ...inView.where((p) => !p.isDraft).take(_maxRenderedParcels),
    ];
  }

  void setYearFilter(String? year) {
    _yearFilter = year;
    _invalidateRender();
    notifyListeners();
  }

  /// Viewport refetch in progress — drives the thin top progress bar.
  bool _loadingViewport = false;
  bool get loadingViewport => _loadingViewport;

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
  Future<void> loadViewport(
    double west,
    double south,
    double east,
    double north,
  ) async {
    final b = (w: west, s: south, e: east, n: north);
    // อัพเดทกรอบมองเสมอ — renderableParcels คัด polygon ตามกรอบนี้
    final moved = _viewBox != b;
    _viewBox = b;
    if (moved) _invalidateRender();
    final cov = _coverage;
    if (_loadingViewport ||
        (cov != null &&
            b.w >= cov.w &&
            b.s >= cov.s &&
            b.e <= cov.e &&
            b.n <= cov.n)) {
      if (moved) notifyListeners();
      return;
    }
    _loadingViewport = true;
    notifyListeners();
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
      ];
      _invalidateRender();
      // จำ coverage เฉพาะ fetch ที่ครบ — truncated มีหลุมในกรอบนี้
      // ห้ามข้าม fetch รอบต่อไปไม่งั้นแปลงหายรอบๆหมุด
      _coverage = page.truncated ? null : b;
    } catch (_) {}
    _loadingViewport = false;
    notifyListeners();
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

  @override
  void dispose() {
    _posSub?.cancel();
    super.dispose();
  }

  /// VM ของ flow ข้อมูลแปลง (info sheet → รายละเอียด → เมนูแก้ไข) —
  /// สร้างต่อแปลงที่แตะ แชร์ service/token เดียวกัน
  ParcelDetailViewModel detailVmFor(Parcel p) =>
      ParcelDetailViewModel(parcel: p, service: _service);

  /// VM ของหน้าดาวน์โหลด — แชร์ service เดียวกัน ไม่สร้างใหม่
  PlotDownloadViewModel createDownloadVm() =>
      PlotDownloadViewModel(_service);

  /// VM หน้า "ข้อมูลฉบับร่าง" — แปลงที่บันทึกลงเครื่องเท่านั้น
  DraftsViewModel createDraftsVm() => DraftsViewModel(_service);

  /// รับผลจากหน้าดาวน์โหลด — เก็บเฉพาะปีที่ติ๊ก + draft ทั้งหมด
  /// แล้วตั้ง coverage/allowlist ให้ viewport fetch กรองตามปีนั้นต่อ
  void applyDownload(ParcelPage page, Set<String?> years) {
    _yearAllowlist = years;
    _parcels = [
      for (final p in page.items)
        if (p.isDraft || years.contains(p.productionYear)) p,
    ];
    _coverage = page.truncated ? null : _parseBox(ParcelService.fullBox);
    _yearFilter = null;
    _loading = false;
    _error = null;
    _invalidateRender();
    notifyListeners();
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
    notifyListeners();
    try {
      final page = await _service.fetchParcels();
      _parcels = page.items;
      _invalidateRender();
      if (!page.truncated) _coverage = _parseBox(ParcelService.fullBox);
    } catch (e) {
      _error = '$e';
      // server ดึงไม่ได้ก็ยังโชว์ร่างในเครื่อง — ร่างต้องอยู่บน
      // แผนที่ตลอดจนกว่าจะลบหรือยืนยันขึ้น server
      _parcels = await _service.fetchDrafts();
      _invalidateRender();
    }
    _loading = false;
    notifyListeners();
  }

  /// เพิ่มพิกัด — enter drawing mode (officers/admins only).
  Future<void> startDrawing() async {
    if (!canDrawManually) return;
    _drawing = true;
    _draft.clear();
    notifyListeners();
    // subscribe position stream ด้วย — แผง GPS ในแถบล่างต้องมี
    // พิกัด/คลาดเคลื่อนจริงแม้โหมดแตะวาด (ไม่ได้เดินวัด)
    if (await _location.ensurePermission()) {
      _posSub ??= _location
          .positionStream()
          .listen(_onPosition, onError: (_) {});
    }
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
    if (_userPos != null) notifyListeners();
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
    notifyListeners();
    _posSub = _location
        .positionStream()
        .listen(_onPosition, onError: (_) {});
    return null;
  }

  /// Pause/resume walk tracking (draft is kept).
  void toggleWalkPause() {
    if (!_walking) return;
    _walkPaused = !_walkPaused;
    _autoPaused = false;
    _badFixStreak = 0;
    notifyListeners();
  }

  /// Stops tracking; the drawn boundary stays for review/saving.
  void stopWalk() {
    _posSub?.cancel();
    _posSub = null;
    _walking = false;
    _walkPaused = false;
    _autoPaused = false;
    _badFixStreak = 0;
    notifyListeners();
  }

  void _onPosition(Position p) {
    _gpsAccuracy = p.accuracy;
    _lastFix = LatLng(p.latitude, p.longitude);
    // โหมดแตะวาด — อัปเดตพิกัด/คลาดเคลื่อนให้แผง GPS อย่างเดียว
    if (!_walking) {
      notifyListeners();
      return;
    }
    // อัพเดท badge แม้ตอนพัก — ผู้วัดเห็นสัญญาณฟื้นตัวก่อนกดเดินต่อ
    if (_walkPaused) {
      notifyListeners();
      return;
    }
    // สัญญาณแย่เกิน — badge เปลี่ยนสีแต่ไม่ลงจุด
    if (p.accuracy > 20) {
      // GPS แย่ต่อเนื่อง — auto-pause กันเส้นกระโดด/จุดหลุด
      // ผู้ใช้กดเดินต่อเองเมื่อสัญญาณดีกลับมา
      _badFixStreak++;
      if (_badFixStreak >= 5) {
        _walkPaused = true;
        _autoPaused = true;
      }
      notifyListeners();
      return;
    }
    _badFixStreak = 0;
    // ลงจุดเฉพาะ fix ที่แม่นพอ (≤6ม.) — แย่กว่านั้น
    // เดินผ่านไปแต่ไม่ปัก เพื่อขอบแม่นสุด
    if (p.accuracy > 6) {
      notifyListeners();
      return;
    }
    if (_draft.isNotEmpty) {
      const dist = Distance();
      final d = dist.as(LengthUnit.Meter, _draft.last, _lastFix!);
      if (d < 2.5) {
        notifyListeners();
        return;
      }
      // GPS spike — กระโดด >25ม. ในไม่กี่วิ เดินไปไม่ถึง
      // เป็น error ไม่ใช่จุดจริง ปฏิเสธไม่ลงขอบ
      if (d > 25) {
        notifyListeners();
        return;
      }
    }
    _draft.add(_lastFix!);
    notifyListeners();
  }

  void addDraftPoint(LatLng p) {
    if (!_drawing) return;
    _draft.add(p);
    notifyListeners();
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
      if (d > 25) return 'พิกัดกระโดดผิดปกติ — ไม่สามารถบันทึกค่าได้';
    }
    _draft.add(fix);
    notifyListeners();
    return null;
  }

  /// ย้อนกลับ — remove the last drafted point.
  void undoDraftPoint() {
    if (_draft.isNotEmpty) _draft.removeLast();
    notifyListeners();
  }

  /// ลากย้ายหมุด — update the point at [index] after a pin drag.
  void moveDraftPoint(int index, LatLng p) {
    if (index < 0 || index >= _draft.length) return;
    _draft[index] = p;
    notifyListeners();
  }

  /// เริ่มใหม่ — clear every drafted point, stay in drawing mode.
  void clearDraft() {
    if (_draft.isEmpty) return;
    _draft.clear();
    notifyListeners();
  }

  void cancelDrawing() {
    _posSub?.cancel();
    _posSub = null;
    _drawing = false;
    _walking = false;
    _walkPaused = false;
    _draft.clear();
    notifyListeners();
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
    if (_saving) return null;
    _saving = true;
    notifyListeners();
    try {
      final p = await _service.createParcel(
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
      );
      _parcels = [..._parcels, p];
      _invalidateRender();
      cancelDrawing();
      return null;
    } catch (e) {
      return '$e';
    } finally {
      _saving = false;
      notifyListeners();
    }
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'package:brr/features/map/models/parcel.dart';
import 'package:brr/core/services/api_client.dart';
import 'package:brr/features/map/data/location_service.dart';
import 'package:brr/features/map/data/parcel_service.dart';

/// ViewModel for the area-measurement map screen — parcel display
/// plus a drawing mode for marking a new boundary.
class MapViewModel extends ChangeNotifier {
  MapViewModel({
    ApiClient? api,
    ParcelService? service,
    LocationService? location,
    this.canDrawManually = true,
  }) : _service = service ?? ParcelService(api),
       _location = location ?? LocationService() {
    load();
  }

  final ParcelService _service;
  final LocationService _location;

  /// Officers/admins may also draw boundaries by tapping; farmers
  /// only get walk-measure mode.
  final bool canDrawManually;

  List<Parcel> _parcels = const [];
  bool _loading = true;
  String? _error;

  // drawing state
  bool _drawing = false;
  final List<LatLng> _draft = [];

  // walk-measure state
  StreamSubscription<Position>? _posSub;
  bool _walking = false;
  bool _walkPaused = false;
  double? _gpsAccuracy;
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

  /// แปลงที่วาดบนแผนที่ตาม filter — draft แสดงเสมอ
  List<Parcel> get visibleParcels => _yearFilter == null
      ? _parcels
      : [
          for (final p in _parcels)
            if (p.isDraft || p.productionYear == _yearFilter) p,
        ];

  void setYearFilter(String? year) {
    _yearFilter = year;
    notifyListeners();
  }

  /// Viewport refetch in progress — drives the thin top progress bar.
  bool _loadingViewport = false;
  bool get loadingViewport => _loadingViewport;

  /// Plot save POST in progress — drives the blocking overlay.
  bool _saving = false;
  bool get saving => _saving;

  /// Reload parcels inside the visible map bounds — keeps local
  /// drafts, drops backend items that scrolled out of view.
  Future<void> loadViewport(String box) async {
    if (_loadingViewport) return;
    _loadingViewport = true;
    notifyListeners();
    try {
      final fresh = await _service.fetchParcels(box: box);
      _parcels = [
        ...fresh.where((p) => !p.isDraft),
        ..._parcels.where((p) => p.isDraft),
      ];
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
  LatLng? get lastFix => _lastFix;

  @override
  void dispose() {
    _posSub?.cancel();
    super.dispose();
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
    notifyListeners();
    try {
      _parcels = await _service.fetchParcels();
    } catch (e) {
      _error = '$e';
    }
    _loading = false;
    notifyListeners();
  }

  /// เพิ่มพิกัด — enter drawing mode (officers/admins only).
  void startDrawing() {
    if (!canDrawManually) return;
    _drawing = true;
    _draft.clear();
    notifyListeners();
  }

  /// Last known user position — set by [locate] (GPS button) or live
  /// fixes while walk-measuring.
  LatLng? get userPos => _lastFix ?? _userPos;
  LatLng? _userPos;

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
    notifyListeners();
  }

  /// Stops tracking; the drawn boundary stays for review/saving.
  void stopWalk() {
    _posSub?.cancel();
    _posSub = null;
    _walking = false;
    _walkPaused = false;
    notifyListeners();
  }

  void _onPosition(Position p) {
    if (_walkPaused || !_walking) return;
    _gpsAccuracy = p.accuracy;
    _lastFix = LatLng(p.latitude, p.longitude);
    // Bad fixes still update the accuracy badge but never plot.
    if (p.accuracy > 20) {
      notifyListeners();
      return;
    }
    if (_draft.isNotEmpty) {
      const dist = Distance();
      if (dist.as(LengthUnit.Meter, _draft.last, _lastFix!) < 2.5) {
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

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../models/parcel.dart';
import '../services/api_client.dart';
import '../services/parcel_service.dart';

/// ViewModel for the area-measurement map screen — parcel display
/// plus a drawing mode for marking a new boundary.
class MapViewModel extends ChangeNotifier {
  MapViewModel({ApiClient? api, ParcelService? service})
    : _service = service ?? ParcelService(api) {
    load();
  }

  final ParcelService _service;

  List<Parcel> _parcels = const [];
  bool _loading = true;
  String? _error;

  // drawing state
  bool _drawing = false;
  final List<LatLng> _draft = [];

  List<Parcel> get parcels => _parcels;
  bool get loading => _loading;
  String? get error => _error;
  bool get drawing => _drawing;
  List<LatLng> get draft => List.unmodifiable(_draft);
  ParcelService get service => _service;

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

  /// เพิ่มพิกัด — enter drawing mode (or stays in it).
  void startDrawing() {
    _drawing = true;
    _draft.clear();
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

  void cancelDrawing() {
    _drawing = false;
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
    try {
      final p = await _service.createParcel(
        name: name,
        productionYear: productionYear,
        officerName: officerName,
        project: project,
        farmerName: farmerName,
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
    }
  }
}

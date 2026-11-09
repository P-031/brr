import 'package:flutter/foundation.dart';

import '../models/parcel.dart';
import '../services/api_client.dart';
import '../services/parcel_service.dart';

/// ViewModel for the area-measurement map screen.
class MapViewModel extends ChangeNotifier {
  MapViewModel({ApiClient? api, ParcelService? service})
    : _service = service ?? ParcelService(api) {
    load();
  }

  final ParcelService _service;

  List<Parcel> _parcels = const [];
  bool _loading = true;
  String? _error;

  List<Parcel> get parcels => _parcels;
  bool get loading => _loading;
  String? get error => _error;

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
}

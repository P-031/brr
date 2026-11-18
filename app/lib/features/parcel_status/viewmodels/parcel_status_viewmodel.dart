import 'package:flutter/foundation.dart';

import 'package:brr/core/services/api_client.dart';
import 'package:brr/features/map/data/parcel_service.dart';
import 'package:brr/features/map/models/parcel.dart';
import 'package:brr/features/parcel_status/models/plot_request.dart';

/// ViewModel ของหน้า "สถานะแปลง" — แถบ tab สถานะดึงจาก backend
/// (`/meta/options → parcelStatuses`) เสมอ ไม่ hardcode
///
/// รายการต่อ tab = คำขอแปลงจริงจาก `GET /plot-requests` กรองตาม
/// status ของคำขอ (รออนุมัติ/อนุมัติ/… ตรงชื่อ tab จาก backend)
class ParcelStatusViewModel extends ChangeNotifier {
  ParcelStatusViewModel(ParcelService? service) : _service = service {
    load();
  }

  /// สร้างจาก session api — view ส่งแค่นี้ ไม่ต้องเห็น ParcelService
  /// (api null = ออฟไลน์)
  ParcelStatusViewModel.forApi(ApiClient? api)
    : this(api == null ? null : ParcelService(api));

  final ParcelService? _service;

  List<String> _statuses = const [];
  List<PlotRequestEntry> _requests = const [];
  bool _loading = true;
  String? _error;

  /// ชื่อ tab จาก backend — ว่างระหว่างโหลด/ถ้า endpoint ล้มเหลว
  List<String> get statuses => _statuses;

  bool get loading => _loading;
  String? get error => _error;

  /// คำขอที่ตรงสถานะ tab — status เป็นค่าไทยตรงกับ tab จาก backend
  List<PlotRequestEntry> requestsOf(String status) =>
      _requests.where((r) => r.status == status).toList();

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final service = _service;
      if (service != null) {
        final results = await Future.wait([
          service.fetchOptions(),
          service.fetchPlotRequests(),
        ]);
        _statuses = (results[0] as FormOptions).parcelStatuses;
        _requests = results[1] as List<PlotRequestEntry>;
      }
    } catch (e) {
      _error = '$e';
    }
    _loading = false;
    notifyListeners();
  }
}

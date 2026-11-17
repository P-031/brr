import 'package:flutter/foundation.dart';

import 'package:brr/features/map/data/parcel_service.dart';
import 'package:brr/features/map/models/parcel.dart';

/// ViewModel ของหน้า "สถานะแปลง" — แถบ tab สถานะดึงจาก backend
/// (`/meta/options → parcelStatuses`) เสมอ ไม่ hardcode
///
/// TODO(backend): รายการแปลงต่อสถานะยังไม่มี endpoint — เมื่อมีให้
/// เติม [_parcels] จาก service (เช่น filter สถานะฝั่ง server) แล้ว
/// tab เดิมใช้งานต่อได้เลย
class ParcelStatusViewModel extends ChangeNotifier {
  ParcelStatusViewModel(ParcelService? service) : _service = service {
    load();
  }

  final ParcelService? _service;

  List<String> _statuses = const [];
  final List<Parcel> _parcels = const [];
  bool _loading = true;
  String? _error;

  /// ชื่อ tab จาก backend — ว่างระหว่างโหลด/ถ้า endpoint ล้มเหลว
  List<String> get statuses => _statuses;

  /// แปลงที่ตรงสถานะ — ว่างจนกว่าจะมี endpoint รายการแปลง
  List<Parcel> get parcels => _parcels;

  bool get loading => _loading;
  String? get error => _error;

  List<Parcel> parcelsOf(String status) =>
      _parcels.where((p) => (p.status ?? status) == status).toList();

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final opts = await _service?.fetchOptions();
      _statuses = opts?.parcelStatuses ?? const [];
    } catch (e) {
      _error = '$e';
    }
    _loading = false;
    notifyListeners();
  }
}

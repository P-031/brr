import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'package:brr/core/services/api_client.dart';
import 'package:brr/features/map/data/parcel_service.dart';
import 'package:brr/features/map/data/satellite_thumb_service.dart';
import 'package:brr/features/map/models/sat_thumb.dart';
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

  /// หยิบ ApiClient จาก Provider ที่ root — view ไม่ต้องถือ
  /// type ของชั้น data ส่งต่อเอง (MVVM)
  factory ParcelStatusViewModel.forContext(BuildContext context) =>
      ParcelStatusViewModel.forApi(context.read<ApiClient>());

  final ParcelService? _service;

  /// loader รูปดาวเทียมให้ widget SatelliteThumb — view ไม่เห็น
  /// ชั้น data ตรงๆ
  SatThumbLoader get satThumb => SatelliteThumbService.load;

  List<String> _statuses = const [];
  List<PlotRequestEntry> _requests = const [];
  bool _loading = true;
  String? _error;

  /// ชื่อ tab จาก backend — ว่างระหว่างโหลด/ถ้า endpoint ล้มเหลว
  List<String> get statuses => _statuses;

  bool get loading => _loading;
  String? get error => _error;

  /// รายการคำขอโหลดพลาดแต่แถบสถานะยังมา — view โชว์แจ้งเฉพาะส่วน
  /// list แทนที่จะทำทั้งหน้าพัง (endpoint /plot-requests กำลัง
  /// พัฒนาอยู่ฝั่ง backend — 404/500 ไม่ควรทำให้ tab หาย)
  String? get requestsError => _requestsError;
  String? _requestsError;

  /// คำขอที่ตรงสถานะ tab — status เป็นค่าไทยตรงกับ tab จาก backend
  List<PlotRequestEntry> requestsOf(String status) =>
      _requests.where((r) => r.status == status).toList();

  /// คำขอที่ยังไม่ตัดสิน — หน้าอนุมัติใช้ (backend ตั้งชื่อ
  /// สถานะเริ่มต้นว่า "รออนุมัติ" ตรงตัวเลือก parcelStatuses)
  List<PlotRequestEntry> get pending =>
      _requests.where((r) => r.status == 'รออนุมัติ').toList();

  /// ตัดสินคำขอ — PATCH แล้วอัปเดต status ใน list ให้ย้าย tab
  /// ทันที ไม่ต้อง reload ทั้งหน้า; throw ให้ view แจ้ง error
  Future<void> decideRequest(String requestId, String status) async {
    final service = _service;
    if (service == null) {
      throw Exception('ออฟไลน์อยู่ — ตัดสินคำขอไม่ได้');
    }
    final newStatus = await service.updateRequestStatus(requestId, status);
    final i = _requests.indexWhere((r) => r.id == requestId);
    if (i >= 0) {
      final r = _requests[i];
      _requests[i] = PlotRequestEntry(
        id: r.id,
        plotId: r.plotId,
        plotName: r.plotName,
        productionYear: r.productionYear,
        requester: r.requester,
        farmerName: r.farmerName,
        areaSqm: r.areaSqm,
        kind: r.kind,
        payload: r.payload,
        status: newStatus,
        createdAt: r.createdAt,
        points: r.points,
      );
      _safeNotify();
    }
  }

  bool _disposed = false;

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> load() async {
    _loading = true;
    _error = null;
    _requestsError = null;
    _safeNotify();
    final service = _service;
    if (service != null) {
      // โหลดสองส่วนแยกกัน — อย่าให้ request endpoint ที่ยังไม่มี
      // ล้มแล้วลาก statuses ที่โหลดสำเร็จหายไปด้วย
      try {
        _statuses = (await service.fetchOptions()).parcelStatuses;
      } catch (e) {
        _error = '$e'.replaceFirst('Exception: ', '');
      }
      try {
        _requests = await service.fetchPlotRequests();
      } catch (e) {
        _requestsError = '$e'.replaceFirst('Exception: ', '');
      }
    }
    _loading = false;
    _safeNotify();
  }
}

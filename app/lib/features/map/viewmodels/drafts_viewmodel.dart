import 'package:flutter/widgets.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import 'package:brr/core/services/api_client.dart';
import 'package:brr/features/map/data/parcel_service.dart';
import 'package:brr/features/map/data/satellite_thumb_service.dart';
import 'package:brr/features/map/models/parcel.dart';
import 'package:brr/features/map/models/sat_thumb.dart';
import 'package:brr/features/map/viewmodels/parcel_detail_viewmodel.dart';
import 'package:brr/features/map/models/measurement_result.dart';

/// ViewModel หน้า "ข้อมูลฉบับร่าง" — แปลงที่กด "บันทึกข้อมูลลงเครื่อง
/// (ฉบับร่าง)" ไว้ อยู่ใน SharedPreferences ไม่เคยยิงขึ้น backend
/// ดึง/ลบ/ยืนยันผ่าน ParcelService เท่านั้น (view ไม่แตะ storage
/// ตรงๆ)
class DraftsViewModel extends ChangeNotifier {
  DraftsViewModel(this._service) {
    refresh();
  }

  /// สร้างจาก session api — view ส่งแค่นี้ ไม่ต้องเห็น ParcelService
  DraftsViewModel.forApi(ApiClient? api) : this(ParcelService(api));

  /// หยิบ ApiClient จาก Provider ที่ root — view ไม่ต้องถือ
  /// type ของชั้น data ส่งต่อเอง (MVVM)
  factory DraftsViewModel.forContext(BuildContext context) =>
      DraftsViewModel.forApi(context.read<ApiClient>());

  final ParcelService _service;

  List<Parcel> _drafts = const [];
  bool _loading = true;
  String? _busyId;

  List<Parcel> get drafts => _drafts;
  bool get loading => _loading;

  /// ฟิลเตอร์สถานะการ์ด: 'all' | 'confirmed' | 'pending'
  /// (ยืนยันแล้ว = status 'confirmed' ที่ stamp ตอน upload สำเร็จ)
  String _statusFilter = 'all';
  String get statusFilter => _statusFilter;

  set statusFilter(String v) {
    _statusFilter = v;
    _shown = pageSize;
    notifyListeners();
  }

  /// รายการตามฟิลเตอร์ที่เลือก — ร่างเก่าไม่มี status = ยังไม่ยืนยัน
  List<Parcel> get filteredDrafts => switch (_statusFilter) {
    'confirmed' => [
      for (final d in _drafts)
        if (d.status == 'confirmed') d,
    ],
    'pending' => [
      for (final d in _drafts)
        if (d.status != 'confirmed') d,
    ],
    _ => _drafts,
  };

  /// โชว์ทีละหน้าเหมือนหน้ากิจกรรมแปลง — ข้อมูล local ไม่ต้อง
  /// fetch แต่ list ยาวๆ ให้กด "โหลดเพิ่ม" แทนจอเลื่อนไม่สุด
  static const pageSize = 15;
  int _shown = pageSize;

  /// รายการที่โชว์จริงตอนนี้ (ฟิลเตอร์ + จำนวนหน้าที่ขยาย)
  List<Parcel> get visibleDrafts => filteredDrafts.take(_shown).toList();

  /// ยังเหลือรายการให้ "โหลดเพิ่ม" อีกไหม
  bool get hasMore => _shown < filteredDrafts.length;

  void loadMore() {
    _shown += pageSize;
    notifyListeners();
  }

  /// id ของร่างที่กำลังยืนยัน/แก้ไขอยู่ — ปิดปุ่มใบนั้นกันกดซ้ำ
  String? get busyId => _busyId;

  /// loader รูปดาวเทียมให้ widget SatelliteThumb — view ผูกเข้า
  /// widget ไม่เห็นชั้น data ตรงๆ
  SatThumbLoader get satThumb => SatelliteThumbService.load;

  /// fetcher ของหน้าฟอร์มแก้ไขร่าง — ส่งต่อ service เหมือน
  /// MapViewModel ทำให้หน้าบันทึกการวัด
  Future<List<String>> fetchOfficers() => _service.fetchOfficers();
  Future<List<FarmerRef>> fetchFarmers() => _service.fetchFarmers();
  Future<FormOptions> fetchOptions() => _service.fetchOptions();

  /// โหลดรายการร่างใหม่ — เรียกตอนเข้าหน้าและหลังลบ/ยืนยัน
  Future<void> refresh() async {
    _loading = true;
    notifyListeners();
    _drafts = await _service.fetchDrafts();
    _loading = false;
    notifyListeners();
  }

  /// true เมื่อมีร่างถูกลบ/ยืนยันระหว่างเปิดหน้า — view pop ค่านี้
  /// กลับให้หน้าแผนที่ refetch แปลงที่วาดอยู่
  bool get changed => _changed;
  bool _changed = false;

  /// ลบร่างออกจากเครื่อง — view confirm ก่อนเอง
  Future<void> remove(Parcel p) async {
    await _service.removeDraft(p.id);
    _changed = true;
    await refresh();
  }

  /// ยืนยันร่าง — replay payload ที่เก็บใน meta เป็น POST /plots
  /// จริง สำเร็จแล้ว stamp ร่างเป็น "ยืนยันแล้ว" (ยังอยู่ใน list
  /// ให้กรองดูย้อนได้); คืน error text เมื่อล้มเหลว (เช่น
  /// ออฟไลน์) ร่างยังสถานะเดิม
  Future<String?> confirm(Parcel p) {
    return _save(
      p,
      (points) async {
        final id = await _service.ensureClientId(p);
        return _service.createParcel(
          id: id,
          name: p.name,
          variety: p.variety ?? '',
          productionYear: p.productionYear ?? _s(p, 'productionYear'),
          officerName: _s(p, 'officerName'),
          project: _s(p, 'project'),
          farmerName: _s(p, 'farmerName'),
          farmerId: _s(p, 'farmerId'),
          caneGroup: _s(p, 'caneGroup'),
          zone: _s(p, 'zone'),
          province: _s(p, 'province'),
          district: _s(p, 'district'),
          subdistrict: _s(p, 'subdistrict'),
          village: _s(p, 'village'),
          rootNo: _s(p, 'rootNo'),
          sequenceNo: _s(p, 'sequenceNo'),
          prevPlotNo: _s(p, 'prevPlotNo'),
          caneType: _s(p, 'caneType'),
          caneVariety: _s(p, 'caneVariety'),
          ownership: _s(p, 'ownership'),
          terrain: _s(p, 'terrain'),
          hasLoss: _s(p, 'hasLoss'),
          lossRai: '${p.meta?['lossRai'] ?? ''}'.isEmpty
              ? null
              : '${p.meta?['lossRai']}',
          targetYield: '${p.meta?['targetYield'] ?? ''}'.isEmpty
              ? null
              : '${p.meta?['targetYield']}',
          note: _s(p, 'note'),
          photos: _photosOf(p),
          points: points,
          survey: _surveyOf(p),
        );
      },
      confirm: true,
      photos: _photosOf(p),
    );
  }

  /// บันทึกผลแก้ไขจากฟอร์ม — ร่างใหม่ (draft:true) หรือส่งจริง
  /// (draft:false) ด้วย polygon เดิม แล้วลบร่างเก่าออก
  /// คืน error text เมื่อล้มเหลว ร่างเก่ายังอยู่
  Future<String?> applyEdit(Parcel old, MeasurementResult r) {
    return _save(
      old,
      (points) async {
        final id = await _service.ensureClientId(old);
        return _service.createParcel(
          id: id,
          name: r.name,
          productionYear: r.productionYear,
          officerName: r.officerName,
          project: r.project,
          farmerName: r.farmerName,
          farmerId: r.farmerId,
          caneGroup: r.caneGroup,
          zone: r.zone,
          province: r.province,
          district: r.district,
          subdistrict: r.subdistrict,
          village: r.village,
          rootNo: r.rootNo,
          sequenceNo: r.sequenceNo,
          prevPlotNo: r.prevPlotNo,
          caneType: r.caneType,
          caneVariety: r.caneVariety,
          ownership: r.ownership,
          terrain: r.terrain,
          hasLoss: r.hasLoss,
          lossRai: r.lossRai,
          targetYield: r.targetYield,
          note: r.note,
          photos: r.photos,
          draft: r.draft,
          points: points,
          survey: _surveyOf(old),
        );
      },
      // ส่งจริง → ร่างเดิมกลายเป็น "ยืนยันแล้ว"; บันทึกร่างใหม่
      // → ลบตัวเก่า (ถูกร่างใหม่แทนแล้ว)
      confirm: !r.draft,
      photos: r.photos,
    );
  }

  /// ดาวน์โหลด/อัปเดตจุดเสี่ยงภัยพิบัติล่าสุดลงเครื่อง —
  /// คืน error text เมื่อล้มเหลว (ออฟไลน์/endpoint ยังไม่มี)
  Future<String?> downloadRiskData() async {
    try {
      final n = await _service.downloadRiskPoints();
      return n == 0 ? 'ดาวน์โหลดแล้วแต่ไม่มีข้อมูลจุดเสี่ยง' : null;
    } catch (e) {
      return '$e';
    }
  }

  Map<String, Object?>? _surveyOf(Parcel parcel) {
    final raw = parcel.meta?['survey'];
    if (raw is! Map) return null;
    return Map<String, Object?>.from(raw);
  }

  /// meta['photos'] จาก backend/เครื่องอาจไม่ใช่ List เสมอ
  /// (field ผิดชนิด) — cast ดิบจะพังทั้งหน้ารายการ
  static List<String> _photosOf(Parcel p) {
    final raw = p.meta?['photos'];
    return raw is List ? [for (final x in raw) '$x'] : const [];
  }

  /// สร้าง parcel ผ่าน callback → สำเร็จแล้วจัดการร่างต้นทาง
  /// (ยืนยัน = stamp confirmed; แก้ไข = ลบทิ้งเพราะถูกแทนด้วยร่างใหม่)
  /// callback ปิดล้อม _service ไว้ใน VM — ไม่รั่วชนิด service ออกนอกชั้น
  Future<String?> _save(
    Parcel source,
    Future<Parcel> Function(List<LatLng>) create, {
    bool confirm = false,
    List<String> photos = const [],
  }) async {
    _busyId = source.id;
    notifyListeners();
    try {
      final created = await create(source.points);
      if (confirm) {
        // รูปประกอบการวัดไม่มี endpoint อัปโหลด — เก็บเป็น activity
        // draft ผูกกับแปลงจริงที่สร้าง กันรูปหายเงียบๆ ตอนยืนยัน
        if (photos.isNotEmpty) {
          try {
            await _service.saveActivityDraft(
              plotId: created.id,
              photoPaths: photos,
              detailPending: true,
            );
          } catch (_) {}
        }
        await _service.markDraftConfirmed(source.id);
      } else {
        await _service.removeDraft(source.id);
      }
      _changed = true;
      await refresh();
      return null;
    } catch (e) {
      return '$e';
    } finally {
      _busyId = null;
      notifyListeners();
    }
  }

  static String? _s(Parcel p, String k) {
    final v = '${p.meta?[k] ?? ''}';
    return v.isEmpty ? null : v;
  }

  /// VM ของ flow ข้อมูลแปลง — view ใช้เปิด info sheet/หน้ารายละเอียด
  /// โดยไม่แตะ ParcelService ตรงๆ (draft → detail resolve null)
  ParcelDetailViewModel detailVmFor(Parcel p) =>
      ParcelDetailViewModel(parcel: p, service: _service);
}

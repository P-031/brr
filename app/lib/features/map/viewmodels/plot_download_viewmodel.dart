import 'package:flutter/foundation.dart';

import 'package:brr/features/map/data/parcel_service.dart';
import 'package:brr/features/map/models/parcel.dart';

/// ผลลัพธ์ที่หน้าดาวน์โหลด pop กลับให้หน้าแผนที่ — payload แปลง
/// ที่โหลดมา + ชุดปีที่ผู้ใช้ติ๊กไว้ (ใช้กรองต่อบนแผนที่)
typedef PlotDownloadResult = ({ParcelPage page, Set<String?> selected});

/// ViewModel for the plot-download selection screen — owns the year
/// index, the checked set, download progress and the offline cache
/// fallback. The view only renders this state and pops the result.
class PlotDownloadViewModel extends ChangeNotifier {
  PlotDownloadViewModel(ParcelService service) : _service = service {
    loadIndex();
  }

  final ParcelService _service;

  /// จำนวนแปลงต่อปีจาก server (ไม่รวม draft) — null ขณะโหลดรอบแรก.
  Map<String?, int>? _serverYears;
  List<Parcel> _drafts = const [];
  String? _error;

  /// true ขณะกำลังดาวน์โหลดขอบแปลงจริงหลังกดปุ่ม.
  bool _downloading = false;
  String? _downloadError;

  /// ความคืบหน้าดาวน์โหลด — received bytes / total (null = ไม่ทราบขนาด).
  int _received = 0;
  int? _total;

  /// true ตอนรับ bytes ครบแล้วกำลัง gunzip+parse — UI เปลี่ยนเป็น
  /// "กำลังเตรียมข้อมูล" แทนที่จะปล่อยให้ดูเหมือนค้างที่ 100%
  bool _processing = false;

  /// ปีที่ติ๊กเลือก — null inside = แปลงที่ไม่มีปีการผลิต.
  final Set<String?> _selected = {};

  Map<String?, int>? get serverYears => _serverYears;
  List<Parcel> get drafts => _drafts;
  String? get error => _error;
  bool get downloading => _downloading;
  String? get downloadError => _downloadError;
  int get received => _received;
  int? get total => _total;
  bool get processing => _processing;
  Set<String?> get selected => _selected;

  /// จำนวนแปลงต่อปีสำหรับแสดง — รวม draft ในเครื่องเข้ากลุ่มปีของมัน
  /// (draft ถูกดาวน์โหลดเสมอไม่ว่าจะติ๊กปีไหน).
  Map<String?, int> get displayYears {
    final merged = Map<String?, int>.from(_serverYears ?? const {});
    for (final d in _drafts) {
      merged.update(d.productionYear, (v) => v + 1, ifAbsent: () => 1);
    }
    return merged;
  }

  /// เรียงปีล่าสุดก่อน ปีว่างไว้ท้ายสุด.
  List<MapEntry<String?, int>> get sortedYears {
    final entries = displayYears.entries.toList()
      ..sort((a, b) {
        if (a.key == null) return 1;
        if (b.key == null) return -1;
        return b.key!.compareTo(a.key!);
      });
    return entries;
  }

  /// แปลงที่จะดาวน์โหลด = ปีที่ติ๊ก (นับจาก server) + draft ทั้งหมด.
  int get selectedCount {
    var n = _drafts.length;
    (_serverYears ?? const {}).forEach((y, c) {
      if (_selected.contains(y)) n += c;
    });
    return n;
  }

  /// เปอร์เซ็นต์ดาวน์โหลด — null เมื่อ server ไม่บอกขนาด (แถบเดินไม่รู้จบ).
  double? get progress => _total == null || _total! <= 0
      ? null
      : (_received / _total!).clamp(0.0, 1.0);

  /// รอบแรก — ดึงเฉพาะรายการปี + จำนวน (เบา ไม่มี geometry).
  Future<void> loadIndex() async {
    _error = null;
    _serverYears = null;
    notifyListeners();
    try {
      final index = await _service.fetchYearIndex();
      _serverYears = index.years;
      _drafts = index.drafts;
      _selected
        ..clear()
        ..addAll(displayYears.keys);
    } catch (e) {
      _error = '$e'.replaceFirst('Exception: ', '');
    }
    notifyListeners();
  }

  /// รอบสอง — กดปุ่มแล้วค่อยดาวน์โหลดขอบแปลงจริงพร้อม % bytes.
  /// คืน null เมื่อล้มเหลว (error อยู่ใน [downloadError]).
  Future<ParcelPage?> download() async {
    _downloading = true;
    _downloadError = null;
    _received = 0;
    _total = null;
    _processing = false;
    notifyListeners();
    try {
      final page = await _service.fetchParcels(
        // ส่งปีที่เลือกไปให้ backend กรองใน SQL — payload เหลือ
        // เท่าที่จะใช้จริง ไม่ต้องโหลดทุกปีมาตัดในแอป
        years: _selected,
        onProgress: (received, total) {
          _received = received;
          _total = total;
          notifyListeners();
        },
        onProcessing: () {
          _processing = true;
          notifyListeners();
        },
      );
      // สำเร็จ — ไม่ notify กลับ: ถ้าเคลียร์ flag ตอนนี้ UI จะ
      // flash กลับไปแสดงรายการปี 1 เฟรมก่อน push หน้าแผนที่
      // ค้างสถานะ "กำลังเตรียมข้อมูล" ไว้ครอบช่วง map init ด้วย
      return page;
    } catch (e) {
      _downloading = false;
      _processing = false;
      _downloadError = '$e'.replaceFirst('Exception: ', '');
      notifyListeners();
      return null;
    }
  }

  /// ออฟไลน์ fallback — ดาวน์โหลดไม่ได้ แต่เคยสำเร็จมาก่อน:
  /// ใช้ payload จาก cache ไฟล์ล่าสุดแทน
  Future<ParcelPage?> useCache() async {
    _downloading = true;
    _downloadError = null;
    // อ่าน+parse จากไฟล์ทั้งหมดใน isolate — เป็นเฟส processing ตลอด
    _processing = true;
    notifyListeners();
    try {
      final page = await _service.loadCachedParcels();
      if (page == null || page.items.isEmpty) {
        _downloading = false;
        _processing = false;
        _downloadError = 'ไม่มีข้อมูลที่บันทึกไว้';
        notifyListeners();
        return null;
      }
      // ไม่ notify — เหตุผลเดียวกับ download(): กัน flash กลับ
      // ไปหน้ารายการปี 1 เฟรมก่อนสลับไปหน้าแผนที่
      return page;
    } catch (e) {
      _downloading = false;
      _processing = false;
      _downloadError = '$e'.replaceFirst('Exception: ', '');
      notifyListeners();
      return null;
    }
  }

  void toggleYear(String? year, bool on) {
    on ? _selected.add(year) : _selected.remove(year);
    notifyListeners();
  }

  /// เลือกทั้งหมด/ยกเลิกทั้งหมดตาม [on].
  void toggleAll(bool on) {
    _selected.clear();
    if (on) _selected.addAll(displayYears.keys);
    notifyListeners();
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:brr/features/map/models/parcel.dart';

/// ชั้น local persistence ของแปลง — SharedPreferences + ไฟล์ใน
/// documents ทั้งหมด (ร่างแปลง/กิจกรรม/จุดเสี่ยง/โครงการ/ยืนยันแปลง/
/// สถานะตัด/คิว PATCH ค้างส่ง + รูปถ่ายที่ persist)
///
/// [ParcelService] delegate มาที่นี่ — service เหลือแค่ network;
/// view/VM เห็นแค่ API เดิมของ service ไม่ต้องรู้จัก store นี้
class ParcelLocalStore {
  ParcelLocalStore();

  /// SharedPreferences key holding device-only draft parcels.
  static const _draftsKey = 'draft_parcels';
  static const _activityKey = 'activity_drafts_v1';
  static const _activitySeenKey = 'activity_seen_v1';
  static const _riskKey = 'risk_points_v1';
  static const _projectKey = 'plot_projects_v1';
  static const _confirmKey = 'parcel_confirms_v1';
  static const _cutKey = 'cut_status_v1';
  static const _pendingEditKey = 'pending_plot_edits_v1';
  static const _failedEditKey = 'failed_plot_edits_v1';

  /// ไฟล์ cache payload ดาวน์โหลดล่าสุด — fallback ตอนเน็ตล่ม.
  static const _cacheName = 'parcels_cache.json';

  /// คิวเขียน prefs ทีละงานตามลำดับ — กัน load→แก้→save 2 งาน
  /// แข่งกันแล้วตัวหลังทับตัวแรกหาย (เช่น flushPendingEdits อัตโนมัติ
  /// ชนกับ queuePendingEdit ที่เขียนจาก PATCH ล้มพร้อมกัน)
  /// static เพราะ store ถูกสร้างหลาย instance ตาม service —
  /// คิวต้องแชร์ทั้งแอปไม่งั้น serialize ไม่ได้ผล
  static Future<void> _writeQueue = Future.value();

  static Future<T> _serialized<T>(Future<T> Function() op) {
    final run = _writeQueue.then((_) => op());
    _writeQueue = run.then((_) {}, onError: (_) {});
    return run;
  }

  // ---- ไฟล์ cache payload ดาวน์โหลด (เขียน/อ่านอย่างเดียว —
  // parse + merge ร่างเป็นหน้าที่ของ service) ----

  Future<File> _cacheFile() async =>
      File('${(await getApplicationDocumentsDirectory()).path}/$_cacheName');

  /// body ดิบของ /plots/map ครั้งล่าสุด — null ถ้าไม่เคยดาวน์โหลด
  Future<String?> readParcelCache() async {
    try {
      final f = await _cacheFile();
      if (!await f.exists()) return null;
      return await f.readAsString();
    } catch (_) {
      return null;
    }
  }

  Future<void> writeParcelCache(String body) async {
    try {
      final f = await _cacheFile();
      // เขียน tmp แล้ว rename — writeAsString ตรงๆ เสี่ยงไฟล์ค้าง
      // ครึ่งเดียวตอนแอปดับ/เขียนซ้อน → cache ออฟไลน์พังทั้งไฟล์
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(body, flush: true);
      await tmp.rename(f.path);
    } catch (_) {}
  }

  // ---- รูปถ่าย — image_picker คืนไฟล์ใน temp cache ที่ระบบล้าง ----
  // ได้ทุกเมื่อ; draft/activity เก็บแค่ path เลยต้องย้ายมา documents

  static int _photoSeq = 0;
  static int _actSeq = 0;

  Future<Directory> _photosDir() async =>
      Directory('${(await getApplicationDocumentsDirectory()).path}/photos');

  /// คัดลอกรูปไปเก็บถาวรใน documents — คืน path ใหม่ (path เดิมถ้า
  /// copy ไม่ได้ ดีกว่าทิ้งรูป; path ที่ persist แล้วคืนตัวเดิม)
  /// ล้มเหลวจะ log เตือน — temp path อาจโดน OS ล้าง รูปหายเงียบ
  /// ไม่ควรเกิดขึ้นเงียบๆ โดยไม่มีร่องรอย
  Future<String> persistPhoto(String path) async {
    try {
      final dir = await _photosDir();
      if (path.startsWith('${dir.path}/')) return path;
      final src = File(path);
      if (!await src.exists()) {
        debugPrint('persistPhoto: ไฟล์ต้นทางไม่มีอยู่แล้ว $path');
        return path;
      }
      if (!await dir.exists()) await dir.create(recursive: true);
      final i = path.lastIndexOf('.');
      final ext = i < 0 ? '.jpg' : path.substring(i);
      final name =
          'p_${DateTime.now().microsecondsSinceEpoch}_${_photoSeq++}$ext';
      return (await src.copy('${dir.path}/$name')).path;
    } catch (e) {
      debugPrint('persistPhoto: copy ล้มเหลว $path ($e)');
      return path;
    }
  }

  /// ลบรูปที่ persist ไว้ — ลบเฉพาะไฟล์ใต้ photos/ เท่านั้น กัน
  /// เผลอลบไฟล์อื่นของผู้ใช้
  Future<void> deletePersistedPhoto(String path) async {
    try {
      final dir = await _photosDir();
      if (path.startsWith('${dir.path}/')) {
        final f = File(path);
        if (await f.exists()) await f.delete();
      }
    } catch (_) {}
  }

  /// path รูปทั้งหมดที่ records ยังอ้างอยู่ — persistPhoto คืน path
  /// เดิมให้ไฟล์ที่ persist แล้ว ทำให้ไฟล์เดียวถูกแชร์ข้ามร่างแปลง/
  /// กิจกรรม/ยืนยันแปลงได้ ลบไฟล์ที่ยังถูกอ้าง = รูปหน้าอื่นพังเงียบ
  /// ใช้เช็กก่อนลบทุกครั้ง (เรียกหลัง record ถูกเขียน/ลบแล้ว)
  Future<Set<String>> _referencedPhotos() async {
    final refs = <String>{};
    void collect(Object? v) {
      if (v is List) {
        for (final p in v) {
          refs.add('$p');
        }
      }
    }

    for (final d in await loadDrafts()) {
      collect(d.meta?['photos']);
    }
    for (final a in await _loadActivities()) {
      collect(a['photos']);
    }
    for (final c in await _loadParcelConfirms()) {
      collect(c['photos']);
    }
    return refs;
  }

  /// ลบเฉพาะไฟล์ที่ไม่มี record ไหนอ้างแล้ว — แชร์ไฟล์ข้ามชนิด
  /// record ได้ ลบเฉพาะ orphan จริงๆ เท่านั้น
  Future<void> _deleteUnreferenced(Iterable<Object?> paths) async {
    final refs = await _referencedPhotos();
    for (final p in paths) {
      final s = '$p';
      if (!refs.contains(s)) {
        try {
          await deletePersistedPhoto(s);
        } catch (_) {}
      }
    }
  }

  /// decode JSON list ทีละ entry — item เสียตัวเดียว (field ผิดชนิด/
  /// เวอร์ชันเก่า/เขียนค้าง) ข้ามไป ไม่ลากทั้งชุดให้หายหมด
  static List<Map<String, dynamic>> _decodeMapList(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    final out = <Map<String, dynamic>>[];
    for (final j in decoded) {
      if (j is Map) {
        try {
          out.add(Map<String, dynamic>.from(j));
        } catch (_) {}
      }
    }
    return out;
  }

  // ---- ร่างแปลง ----

  Future<List<Parcel>> loadDrafts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_draftsKey);
    if (raw == null) return [];
    final List decoded;
    try {
      decoded = jsonDecode(raw) as List;
    } catch (_) {
      return [];
    }
    // parse ต่อ entry — ร่างเสียตัวเดียวไม่ให้ร่างดีตัวอื่นหายไปด้วย
    final out = <Parcel>[];
    for (final j in decoded) {
      if (j is! Map) continue;
      try {
        out.add(Parcel.fromJson(Map<String, dynamic>.from(j)));
      } catch (_) {}
    }
    return out;
  }

  Future<void> saveDraft(Parcel p) => _serialized(() async {
    final prefs = await SharedPreferences.getInstance();
    final drafts = await loadDrafts();
    drafts.add(p);
    await prefs.setString(
      _draftsKey,
      jsonEncode([for (final d in drafts) d.toJson()]),
    );
  });

  /// ยืนยันร่างสำเร็จ — ไม่ลบ แต่ stamp `status = 'confirmed'` +
  /// `confirmedAt` ไว้ให้หน้าฉบับร่างกรอง + prune ตามอายุได้
  Future<void> markDraftConfirmed(String id) => _serialized(() async {
    final prefs = await SharedPreferences.getInstance();
    final drafts = await loadDrafts();
    final i = drafts.indexWhere((d) => d.id == id);
    if (i < 0) return;
    final d = drafts[i];
    drafts[i] = Parcel(
      id: d.id,
      name: d.name,
      variety: d.variety,
      owner: d.owner,
      productionYear: d.productionYear,
      meta: {...?d.meta, 'confirmedAt': DateTime.now().toIso8601String()},
      status: 'confirmed',
      points: d.points,
      isDraft: d.isDraft,
      savedAt: d.savedAt,
      centerOverride: d.centerOverride,
    );
    await prefs.setString(
      _draftsKey,
      jsonEncode([for (final d in drafts) d.toJson()]),
    );
  });

  /// รหัสที่ใช้ยิง POST จริงของร่างนี้ — จำไว้ในเครื่อง เพื่อกดยืนยันซ้ำแล้วไม่สร้างแปลงใบที่สอง
  /// [newId] = รหัสที่ caller gen มาให้ (store gen เองไม่ได้เพราะ
  /// newPlotId อยู่ชั้น service) — ถ้า meta มี clientId อยู่แล้ว
  /// คืนของเดิม ไม่เขียนทับ
  Future<String> ensureClientId(Parcel draft, String newId) =>
      _serialized(() async {
        final raw = draft.meta?['clientId'];
        if (raw is String && raw.isNotEmpty) return raw;
        final prefs = await SharedPreferences.getInstance();
        final drafts = await loadDrafts();
        final i = drafts.indexWhere((d) => d.id == draft.id);
        if (i < 0) return newId;
        final d = drafts[i];
        // ระหว่างรอ queue อาจมีใคร stamp ไปแล้ว — เช็คซ้ำก่อนเขียน
        final existing = d.meta?['clientId'];
        if (existing is String && existing.isNotEmpty) return existing;
        drafts[i] = Parcel(
          id: d.id,
          name: d.name,
          variety: d.variety,
          owner: d.owner,
          productionYear: d.productionYear,
          meta: {...?d.meta, 'clientId': newId},
          status: d.status,
          points: d.points,
          isDraft: d.isDraft,
          savedAt: d.savedAt,
          centerOverride: d.centerOverride,
        );
        await prefs.setString(
          _draftsKey,
          jsonEncode([for (final item in drafts) item.toJson()]),
        );
        return newId;
      });

  /// ร่างที่ยืนยันแล้วเก็บไว้เป็นหลักฐานแค่ช่วงหนึ่ง — ข้อมูลจริง
  /// อยู่บน server แล้ว ปล่อยสะสมถาวรจะทำ prefs/หน้ารายการโต
  /// เกินจำเป็น (ปีการผลิตนึงอาจหลายร้อยแปลง)
  static const confirmedDraftMaxAge = Duration(days: 30);

  /// เวลา prune ล่าสุด — throttle กันทุก viewport refetch เรียก
  /// load+decode ร่างทั้งชุดซ้ำ (service เรียกทุก _drafts())
  static DateTime? _lastPrune;

  /// ตัดร่าง confirmed ที่เกิน [maxAge] ทิ้ง — ร่างเก่าก่อนมี
  /// `confirmedAt` ใช้ `savedAt` แทน; ไม่มีเวลาเลย = ยืนยันมานาน
  /// แล้วแน่ๆ ตัดออกได้เลย (ข้อมูลบน server ปลอดภัย)
  /// คืนจำนวนที่ตัด — รูปที่ไม่มีใครอ้างถูกลบตาม
  Future<int> pruneConfirmedDrafts({Duration maxAge = confirmedDraftMaxAge}) {
    final now = DateTime.now();
    final last = _lastPrune;
    if (last != null && now.difference(last) < const Duration(minutes: 5)) {
      return Future.value(0);
    }
    _lastPrune = now;
    return _serialized(() async {
      final prefs = await SharedPreferences.getInstance();
      final drafts = await loadDrafts();
      final cutoff = DateTime.now().subtract(maxAge);
      final removed = <Parcel>[];
      drafts.removeWhere((d) {
        if (d.status != 'confirmed') return false;
        final stamp =
            DateTime.tryParse('${d.meta?['confirmedAt'] ?? ''}') ?? d.savedAt;
        final prune = stamp == null || stamp.isBefore(cutoff);
        if (prune) removed.add(d);
        return prune;
      });
      if (removed.isEmpty) return 0;
      await prefs.setString(
        _draftsKey,
        jsonEncode([for (final d in drafts) d.toJson()]),
      );
      await _deleteUnreferenced(
        removed.expand((d) {
          final ph = d.meta?['photos'];
          return ph is List ? ph : const [];
        }),
      );
      return removed.length;
    });
  }

  Future<void> removeDraft(String id) => _serialized(() async {
    final prefs = await SharedPreferences.getInstance();
    final drafts = await loadDrafts();
    final removed = drafts.where((d) => d.id == id).toList();
    drafts.removeWhere((d) => d.id == id);
    await prefs.setString(
      _draftsKey,
      jsonEncode([for (final d in drafts) d.toJson()]),
    );
    // ลบ record ไปแล้ว — ไฟล์รูปลบพลาด (ไฟล์หาย/path เสีย)
    // ไม่ให้ op ทั้งตัวรายงาน fail ทั้งที่ลบ entry สำเร็จ
    // ไฟล์ที่ record อื่นยังอ้าง (ร่างใหม่/กิจกรรม) ไม่ถูกลบ
    await _deleteUnreferenced(
      removed.expand((d) {
        final ph = d.meta?['photos'];
        return ph is List ? ph : const [];
      }),
    );
  });

  // ---- กิจกรรมแปลง — บันทึกลงเครื่องก่อน รอ endpoint นำส่ง backend ----

  Future<List<Map<String, dynamic>>> _loadActivities() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_activityKey);
    if (raw == null) return [];
    try {
      return _decodeMapList(raw);
    } catch (_) {
      return [];
    }
  }

  /// บันทึกกิจกรรมลงเครื่อง — `detailPending` = บันทึกเฉพาะรูปไว้ก่อน
  /// รอกรอกรายละเอียด ("นำส่งกิจกรรมในเครื่อง" จะหยิบ list นี้ต่อ)
  Future<void> saveActivityDraft({
    required String plotId,
    required List<String> photoPaths,
    bool detailPending = false,
    String? plantedAt,
    String? caneGroup,
    String? herbicideUsed,
    String? fertilizerRate,
    String? npkN,
    String? npkP,
    String? npkK,
    bool? mpiApplied,
    List<Map<String, dynamic>>? fertilizerRounds,
    String? organicFertilizerType,
    String? organicRate,
    String? organicDate,
    String? dolomiteRate,
    String? dolomiteDate,
    bool? weedPresent,
    bool? subsoiled,
    String? subsoilDepth,
    bool? diseasePresent,
    String? diseaseType,
    String? diseaseSpread,
    bool? diseaseManaged,
    bool? pestPresent,
    String? pestType,
    String? pestSpread,
    String? pestDamage,
    bool? pestManaged,
    bool? hilled,
    String? germinationPercent,
    String? harvestGroupFarmerId,
    String? harvestGroupFarmer,
    String? lossReason,
    String? lossAreaRai,
    String? yieldEstimate,
    String? totalTons,
    String? cutVarietyDeduction,
    String? cutLossKgPerRai,
    String? cutLossTons,
    String? cutLossReason,
    String? actualHarvestTons,
    bool? seedCane,
    String? seedCaneNote,
    String? suggestion,
    // แก้ไขร่างเดิม — ส่ง id ของรายการเดิมมา จะเขียนทับแทนเพิ่มใหม่
    // (เก็บ id/createdAt/submitStatus เดิมไว้)
    String? activityId,
    // ผู้บันทึก (แสดงในหน้าประวัติ) — มาจาก profile ผู้ใช้ที่ล็อกอิน
    String? recordedBy,
    String? recordedByRole,
  }) => _serialized(() async {
    final prefs = await SharedPreferences.getInstance();
    final items = await _loadActivities();
    final entry = <String, dynamic>{
      // microseconds + counter — 2 รายการใน ms เดียวกัน (double-tap
      // เครื่องช้า) id ชนกัน → indexWhere เจอตัวแรกตลอด ลบ/ส่งผิดตัว
      'id':
          activityId ??
          'act-${DateTime.now().microsecondsSinceEpoch}-${_actSeq++}',
      'plotId': plotId,
      'photos': [for (final p in photoPaths) await persistPhoto(p)],
      'detailPending': detailPending,
      'plantedAt': ?plantedAt,
      'caneGroup': ?caneGroup,
      'herbicideUsed': ?herbicideUsed,
      'fertilizerRate': ?fertilizerRate,
      'npkN': ?npkN,
      'npkP': ?npkP,
      'npkK': ?npkK,
      'mpiApplied': ?mpiApplied,
      'fertilizerRounds': ?fertilizerRounds,
      'organicFertilizerType': ?organicFertilizerType,
      'organicRate': ?organicRate,
      'organicDate': ?organicDate,
      'dolomiteRate': ?dolomiteRate,
      'dolomiteDate': ?dolomiteDate,
      'weedPresent': ?weedPresent,
      'subsoiled': ?subsoiled,
      'subsoilDepth': ?subsoilDepth,
      'diseasePresent': ?diseasePresent,
      'diseaseType': ?diseaseType,
      'diseaseSpread': ?diseaseSpread,
      'diseaseManaged': ?diseaseManaged,
      'pestPresent': ?pestPresent,
      'pestType': ?pestType,
      'pestSpread': ?pestSpread,
      'pestDamage': ?pestDamage,
      'pestManaged': ?pestManaged,
      'hilled': ?hilled,
      'germinationPercent': ?germinationPercent,
      'harvestGroupFarmerId': ?harvestGroupFarmerId,
      'harvestGroupFarmer': ?harvestGroupFarmer,
      'lossReason': ?lossReason,
      'lossAreaRai': ?lossAreaRai,
      'yieldEstimate': ?yieldEstimate,
      'totalTons': ?totalTons,
      'cutVarietyDeduction': ?cutVarietyDeduction,
      'cutLossKgPerRai': ?cutLossKgPerRai,
      'cutLossTons': ?cutLossTons,
      'cutLossReason': ?cutLossReason,
      'actualHarvestTons': ?actualHarvestTons,
      'seedCane': ?seedCane,
      'seedCaneNote': ?seedCaneNote,
      'suggestion': ?suggestion,
      'recordedBy': ?recordedBy,
      'recordedByRole': ?recordedByRole,
    };
    // อัปเดตรายการเดิม — คงเวลาบันทึกแรก + สถานะการส่งไว้
    if (activityId != null) {
      final i = items.indexWhere((a) => a['id'] == activityId);
      if (i >= 0) {
        entry['createdAt'] = items[i]['createdAt'];
        entry['submitStatus'] = items[i]['submitStatus'] ?? 'pending';
        // ผู้บันทึกเดิม — ถ้า call นี้ไม่ได้ส่งมาให้คงค่าเดิมไว้
        entry['recordedBy'] ??= items[i]['recordedBy'];
        entry['recordedByRole'] ??= items[i]['recordedByRole'];
        // รูป persist เก่าที่ถูกแทนด้วยรูปชุดใหม่ — ลบไฟล์ทิ้ง
        // ไม่งั้นทุกครั้งที่แก้ร่างไฟล์รูปเก่าค้างดิสก์เรื่อยๆ
        // (รูปที่ยังอยู่จะถูกส่งกลับมาแล้ว persist คืน path เดิม
        // → อยู่ใน list ใหม่ ไม่ถูกลบ)
        final rawOld = items[i]['photos'];
        final oldPhotos = rawOld is List ? rawOld : const [];
        final rawNew = entry['photos'];
        final newPhotos = rawNew is List ? rawNew : const [];
        items[i] = entry;
        await prefs.setString(_activityKey, jsonEncode(items));
        await _deleteUnreferenced(
          oldPhotos.where((p) => !newPhotos.contains(p)),
        );
        return;
      }
    }
    entry['submitStatus'] = 'pending';
    entry['createdAt'] = DateTime.now().toIso8601String();
    items.add(entry);
    await prefs.setString(_activityKey, jsonEncode(items));
  });

  /// จำนวนกิจกรรมในเครื่องของแปลง — ใช้ตั้งชื่อ "ครั้งที่ N"
  Future<int> activityDraftCount(String plotId) async =>
      (await _loadActivities()).where((a) => a['plotId'] == plotId).length;

  /// กิจกรรมที่บันทึกไว้ในเครื่องของแปลง — ใหม่สุดขึ้นก่อน
  /// (หน้า "นำส่งกิจกรรมที่บันทึกไว้ในเครื่อง" แสดง list นี้)
  Future<List<Map<String, dynamic>>> activitiesFor(String plotId) async {
    final items = (await _loadActivities())
        .where((a) => a['plotId'] == plotId)
        .toList();
    items.sort((a, b) => '${b['createdAt']}'.compareTo('${a['createdAt']}'));
    return items;
  }

  // ---- badge "กิจกรรมใหม่" — จำจำนวนที่เคยเปิดดูแล้วต่อแปลง ----

  /// {plotId: [id กิจกรรมที่ดูแล้ว]} — ค่า int เก่า (จำนวน) ยังอ่านได้
  /// โดยนับ id ตัวท้าย N ตัวเป็นดูแล้ว (ค่าเก่าแปลว่าดูแล้ว N รายการ
  /// แรกตอนที่ยังนับเป็นจำนวน — รายการเรียงใหม่สุดก่อน เลย take จากท้าย)
  Future<Map<String, List<String>>> _loadActivitySeen(
    String plotId,
    List<Map<String, dynamic>> acts,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_activitySeenKey);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw) as Map;
      return {
        for (final e in decoded.entries)
          e.key: e.value is List
              ? [for (final v in e.value as List) '$v']
              : e.value is num
              ? [
                  // legacy: จำนวนที่ดูแล้ว — acts เรียงใหม่สุดก่อน
                  // แต่ค่าเก่าบันทึกตอน append ท้าย = ที่ดูคือ N ตัว
                  // "เก่าสุด" เลยต้อง take จากท้าย list ไม่ใช่หัว
                  if (e.key == plotId)
                    for (final a in acts.reversed.take(
                      (e.value as num).toInt(),
                    ))
                      '${a['id']}',
                ]
              : const <String>[],
      };
    } catch (_) {
      return {};
    }
  }

  /// จำนวนกิจกรรมใหม่ที่ยังไม่เคยเปิดดู — ใช้เป็น badge บนปุ่มเมนู
  Future<int> unseenActivityCount(String plotId) async {
    final acts = await activitiesFor(plotId);
    final seen = (await _loadActivitySeen(plotId, acts))[plotId] ?? const [];
    return acts.where((a) => !seen.contains('${a['id']}')).length;
  }

  /// ทำเครื่องหมายว่าดูกิจกรรมของแปลงครบแล้ว — badge หาย
  Future<void> markActivitiesSeen(String plotId) => _serialized(() async {
    final acts = await activitiesFor(plotId);
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_activitySeenKey);
    // prefs เสีย → ถือว่าไม่เคยดู แทนที่จะ throw ทำหน้าประวัติเปิดไม่ได้
    Map<dynamic, dynamic> decoded = const {};
    if (raw != null) {
      try {
        decoded = jsonDecode(raw) as Map;
      } catch (_) {}
    }
    final seen = <String, dynamic>{
      for (final e in decoded.entries) e.key: e.value,
    };
    seen[plotId] = [for (final a in acts) '${a['id']}'];
    await prefs.setString(_activitySeenKey, jsonEncode(seen));
  });

  /// ล้างสถานะ "ดูแล้ว" ทั้งหมด — เรียกตอน logout เพราะเป็นข้อมูล
  /// ตามผู้ใช้ (อีกคน login เครื่องเดียวกันไม่ควรเห็น badge ตามของเก่า)
  /// ร่าง/คิวส่งไม่แตะ — งานค้างของผู้ใช้ต้องอยู่ครบ
  static Future<void> clearActivitySeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_activitySeenKey);
  }

  /// ลบกิจกรรมในเครื่อง + ลบรูปที่ persist ไว้ตามรายการด้วย
  /// กันไฟล์รกค้างในเครื่อง
  Future<void> removeActivityDraft(String id) => _serialized(() async {
    final prefs = await SharedPreferences.getInstance();
    final items = await _loadActivities();
    final removed = items.where((a) => a['id'] == id).toList();
    items.removeWhere((a) => a['id'] == id);
    await prefs.setString(_activityKey, jsonEncode(items));
    for (final a in removed) {
      final ph = a['photos'];
      await _deleteUnreferenced(ph is List ? ph : const []);
    }
  });

  /// อัปเดต submitStatus ของกิจกรรม (pending/failed/sent) —
  /// หน้านำส่งใช้แยก tab ตามสถานะนี้
  Future<void> setActivitySubmitStatus(String id, String status) =>
      _serialized(() async {
        final prefs = await SharedPreferences.getInstance();
        final items = await _loadActivities();
        final i = items.indexWhere((a) => a['id'] == id);
        if (i < 0) return;
        items[i] = {...items[i], 'submitStatus': status};
        await prefs.setString(_activityKey, jsonEncode(items));
      });

  // ---- จุดเสี่ยงภัยพิบัติ — เก็บลงเครื่องก่อน รอ endpoint backend ----

  Future<List<Map<String, dynamic>>> loadRiskPoints() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_riskKey);
    if (raw == null) return [];
    try {
      return _decodeMapList(raw);
    } catch (_) {
      return [];
    }
  }

  /// จุดเสี่ยงล่าสุดของแปลง (เก็บทับรายการเดิมต่อ plotId)
  Future<Map<String, dynamic>?> riskPointFor(String plotId) async {
    for (final r in await loadRiskPoints()) {
      if (r['plotId'] == plotId) return r;
    }
    return null;
  }

  /// บันทึก/อัปเดตจุดเสี่ยงของแปลง — type จาก backend riskLevels,
  /// severity 1-5, name/note พิมพ์เอง
  Future<void> saveRiskPoint({
    required String plotId,
    required String type,
    String? name,
    int? severity,
    String? note,
  }) => _serialized(() async {
    final prefs = await SharedPreferences.getInstance();
    final items = await loadRiskPoints();
    items.removeWhere((r) => r['plotId'] == plotId);
    items.add({
      'plotId': plotId,
      'type': type,
      'name': ?name,
      'severity': ?severity,
      'note': ?note,
      'updatedAt': DateTime.now().toIso8601String(),
    });
    await prefs.setString(_riskKey, jsonEncode(items));
  });

  /// โหลด→แก้→บันทึกจุดเสี่ยงภายใต้ write queue เดียว —
  /// downloadRiskPoints merge ผ่านนี้ ไม่งั้น list ที่โหลดก่อน
  /// ผู้ใช้บันทึกจุดใหม่จะทับจุดนั้นหาย (load/save คนละขั้นกัน)
  Future<T> updateRiskPoints<T>(
    Future<T> Function(List<Map<String, dynamic>> items) transform,
  ) => _serialized(() async {
    final prefs = await SharedPreferences.getInstance();
    final items = await loadRiskPoints();
    final result = await transform(items);
    await prefs.setString(_riskKey, jsonEncode(items));
    return result;
  });

  // ---- โครงการส่งเสริมแปลง (นสล.) — เก็บลงเครื่องก่อน รอ endpoint ----

  Future<List<Map<String, dynamic>>> _loadPlotProjects() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_projectKey);
    if (raw == null) return [];
    try {
      return _decodeMapList(raw);
    } catch (_) {
      return [];
    }
  }

  /// โครงการที่เลือกไว้ของแปลง — {items: [ชื่อ], passed: bool}
  Future<Map<String, dynamic>?> plotProjectFor(String plotId) async {
    for (final r in await _loadPlotProjects()) {
      if (r['plotId'] == plotId) return r;
    }
    return null;
  }

  /// บันทึกรายการโครงการที่ติ๊ก — passed = ครบเกณฑ์บังคับแล้ว
  /// choices = ตัวเลือกย่อยต่อเกณฑ์ {ชื่อเกณฑ์: ชนิด} (เช่น ชนิดปุ๋ยอินทรีย์)
  Future<void> savePlotProject({
    required String plotId,
    required List<String> items,
    Map<String, String> choices = const {},
    required bool passed,
  }) => _serialized(() async {
    final prefs = await SharedPreferences.getInstance();
    final rows = await _loadPlotProjects();
    rows.removeWhere((r) => r['plotId'] == plotId);
    rows.add({
      'plotId': plotId,
      'items': items,
      'choices': choices,
      'passed': passed,
      'updatedAt': DateTime.now().toIso8601String(),
    });
    await prefs.setString(_projectKey, jsonEncode(rows));
  });

  // ---- ยืนยันแปลงข้ามปี — เก็บลงเครื่องก่อน รอ endpoint นำส่ง ----

  Future<List<Map<String, dynamic>>> _loadParcelConfirms() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_confirmKey);
    if (raw == null) return [];
    try {
      return _decodeMapList(raw);
    } catch (_) {
      return [];
    }
  }

  /// การยืนยันข้ามปีล่าสุดของแปลง (เก็บทับรายการเดิมต่อ plotId)
  Future<Map<String, dynamic>?> parcelConfirmFor(String plotId) async {
    for (final r in await _loadParcelConfirms()) {
      if (r['plotId'] == plotId) return r;
    }
    return null;
  }

  /// บันทึกยืนยันแปลงข้ามปี — รูป copy เข้า documents เหมือน
  /// รูปกิจกรรม/รูปแปลง กัน temp cache ถูกระบบล้าง
  Future<void> saveParcelConfirm({
    required String plotId,
    String? targetYear,
    String? status,
    String? note,
    List<String> photoPaths = const [],
    String? recordedBy,
  }) => _serialized(() async {
    final prefs = await SharedPreferences.getInstance();
    final rows = await _loadParcelConfirms();
    // เก็บรูป persist ของแถวเดิมไว้ลบทีหลัง — เขียนทับแล้ว
    // รูปเก่าที่ไม่ได้ใช้ต่อจะค้างดิสก์
    final oldPhotos = [
      for (final r in rows.where((r) => r['plotId'] == plotId))
        for (final p in r['photos'] is List ? r['photos'] as List : const [])
          '$p',
    ];
    final newPhotos = [for (final p in photoPaths) await persistPhoto(p)];
    rows.removeWhere((r) => r['plotId'] == plotId);
    rows.add({
      'plotId': plotId,
      'targetYear': ?targetYear,
      'status': ?status,
      'note': ?note,
      'photos': newPhotos,
      'recordedBy': ?recordedBy,
      'updatedAt': DateTime.now().toIso8601String(),
    });
    await prefs.setString(_confirmKey, jsonEncode(rows));
    await _deleteUnreferenced(oldPhotos.where((p) => !newPhotos.contains(p)));
  });

  // ---- สถานะแปลงตัด — เก็บลงเครื่องก่อน รอ endpoint backend ----

  Future<List<Map<String, dynamic>>> _loadCutStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cutKey);
    if (raw == null) return [];
    try {
      return _decodeMapList(raw);
    } catch (_) {
      return [];
    }
  }

  /// สถานะตัดล่าสุดของแปลง — {status, startDate, endDate,
  /// estimateTons, cutCaneTons, updatedAt}
  Future<Map<String, dynamic>?> cutStatusFor(String plotId) async {
    for (final r in await _loadCutStatus()) {
      if (r['plotId'] == plotId) return r;
    }
    return null;
  }

  /// บันทึก/อัปเดตสถานะแปลงตัด — status = ชื่อตัวเลือกที่แสดง,
  /// statusCode = รหัสสถานะจาก backend (กัน label เปลี่ยน)
  Future<void> saveCutStatus({
    required String plotId,
    required String status,
    String? statusCode,
    String? startDate,
    String? endDate,
    String? estimateTons,
    String? cutCaneTons,
  }) => _serialized(() async {
    final prefs = await SharedPreferences.getInstance();
    final rows = await _loadCutStatus();
    rows.removeWhere((r) => r['plotId'] == plotId);
    rows.add({
      'plotId': plotId,
      'status': status,
      'statusCode': ?statusCode,
      'startDate': ?startDate,
      'endDate': ?endDate,
      'estimateTons': ?estimateTons,
      'cutCaneTons': ?cutCaneTons,
      'updatedAt': DateTime.now().toIso8601String(),
    });
    await prefs.setString(_cutKey, jsonEncode(rows));
  });

  // ---- คิว PATCH ที่ค้างเพราะออฟไลน์ — retry เมื่อเน็ตกลับ ----

  Future<List<Map<String, dynamic>>> loadPendingEdits() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pendingEditKey);
    if (raw == null) return [];
    try {
      return _decodeMapList(raw);
    } catch (_) {
      return [];
    }
  }

  /// โหลด→แก้→บันทึกคิว pending ภายใต้ write queue เดียว —
  /// service ใช้ทั้ง queue (เพิ่ม/merge) และ flush (ส่งแล้วตัดออก)
  Future<T> updatePendingEdits<T>(
    Future<T> Function(List<Map<String, dynamic>> items) transform,
  ) => _serialized(() async {
    final prefs = await SharedPreferences.getInstance();
    final items = await loadPendingEdits();
    final result = await transform(items);
    await prefs.setString(_pendingEditKey, jsonEncode(items));
    return result;
  });

  // ---- การแก้ไขที่ server ปฏิเสธตอน flush — เก็บไว้แจ้งผู้ใช้
  // ภายหลัง แทนที่จะทิ้งเงียบ (ข้อมูลที่ผู้ใช้ตั้งใจแก้ห้ามหาย
  // โดยไม่มีหลักฐาน) ----

  static const _maxFailedEdits = 50;

  /// รายการแก้ไขที่ flush แล้ว server ปฏิเสธ (เช่น 409 ซ้ำ /
  /// 410 ถูกลบ) — เก็บ plotId+body+สาเหตุ ให้ UI/ซัพพอร์ตดูย้อนได้
  Future<List<Map<String, dynamic>>> loadFailedEdits() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_failedEditKey);
    if (raw == null) return [];
    try {
      return _decodeMapList(raw);
    } catch (_) {
      return [];
    }
  }

  /// เก็บ entry ที่ถูกปฏิเสธ — จำกัด [_maxFailedEdits] รายการ
  /// ล่าสุด กัน prefs โตไม่รู้จบ
  Future<void> recordFailedEdit(Map<String, dynamic> entry) =>
      _serialized(() async {
        final prefs = await SharedPreferences.getInstance();
        final items = await loadFailedEdits()
          ..add({...entry, 'failedAt': DateTime.now().toIso8601String()});
        while (items.length > _maxFailedEdits) {
          items.removeAt(0);
        }
        await prefs.setString(_failedEditKey, jsonEncode(items));
      });

  /// ล้างรายการที่ปฏิเสธ — เรียกหลังผู้ใช้รับทราบ/แก้ไขแล้ว
  Future<void> clearFailedEdits() => _serialized(() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_failedEditKey);
  });

  /// โหลด→แก้→บันทึก failed list ภายใต้ write queue เดียว —
  /// retry/discard ต่อ entry ต้อง serialized ไม่งั้นสองจอ
  /// ที่เปิดพร้อมกันเขียนทับกัน
  Future<T> updateFailedEdits<T>(
    Future<T> Function(List<Map<String, dynamic>> items) transform,
  ) => _serialized(() async {
    final prefs = await SharedPreferences.getInstance();
    final items = await loadFailedEdits();
    final result = await transform(items);
    await prefs.setString(_failedEditKey, jsonEncode(items));
    return result;
  });
}

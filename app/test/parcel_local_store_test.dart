import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:brr/features/map/data/parcel_local_store.dart';
import 'package:brr/features/map/models/parcel.dart';

Parcel draft(
  String id, {
  String? status,
  DateTime? savedAt,
  Map<String, dynamic>? meta,
}) => Parcel(
  id: id,
  name: 'แปลง$id',
  isDraft: true,
  status: status,
  savedAt: savedAt,
  meta: meta,
  points: const [
    LatLng(14.0, 100.0),
    LatLng(14.001, 100.0),
    LatLng(14.001, 100.001),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late ParcelLocalStore store;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('brr_store_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
    SharedPreferences.setMockInitialValues({});
    store = ParcelLocalStore();
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('activity id', () {
    test('บันทึก 2 ครั้งติดกันได้ id ไม่ซ้ำ', () async {
      await store.saveActivityDraft(plotId: 'p1', photoPaths: const []);
      await store.saveActivityDraft(plotId: 'p1', photoPaths: const []);
      final acts = await store.activitiesFor('p1');
      expect(acts.length, 2);
      expect(acts[0]['id'], isNot(acts[1]['id']));
    });
  });

  group('pruneConfirmedDrafts', () {
    test('ตัดเฉพาะ confirmed เกินอายุ ไม่แตะร่างปกติ', () async {
      final prefs = await SharedPreferences.getInstance();
      final old = DateTime.now().subtract(const Duration(days: 45));
      final fresh = DateTime.now().subtract(const Duration(days: 5));
      await prefs.setString(
        'draft_parcels',
        jsonEncode([
          draft(
            'old-confirmed',
            status: 'confirmed',
            meta: {'confirmedAt': old.toIso8601String()},
          ).toJson(),
          // ร่างเก่าก่อนมี confirmedAt — fallback ไป savedAt
          draft('legacy-confirmed', status: 'confirmed', savedAt: old).toJson(),
          draft(
            'fresh-confirmed',
            status: 'confirmed',
            meta: {'confirmedAt': fresh.toIso8601String()},
          ).toJson(),
          // ไม่มี timestamp เลย = ยืนยันนานแล้ว ตัดได้
          draft('timeless-confirmed', status: 'confirmed').toJson(),
          draft('old-draft', savedAt: old).toJson(),
        ]),
      );

      final removed = await store.pruneConfirmedDrafts();
      expect(removed, 3);

      final remaining = {for (final d in await store.loadDrafts()) d.id};
      expect(remaining, containsAll(['fresh-confirmed', 'old-draft']));
      for (final gone in [
        'old-confirmed',
        'legacy-confirmed',
        'timeless-confirmed',
      ]) {
        expect(remaining, isNot(contains(gone)));
      }
    });
  });

  group('shared photo orphan check', () {
    test('removeDraft ไม่ลบรูปที่ร่างอื่นยังอ้างอยู่', () async {
      final photos = Directory('${tempDir.path}/photos')..createSync();
      final f = File('${photos.path}/shared.jpg')
        ..writeAsBytesSync(const [1, 2, 3]);
      final meta = {
        'photos': [f.path],
      };
      await store.saveDraft(draft('a', meta: meta));
      await store.saveDraft(draft('b', meta: meta));

      await store.removeDraft('a');
      expect(await f.exists(), isTrue, reason: 'ร่าง b ยังอ้างไฟล์อยู่');

      await store.removeDraft('b');
      expect(await f.exists(), isFalse);
    });
  });

  group('updateRiskPoints', () {
    test('merge ผ่าน serialized queue รักษาจุดที่ผู้ใช้บันทึก', () async {
      await store.saveRiskPoint(plotId: 'p1', type: 'flood', severity: 4);
      await store.updateRiskPoints<void>((items) async {
        items.add({'plotId': 'p2', 'type': 'drought'});
      });
      final ids = {for (final r in await store.loadRiskPoints()) r['plotId']};
      expect(ids, containsAll(['p1', 'p2']));
    });
  });

  group('loadDrafts', () {
    test('prefs เสีย → คืน list ว่าง ไม่ throw', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('draft_parcels', '{broken json');
      expect(await store.loadDrafts(), isEmpty);
    });

    test('item เสียตัวเดียวไม่ลากทั้งชุด', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'draft_parcels',
        jsonEncode([
          'not-a-map',
          draft('good').toJson(),
          {'id': 1}, // ไม่มี points → parse พัง ข้ามไป
        ]),
      );
      final ids = {for (final d in await store.loadDrafts()) d.id};
      expect(ids, contains('good'));
    });
  });

  group('markDraftConfirmed', () {
    test('stamp status + confirmedAt ไม่ลบร่าง', () async {
      await store.saveDraft(draft('a'));
      await store.markDraftConfirmed('a');
      final d = (await store.loadDrafts()).single;
      expect(d.status, 'confirmed');
      expect(d.meta?['confirmedAt'], isNotNull);
    });
  });
}

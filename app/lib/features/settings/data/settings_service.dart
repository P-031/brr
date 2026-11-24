import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:brr/core/config/app_info.dart';

/// ชั้น data ของหน้าตั้งค่า — ตอนนี้มีงานเดียวคือ export ข้อมูล
/// ในเครื่อง (backup) ออกไปเป็นโฟลเดอร์ที่ผู้ใช้เปิดจาก file
/// manager ได้
class SettingsService {
  /// prefix ของ SharedPreferences key ที่เป็นความลับ — ห้ามใส่ใน
  /// backup เด็ดขาด (refresh/access token รั่วในไฟล์ JSON ดิบ =
  /// ขโมย session ได้)
  static const _secretKeyPrefixes = ['auth.'];

  /// ส่งออกข้อมูลทั้งหมดในเครื่อง → โฟลเดอร์
  /// `Android/data/com.brr.brr/files/backup/brr_backup_<เวลา>/`
  /// ประกอบด้วย `data.json` (ค่า SharedPreferences ทุก key ที่ไม่ใช่
  /// ความลับ) + `photos/` (รูปที่ persist ของร่างแปลง/กิจกรรม)
  /// คืน path ของโฟลเดอร์ backup ให้ UI แจ้งผู้ใช้
  Future<String> exportBackup() async {
    final prefs = await SharedPreferences.getInstance();
    final data = <String, dynamic>{
      'appVersion': AppInfo.version,
      'exportedAt': DateTime.now().toIso8601String(),
      'prefs': {
        for (final key in prefs.getKeys())
          if (!_secretKeyPrefixes.any(key.startsWith)) key: prefs.get(key),
      },
    };

    final root = await getExternalStorageDirectory();
    if (root == null) throw Exception('เข้าถึงที่จัดเก็บภายนอกไม่ได้');
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final dir = Directory('${root.path}/backup/brr_backup_$stamp')
      ..createSync(recursive: true);

    await File('${dir.path}/data.json')
        .writeAsString(const JsonEncoder.withIndent('  ').convert(data));

    final photos = Directory(
      '${(await getApplicationDocumentsDirectory()).path}/photos',
    );
    if (photos.existsSync()) {
      final dest = Directory('${dir.path}/photos')..createSync();
      await for (final f in photos.list()) {
        if (f is File) {
          await f.copy('${dest.path}/${f.uri.pathSegments.last}');
        }
      }
    }
    return dir.path;
  }
}

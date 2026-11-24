import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:brr/features/auth/models/auth_session.dart';
import 'package:brr/features/auth/models/saved_account.dart';

/// Persists the refresh token (and id_token for the logout hint) in the
/// platform keychain/keystore so the user stays signed in across restarts.
class SessionStore {
  SessionStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  static const _kRefreshToken = 'auth.refresh_token';
  static const _kIdToken = 'auth.id_token';
  static const _kAccessToken = 'auth.access_token';
  static const _kAccounts = 'auth.saved_accounts';

  final FlutterSecureStorage _storage;

  Future<void> save(AuthSession session) async {
    final rt = session.refreshToken;
    if (rt == null) return;
    await _storage.write(key: _kRefreshToken, value: rt);
    await _storage.write(key: _kAccessToken, value: session.accessToken);
    final id = session.idToken;
    if (id != null) await _storage.write(key: _kIdToken, value: id);
  }

  Future<({String refreshToken, String? idToken, String? accessToken})?>
  read() async {
    final rt = await _storage.read(key: _kRefreshToken);
    if (rt == null) return null;
    return (
      refreshToken: rt,
      idToken: await _storage.read(key: _kIdToken),
      accessToken: await _storage.read(key: _kAccessToken),
    );
  }

  Future<List<SavedAccount>> readAccounts() async {
    final raw = await _storage.read(key: _kAccounts);
    if (raw == null) return const [];
    // storage เสีย (เขียนค้าง/ข้อมูลคอร์รัปต์) → ถือว่าไม่มีบัญชีจำไว้
    // ดีกว่า throw ทำหน้าเลือกบัญชี/login พังทั้งหน้า
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return const [];
    }
    if (decoded is! List) return const [];
    return [
      for (final j in decoded)
        if (j is Map)
          // parse ต่อตัว — entry พังในตัวเดียวไม่ลากตัวอื่นหาย
          ?SavedAccount.tryFromJson(Map<String, dynamic>.from(j)),
    ];
  }

  Future<void> saveAccounts(List<SavedAccount> accounts) async {
    await _storage.write(
      key: _kAccounts,
      value: jsonEncode(accounts.map((a) => a.toJson()).toList()),
    );
  }

  /// Per-user profile photo path (local until the backend stores it).
  Future<void> savePhotoPath(String username, String path) =>
      _storage.write(key: 'profile.photo.$username', value: path);

  Future<String?> readPhotoPath(String username) =>
      _storage.read(key: 'profile.photo.$username');

  Future<void> clear() async {
    await _storage.delete(key: _kRefreshToken);
    await _storage.delete(key: _kIdToken);
    await _storage.delete(key: _kAccessToken);
  }
}

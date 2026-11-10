import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:brr/features/auth/models/auth_session.dart';

/// A remembered account for the account picker on the login screen.
class SavedAccount {
  const SavedAccount({
    required this.username,
    required this.displayName,
    required this.refreshToken,
    this.idToken,
  });

  final String username;
  final String displayName;
  final String refreshToken;
  final String? idToken;

  factory SavedAccount.fromJson(Map<String, dynamic> j) => SavedAccount(
    username: j['username'] as String,
    displayName: j['displayName'] as String,
    refreshToken: j['refreshToken'] as String,
    idToken: j['idToken'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'username': username,
    'displayName': displayName,
    'refreshToken': refreshToken,
    'idToken': idToken,
  };
}

/// Persists the refresh token (and id_token for the logout hint) in the
/// platform keychain/keystore so the user stays signed in across restarts.
class SessionStore {
  SessionStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  static const _kRefreshToken = 'auth.refresh_token';
  static const _kIdToken = 'auth.id_token';
  static const _kAccounts = 'auth.saved_accounts';

  final FlutterSecureStorage _storage;

  Future<void> save(AuthSession session) async {
    final rt = session.refreshToken;
    if (rt == null) return;
    await _storage.write(key: _kRefreshToken, value: rt);
    final id = session.idToken;
    if (id != null) await _storage.write(key: _kIdToken, value: id);
  }

  Future<({String refreshToken, String? idToken})?> read() async {
    final rt = await _storage.read(key: _kRefreshToken);
    if (rt == null) return null;
    return (refreshToken: rt, idToken: await _storage.read(key: _kIdToken));
  }

  Future<List<SavedAccount>> readAccounts() async {
    final raw = await _storage.read(key: _kAccounts);
    if (raw == null) return const [];
    try {
      return (jsonDecode(raw) as List)
          .map((j) => SavedAccount.fromJson(j as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
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
  }
}

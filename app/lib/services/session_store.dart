import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/auth_session.dart';

/// Persists the refresh token (and id_token for the logout hint) in the
/// platform keychain/keystore so the user stays signed in across restarts.
class SessionStore {
  SessionStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  static const _kRefreshToken = 'auth.refresh_token';
  static const _kIdToken = 'auth.id_token';

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

  Future<void> clear() async {
    await _storage.delete(key: _kRefreshToken);
    await _storage.delete(key: _kIdToken);
  }
}

import 'package:flutter/foundation.dart';

import '../models/auth_session.dart';
import '../models/user_profile.dart';
import '../services/auth_service.dart';
import '../services/session_store.dart';

enum AuthStatus { restoring, unauthenticated, authenticating, authenticated }

/// ViewModel — owns auth state and exposes it to the views.
/// Views never talk to [AuthService] directly.
class AuthViewModel extends ChangeNotifier {
  AuthViewModel({AuthService? authService, SessionStore? sessionStore})
    : _auth = authService ?? AuthService(),
      _store = sessionStore ?? SessionStore() {
    _restoreSession();
  }

  final AuthService _auth;
  final SessionStore _store;

  AuthStatus _status = AuthStatus.restoring;
  AuthSession? _session;
  String? _error;

  AuthStatus get status => _status;
  bool get isAuthenticated => _status == AuthStatus.authenticated;
  bool get isBusy => _status == AuthStatus.authenticating;
  String? get error => _error;
  UserProfile? get user => _session?.user;

  /// Called once at app start — silently restores a saved session.
  Future<void> _restoreSession() async {
    try {
      final saved = await _store.read();
      if (saved == null) {
        _status = AuthStatus.unauthenticated;
      } else {
        _session = await _auth.refresh(
          saved.refreshToken,
          fallbackIdToken: saved.idToken,
        );
        _status = AuthStatus.authenticated;
        await _store.save(_session!);
      }
    } catch (_) {
      await _clear();
      _status = AuthStatus.unauthenticated;
    }
    notifyListeners();
  }

  Future<void> signIn() async {
    if (isBusy) return;
    _error = null;
    _status = AuthStatus.authenticating;
    notifyListeners();
    try {
      _session = await _auth.login();
      _status = AuthStatus.authenticated;
      await _store.save(_session!);
    } on AuthCancelledException {
      _status = AuthStatus.unauthenticated;
    } catch (e) {
      _status = AuthStatus.unauthenticated;
      _error = 'เข้าสู่ระบบไม่สำเร็จ: $e';
    }
    notifyListeners();
  }

  Future<void> signOut() async {
    final hint = _session?.idToken;
    await _clear();
    notifyListeners();
    try {
      await _auth.endSession(hint);
    } catch (_) {
      // Local session is already cleared; browser logout is best-effort.
    }
  }

  /// Refreshes the access token using the stored refresh token.
  Future<void> refresh() async {
    final rt = _session?.refreshToken;
    if (rt == null) return;
    try {
      _session = await _auth.refresh(rt);
      await _store.save(_session!);
    } catch (_) {
      await _clear();
    }
    notifyListeners();
  }

  Future<void> _clear() async {
    _session = null;
    _status = AuthStatus.unauthenticated;
    try {
      await _store.clear();
    } catch (_) {}
  }
}

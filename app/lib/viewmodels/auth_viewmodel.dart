import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../models/auth_session.dart';
import '../models/user_profile.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/session_store.dart';

enum AuthStatus { restoring, unauthenticated, authenticating, authenticated }

/// ViewModel — owns auth state and exposes it to the views.
/// Views never talk to [AuthService] directly.
class AuthViewModel extends ChangeNotifier {
  AuthViewModel({
    AuthService? authService,
    SessionStore? sessionStore,
    Connectivity? connectivity,
  }) : _auth = authService ?? AuthService(),
       _store = sessionStore ?? SessionStore(),
       _connectivity = connectivity ?? Connectivity() {
    _restoreSession();
    try {
      _connectivitySub = _connectivity.onConnectivityChanged.listen(
        _onConnectivityChanged,
        onError: (_) {},
      );
    } catch (_) {
      // Platform without connectivity support — refresh() can still
      // be called manually.
    }
  }

  final AuthService _auth;
  final SessionStore _store;
  final Connectivity _connectivity;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  AuthStatus _status = AuthStatus.restoring;
  AuthSession? _session;
  String? _error;
  bool _offline = false;

  AuthStatus get status => _status;
  bool get isAuthenticated => _status == AuthStatus.authenticated;
  bool get isBusy => _status == AuthStatus.authenticating;
  String? get error => _error;
  UserProfile? get user => _session?.user;

  /// Saves profile edits — persists locally until the backend
  /// profile endpoint exists (TODO: PATCH /accounts/me).
  Future<void> updateProfile({
    String? email,
    String? phone,
    String? photoPath,
  }) async {
    final s = _session;
    if (s == null) return;
    final u = s.user.copyWith(
      email: email,
      phone: phone,
      photoPath: photoPath,
    );
    _session = AuthSession(
      accessToken: s.accessToken,
      user: u,
      refreshToken: s.refreshToken,
      idToken: s.idToken,
      accessTokenExpiry: s.accessTokenExpiry,
    );
    if (photoPath != null) {
      await _store.savePhotoPath(u.username, photoPath);
    }
    notifyListeners();
  }

  /// Re-attaches the locally-saved profile photo after sign-in/refresh.
  Future<AuthSession> _attachPhoto(AuthSession s) async {
    final p = await _store.readPhotoPath(s.user.username);
    if (p == null) return s;
    return AuthSession(
      accessToken: s.accessToken,
      user: s.user.copyWith(photoPath: p),
      refreshToken: s.refreshToken,
      idToken: s.idToken,
      accessTokenExpiry: s.accessTokenExpiry,
    );
  }

  /// Changes the password via Keycloak — TODO: POST the account
  /// credentials endpoint once wired; returns an error string or
  /// null on success.
  Future<String?> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async => 'ยังไม่เปิดใช้งาน';

  /// Backend API client — injects the current access token as Bearer
  /// and refreshes once on 401. Use for all future backend calls.
  late final ApiClient api = ApiClient(getAccessToken: getAccessToken);

  /// Returns a usable access token, refreshing first when needed.
  /// Returns null when signed out or offline without a token.
  Future<String?> getAccessToken() async {
    final session = _session;
    if (session == null) return null;
    final expiry = session.accessTokenExpiry;
    final fresh = expiry == null || expiry.isBefore(DateTime.now());
    if (fresh && session.refreshToken != null) {
      await refresh();
    }
    final token = _session?.accessToken;
    return (token == null || token.isEmpty) ? null : token;
  }

  /// True when the session is kept alive from local storage only —
  /// the last token refresh failed (offline/server unreachable).
  bool get isOffline => _offline;

  /// Accounts remembered for quick sign-in on the login screen.
  final List<SavedAccount> savedAccounts = [];

  /// Called once at app start — silently restores a saved session.
  Future<void> _restoreSession() async {
    ({String refreshToken, String? idToken})? saved;
    try {
      saved = await _store.read();
      savedAccounts
        ..clear()
        ..addAll(await _store.readAccounts());
    } catch (_) {
      // Storage unavailable — treat as no saved session.
    }
    if (saved == null) {
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return;
    }
    try {
      _session = await _attachPhoto(
        await _auth.refresh(
          saved.refreshToken,
          fallbackIdToken: saved.idToken,
        ),
      );
      _status = AuthStatus.authenticated;
      _offline = false;
      await _store.save(_session!);
    } on AuthException {
      // Server rejected the refresh token — really signed out.
      await _clear();
    } catch (_) {
      // Offline / server unreachable — keep the session with the
      // cached profile and retry refresh when the network returns.
      final idToken = saved.idToken;
      if (idToken != null) {
        _session = await _attachPhoto(
          AuthSession(
            accessToken: '',
            refreshToken: saved.refreshToken,
            idToken: idToken,
            user: UserProfile.fromClaims(
              AuthService.decodeJwt(idToken) ?? const {},
            ),
          ),
        );
        _status = AuthStatus.authenticated;
        _offline = true;
      } else {
        await _clear();
      }
    }
    notifyListeners();
  }

  Future<void> signIn(String username, String password) async {
    if (isBusy) return;
    _error = null;
    _status = AuthStatus.authenticating;
    notifyListeners();
    try {
      _session = await _attachPhoto(
        await _auth.loginWithPassword(username, password),
      );
      _status = AuthStatus.authenticated;
      await _store.save(_session!);
      await _remember(_session!);
    } on AuthException catch (e) {
      _status = AuthStatus.unauthenticated;
      _error = e.message;
    } catch (e) {
      _status = AuthStatus.unauthenticated;
      _error = 'เข้าสู่ระบบไม่สำเร็จ: $e';
    }
    notifyListeners();
  }

  /// Alternative browser-based OIDC flow (kept for future use).
  Future<void> signInWithBrowser() async {
    if (isBusy) return;
    _error = null;
    _status = AuthStatus.authenticating;
    notifyListeners();
    try {
      _session = await _attachPhoto(await _auth.login());
      _status = AuthStatus.authenticated;
      await _store.save(_session!);
      await _remember(_session!);
    } on AuthCancelledException {
      _status = AuthStatus.unauthenticated;
    } catch (e) {
      _status = AuthStatus.unauthenticated;
      _error = 'เข้าสู่ระบบไม่สำเร็จ: $e';
    }
    notifyListeners();
  }

  /// Signs in with an account picked from the saved list — uses its
  /// stored refresh token, no password needed.
  Future<void> signInWithSaved(SavedAccount account) async {
    if (isBusy) return;
    _error = null;
    _status = AuthStatus.authenticating;
    notifyListeners();
    try {
      _session = await _attachPhoto(
        await _auth.refresh(
          account.refreshToken,
          fallbackIdToken: account.idToken,
        ),
      );
      _status = AuthStatus.authenticated;
      await _store.save(_session!);
      await _remember(_session!);
    } on AuthException {
      savedAccounts.removeWhere((a) => a.username == account.username);
      _store.saveAccounts(savedAccounts);
      _status = AuthStatus.unauthenticated;
      _error = 'เซสชันของ ${account.username} หมดอายุ กรุณาเข้าสู่ระบบใหม่';
    } catch (e) {
      _status = AuthStatus.unauthenticated;
      _error = 'เข้าสู่ระบบไม่สำเร็จ: $e';
    }
    notifyListeners();
  }

  /// Remembers the signed-in account for the picker on next launch.
  Future<void> _remember(AuthSession session) async {
    final acc = SavedAccount(
      username: session.user.username,
      displayName: session.user.displayName,
      refreshToken: session.refreshToken ?? '',
      idToken: session.idToken,
    );
    savedAccounts.removeWhere((a) => a.username == acc.username);
    savedAccounts.add(acc);
    await _store.saveAccounts(savedAccounts);
  }

  Future<void> signOut() async {
    // Clears the local session only — do NOT end the Keycloak session
    // server-side, or saved accounts' refresh tokens would die too
    // and the account picker on the login screen would be useless.
    await _clear();
    notifyListeners();
  }

  /// Retries the token refresh when connectivity returns and the
  /// session is in offline mode.
  void _onConnectivityChanged(List<ConnectivityResult> results) {
    final online = results.any((r) => r != ConnectivityResult.none);
    if (online && isAuthenticated && _offline) {
      refresh();
    }
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    super.dispose();
  }

  /// Refreshes the access token using the stored refresh token.
  /// Call when the app resumes or connectivity returns.
  Future<void> refresh() async {
    final rt = _session?.refreshToken;
    if (rt == null) return;
    try {
      _session = await _attachPhoto(
        await _auth.refresh(rt, fallbackIdToken: _session?.idToken),
      );
      _offline = false;
      await _store.save(_session!);
    } on AuthException {
      await _clear();
    } catch (_) {
      _offline = true;
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

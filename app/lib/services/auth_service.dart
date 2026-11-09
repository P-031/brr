import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_appauth/flutter_appauth.dart';

import '../config/keycloak_config.dart';
import '../models/auth_session.dart';
import '../models/user_profile.dart';

/// Thrown when the user closes the Keycloak login page without signing in.
class AuthCancelledException implements Exception {
  const AuthCancelledException();

  @override
  String toString() => 'User cancelled the sign-in flow';
}

/// Data layer — talks to Keycloak via flutter_appauth (OIDC + PKCE).
/// Holds no state; each call returns a fresh [AuthSession].
class AuthService {
  AuthService([FlutterAppAuth? appAuth])
    : _appAuth = appAuth ?? const FlutterAppAuth();

  final FlutterAppAuth _appAuth;

  /// Opens the Keycloak login page and exchanges the code for tokens.
  /// Throws [AuthCancelledException] if the user cancels.
  Future<AuthSession> login() async {
    try {
      final result = await _appAuth.authorizeAndExchangeCode(
        AuthorizationTokenRequest(
          KeycloakConfig.clientId,
          KeycloakConfig.redirectUri,
          issuer: KeycloakConfig.issuer,
          scopes: KeycloakConfig.scopes,
        ),
      );
      return _toSession(result);
    } on PlatformException catch (e) {
      if (e.code.contains('cancel')) throw const AuthCancelledException();
      rethrow;
    }
  }

  /// Exchanges a refresh token for a new session.
  /// Keycloak may omit id_token on refresh — [fallbackIdToken] keeps
  /// the previous one so the user profile survives.
  Future<AuthSession> refresh(
    String refreshToken, {
    String? fallbackIdToken,
  }) async {
    final result = await _appAuth.token(
      TokenRequest(
        KeycloakConfig.clientId,
        KeycloakConfig.redirectUri,
        issuer: KeycloakConfig.issuer,
        refreshToken: refreshToken,
        scopes: KeycloakConfig.scopes,
      ),
    );
    return _toSession(result, fallbackIdToken: fallbackIdToken);
  }

  /// Ends the Keycloak session in the system browser.
  Future<void> endSession(String? idTokenHint) async {
    if (idTokenHint == null) return;
    await _appAuth.endSession(
      EndSessionRequest(
        idTokenHint: idTokenHint,
        postLogoutRedirectUrl: KeycloakConfig.postLogoutRedirectUri,
        issuer: KeycloakConfig.issuer,
      ),
    );
  }

  AuthSession _toSession(TokenResponse result, {String? fallbackIdToken}) {
    final token = result.accessToken;
    if (token == null) {
      throw StateError('Keycloak returned no access token');
    }
    final idToken = result.idToken ?? fallbackIdToken;
    return AuthSession(
      accessToken: token,
      refreshToken: result.refreshToken,
      idToken: idToken,
      accessTokenExpiry: result.accessTokenExpirationDateTime,
      user: UserProfile.fromClaims(_decodeJwt(idToken) ?? const {}),
    );
  }

  static Map<String, dynamic>? _decodeJwt(String? token) {
    if (token == null) return null;
    final parts = token.split('.');
    if (parts.length != 3) return null;
    try {
      final payload = utf8.decode(
        base64Url.decode(base64Url.normalize(parts[1])),
      );
      return jsonDecode(payload) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}

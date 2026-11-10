import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:http/http.dart' as http;

import 'package:brr/core/config/keycloak_config.dart';
import 'package:brr/features/auth/models/auth_session.dart';
import 'package:brr/features/auth/models/user_profile.dart';

/// Thrown when the user closes the Keycloak login page without signing in.
class AuthCancelledException implements Exception {
  const AuthCancelledException();

  @override
  String toString() => 'User cancelled the sign-in flow';
}

/// Thrown when Keycloak rejects a direct-grant sign-in (bad credentials, etc.)
class AuthException implements Exception {
  const AuthException(this.message);

  final String message;

  @override
  String toString() => message;
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
          // Dev only — Keycloak runs on http locally. Remove for production.
          allowInsecureConnections: true,
        ),
      );
      return _toSession(result);
    } on PlatformException catch (e) {
      if (e.code.contains('cancel')) throw const AuthCancelledException();
      rethrow;
    }
  }

  /// Direct Access Grant — posts username/password straight to the
  /// Keycloak token endpoint. Requires `directAccessGrantsEnabled`.
  Future<AuthSession> loginWithPassword(
    String username,
    String password,
  ) async {
    final res = await http.post(
      Uri.parse('${KeycloakConfig.issuer}/protocol/openid-connect/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'password',
        'client_id': KeycloakConfig.clientId,
        'username': username,
        'password': password,
        'scope': KeycloakConfig.scopes.join(' '),
      },
    );
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      final error = json['error'] as String?;
      throw AuthException(
        error == 'invalid_grant'
            ? 'ชื่อบัญชีหรือรหัสผ่านไม่ถูกต้อง'
            : (json['error_description'] as String? ?? 'เข้าสู่ระบบไม่สำเร็จ'),
      );
    }
    return _sessionFromJson(json);
  }

  /// Exchanges a refresh token for a new session.
  /// Keycloak may omit id_token on refresh — [fallbackIdToken] keeps
  /// the previous one so the user profile survives.
  ///
  /// Throws [AuthException] when the token is rejected (revoked/expired).
  /// Network failures surface as [http.ClientException]/SocketException
  /// so the caller can keep the session in offline mode.
  Future<AuthSession> refresh(
    String refreshToken, {
    String? fallbackIdToken,
  }) async {
    final res = await http.post(
      Uri.parse('${KeycloakConfig.issuer}/protocol/openid-connect/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'refresh_token',
        'client_id': KeycloakConfig.clientId,
        'refresh_token': refreshToken,
      },
    );
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      throw AuthException(
        json['error_description'] as String? ?? 'เซสชันหมดอายุ',
      );
    }
    return _sessionFromJson(json, fallbackIdToken: fallbackIdToken);
  }

  /// Ends the Keycloak session in the system browser.
  Future<void> endSession(String? idTokenHint) async {
    if (idTokenHint == null) return;
    // Plain http call — AppAuth's native https check crashes the app
    // on http:// Keycloak during dev.
    final uri = Uri.parse(
      '${KeycloakConfig.issuer}/protocol/openid-connect/logout',
    ).replace(
      queryParameters: {
        'id_token_hint': idTokenHint,
        'post_logout_redirect_uri': KeycloakConfig.postLogoutRedirectUri,
        'client_id': KeycloakConfig.clientId,
      },
    );
    final client = http.Client();
    try {
      final req = http.Request('GET', uri)..followRedirects = false;
      await client.send(req);
    } finally {
      client.close();
    }
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
      user: UserProfile.fromClaims(decodeJwt(idToken) ?? const {}),
    );
  }

  AuthSession _sessionFromJson(
    Map<String, dynamic> json, {
    String? fallbackIdToken,
  }) {
    final token = json['access_token'] as String?;
    if (token == null) {
      throw StateError('Keycloak returned no access token');
    }
    final idToken = json['id_token'] as String? ?? fallbackIdToken;
    final expiresIn = json['expires_in'] as int?;
    return AuthSession(
      accessToken: token,
      refreshToken: json['refresh_token'] as String?,
      idToken: idToken,
      accessTokenExpiry: expiresIn != null
          ? DateTime.now().add(Duration(seconds: expiresIn))
          : null,
      user: UserProfile.fromClaims(decodeJwt(idToken) ?? const {}),
    );
  }

  /// Decodes the payload of a JWT (no signature verification — tokens
  /// come straight from Keycloak over TLS).
  static Map<String, dynamic>? decodeJwt(String? token) {
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

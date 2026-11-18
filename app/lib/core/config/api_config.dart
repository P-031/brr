import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// Backend API configuration. The app talks to the real backend
/// at port 3000 — Android emulators reach the host via 10.0.2.2.
///
/// เปลี่ยน backend โดยไม่แก้โค้ด — ส่งตอน build/run:
/// `flutter run --dart-define=API_BASE_URL=http://192.168.1.50:3000`
class ApiConfig {
  static const bool enabled = true;

  static String get baseUrl {
    const fromEnv = String.fromEnvironment('API_BASE_URL');
    if (fromEnv.isNotEmpty) return fromEnv;
    return (!kIsWeb && Platform.isAndroid)
        ? 'http://10.0.2.2:3000'
        : 'http://127.0.0.1:3000';
  }

  /// Endpoint the backend should expose to create users
  /// (backend calls Keycloak Admin REST with service credentials).
  static const String registerPath = '/api/v1/auth/register';

  /// Changes the signed-in user's Keycloak password through the
  /// backend (verifies the old password, then Admin REST reset).
  static const String accountPasswordPath = '/me/password';
}

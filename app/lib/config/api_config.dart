import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// Backend API configuration. The app talks to the real backend
/// at port 3000 — Android emulators reach the host via 10.0.2.2.
class ApiConfig {
  static const bool enabled = true;

  static String get baseUrl =>
      (!kIsWeb && Platform.isAndroid) ? 'http://10.0.2.2:3000' : 'http://127.0.0.1:3000';

  /// Endpoint the backend should expose to create users
  /// (backend calls Keycloak Admin REST with service credentials).
  static const String registerPath = '/api/v1/auth/register';
}

import 'package:flutter/foundation.dart';

/// Keycloak / OIDC configuration.
///
/// Base URL is picked per platform:
/// - Android emulator: 10.0.2.2 maps to the host machine's localhost.
/// - Physical device: replace [lanBaseUrl] with your PC's LAN IP,
///   e.g. http://192.168.1.50:8080 (same Wi-Fi, firewall port 8080 open).
/// - Other platforms: localhost.
class KeycloakConfig {
  static const String lanBaseUrl = 'http://192.168.1.50:8080';

  static String get baseUrl => switch (defaultTargetPlatform) {
    TargetPlatform.android =>
      _isPhysicalDevice ? lanBaseUrl : 'http://10.0.2.2:8080',
    _ => 'http://localhost:8080',
  };

  // flip to true when testing on a physical Android device
  static const bool _isPhysicalDevice = false;

  static const String realm = 'brr';
  static const String clientId = 'brr-app';

  static String get issuer => '$baseUrl/realms/$realm';

  /// Must match `appAuthRedirectScheme` in android/app/build.gradle.kts
  /// and CFBundleURLSchemes in ios/Runner/Info.plist,
  /// and be whitelisted in the Keycloak client's redirect URIs.
  static const String redirectUri = 'com.brr.brr://oauthredirect';
  static const String postLogoutRedirectUri = 'com.brr.brr://oauthredirect';

  static const List<String> scopes = ['openid', 'profile', 'email'];
}

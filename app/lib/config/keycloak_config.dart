/// Keycloak / OIDC configuration.
///
/// Update these values once the Keycloak server is running.
/// Note for Android emulator: use http://10.0.2.2:8080 instead of localhost.
class KeycloakConfig {
  static const String baseUrl = 'http://localhost:8080';
  static const String realm = 'brr';
  static const String clientId = 'brr-app';

  static const String issuer = '$baseUrl/realms/$realm';

  /// Must match `appAuthRedirectScheme` in android/app/build.gradle.kts
  /// and CFBundleURLSchemes in ios/Runner/Info.plist,
  /// and be whitelisted in the Keycloak client's redirect URIs.
  static const String redirectUri = 'com.brr.brr://oauthredirect';
  static const String postLogoutRedirectUri = 'com.brr.brr://oauthredirect';

  static const List<String> scopes = [
    'openid',
    'profile',
    'email',
    'offline_access',
  ];

  /// Direct link to the Keycloak self-registration page.
  static const String registrationUrl =
      '$issuer/protocol/openid-connect/registrations'
      '?client_id=$clientId&redirect_uri=$redirectUri&response_type=code'
      '&scope=openid';
}

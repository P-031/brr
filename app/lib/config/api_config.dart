/// Backend API configuration.
///
/// Flip [enabled] to true once the backend is deployed and set
/// [baseUrl] to its address. Until then the app talks to Keycloak
/// directly (direct grant + registration form).
class ApiConfig {
  static const bool enabled = false;
  static const String baseUrl = 'http://localhost:8081';

  /// Endpoint the backend should expose to create users
  /// (backend calls Keycloak Admin REST with service credentials).
  static const String registerPath = '/api/v1/auth/register';
}

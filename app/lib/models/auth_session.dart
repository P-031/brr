import 'user_profile.dart';

/// Domain model holding the OIDC tokens plus the resolved user.
class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.user,
    this.refreshToken,
    this.idToken,
    this.accessTokenExpiry,
  });

  final String accessToken;
  final String? refreshToken;
  final String? idToken;
  final DateTime? accessTokenExpiry;
  final UserProfile user;
}

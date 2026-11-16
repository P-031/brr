/// Domain model for the signed-in user, decoded from the OIDC id_token.
class UserProfile {
  const UserProfile({
    required this.id,
    required this.username,
    this.name,
    this.email,
    this.phone,
    this.photoPath,
    this.role,
  });

  /// `sub` claim.
  final String id;

  /// `preferred_username` claim.
  final String username;
  final String? name;
  final String? email;

  /// Locally-edited fields — backend will own these eventually.
  final String? phone;
  final String? photoPath;

  /// 'OFFICER' / 'FARMER' — from the Keycloak realm roles.
  final String? role;

  static String? _roleFromClaims(Map<String, dynamic> claims) {
    final access = claims['realm_access'];
    if (access is! Map || access['roles'] is! List) return null;
    final roles = (access['roles'] as List).cast<String>();
    if (roles.contains('officer')) return 'OFFICER';
    if (roles.contains('farmer')) return 'FARMER';
    return null;
  }

  factory UserProfile.fromClaims(Map<String, dynamic> claims) {
    return UserProfile(
      id: claims['sub'] as String? ?? '',
      username: claims['preferred_username'] as String? ?? '',
      name: claims['name'] as String?,
      email: claims['email'] as String?,
      role: _roleFromClaims(claims),
    );
  }

  UserProfile copyWith({String? email, String? phone, String? photoPath}) =>
      UserProfile(
        id: id,
        username: username,
        name: name,
        email: email ?? this.email,
        phone: phone ?? this.phone,
        photoPath: photoPath ?? this.photoPath,
        role: role,
      );

  String get displayName => (name?.isNotEmpty ?? false) ? name! : username;
}

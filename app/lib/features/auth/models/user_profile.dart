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
    this.zone,
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

  static const roleOfficer = 'OFFICER';
  static const roleFarmer = 'FARMER';

  bool get isOfficer => role == roleOfficer;

  /// เขตที่รับผิดชอบ — จาก custom claim `zone` ของ token (null ถ้า
  /// Keycloak ยังไม่ส่งมา)
  final String? zone;

  static String? _roleFromClaims(Map<String, dynamic> claims) {
    final access = claims['realm_access'];
    if (access is! Map || access['roles'] is! List) return null;
    final roles = {for (final r in access['roles'] as List) '$r'};
    if (roles.contains('officer')) return roleOfficer;
    if (roles.contains('farmer')) return roleFarmer;
    return null;
  }

  factory UserProfile.fromClaims(Map<String, dynamic> claims) {
    return UserProfile(
      id: '${claims['sub'] ?? ''}',
      username: '${claims['preferred_username'] ?? ''}',
      name: claims['name']?.toString(),
      email: claims['email']?.toString(),
      role: _roleFromClaims(claims),
      zone: claims['zone']?.toString(),
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
        zone: zone,
      );

  String get displayName => (name?.isNotEmpty ?? false) ? name! : username;
}

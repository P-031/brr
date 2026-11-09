/// Domain model for the signed-in user, decoded from the OIDC id_token.
class UserProfile {
  const UserProfile({
    required this.id,
    required this.username,
    this.name,
    this.email,
  });

  /// `sub` claim.
  final String id;

  /// `preferred_username` claim.
  final String username;
  final String? name;
  final String? email;

  factory UserProfile.fromClaims(Map<String, dynamic> claims) {
    return UserProfile(
      id: claims['sub'] as String? ?? '',
      username: claims['preferred_username'] as String? ?? '',
      name: claims['name'] as String?,
      email: claims['email'] as String?,
    );
  }

  String get displayName => (name?.isNotEmpty ?? false) ? name! : username;
}

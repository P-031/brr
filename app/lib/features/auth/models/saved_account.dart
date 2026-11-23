/// A remembered account for the account picker on the login screen.
class SavedAccount {
  const SavedAccount({
    required this.username,
    required this.displayName,
    required this.refreshToken,
    this.idToken,
    this.accessToken,
  });

  final String username;
  final String displayName;
  final String refreshToken;
  final String? idToken;

  /// Last access token — kept for its claims (e.g. `realm_access` roles
  /// live only here), never reused for API calls after expiry.
  final String? accessToken;

  /// parse ทนค่าผิดชนิด — คืน null แทนที่จะ throw ทำ entry อื่นหาย
  static SavedAccount? tryFromJson(Map<String, dynamic> j) {
    try {
      return SavedAccount.fromJson(j);
    } catch (_) {
      return null;
    }
  }

  factory SavedAccount.fromJson(Map<String, dynamic> j) => SavedAccount(
    username: j['username'] as String,
    displayName: j['displayName'] as String,
    refreshToken: j['refreshToken'] as String,
    idToken: j['idToken'] as String?,
    accessToken: j['accessToken'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'username': username,
    'displayName': displayName,
    'refreshToken': refreshToken,
    'idToken': idToken,
    'accessToken': accessToken,
  };
}

/// A remembered account for the account picker on the login screen.
class SavedAccount {
  const SavedAccount({
    required this.username,
    required this.displayName,
    required this.refreshToken,
    this.idToken,
  });

  final String username;
  final String displayName;
  final String refreshToken;
  final String? idToken;

  factory SavedAccount.fromJson(Map<String, dynamic> j) => SavedAccount(
    username: j['username'] as String,
    displayName: j['displayName'] as String,
    refreshToken: j['refreshToken'] as String,
    idToken: j['idToken'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'username': username,
    'displayName': displayName,
    'refreshToken': refreshToken,
    'idToken': idToken,
  };
}

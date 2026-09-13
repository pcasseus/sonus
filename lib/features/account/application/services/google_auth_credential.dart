class GoogleAuthCredential {
  const GoogleAuthCredential({
    required this.idToken,
    required this.accessToken,
  });

  final String idToken;
  final String accessToken;
}

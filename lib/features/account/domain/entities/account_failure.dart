/// Why signing in did not finish, in terms the person can act on.
enum AccountFailureKind {
  /// No connection to Google or to the Sonus account service.
  offline,

  /// Google refused this app's sign-in setup: the Android sign-in for this
  /// package and signing key is not registered, or the build was made
  /// without the Google client ID.
  googleSetup,

  /// Sign-in was interrupted before it finished (not cancelled).
  interrupted,

  /// Google signed in, but the Sonus account service refused the result.
  serverRejected,

  unknown,
}

/// A failed sign-in, with the underlying error kept for logs only.
class AccountFailure implements Exception {
  const AccountFailure(this.kind, {this.cause});

  final AccountFailureKind kind;
  final Object? cause;

  @override
  String toString() => 'AccountFailure(${kind.name}, ${cause.runtimeType})';
}

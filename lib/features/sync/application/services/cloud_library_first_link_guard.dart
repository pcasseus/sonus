/// This device has never synced with the account, so nothing is uploaded
/// or downloaded until the person chooses to start. With
/// [cloudHasLibrary], the account already has a cloud library that would
/// be brought onto this device; otherwise this device's library would be
/// the first one sent to the account.
class SyncNeedsCloudLibraryChoice implements Exception {
  const SyncNeedsCloudLibraryChoice({this.cloudHasLibrary = true});

  final bool cloudHasLibrary;

  @override
  String toString() => cloudHasLibrary
      ? 'This account already has a cloud library. Choose whether to bring '
            'it onto this device.'
      : 'Cloud sync has not been turned on for this device. Choose whether '
            'to send this library to the account.';
}

abstract interface class CloudLibraryProbe {
  /// Whether the account has any library or archive records in the cloud.
  Future<bool> hasLibrary(String userId);
}

abstract interface class CloudLibraryConsentStore {
  Future<bool> hasConsent(String userId);

  Future<void> grant(String userId);
}

/// Stops the first sync between this device and an account until the
/// person chooses to start it, in both directions: an existing cloud
/// library never repopulates this library unexpectedly, and this library
/// is never uploaded just because someone signed in.
///
/// "Linked" means this device has completed a sync with the account
/// ([syncedBefore]); signing in alone binds the device to the account but
/// does not count, because sign-in must never start a transfer by itself.
class CloudLibraryFirstLinkGuard {
  CloudLibraryFirstLinkGuard({
    required this._syncedBefore,
    required this._probe,
    required this._consent,
  });

  final Future<bool> Function(String userId) _syncedBefore;
  final CloudLibraryProbe _probe;
  final CloudLibraryConsentStore _consent;

  Future<void> check(String userId) async {
    if (await _syncedBefore(userId)) return;
    if (await _consent.hasConsent(userId)) return;
    throw SyncNeedsCloudLibraryChoice(
      cloudHasLibrary: await _probe.hasLibrary(userId),
    );
  }
}

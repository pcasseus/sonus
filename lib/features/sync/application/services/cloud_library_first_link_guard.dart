/// The account already has a cloud library and this device has never
/// synced with it. Nothing is uploaded or downloaded until the person
/// chooses to bring that library onto this device.
class SyncNeedsCloudLibraryChoice implements Exception {
  const SyncNeedsCloudLibraryChoice();

  @override
  String toString() =>
      'This account already has a cloud library. Choose whether to bring it '
      'onto this device.';
}

abstract interface class CloudLibraryProbe {
  /// Whether the account has any library or archive records in the cloud.
  Future<bool> hasLibrary(String userId);
}

abstract interface class CloudLibraryConsentStore {
  Future<bool> hasConsent(String userId);

  Future<void> grant(String userId);
}

/// Stops the first sync of a device that has never been linked to the
/// account, when the account already has a cloud library, so that old cloud
/// records never repopulate a library unexpectedly. A device already linked
/// to the account, or an account with nothing in the cloud, syncs as before.
class CloudLibraryFirstLinkGuard {
  CloudLibraryFirstLinkGuard({
    required this._boundUserId,
    required this._probe,
    required this._consent,
  });

  final Future<String?> Function() _boundUserId;
  final CloudLibraryProbe _probe;
  final CloudLibraryConsentStore _consent;

  Future<void> check(String userId) async {
    // Linked before: an account mismatch is reported by the binding itself.
    if (await _boundUserId() != null) return;
    if (await _consent.hasConsent(userId)) return;
    if (!await _probe.hasLibrary(userId)) return;
    throw const SyncNeedsCloudLibraryChoice();
  }
}

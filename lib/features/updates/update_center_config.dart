/// Sonus Update Center (App Update 1.2, DEV-20): a private, user-initiated
/// update check. This build carries only its tested foundation
/// (`UpdatePolicy`, `UpdateDownloadVerifier`); it is switched off, pins no
/// keys, has no screen, no network call and no install permission.
///
/// Turning it on needs, each with its own approval:
/// - an Ed25519 verifier package (for example `cryptography`);
/// - manifest signing keys (private keys never in this repository) and
///   their public keys pinned here, two for rotation;
/// - hosting for the manifest and APKs, and its host below;
/// - Android's REQUEST_INSTALL_PACKAGES permission and a PackageInstaller
///   session, with the system confirmation every time;
/// - a release-mode build path (non-debuggable builds end `run-as`
///   backups) and the signing-key decision.
abstract final class UpdateCenterConfig {
  static const bool enabled = false;

  /// Pinned manifest public keys by key id. None until approved.
  static const Map<String, List<int>> trustedKeys = {};

  /// The only host update files may come from. None until approved.
  static const String trustedHost = '';
}

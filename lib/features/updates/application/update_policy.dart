import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;

import '../domain/update_manifest.dart';

/// Verifies a signature over a manifest's bytes with a pinned public key.
///
/// No real implementation ships yet: Ed25519 needs a maintained package
/// (for example `cryptography`), which is a dependency awaiting approval.
abstract interface class UpdateSignatureVerifier {
  Future<bool> verify({
    required List<int> publicKey,
    required List<int> message,
    required List<int> signature,
  });
}

/// The installed app, as Android reports it.
class InstalledApp {
  const InstalledApp({
    required this.applicationId,
    required this.versionCode,
    required this.signerSha256,
  });

  final String applicationId;
  final int versionCode;
  final String signerSha256;
}

enum UpdateRejection {
  /// The Update Center is switched off in this build.
  disabled,

  /// Not a signed manifest envelope.
  malformedEnvelope,

  /// Signed by a key this build does not pin.
  untrustedKey,

  /// The signature does not verify: tampered or forged.
  badSignature,

  /// Signed, but not a manifest this build can read.
  malformedManifest,

  /// For another app.
  wrongPackage,

  /// Signed by another certificate: Android could not update in place.
  wrongSigner,

  /// Not newer than what is installed: never a downgrade or reinstall.
  notNewer,

  /// Older than a manifest already seen: a replayed old manifest.
  replayed,

  expired,

  /// The APK is not offered over HTTPS from the trusted host.
  untrustedLocation,

  /// The stated size is impossible.
  badSize,
}

/// The outcome of checking a manifest: an offer, or why there is none.
class UpdateEvaluation {
  const UpdateEvaluation.offer(UpdateManifest this.manifest) : rejection = null;
  const UpdateEvaluation.rejected(UpdateRejection this.rejection)
    : manifest = null;

  final UpdateManifest? manifest;
  final UpdateRejection? rejection;

  bool get isOffer => manifest != null;
}

/// Decides whether a fetched manifest may be offered (App Update 1.2,
/// DEV-20). Every check must pass; the first failure is reported. Only a
/// user's explicit choice would then download it, and Android's own
/// confirmation installs it: nothing here downloads or installs.
class UpdatePolicy {
  const UpdatePolicy({
    required this.enabled,
    required this.trustedKeys,
    required this.verifier,
    required this.trustedHost,
    this.maximumSizeBytes = 512 * 1024 * 1024,
  });

  final bool enabled;

  /// Pinned public keys by id; two are expected so a key can rotate.
  final Map<String, List<int>> trustedKeys;
  final UpdateSignatureVerifier verifier;

  /// The only host APKs are fetched from, over HTTPS.
  final String trustedHost;
  final int maximumSizeBytes;

  Future<UpdateEvaluation> evaluate({
    required String fetched,
    required InstalledApp installed,
    required int highestSeenVersionCode,
    required DateTime nowUtc,
  }) async {
    UpdateEvaluation reject(UpdateRejection why) =>
        UpdateEvaluation.rejected(why);

    if (!enabled) return reject(UpdateRejection.disabled);
    final envelope = SignedUpdateManifest.tryParse(fetched);
    if (envelope == null) return reject(UpdateRejection.malformedEnvelope);
    final key = trustedKeys[envelope.keyId];
    if (key == null) return reject(UpdateRejection.untrustedKey);
    final authentic = await verifier.verify(
      publicKey: key,
      message: envelope.payload,
      signature: envelope.signature,
    );
    if (!authentic) return reject(UpdateRejection.badSignature);

    final manifest = UpdateManifest.tryParse(envelope.payload);
    if (manifest == null) return reject(UpdateRejection.malformedManifest);
    if (manifest.applicationId != installed.applicationId) {
      return reject(UpdateRejection.wrongPackage);
    }
    if (manifest.signerSha256 != installed.signerSha256.toLowerCase()) {
      return reject(UpdateRejection.wrongSigner);
    }
    if (manifest.versionCode <= installed.versionCode) {
      return reject(UpdateRejection.notNewer);
    }
    if (manifest.versionCode < highestSeenVersionCode) {
      return reject(UpdateRejection.replayed);
    }
    if (!manifest.expiresAtUtc.isAfter(nowUtc.toUtc())) {
      return reject(UpdateRejection.expired);
    }
    final url = manifest.apkUrl;
    if (url.scheme != 'https' ||
        url.host != trustedHost ||
        url.userInfo.isNotEmpty) {
      return reject(UpdateRejection.untrustedLocation);
    }
    if (manifest.sizeBytes <= 0 || manifest.sizeBytes > maximumSizeBytes) {
      return reject(UpdateRejection.badSize);
    }
    return UpdateEvaluation.offer(manifest);
  }
}

enum DownloadRejection { missing, wrongSize, wrongHash }

/// Checks a downloaded APK against its verified manifest before anything
/// is handed to Android: the exact size, then the SHA-256 of every byte.
/// Android then checks the APK's own signature against the installed app.
class UpdateDownloadVerifier {
  const UpdateDownloadVerifier();

  Future<DownloadRejection?> check(File apk, UpdateManifest manifest) async {
    if (!await apk.exists()) return DownloadRejection.missing;
    if (await apk.length() != manifest.sizeBytes) {
      return DownloadRejection.wrongSize;
    }
    final digest = await crypto.sha256.bind(apk.openRead()).first;
    return digest.toString() == manifest.sha256
        ? null
        : DownloadRejection.wrongHash;
  }
}

import 'dart:convert';

/// A signed update manifest as fetched: the manifest's exact bytes
/// (base64) and a signature over those bytes by a pinned key
/// (App Update 1.2, DEV-20; foundation only).
class SignedUpdateManifest {
  const SignedUpdateManifest({
    required this.keyId,
    required this.payload,
    required this.signature,
  });

  final String keyId;

  /// The exact signed bytes; the manifest is parsed from these only after
  /// the signature over them verifies.
  final List<int> payload;
  final List<int> signature;

  /// Reads the envelope `{"keyId", "payload", "signature"}`; null when it is
  /// not one (nothing in it is trusted yet).
  static SignedUpdateManifest? tryParse(String text) {
    try {
      final json = jsonDecode(text);
      if (json is! Map<String, dynamic>) return null;
      final keyId = json['keyId'];
      final payload = json['payload'];
      final signature = json['signature'];
      if (keyId is! String ||
          keyId.isEmpty ||
          payload is! String ||
          signature is! String) {
        return null;
      }
      return SignedUpdateManifest(
        keyId: keyId,
        payload: base64Decode(payload),
        signature: base64Decode(signature),
      );
    } on FormatException {
      return null;
    }
  }
}

/// What an update offers, read from a verified payload.
class UpdateManifest {
  const UpdateManifest({
    required this.applicationId,
    required this.versionCode,
    required this.versionName,
    required this.commit,
    required this.apkUrl,
    required this.sizeBytes,
    required this.sha256,
    required this.signerSha256,
    required this.publishedAtUtc,
    required this.expiresAtUtc,
    required this.releaseNotes,
  });

  /// The only manifest format this build reads.
  static const int schema = 1;

  final String applicationId;
  final int versionCode;
  final String versionName;
  final String commit;
  final Uri apkUrl;
  final int sizeBytes;

  /// Lower-case hex SHA-256 of the APK file.
  final String sha256;

  /// Lower-case hex SHA-256 of the APK's only signing certificate.
  final String signerSha256;
  final DateTime publishedAtUtc;
  final DateTime expiresAtUtc;
  final String releaseNotes;

  static final _hex64 = RegExp(r'^[0-9a-f]{64}$');

  /// The manifest in [payload], or null when any field is missing, of the
  /// wrong type or out of range. Strict: nothing is defaulted.
  static UpdateManifest? tryParse(List<int> payload) {
    try {
      final json = jsonDecode(utf8.decode(payload));
      if (json is! Map<String, dynamic> || json['schema'] != schema) {
        return null;
      }
      final applicationId = json['applicationId'];
      final versionCode = json['versionCode'];
      final versionName = json['versionName'];
      final commit = json['commit'];
      final url = json['apkUrl'];
      final size = json['sizeBytes'];
      final sha = json['sha256'];
      final signer = json['signerSha256'];
      final published = json['publishedAtUtc'];
      final expires = json['expiresAtUtc'];
      final notes = json['releaseNotes'];
      if (applicationId is! String ||
          versionCode is! int ||
          versionName is! String ||
          commit is! String ||
          url is! String ||
          size is! int ||
          sha is! String ||
          signer is! String ||
          published is! String ||
          expires is! String ||
          notes is! String ||
          !_hex64.hasMatch(sha) ||
          !_hex64.hasMatch(signer)) {
        return null;
      }
      final apkUrl = Uri.tryParse(url);
      final publishedAt = DateTime.tryParse(published);
      final expiresAt = DateTime.tryParse(expires);
      if (apkUrl == null || publishedAt == null || expiresAt == null) {
        return null;
      }
      return UpdateManifest(
        applicationId: applicationId,
        versionCode: versionCode,
        versionName: versionName,
        commit: commit,
        apkUrl: apkUrl,
        sizeBytes: size,
        sha256: sha,
        signerSha256: signer,
        publishedAtUtc: publishedAt.toUtc(),
        expiresAtUtc: expiresAt.toUtc(),
        releaseNotes: notes,
      );
    } on FormatException {
      return null;
    }
  }
}

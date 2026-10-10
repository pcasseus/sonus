class CoverArtArchiveUriPolicy {
  const CoverArtArchiveUriPolicy._();

  static bool isTrusted(Uri uri) {
    final host = uri.host.toLowerCase();

    final trustedHost =
        host == 'coverartarchive.org' ||
        host.endsWith('.coverartarchive.org') ||
        host == 'archive.org' ||
        host.endsWith('.archive.org');

    return uri.scheme == 'https' &&
        trustedHost &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty &&
        (!uri.hasPort || uri.port == 443);
  }

  static bool isTrustedString(String value) {
    final uri = Uri.tryParse(value);
    return uri != null && isTrusted(uri);
  }
}

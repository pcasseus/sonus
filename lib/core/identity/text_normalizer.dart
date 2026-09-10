abstract final class TextNormalizer {
  static String canonicalize(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  static String normalizePath(String value) {
    return value.trim().replaceAll('\\', '/').toLowerCase();
  }
}

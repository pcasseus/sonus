enum ImportSourceDiscoveryFailureType {
  sourceMissing,
  unsupportedFormat,
  invalidStructure,
}

class ImportSourceDiscoveryException implements Exception {
  const ImportSourceDiscoveryException({
    required this.type,
    required this.message,
    this.path,
  });

  final ImportSourceDiscoveryFailureType type;
  final String message;
  final String? path;

  @override
  String toString() {
    final sourcePath = path;

    if (sourcePath == null) {
      return 'ImportSourceDiscoveryException($type): $message';
    }

    return 'ImportSourceDiscoveryException($type): $message [$sourcePath]';
  }
}

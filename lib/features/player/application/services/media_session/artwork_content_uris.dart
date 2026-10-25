import 'dart:io';

import 'package:path/path.dart' as p;

/// Builds the `content://` URIs that car hosts use to read artwork.
///
/// Android Auto runs in another app and cannot open Sonus's private
/// files, so artwork is offered through SonusArtworkProvider.kt. Only
/// files directly inside Sonus's managed artwork folder are offered; any
/// other path (an imported folder, a missing file) gets no artwork rather
/// than a URI the provider would refuse.
class ArtworkContentUris {
  ArtworkContentUris({
    required String artworkDirectory,
    bool Function(String path)? fileExists,
  }) : _directory = p.normalize(artworkDirectory),
       _fileExists = fileExists ?? _exists;

  /// Must match the provider's authority in AndroidManifest.xml.
  static const String authority = 'com.sonus.sonus_next.artwork';

  /// Managed artwork file names, as FileSystemArtworkManagedStorage
  /// creates them. The provider applies the same rule.
  static final RegExp fileNamePattern = RegExp(
    r'^artwork_[A-Za-z0-9_-]+\.[A-Za-z0-9]{1,5}$',
  );

  final String _directory;
  final bool Function(String path) _fileExists;

  Uri? resolve(String? artworkPath) {
    final trimmed = artworkPath?.trim();

    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }

    final normalized = p.normalize(trimmed);

    if (p.dirname(normalized) != _directory) {
      return null;
    }

    final name = p.basename(normalized);

    if (!fileNamePattern.hasMatch(name) || !_fileExists(normalized)) {
      return null;
    }

    return Uri(scheme: 'content', host: authority, pathSegments: [name]);
  }

  static bool _exists(String path) {
    try {
      return File(path).existsSync();
    } on FileSystemException {
      return false;
    }
  }
}

import 'package:path/path.dart' as path;

import '../../../../core/identity/text_normalizer.dart';

/// Identifies the folder an audio file is in, for SN-45's rule that a
/// folder's songs stay together as one album.
///
/// File paths use their parent directory. Android document URIs
/// (`content://…/document/<id>`) use the document ID only when it spells a
/// path (`primary:Music/Album/01.mp3`, as device storage does); providers
/// with opaque IDs have no reliable folder, so the key is null and nothing
/// is grouped by guesswork.
abstract final class SourceFolderKey {
  static String? of(String filePath) {
    final normalized = TextNormalizer.normalizePath(filePath);

    if (normalized.isEmpty) {
      return null;
    }

    if (normalized.startsWith('content://')) {
      final marker = normalized.lastIndexOf('/document/');

      if (marker == -1) {
        return null;
      }

      final String documentId;
      try {
        documentId = Uri.decodeComponent(
          normalized.substring(marker + '/document/'.length),
        );
      } on ArgumentError {
        return null;
      }

      final slash = documentId.lastIndexOf('/');

      if (slash <= 0) {
        return null;
      }

      // Tree URIs from different picks can name the same document, so the
      // key uses the provider and document path, not the tree.
      final authority = Uri.tryParse(normalized)?.authority ?? '';
      return 'content://$authority/${documentId.substring(0, slash)}';
    }

    final directory = path.posix.dirname(normalized);
    return directory == '.' || directory.isEmpty ? null : directory;
  }

  /// The containing folder's name with its original capitalization, for
  /// an album title of last resort. [filePath] may be a path relative to the
  /// picked folder (preferred for document URIs) or a full path.
  static String? folderName(String filePath) {
    var value = filePath.trim().replaceAll(r'\', '/');

    if (value.startsWith('content://')) {
      final marker = value.toLowerCase().lastIndexOf('/document/');
      if (marker == -1) return null;
      try {
        value = Uri.decodeComponent(value.substring(marker + 10));
      } on ArgumentError {
        return null;
      }
    }

    final directory = path.posix.dirname(value);
    final name = path.posix.basename(directory).split(':').last.trim();
    return directory == '.' || name.isEmpty ? null : name;
  }

  /// A prefix every file in the folder's normalized path starts with, for
  /// a cheap database pre-filter. Results must still be checked with [of].
  static String? pathPrefix(String filePath) {
    final normalized = TextNormalizer.normalizePath(filePath);

    if (normalized.startsWith('content://')) {
      final encoded = normalized.lastIndexOf('%2f');
      return encoded == -1 ? null : normalized.substring(0, encoded + 3);
    }

    final slash = normalized.lastIndexOf('/');
    return slash <= 0 ? null : normalized.substring(0, slash + 1);
  }
}

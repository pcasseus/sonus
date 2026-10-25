import '../../../../core/identity/text_normalizer.dart';
import '../../domain/models/audio_metadata.dart';
import '../../domain/models/import_folder_placement.dart';

/// One file of an import batch, with the folder it is in.
class FolderPlanEntry {
  const FolderPlanEntry({
    required this.normalizedPath,
    required this.folderKey,
    required this.folderName,
    required this.metadata,
  });

  final String normalizedPath;

  /// Null when the folder cannot be known reliably (see SourceFolderKey).
  final String? folderKey;
  final String? folderName;
  final AudioMetadata metadata;
}

/// Decides one album identity per folder (SN-45: the folder is the album).
///
/// - **Title:** the album title the folder's files agree on. When they
///   disagree, the most common one; when no title leads, the folder's name.
/// - **Owner:** the album artist the tagged files agree on. Otherwise the
///   one performer when every song has the same one, otherwise "Various
///   Artists". Performers are never replaced by the album's name.
///
/// Files whose folder is unknown get no placement and keep today's
/// tag-based behaviour.
abstract final class FolderAlbumPlanner {
  static const String variousArtists = 'Various Artists';

  /// Placements by normalized file path.
  static Map<String, ImportFolderPlacement> plan(
    Iterable<FolderPlanEntry> entries,
  ) {
    final byFolder = <String, List<FolderPlanEntry>>{};

    for (final entry in entries) {
      final key = entry.folderKey;
      if (key == null) continue;
      byFolder.putIfAbsent(key, () => []).add(entry);
    }

    final result = <String, ImportFolderPlacement>{};

    for (final MapEntry(key: folderKey, value: files) in byFolder.entries) {
      final placement = ImportFolderPlacement(
        folderKey: folderKey,
        albumTitle: _title(files),
        albumArtistName: _owner(files),
      );

      for (final file in files) {
        result[file.normalizedPath] = placement;
      }
    }

    return result;
  }

  static String _title(List<FolderPlanEntry> files) {
    final winner = _leader([
      for (final file in files) file.metadata.albumTitle,
    ]);

    if (winner != null) return winner;

    return files
            .map((file) => file.folderName)
            .whereType<String>()
            .firstOrNull ??
        files.first.metadata.albumTitle;
  }

  static String _owner(List<FolderPlanEntry> files) {
    final tagged = [
      for (final file in files)
        if ((file.metadata.albumArtistName ?? '').trim().isNotEmpty)
          file.metadata.albumArtistName!.trim(),
    ];

    if (tagged.isNotEmpty && _allSame(tagged)) {
      return tagged.first;
    }

    final performers = [for (final file in files) file.metadata.artistName];

    if (_allSame(performers)) {
      return performers.first.trim();
    }

    return variousArtists;
  }

  /// The value most of [values] share (by canonical form), keeping the
  /// first spelling seen. Null when there is no single leader.
  static String? _leader(List<String> values) {
    final counts = <String, int>{};
    final spelling = <String, String>{};

    for (final value in values) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) continue;
      final canonical = TextNormalizer.canonicalize(trimmed);
      counts[canonical] = (counts[canonical] ?? 0) + 1;
      spelling.putIfAbsent(canonical, () => trimmed);
    }

    if (counts.isEmpty) return null;

    final ranked = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    if (ranked.length > 1 && ranked[0].value == ranked[1].value) {
      return null;
    }

    return spelling[ranked.first.key];
  }

  static bool _allSame(List<String> values) {
    final canonical = {
      for (final value in values) TextNormalizer.canonicalize(value.trim()),
    };
    return canonical.length == 1 && canonical.single.isNotEmpty;
  }
}

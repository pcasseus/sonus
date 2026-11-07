import '../entities/media_file_binding.dart';

/// The files one scan of an import source found (App Update 1.2,
/// duplicate prevention).
///
/// A scan marks the files it did not find as unavailable only after every
/// file has been imported (ImportSourceReconciliationService). Until then a
/// moved or renamed folder's old paths still look available. The snapshot
/// lets the importer see, during the scan, that a known file of the same
/// source is no longer where it was. That file has moved away: it no
/// longer plays the song, and the song may be relinked to the file the
/// scan found instead.
///
/// The snapshot never says a file was deleted. Files of another source, or
/// with no source, are judged only by their availability flag.
class ImportScanSnapshot {
  ImportScanSnapshot({
    required this.sourceId,
    required Iterable<String> seenNormalizedPaths,
    required this.discoveredAt,
  }) : seenNormalizedPaths = Set.unmodifiable(seenNormalizedPaths);

  final String sourceId;
  final Set<String> seenNormalizedPaths;

  /// When the scan listed its files. A binding written after this instant
  /// (for example by an overlapping newer scan) is not judged by it, the
  /// same rule as the reconciliation.
  final DateTime discoveredAt;

  /// True when [binding] belongs to this scan's source, was not found by
  /// the scan, and is older than the scan's file listing.
  bool hasMovedAway(MediaFileBinding binding) =>
      binding.sourceId == sourceId &&
      !seenNormalizedPaths.contains(binding.normalizedPath) &&
      !binding.updatedAt.isAfter(discoveredAt);

  /// Whether [binding] still plays its song as far as this scan knows.
  static bool isLive(MediaFileBinding binding, ImportScanSnapshot? scan) =>
      binding.isAvailable && !(scan?.hasMovedAway(binding) ?? false);

  /// The same test for a raw `media_file_bindings` row.
  static bool isLiveRow(Map<String, Object?> row, ImportScanSnapshot? scan) {
    if ((row['is_available'] as int? ?? 0) != 1) return false;
    if (scan == null) return true;
    final updatedAt = DateTime.tryParse(row['updated_at'] as String? ?? '');
    final movedAway =
        row['source_id'] == scan.sourceId &&
        !scan.seenNormalizedPaths.contains(row['normalized_path']) &&
        updatedAt != null &&
        !updatedAt.isAfter(scan.discoveredAt);
    return !movedAway;
  }
}

/// One file of a folder, as evidence that the folder holds the same
/// recordings as an album already in the library.
class FolderRecording {
  const FolderRecording({
    required this.canonicalTitle,
    required this.versionLabel,
    required this.discNumber,
    required this.trackNumber,
    required this.durationSeconds,
  });

  final String canonicalTitle;
  final String? versionLabel;
  final int discNumber;
  final int trackNumber;
  final int durationSeconds;
}

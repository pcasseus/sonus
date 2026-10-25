/// How a finding is presented: what is verified, what Sonus can fix safely
/// when asked, what is worth knowing, and what needs a decision.
enum HealthSeverity { verified, safeCorrection, warning, needsReview }

/// Every check the integrity verification runs.
enum HealthCheck {
  playableFiles,
  duplicateRecordings,
  albumEditions,
  primaryEdition,
  editionListings,
  crossAlbumListings,
  trackPositions,
  trackNumbers,
  mainCredits,
  linkedCredits,
  artworkFiles,
  durations,
  placeholderNames,
  importReviews,
  userCorrections,
  soundtrackOrganization,
}

/// A deterministic, low-risk correction. Never applied without the user.
sealed class SafeCorrection {
  const SafeCorrection();
}

/// An album with a single edition and no primary edition: make it primary.
class SetPrimaryEdition extends SafeCorrection {
  const SetPrimaryEdition({required this.albumId, required this.editionId});

  final String albumId;
  final String editionId;
}

/// A song its own home edition doesn't list: list it there, at the song's
/// disc and track number.
class ListOnHomeEdition extends SafeCorrection {
  const ListOnHomeEdition({required this.songId, required this.editionId});

  final String songId;
  final String editionId;
}

class HealthFinding {
  const HealthFinding({
    required this.check,
    required this.severity,
    required this.summary,
    this.entityIds = const [],
    this.corrections = const [],
  });

  final HealthCheck check;
  final HealthSeverity severity;

  /// One plain sentence for the report.
  final String summary;

  /// What the finding is about (song, album, edition or artwork ids).
  final List<String> entityIds;

  /// Offered when [severity] is safeCorrection.
  final List<SafeCorrection> corrections;
}

/// Counts from the import that triggered the check, when there was one.
class ImportHealthCounts {
  const ImportHealthCounts({
    required this.imported,
    required this.relinked,
    required this.skipped,
    required this.failed,
  });

  final int imported;
  final int relinked;
  final int skipped;
  final int failed;
}

class LibraryHealthReport {
  const LibraryHealthReport({
    required this.checkedAt,
    required this.songCount,
    required this.albumCount,
    required this.artistCount,
    required this.findings,
    this.importCounts,
  });

  final DateTime checkedAt;
  final int songCount;
  final int albumCount;
  final int artistCount;
  final List<HealthFinding> findings;
  final ImportHealthCounts? importCounts;

  List<HealthFinding> withSeverity(HealthSeverity severity) => [
    for (final finding in findings)
      if (finding.severity == severity) finding,
  ];

  bool get isHealthy => findings.every(
    (finding) =>
        finding.severity == HealthSeverity.verified ||
        finding.severity == HealthSeverity.warning,
  );
}

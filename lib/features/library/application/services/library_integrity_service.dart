import '../../data/daos/library_integrity_dao.dart';
import '../models/library_health_report.dart';
import 'album_edition_management_service.dart';

typedef FileExists = Future<bool> Function(String path);

/// Verifies the library as it is stored, after an import or on request
/// ("Verify Library"), instead of assuming a successful import means a
/// well-organized library.
///
/// Verification only reads: it can be run any number of times and never
/// changes the library. The few deterministic corrections it can offer are
/// applied only by [applyCorrection], one at a time, when the user asks;
/// identity, edition and ownership questions are left for review. It works
/// offline.
class LibraryIntegrityService {
  const LibraryIntegrityService({
    required this.dao,
    required this.editions,
    required this.fileExists,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final LibraryIntegrityDao dao;
  final AlbumEditionManagementService editions;
  final FileExists fileExists;
  final DateTime Function() _now;

  Future<LibraryHealthReport> verify({ImportHealthCounts? importCounts}) async {
    final totals = await dao.totals();
    final findings = <HealthFinding>[];

    void add(
      HealthCheck check,
      List<String> ids, {
      required HealthSeverity whenFound,
      required String verified,
      required String Function(int count) found,
      List<SafeCorrection> corrections = const [],
    }) {
      findings.add(
        ids.isEmpty
            ? HealthFinding(
                check: check,
                severity: HealthSeverity.verified,
                summary: verified,
              )
            : HealthFinding(
                check: check,
                severity: whenFound,
                summary: found(ids.length),
                entityIds: List.unmodifiable(ids),
                corrections: List.unmodifiable(corrections),
              ),
      );
    }

    add(
      HealthCheck.playableFiles,
      await dao.songsWithoutPlayableFile(),
      whenFound: HealthSeverity.warning,
      verified: 'Every song has an audio file on this device.',
      found: (n) => '${_songs(n)} without an audio file on this device.',
    );

    add(
      HealthCheck.duplicateRecordings,
      await dao.possibleDuplicateRecordings(),
      whenFound: HealthSeverity.needsReview,
      verified: 'No album holds the same recording twice.',
      found: (n) =>
          '${_count(n, 'pair')} of songs on one album look like the same '
          'recording.',
    );

    add(
      HealthCheck.albumEditions,
      await dao.albumsWithoutEditions(),
      whenFound: HealthSeverity.needsReview,
      verified: 'Every album has an edition.',
      found: (n) => '${_count(n, 'album')} without any edition.',
    );

    final noPrimary = await dao.albumsWithoutPrimaryEdition();
    final severalPrimary = await dao.albumsWithSeveralPrimaryEditions();
    final singleEditionFixes = [
      for (final row in noPrimary)
        if (row.split('|')[1] == '1')
          SetPrimaryEdition(
            albumId: row.split('|')[0],
            editionId: row.split('|')[2],
          ),
    ];
    final primaryProblems = [
      for (final row in noPrimary) row.split('|')[0],
      ...severalPrimary,
    ];
    add(
      HealthCheck.primaryEdition,
      primaryProblems,
      whenFound: singleEditionFixes.length == primaryProblems.length
          ? HealthSeverity.safeCorrection
          : HealthSeverity.needsReview,
      verified: 'Every album has exactly one primary edition.',
      found: (n) =>
          '${_count(n, 'album')} without exactly one primary edition.',
      corrections: singleEditionFixes,
    );

    final unlisted = await dao.songsMissingFromHomeEdition();
    add(
      HealthCheck.editionListings,
      [for (final row in unlisted) row.split('|')[0]],
      whenFound: HealthSeverity.safeCorrection,
      verified: 'Every song is listed on its edition.',
      found: (n) => '${_songs(n)} missing from their own edition.',
      corrections: [
        for (final row in unlisted)
          ListOnHomeEdition(
            songId: row.split('|')[0],
            editionId: row.split('|')[1],
          ),
      ],
    );

    add(
      HealthCheck.crossAlbumListings,
      await dao.listingsOnAnotherAlbum(),
      whenFound: HealthSeverity.needsReview,
      verified: "No song is listed on another album's edition.",
      found: (n) => "${_songs(n)} listed on another album's edition.",
    );

    add(
      HealthCheck.trackPositions,
      await dao.editionsWithRepeatedPositions(),
      whenFound: HealthSeverity.warning,
      verified: 'No edition repeats a disc and track number.',
      found: (n) => '${_count(n, 'edition')} with a repeated track number.',
    );

    add(
      HealthCheck.trackNumbers,
      await dao.listingsWithoutTrackNumber(),
      whenFound: HealthSeverity.warning,
      verified: 'Every listed track has a track number.',
      found: (n) =>
          '${_count(n, 'track')} without a track number; they are listed '
          'after the numbered tracks.',
    );

    add(
      HealthCheck.mainCredits,
      await dao.songsWithoutMainCredit(),
      whenFound: HealthSeverity.needsReview,
      verified: 'Every credited song has a main artist.',
      found: (n) => '${_songs(n)} with credits but no main artist.',
    );

    add(
      HealthCheck.linkedCredits,
      await dao.unlinkedCredits(),
      whenFound: HealthSeverity.warning,
      verified: 'Every credit is linked to an artist.',
      found: (n) =>
          '${_count(n, 'credited name')} not linked to an artist, such as '
          'featured performers.',
    );

    add(
      HealthCheck.artworkFiles,
      [
        for (final artwork in await dao.artworkFiles())
          if (!await fileExists(artwork.path)) artwork.id,
      ],
      whenFound: HealthSeverity.warning,
      verified: 'Every artwork file is present.',
      found: (n) => '${_count(n, 'artwork file')} missing on this device.',
    );

    add(
      HealthCheck.durations,
      await dao.songsWithoutDuration(),
      whenFound: HealthSeverity.warning,
      verified: 'Every song has a duration.',
      found: (n) => '${_songs(n)} without a duration.',
    );

    add(
      HealthCheck.placeholderNames,
      await dao.placeholderNames(),
      whenFound: HealthSeverity.needsReview,
      verified: 'No artist or album is named "Unknown".',
      found: (n) =>
          '${_count(n, 'artist or album', plural: 'artists or albums')} '
          'named "Unknown".',
    );

    add(
      HealthCheck.importReviews,
      await dao.unresolvedImportReviews(),
      whenFound: HealthSeverity.needsReview,
      verified: 'No import reviews are waiting.',
      found: (n) => '${_songs(n)} waiting in Import Review.',
    );

    final corrections = await dao.userConfirmedFields();
    findings.add(
      HealthFinding(
        check: HealthCheck.userCorrections,
        severity: HealthSeverity.verified,
        summary: corrections == 0
            ? 'No user corrections to protect yet.'
            : '${_count(corrections, 'correction')} you made are kept.',
      ),
    );

    final projects = await dao.classifiedProjects();
    findings.add(
      HealthFinding(
        check: HealthCheck.soundtrackOrganization,
        severity: HealthSeverity.verified,
        summary: projects == 0
            ? 'No albums are classified as soundtracks or compilations yet.'
            : '${_count(projects, 'album')} classified as a soundtrack, cast '
                  'recording or compilation.',
      ),
    );

    return LibraryHealthReport(
      checkedAt: _now(),
      songCount: totals.songs,
      albumCount: totals.albums,
      artistCount: totals.artists,
      findings: List.unmodifiable(findings),
      importCounts: importCounts,
    );
  }

  /// Applies one offered correction, in its own transaction.
  Future<void> applyCorrection(SafeCorrection correction, {String? userId}) {
    return switch (correction) {
      SetPrimaryEdition(:final editionId) => editions.setPrimary(
        editionId: editionId,
        userId: userId,
      ),
      ListOnHomeEdition(:final songId, :final editionId) =>
        editions
            .assignTracks(editionId: editionId, songIds: [songId])
            .then((_) {}),
    };
  }

  static String _songs(int n) => _count(n, 'song');

  static String _count(int n, String noun, {String? plural}) =>
      '$n ${n == 1 ? noun : plural ?? '${noun}s'}';
}

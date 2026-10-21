import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/recovery/application/models/recovery_coverage.dart';
import 'package:sonus_next/features/recovery/application/models/recovery_data_category.dart';
import 'package:sonus_next/features/recovery/application/services/recovery_contract_service.dart';

void main() {
  const service = RecoveryContractService();

  test('covers every recovery category exactly once', () {
    final assessment = service.assess();

    expect(
      assessment.coverage.map((entry) => entry.category).toSet(),
      RecoveryDataCategory.values.toSet(),
    );

    expect(assessment.coverage.length, RecoveryDataCategory.values.length);
  });

  test('recognizes the five existing cloud entity types', () {
    final assessment = service.assess();

    for (final category in [
      RecoveryDataCategory.artist,
      RecoveryDataCategory.album,
      RecoveryDataCategory.albumEdition,
      RecoveryDataCategory.song,
      RecoveryDataCategory.artworkAsset,
    ]) {
      final coverage = assessment.forCategory(category);

      expect(coverage.status, RecoveryCoverageStatus.cloudSupported);
      expect(coverage.requiresVerification, isTrue);
    }
  });

  test('does not claim local-only features are cloud recoverable', () {
    final assessment = service.assess();

    for (final category in [
      RecoveryDataCategory.playlists,
      RecoveryDataCategory.playlistItems,
      RecoveryDataCategory.playbackSessions,
      RecoveryDataCategory.playbackListeningSegments,
      RecoveryDataCategory.qualifiedPlays,
      RecoveryDataCategory.chartSnapshots,
      RecoveryDataCategory.chartEntries,
      RecoveryDataCategory.chartMomentEvents,
      RecoveryDataCategory.songArtistCredits,
      RecoveryDataCategory.albumEditionTracks,
      RecoveryDataCategory.metadataFieldStates,
      RecoveryDataCategory.trackLyrics,
      RecoveryDataCategory.songImportReviews,
    ]) {
      expect(
        assessment.forCategory(category).status,
        RecoveryCoverageStatus.notCloudSupported,
      );
    }
  });

  test('recognizes explicitly device-local contract entities', () {
    final assessment = service.assess();

    expect(
      assessment.forCategory(RecoveryDataCategory.mediaFileBindings).status,
      RecoveryCoverageStatus.deviceLocal,
    );

    expect(
      assessment.forCategory(RecoveryDataCategory.importBatches).status,
      RecoveryCoverageStatus.deviceLocal,
    );
  });

  test('never equates cloud support with successful recovery', () {
    final assessment = service.assess();

    expect(assessment.isFullyRecoverable, isFalse);
    expect(assessment.hasUnverifiedCloudCoverage, isTrue);
    expect(assessment.hasUnsupportedCoverage, isTrue);
  });

  test('produces deterministic immutable coverage', () {
    final first = service.assess();
    final second = service.assess();

    expect(
      first.coverage.map((entry) => entry.category).toList(),
      second.coverage.map((entry) => entry.category).toList(),
    );

    expect(() => first.coverage.clear(), throwsUnsupportedError);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/library/application/models/external_metadata_candidate.dart';
import 'package:sonus_next/features/library/application/models/external_metadata_match_evaluation.dart';
import 'package:sonus_next/features/library/application/models/external_metadata_search_query.dart';
import 'package:sonus_next/features/library/application/services/external_metadata_confidence_evaluator.dart';
import 'package:sonus_next/features/library/application/services/external_metadata_release_selector.dart';

void main() {
  const selector = ExternalMetadataReleaseSelector();

  ExternalMetadataCandidate recording(
    List<ExternalMetadataReleaseOption> options,
  ) => ExternalMetadataCandidate(
    provider: ExternalMetadataProviderKind.musicBrainz,
    entityKind: ExternalMetadataEntityKind.track,
    providerEntityId: 'rec-1',
    displayName: 'Song',
    durationSeconds: 180,
    releaseOptions: options,
  );

  const standard = ExternalMetadataReleaseOption(
    releaseId: 'r-standard',
    title: 'locket',
    mediumPosition: 1,
    trackNumber: 3,
    trackCount: 12,
  );
  const deluxe = ExternalMetadataReleaseOption(
    releaseId: 'r-deluxe',
    title: 'locket (Deluxe)',
    mediumPosition: 1,
    trackNumber: 3,
    trackCount: 16,
  );
  const compilation = ExternalMetadataReleaseOption(
    releaseId: 'r-hits',
    title: 'Hits',
    trackNumber: 12,
  );

  test('chooses the release matching the local edition', () {
    final selection = selector.select(
      recording(const [compilation, standard, deluxe]),
      localTitles: const ['locket (Deluxe)', 'locket'],
      discNumber: 1,
      trackNumber: 3,
      editionTrackCount: 16,
    );

    expect(selection.outcome, ReleaseSelectionOutcome.matched);
    expect(selection.release?.releaseId, 'r-deluxe');
  });

  test('two equally fitting releases choose nothing', () {
    final selection = selector.select(
      recording(const [standard, deluxe]),
      localTitles: const ['locket (Deluxe)', 'locket'],
      trackNumber: 3,
    );

    expect(selection.outcome, ReleaseSelectionOutcome.ambiguous);
    expect(selection.release, isNull);
  });

  test('no title match chooses nothing, not the first release', () {
    final selection = selector.select(
      recording(const [compilation, standard]),
      localTitles: const ['Something Else'],
    );

    expect(selection.outcome, ReleaseSelectionOutcome.none);
  });

  test('unknown local positions never rule out a release', () {
    final selection = selector.select(
      recording(const [compilation, standard]),
      localTitles: const ['locket'],
      trackNumber: 0,
      editionTrackCount: 99,
    );

    expect(selection.release?.releaseId, 'r-standard');
  });

  test("the album signal finds the album among a recording's releases", () {
    const evaluator = ExternalMetadataConfidenceEvaluator();
    const query = ExternalMetadataSearchQuery(
      entityKind: ExternalMetadataEntityKind.track,
      title: 'Song',
      albumTitle: 'locket',
      durationSeconds: 180,
    );

    final albumFirst = evaluator.evaluate(
      query: query,
      candidate: recording(const [standard, compilation]),
    );
    final compilationFirst = evaluator.evaluate(
      query: query,
      candidate: recording(const [compilation, standard]),
    );

    ExternalMetadataMatchSignalStatus albumSignal(
      ExternalMetadataMatchEvaluation evaluation,
    ) => evaluation.signals
        .firstWhere((s) => s.kind == ExternalMetadataMatchSignalKind.album)
        .status;

    expect(
      albumSignal(compilationFirst),
      ExternalMetadataMatchSignalStatus.match,
    );
    expect(compilationFirst.score, albumFirst.score);
  });
}

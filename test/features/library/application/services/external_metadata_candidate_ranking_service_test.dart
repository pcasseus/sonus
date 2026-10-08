import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/library/application/models/external_metadata_candidate.dart';
import 'package:sonus_next/features/library/application/models/external_metadata_search_query.dart';
import 'package:sonus_next/features/library/application/services/external_metadata_candidate_ranking_service.dart';

void main() {
  const service = ExternalMetadataCandidateRankingService();

  const query = ExternalMetadataSearchQuery(
    entityKind: ExternalMetadataEntityKind.track,
    title: 'Halo',
    artistName: 'Beyonce',
    albumTitle: 'I Am Sasha Fierce',
    durationSeconds: 224,
  );

  ExternalMetadataCandidate candidate(
    String id, {
    String title = 'Halo',
    String artist = 'Beyonce',
    String? album = 'I Am Sasha Fierce',
    int? duration = 224,
    ExternalMetadataEntityKind kind = ExternalMetadataEntityKind.track,
  }) {
    return ExternalMetadataCandidate(
      provider: ExternalMetadataProviderKind.musicBrainz,
      entityKind: kind,
      providerEntityId: id,
      displayName: title,
      artistCredits: artist.isEmpty
          ? const []
          : [ExternalMetadataArtistCredit(name: artist)],
      releaseTitle: album,
      durationSeconds: duration,
    );
  }

  group('ExternalMetadataCandidateRankingService', () {
    test('empty candidates produce no recommendation', () {
      final result = service.rank(query: query, candidates: []);

      expect(result.candidates, isEmpty);
      expect(result.bestCandidate, isNull);
      expect(result.hasResults, isFalse);
      expect(result.isAmbiguous, isFalse);
      expect(result.requiresCarefulReview, isTrue);
    });

    test('stronger candidate ranks before weaker candidate', () {
      final result = service.rank(
        query: query,
        candidates: [
          candidate('weak', artist: 'Different Artist'),
          candidate('strong'),
        ],
      );

      expect(result.bestCandidate?.candidate.providerEntityId, 'strong');
      expect(result.isAmbiguous, isFalse);
    });

    test('exact ranking ties preserve provider order', () {
      final result = service.rank(
        query: query,
        candidates: [candidate('first'), candidate('second')],
      );

      expect(result.candidates.map((item) => item.candidate.providerEntityId), [
        'first',
        'second',
      ]);
    });

    test('distinct identities with identical scores are ambiguous', () {
      final result = service.rank(
        query: query,
        candidates: [candidate('recording-1'), candidate('recording-2')],
      );

      expect(result.isAmbiguous, isTrue);
      expect(result.ambiguityReasons, isNotEmpty);
      expect(result.requiresCarefulReview, isTrue);
    });

    test('duplicate provider identities are not competing matches', () {
      final result = service.rank(
        query: query,
        candidates: [candidate('recording-1'), candidate('recording-1')],
      );

      expect(result.isAmbiguous, isFalse);
    });

    test('close competitors are considered ambiguous', () {
      final result = service.rank(
        query: query,
        candidates: [candidate('leader'), candidate('close', duration: 230)],
      );

      expect(result.isAmbiguous, isTrue);
    });

    test('clearly weaker competitor does not trigger ambiguity', () {
      final result = service.rank(
        query: query,
        candidates: [
          candidate('leader'),
          candidate('weak', artist: 'Different Artist'),
        ],
      );

      expect(result.isAmbiguous, isFalse);
    });

    test('sufficient evidence outranks a sparse perfect match', () {
      final result = service.rank(
        query: query,
        candidates: [
          candidate('sparse', artist: '', album: null, duration: null),
          candidate('complete', duration: 230),
        ],
      );

      expect(result.bestCandidate?.candidate.providerEntityId, 'complete');
    });

    test('incompatible candidates rank below compatible ones', () {
      final result = service.rank(
        query: query,
        candidates: [
          candidate('album-1', kind: ExternalMetadataEntityKind.album),
          candidate('recording-1'),
        ],
      );

      expect(result.bestCandidate?.candidate.providerEntityId, 'recording-1');
      expect(result.candidates.last.evaluation.comparable, isFalse);
    });

    test('weak but supported candidate remains available for review', () {
      final result = service.rank(
        query: query,
        candidates: [
          candidate(
            'weak-recording',
            title: 'Different Title',
            artist: 'Beyonce',
            album: 'Different Album',
            duration: 310,
          ),
        ],
      );

      expect(result.hasResults, isTrue);
      expect(result.bestCandidate, isNotNull);
      expect(result.bestCandidate!.evaluation.score, 30);
      expect(result.bestCandidate!.evaluation.evidenceCoverage, 100);
      expect(result.requiresCarefulReview, isTrue);
    });
    test('zero-evidence candidates are not recommended', () {
      const emptyQuery = ExternalMetadataSearchQuery(
        entityKind: ExternalMetadataEntityKind.track,
      );

      final result = service.rank(
        query: emptyQuery,
        candidates: [candidate('recording-without-evidence')],
      );

      expect(result.hasResults, isTrue);
      expect(result.candidates.single.evaluation.comparable, isTrue);
      expect(result.candidates.single.evaluation.evidenceCoverage, 0);
      expect(result.bestCandidate, isNull);
      expect(result.requiresCarefulReview, isTrue);
    });
    test('all-incompatible results have no valid best candidate', () {
      final result = service.rank(
        query: query,
        candidates: [
          candidate('album-1', kind: ExternalMetadataEntityKind.album),
        ],
      );

      expect(result.hasResults, isTrue);
      expect(result.bestCandidate, isNull);
      expect(result.requiresCarefulReview, isTrue);
    });
  });
}

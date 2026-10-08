import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/library/application/models/external_metadata_candidate.dart';
import 'package:sonus_next/features/library/application/models/external_metadata_match_evaluation.dart';
import 'package:sonus_next/features/library/application/models/external_metadata_search_query.dart';
import 'package:sonus_next/features/library/application/services/external_metadata_confidence_evaluator.dart';

void main() {
  const evaluator = ExternalMetadataConfidenceEvaluator();

  const trackQuery = ExternalMetadataSearchQuery(
    entityKind: ExternalMetadataEntityKind.track,
    title: 'Halo',
    artistName: 'Beyonce',
    albumTitle: 'I Am Sasha Fierce',
    durationSeconds: 224,
  );

  ExternalMetadataCandidate trackCandidate({
    String title = 'Halo',
    String artist = 'Beyonce',
    String? album = 'I Am Sasha Fierce',
    int? duration = 224,
  }) {
    return ExternalMetadataCandidate(
      provider: ExternalMetadataProviderKind.musicBrainz,
      entityKind: ExternalMetadataEntityKind.track,
      providerEntityId: 'recording-1',
      displayName: title,
      artistCredits: artist.isEmpty
          ? const []
          : [ExternalMetadataArtistCredit(name: artist)],
      releaseTitle: album,
      durationSeconds: duration,
    );
  }

  group('ExternalMetadataConfidenceEvaluator', () {
    test('exact track match has full score and coverage', () {
      final result = evaluator.evaluate(
        query: trackQuery,
        candidate: trackCandidate(),
      );

      expect(result.comparable, isTrue);
      expect(result.score, 100);
      expect(result.evidenceCoverage, 100);
      expect(result.isStrongMatch, isTrue);
      expect(result.signals, hasLength(4));
    });

    test('wrong artist reduces confidence', () {
      final result = evaluator.evaluate(
        query: trackQuery,
        candidate: trackCandidate(artist: 'Different Artist'),
      );

      expect(result.score, 70);
      expect(result.isStrongMatch, isFalse);
      expect(
        result.signals[1].status,
        ExternalMetadataMatchSignalStatus.mismatch,
      );
    });

    test('wrong album reduces confidence', () {
      final result = evaluator.evaluate(
        query: trackQuery,
        candidate: trackCandidate(album: 'Different Release'),
      );

      expect(result.score, 85);
      expect(
        result.signals[2].status,
        ExternalMetadataMatchSignalStatus.mismatch,
      );
    });

    test('three-second duration difference counts as matching', () {
      final result = evaluator.evaluate(
        query: trackQuery,
        candidate: trackCandidate(duration: 227),
      );

      expect(result.score, 100);
      expect(result.signals[3].status, ExternalMetadataMatchSignalStatus.match);
    });

    test('substantial duration difference reduces confidence', () {
      final result = evaluator.evaluate(
        query: trackQuery,
        candidate: trackCandidate(duration: 310),
      );

      expect(result.score, 85);
      expect(
        result.signals[3].status,
        ExternalMetadataMatchSignalStatus.mismatch,
      );
    });

    test('missing candidate evidence reduces coverage, not similarity', () {
      final result = evaluator.evaluate(
        query: trackQuery,
        candidate: trackCandidate(artist: '', album: null, duration: null),
      );

      expect(result.score, 100);
      expect(result.evidenceCoverage, 40);
      expect(result.hasSufficientEvidence, isFalse);
      expect(result.isStrongMatch, isFalse);
      expect(result.requiresCarefulReview, isTrue);
    });

    test('different entity kinds are not comparable', () {
      const candidate = ExternalMetadataCandidate(
        provider: ExternalMetadataProviderKind.musicBrainz,
        entityKind: ExternalMetadataEntityKind.album,
        providerEntityId: 'release-group-1',
        displayName: 'Halo',
      );

      final result = evaluator.evaluate(
        query: trackQuery,
        candidate: candidate,
      );

      expect(result.comparable, isFalse);
      expect(result.score, 0);
      expect(result.evidenceCoverage, 0);
      expect(result.requiresCarefulReview, isTrue);
    });

    test('artist-only search normalizes its available weight', () {
      const query = ExternalMetadataSearchQuery(
        entityKind: ExternalMetadataEntityKind.artist,
        artistName: 'Beyonce',
      );
      const candidate = ExternalMetadataCandidate(
        provider: ExternalMetadataProviderKind.musicBrainz,
        entityKind: ExternalMetadataEntityKind.artist,
        providerEntityId: 'artist-1',
        displayName: 'Beyonce',
      );

      final result = evaluator.evaluate(query: query, candidate: candidate);

      expect(result.score, 100);
      expect(result.evidenceCoverage, 100);
      expect(result.isStrongMatch, isTrue);
    });

    test('accented album titles normalize consistently', () {
      const query = ExternalMetadataSearchQuery(
        entityKind: ExternalMetadataEntityKind.album,
        albumTitle: 'Motomami',
        artistName: 'Rosalia',
      );

      const candidate = ExternalMetadataCandidate(
        provider: ExternalMetadataProviderKind.musicBrainz,
        entityKind: ExternalMetadataEntityKind.album,
        providerEntityId: 'album-accented',
        displayName: 'MOTOMAMI',
        artistCredits: [ExternalMetadataArtistCredit(name: 'Rosalía')],
      );

      final result = evaluator.evaluate(query: query, candidate: candidate);

      expect(result.score, 100);
      expect(result.evidenceCoverage, 100);
      expect(result.isStrongMatch, isTrue);
    });

    test('primary artist remains recognizable in collaborative credits', () {
      const query = ExternalMetadataSearchQuery(
        entityKind: ExternalMetadataEntityKind.track,
        title: 'Collaboration',
        artistName: 'Beyonce',
        durationSeconds: 240,
      );

      const candidate = ExternalMetadataCandidate(
        provider: ExternalMetadataProviderKind.musicBrainz,
        entityKind: ExternalMetadataEntityKind.track,
        providerEntityId: 'collaboration-recording',
        displayName: 'Collaboration',
        artistCredits: [
          ExternalMetadataArtistCredit(name: 'Beyoncé', joinPhrase: ' & '),
          ExternalMetadataArtistCredit(name: 'Another Artist'),
        ],
        durationSeconds: 240,
      );

      final result = evaluator.evaluate(query: query, candidate: candidate);

      expect(result.signals[1].status, ExternalMetadataMatchSignalStatus.match);
      expect(result.score, 100);
      expect(result.evidenceCoverage, 85);
    });
    test('accented artist names normalize consistently', () {
      const query = ExternalMetadataSearchQuery(
        entityKind: ExternalMetadataEntityKind.artist,
        artistName: 'Beyonce',
      );
      const candidate = ExternalMetadataCandidate(
        provider: ExternalMetadataProviderKind.musicBrainz,
        entityKind: ExternalMetadataEntityKind.artist,
        providerEntityId: 'artist-1',
        displayName: 'Beyoncé',
      );

      final result = evaluator.evaluate(query: query, candidate: candidate);

      expect(result.score, 100);
      expect(result.evidenceCoverage, 100);
    });
  });
}

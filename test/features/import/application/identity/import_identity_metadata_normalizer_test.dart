import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/import/application/identity/import_identity_metadata_normalizer.dart';
import 'package:sonus_next/features/import/domain/models/audio_metadata.dart';
import 'package:sonus_next/features/import/domain/models/import_candidate.dart';

void main() {
  const normalizer = ImportIdentityMetadataNormalizer();

  ImportCandidate candidate({String folderArtist = 'Beyoncé'}) {
    return ImportCandidate(
      filePath: r'C:\Music\track.mp3',
      normalizedPath: 'c:/music/track.mp3',
      discoveredAt: DateTime.utc(2026, 10, 1),
      metadataFallbackPath: '$folderArtist/Album/01 Song.mp3',
      structure: ImportCandidateStructure.artistAlbum,
    );
  }

  AudioMetadata metadata({
    required String artistName,
    List<String> featuredArtists = const [],
  }) {
    return AudioMetadata(
      title: 'Song',
      artistName: artistName,
      albumTitle: 'Album',
      durationSeconds: 200,
      trackNumber: 1,
      discNumber: 1,
      isSingle: false,
      featuredArtists: featuredArtists,
    );
  }

  test('extracts explicit feat credit without creating composite Artist', () {
    final result = normalizer.normalize(
      candidate: candidate(),
      metadata: metadata(artistName: 'Beyoncé feat. Jack White'),
    );

    expect(result.artistName, 'Beyoncé');
    expect(result.albumArtistName, 'Beyoncé');
    expect(result.featuredArtists, ['Jack White']);
  });

  test('extracts bracketed Ft. credit', () {
    final result = normalizer.normalize(
      candidate: candidate(),
      metadata: metadata(artistName: 'Beyoncé [Ft. Jack White]'),
    );

    expect(result.artistName, 'Beyoncé');
    expect(result.albumArtistName, 'Beyoncé');
    expect(result.featuredArtists, ['Jack White']);
  });

  test('extracts parenthesized featuring credit', () {
    final result = normalizer.normalize(
      candidate: candidate(),
      metadata: metadata(artistName: 'Beyoncé (featuring Jack White)'),
    );

    expect(result.artistName, 'Beyoncé');
    expect(result.featuredArtists, ['Jack White']);
  });

  test('does not split arbitrary ampersand artist credit', () {
    final result = normalizer.normalize(
      candidate: candidate(folderArtist: 'Beyoncé'),
      metadata: metadata(artistName: 'Beyoncé & Jay-Z'),
    );

    expect(result.artistName, 'Beyoncé & Jay-Z');
    expect(result.albumArtistName, 'Beyoncé');
    expect(result.featuredArtists, isEmpty);
  });

  test('detects folder-backed ambiguous ampersand credit', () {
    final rawCredit = normalizer.ambiguousSeparatorArtistCredit(
      candidate: candidate(folderArtist: 'Beyoncé'),
      metadata: metadata(artistName: 'Beyoncé & Jay-Z'),
    );

    expect(rawCredit, 'Beyoncé & Jay-Z');
  });

  test('does not flag legitimate ampersand group matching its folder', () {
    final rawCredit = normalizer.ambiguousSeparatorArtistCredit(
      candidate: candidate(folderArtist: 'Simon & Garfunkel'),
      metadata: metadata(artistName: 'Simon & Garfunkel'),
    );

    expect(rawCredit, isNull);
  });
  test('deduplicates explicit feature against structured feature metadata', () {
    final result = normalizer.normalize(
      candidate: candidate(),
      metadata: metadata(
        artistName: 'Beyoncé ft. Jack White',
        featuredArtists: const ['Jack White'],
      ),
    );

    expect(result.featuredArtists, ['Jack White']);
  });
}

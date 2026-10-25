import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/import/application/identity/recording_evidence.dart';
import 'package:sonus_next/features/import/domain/models/audio_metadata.dart';
import 'package:sonus_next/features/library/domain/entities/song.dart';

void main() {
  final now = DateTime.utc(2026, 10, 25);

  Song song({int seconds = 200, List<String> featured = const []}) => Song(
    id: 'song',
    artistId: 'artist',
    albumId: 'album',
    albumEditionId: 'edition',
    title: 'ErrTime',
    canonicalTitle: 'errtime',
    trackNumber: 1,
    durationSeconds: seconds,
    isSingle: false,
    featuredArtists: featured,
    createdAt: now,
    updatedAt: now,
  );

  AudioMetadata file({int seconds = 200, List<String> featured = const []}) =>
      AudioMetadata(
        title: 'ErrTime',
        artistName: 'Cardi B',
        albumTitle: 'Album',
        durationSeconds: seconds,
        trackNumber: 1,
        discNumber: 1,
        isSingle: false,
        featuredArtists: featured,
      );

  bool distinct(Song s, AudioMetadata m) =>
      RecordingEvidence.distinguishes(s, m);

  test('short tracks allow three seconds', () {
    expect(distinct(song(seconds: 146), file(seconds: 149)), isFalse);
    expect(distinct(song(seconds: 146), file(seconds: 150)), isTrue);
  });

  test('long tracks allow two percent', () {
    // 2% of 600 s is 12 s.
    expect(distinct(song(seconds: 600), file(seconds: 611)), isFalse);
    expect(distinct(song(seconds: 600), file(seconds: 613)), isTrue);
  });

  test('an unknown duration on either side is not evidence', () {
    expect(distinct(song(seconds: 0), file(seconds: 196)), isFalse);
    expect(distinct(song(seconds: 146), file(seconds: 0)), isFalse);
  });

  test('featured artists compare by name, ignoring case and order', () {
    expect(
      distinct(
        song(featured: ['GloRilla', 'Offset']),
        file(featured: ['offset', 'GLORILLA']),
      ),
      isFalse,
    );
    expect(distinct(song(), file(featured: ['GloRilla'])), isTrue);
    expect(distinct(song(featured: ['A']), file(featured: ['B'])), isTrue);
  });
}

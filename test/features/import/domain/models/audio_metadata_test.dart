import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/import/domain/models/audio_metadata.dart';

void main() {
  test('stores structured metadata without encoding identities', () {
    final metadata = AudioMetadata(
      title: 'Song',
      artistName: 'Artist',
      albumTitle: 'Album',
      durationSeconds: 240,
      trackNumber: 3,
      discNumber: 1,
      isSingle: false,
      featuredArtists: const ['Guest One', 'Guest Two'],
      releaseDate: DateTime.utc(2026, 1, 1),
      genre: 'Pop',
    );

    expect(metadata.title, 'Song');
    expect(metadata.artistName, 'Artist');
    expect(metadata.albumTitle, 'Album');
    expect(metadata.durationSeconds, 240);
    expect(metadata.trackNumber, 3);
    expect(metadata.discNumber, 1);
    expect(metadata.featuredArtists, ['Guest One', 'Guest Two']);
  });
}

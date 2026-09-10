import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/import/data/services/path_fallback_metadata_reader.dart';
import 'package:sonus_next/features/import/domain/models/import_candidate.dart';

void main() {
  const reader = PathFallbackMetadataReader();

  test('derives artist album title and track from folder path', () async {
    final candidate = ImportCandidate(
      filePath: r'C:\Music\Artist Name\Album Name\03 Song Title.mp3',
      normalizedPath: 'c:/music/artist name/album name/03 song title.mp3',
      discoveredAt: DateTime.utc(2026, 9, 10),
    );

    final metadata = await reader.read(candidate);

    expect(metadata.artistName, 'artist name');
    expect(metadata.albumTitle, 'album name');
    expect(metadata.title, 'song title');
    expect(metadata.trackNumber, 3);
    expect(metadata.discNumber, 1);
    expect(metadata.durationSeconds, 0);
  });

  test('uses unknown values when parent folders are unavailable', () async {
    final candidate = ImportCandidate(
      filePath: 'song.mp3',
      normalizedPath: 'song.mp3',
      discoveredAt: DateTime.utc(2026, 9, 10),
    );

    final metadata = await reader.read(candidate);

    expect(metadata.artistName, 'Unknown Artist');
    expect(metadata.albumTitle, 'Unknown Album');
    expect(metadata.title, 'song');
  });

  test('rejects empty normalized path', () async {
    final candidate = ImportCandidate(
      filePath: '',
      normalizedPath: '',
      discoveredAt: DateTime.utc(2026, 9, 10),
    );

    expect(() => reader.read(candidate), throwsA(isA<FormatException>()));
  });
}

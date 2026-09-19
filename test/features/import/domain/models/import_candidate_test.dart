import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/import/domain/models/import_candidate.dart';

void main() {
  test('candidate identity is based on normalized path', () {
    final now = DateTime.utc(2026, 9, 10);

    final first = ImportCandidate(
      filePath: r'C:\Music\Artist\Album\Song.mp3',
      normalizedPath: 'c:/music/artist/album/song.mp3',
      discoveredAt: now,
    );

    final second = ImportCandidate(
      filePath: r'C:\MUSIC\ARTIST\ALBUM\SONG.MP3',
      normalizedPath: 'c:/music/artist/album/song.mp3',
      discoveredAt: now,
    );

    expect(first, second);
    expect(first.hashCode, second.hashCode);
  });

  test('copyWith preserves candidate structure unless explicitly changed', () {
    final now = DateTime.utc(2026, 9, 10);

    final original = ImportCandidate(
      filePath: r'C:\Music\Rags\Song.mp3',
      normalizedPath: 'c:/music/rags/song.mp3',
      discoveredAt: now,
      structure: ImportCandidateStructure.looseAlbum,
    );

    final rescanned = original.copyWith(
      discoveredAt: now.add(const Duration(minutes: 5)),
      sourceId: 'source-1',
    );

    expect(rescanned.structure, ImportCandidateStructure.looseAlbum);
    expect(rescanned.sourceId, 'source-1');

    final changed = rescanned.copyWith(
      structure: ImportCandidateStructure.artistAlbum,
    );

    expect(changed.structure, ImportCandidateStructure.artistAlbum);
  });
  test('different normalized paths are different candidates', () {
    final now = DateTime.utc(2026, 9, 10);

    final first = ImportCandidate(
      filePath: r'C:\Music\Song.mp3',
      normalizedPath: 'c:/music/song.mp3',
      discoveredAt: now,
    );

    final second = ImportCandidate(
      filePath: r'D:\Music\Song.mp3',
      normalizedPath: 'd:/music/song.mp3',
      discoveredAt: now,
    );

    expect(first, isNot(second));
  });
}

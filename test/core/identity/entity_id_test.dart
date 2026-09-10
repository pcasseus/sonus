import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/identity/entity_id.dart';
import 'package:sonus_next/core/identity/text_normalizer.dart';

void main() {
  group('EntityId', () {
    test('creates unique permanent artist IDs', () {
      final first = EntityId.artist();
      final second = EntityId.artist();

      expect(first, startsWith('artist_'));
      expect(second, startsWith('artist_'));
      expect(first, isNot(second));
    });

    test('creates unique permanent song IDs', () {
      final first = EntityId.song();
      final second = EntityId.song();

      expect(first, startsWith('song_'));
      expect(second, startsWith('song_'));
      expect(first, isNot(second));
    });

    test('song identity is not based on a file path', () {
      final id = EntityId.song();

      expect(id, isNot(contains('/music/')));
      expect(id, startsWith('song_'));
    });
  });

  group('TextNormalizer', () {
    test('canonicalizes text without making it an identity', () {
      expect(TextNormalizer.canonicalize('  Taylor   Swift  '), 'taylor swift');
    });

    test('normalizes Windows paths for comparison', () {
      expect(
        TextNormalizer.normalizePath(r'C:\Music\Artist\Song.mp3'),
        'c:/music/artist/song.mp3',
      );
    });
  });
}

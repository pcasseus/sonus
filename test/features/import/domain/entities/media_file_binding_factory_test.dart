import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/import/domain/entities/media_file_binding_factory.dart';

void main() {
  group('MediaFileBindingFactory', () {
    final now = DateTime.utc(2026, 9, 10, 12);

    test('creates binding with permanent ID', () {
      final binding = MediaFileBindingFactory.create(
        songId: 'song_test',
        filePath: r'C:\Music\Artist\Album\Song.mp3',
        now: now,
      );

      expect(binding.id, startsWith('media_'));
      expect(binding.songId, 'song_test');
      expect(binding.createdAt, now);
      expect(binding.updatedAt, now);
    });

    test('normalizes local path without changing song identity', () {
      final binding = MediaFileBindingFactory.create(
        songId: 'song_permanent',
        filePath: r'C:\Music\Artist\Album\Song.mp3',
        now: now,
      );

      expect(binding.normalizedPath, 'c:/music/artist/album/song.mp3');
      expect(binding.songId, 'song_permanent');
    });

    test('two bindings can point to the same permanent song', () {
      final first = MediaFileBindingFactory.create(
        songId: 'song_permanent',
        filePath: r'C:\Music\Song.mp3',
        now: now,
      );

      final second = MediaFileBindingFactory.create(
        songId: 'song_permanent',
        filePath: r'D:\Backup\Song.mp3',
        now: now,
      );

      expect(first.songId, second.songId);
      expect(first.id, isNot(second.id));
      expect(first.normalizedPath, isNot(second.normalizedPath));
    });

    test('tracks availability separately from permanent song identity', () {
      final binding = MediaFileBindingFactory.create(
        songId: 'song_permanent',
        filePath: r'C:\Music\Song.mp3',
        isAvailable: false,
        now: now,
      );

      expect(binding.songId, 'song_permanent');
      expect(binding.isAvailable, isFalse);
    });

    test('defaults last seen time to creation time', () {
      final binding = MediaFileBindingFactory.create(
        songId: 'song_test',
        filePath: r'C:\Music\Song.mp3',
        now: now,
      );

      expect(binding.lastSeenAt, now);
    });
  });
}

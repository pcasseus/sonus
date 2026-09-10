import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/import/domain/entities/media_file_binding_factory.dart';

void main() {
  group('MediaFileBinding identity', () {
    final now = DateTime.utc(2026, 9, 10);

    test('moving a file does not change binding identity', () {
      final binding = MediaFileBindingFactory.create(
        songId: 'song_permanent',
        filePath: r'C:\Music\Song.mp3',
        now: now,
      );

      final moved = binding.copyWith(
        filePath: r'D:\Music\Song.mp3',
        normalizedPath: 'd:/music/song.mp3',
      );

      expect(moved.id, binding.id);
      expect(moved.songId, binding.songId);
      expect(moved, binding);
    });

    test('nullable file metadata can be cleared', () {
      final binding = MediaFileBindingFactory.create(
        songId: 'song_permanent',
        filePath: r'C:\Music\Song.mp3',
        fileSizeBytes: 123456,
        modifiedAt: DateTime.utc(2026, 9, 1),
        now: now,
      );

      final cleared = binding.copyWith(
        lastSeenAt: null,
        fileSizeBytes: null,
        modifiedAt: null,
      );

      expect(cleared.lastSeenAt, isNull);
      expect(cleared.fileSizeBytes, isNull);
      expect(cleared.modifiedAt, isNull);
    });
  });
}

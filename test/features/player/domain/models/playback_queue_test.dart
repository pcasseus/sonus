import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/player/domain/models/playback_queue.dart';
import 'package:sonus_next/features/player/domain/models/playback_track.dart';

void main() {
  PlaybackTrack track(String id) {
    return PlaybackTrack(
      songId: id,
      title: id,
      artistId: 'artist_1',
      artistName: 'Artist',
      albumId: 'album_1',
      albumTitle: 'Album',
      filePath: 'C:/Music/$id.mp3',
      duration: const Duration(minutes: 3),
    );
  }

  test('empty queue has no current track', () {
    const queue = PlaybackQueue();

    expect(queue.isEmpty, isTrue);
    expect(queue.currentTrack, isNull);
    expect(queue.hasNext, isFalse);
    expect(queue.hasPrevious, isFalse);
  });

  test('replace establishes requested starting track', () {
    final queue = const PlaybackQueue().replace(
      tracks: [track('song_1'), track('song_2'), track('song_3')],
      startIndex: 1,
    );

    expect(queue.currentIndex, 1);
    expect(queue.currentTrack?.songId, 'song_2');
    expect(queue.hasPrevious, isTrue);
    expect(queue.hasNext, isTrue);
  });

  test('moves forward and backward deterministically', () {
    var queue = const PlaybackQueue().replace(
      tracks: [track('song_1'), track('song_2'), track('song_3')],
    );

    queue = queue.moveNext();

    expect(queue.currentTrack?.songId, 'song_2');

    queue = queue.movePrevious();

    expect(queue.currentTrack?.songId, 'song_1');
  });

  test('does not move beyond queue boundaries', () {
    final first = const PlaybackQueue().replace(
      tracks: [track('song_1'), track('song_2')],
    );

    expect(first.movePrevious().currentIndex, 0);

    final last = first.moveTo(1);

    expect(last.moveNext().currentIndex, 1);
  });

  test('rejects invalid start index', () {
    expect(
      () => const PlaybackQueue().replace(
        tracks: [track('song_1')],
        startIndex: 4,
      ),
      throwsRangeError,
    );
  });

  test('insert before current track preserves current identity', () {
    final queue = const PlaybackQueue().replace(
      tracks: [track('song_1'), track('song_2'), track('song_3')],
      startIndex: 1,
    );

    final updated = queue.insertTrack(track('inserted'), index: 1);

    expect(updated.tracks.map((track) => track.songId), [
      'song_1',
      'inserted',
      'song_2',
      'song_3',
    ]);

    expect(updated.currentTrack?.songId, 'song_2');
    expect(updated.currentIndex, 2);
  });

  test('remove before current track preserves current identity', () {
    final queue = const PlaybackQueue().replace(
      tracks: [track('song_1'), track('song_2'), track('song_3')],
      startIndex: 2,
    );

    final updated = queue.removeTrackAt(0);

    expect(updated.tracks.map((track) => track.songId), ['song_2', 'song_3']);

    expect(updated.currentTrack?.songId, 'song_3');
    expect(updated.currentIndex, 1);
  });

  test('moving current track updates current index', () {
    final queue = const PlaybackQueue().replace(
      tracks: [track('song_1'), track('song_2'), track('song_3')],
      startIndex: 1,
    );

    final updated = queue.moveTrack(oldIndex: 1, newIndex: 2);

    expect(updated.tracks.map((track) => track.songId), [
      'song_1',
      'song_3',
      'song_2',
    ]);

    expect(updated.currentTrack?.songId, 'song_2');
    expect(updated.currentIndex, 2);
  });
}

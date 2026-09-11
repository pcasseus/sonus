import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/player/domain/models/playback_track.dart';

void main() {
  test('playback identity follows permanent song id', () {
    const first = PlaybackTrack(
      songId: 'song_1',
      title: 'Track',
      artistId: 'artist_1',
      artistName: 'Artist',
      albumId: 'album_1',
      albumTitle: 'Album',
      filePath: r'C:\Music\Track.mp3',
      duration: Duration(minutes: 3),
    );

    const moved = PlaybackTrack(
      songId: 'song_1',
      title: 'Track',
      artistId: 'artist_1',
      artistName: 'Artist',
      albumId: 'album_1',
      albumTitle: 'Album',
      filePath: r'D:\Music\Track.mp3',
      duration: Duration(minutes: 3),
    );

    expect(first, moved);
    expect(first.hashCode, moved.hashCode);
  });

  test('reports whether media path is playable', () {
    const available = PlaybackTrack(
      songId: 'song_1',
      title: 'Track',
      artistId: 'artist_1',
      artistName: 'Artist',
      albumId: 'album_1',
      albumTitle: 'Album',
      filePath: r'C:\Music\Track.mp3',
      duration: Duration(minutes: 3),
    );

    const missing = PlaybackTrack(
      songId: 'song_2',
      title: 'Missing',
      artistId: 'artist_1',
      artistName: 'Artist',
      albumId: 'album_1',
      albumTitle: 'Album',
      filePath: '',
      duration: Duration(minutes: 3),
    );

    expect(available.hasPlayablePath, isTrue);
    expect(missing.hasPlayablePath, isFalse);
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/player/application/mappers/library_track_playback_mapper.dart';

void main() {
  LibraryTrack libraryTrack({
    String songId = 'song_1',
    String? filePath = r'C:\Music\Track.mp3',
    bool isAvailable = true,
  }) {
    return LibraryTrack(
      songId: songId,
      title: 'Track',
      artistId: 'artist_1',
      artistName: 'Artist',
      albumId: 'album_1',
      albumTitle: 'Album',
      albumEditionId: 'edition_1',
      albumEditionTitle: 'Album',
      albumEditionType: AlbumEditionType.standard,
      trackNumber: 1,
      durationSeconds: 245,
      isSingle: false,
      featuredArtists: const [],
      dateAdded: DateTime.utc(2026, 9, 11),
      filePath: filePath,
      isAvailable: isAvailable,
    );
  }

  test('maps permanent library identity into playback track', () {
    final playbackTrack = LibraryTrackPlaybackMapper.toPlaybackTrack(
      libraryTrack(),
    );

    expect(playbackTrack.songId, 'song_1');
    expect(playbackTrack.artistId, 'artist_1');
    expect(playbackTrack.albumId, 'album_1');
  });

  test('maps library metadata required for playback display', () {
    final playbackTrack = LibraryTrackPlaybackMapper.toPlaybackTrack(
      libraryTrack(),
    );

    expect(playbackTrack.title, 'Track');
    expect(playbackTrack.artistName, 'Artist');
    expect(playbackTrack.albumTitle, 'Album');
    expect(playbackTrack.duration, const Duration(seconds: 245));
  });

  test('maps missing file path to empty playback path', () {
    final playbackTrack = LibraryTrackPlaybackMapper.toPlaybackTrack(
      libraryTrack(filePath: null, isAvailable: false),
    );

    expect(playbackTrack.filePath, isEmpty);
    expect(playbackTrack.hasPlayablePath, isFalse);
  });

  test('maps multiple library tracks preserving order', () {
    final tracks = LibraryTrackPlaybackMapper.toPlaybackTracks([
      libraryTrack(songId: 'song_1'),
      libraryTrack(songId: 'song_2'),
      libraryTrack(songId: 'song_3'),
    ]);

    expect(tracks.map((track) => track.songId), ['song_1', 'song_2', 'song_3']);
  });
}

import '../../../library/application/models/library_track.dart';
import '../../domain/models/playback_track.dart';

abstract final class LibraryTrackPlaybackMapper {
  static PlaybackTrack toPlaybackTrack(LibraryTrack track) {
    return PlaybackTrack(
      songId: track.songId,
      title: track.title,
      artistId: track.artistId,
      artistName: track.artistName,
      albumId: track.albumId,
      albumTitle: track.albumTitle,
      albumEditionId: track.albumEditionId,
      albumEditionTitle: track.albumEditionTitle,
      artworkId: track.artworkId,
      artworkPath: track.artworkPath,
      filePath: track.filePath ?? '',
      duration: Duration(seconds: track.durationSeconds),
    );
  }

  static List<PlaybackTrack> toPlaybackTracks(Iterable<LibraryTrack> tracks) {
    return tracks.map(toPlaybackTrack).toList(growable: false);
  }
}

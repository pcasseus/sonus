import '../../domain/entities/playlist.dart';
import 'playlist_track.dart';

class PlaylistDetail {
  const PlaylistDetail({required this.playlist, required this.tracks});

  final Playlist playlist;
  final List<PlaylistTrack> tracks;

  int get trackCount => tracks.length;
}

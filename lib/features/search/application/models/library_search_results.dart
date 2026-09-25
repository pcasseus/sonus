import '../../../library/application/models/library_album.dart';
import '../../../library/application/models/library_artist.dart';
import '../../../library/application/models/library_track.dart';

class LibrarySearchResults {
  const LibrarySearchResults({
    this.artists = const [],
    this.albums = const [],
    this.tracks = const [],
  });

  final List<LibraryArtist> artists;
  final List<LibraryAlbum> albums;
  final List<LibraryTrack> tracks;

  bool get isEmpty {
    return artists.isEmpty && albums.isEmpty && tracks.isEmpty;
  }

  bool get isNotEmpty => !isEmpty;

  int get totalCount => artists.length + albums.length + tracks.length;
}

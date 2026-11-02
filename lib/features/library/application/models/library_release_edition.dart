import 'library_album_edition.dart';

/// An edition with the number of songs listed on it, as its edition view
/// lists them: each song once, and only songs of the edition's own
/// release. Used to choose how a release is presented at album level.
class LibraryReleaseEdition {
  const LibraryReleaseEdition({
    required this.edition,
    required this.trackCount,
  });

  final LibraryAlbumEdition edition;
  final int trackCount;
}

import '../../../library/application/models/library_album.dart';
import '../../../library/application/models/library_release_edition.dart';
import '../../../library/application/models/library_track.dart';
import '../../../library/domain/entities/library_organization.dart';
import '../../../library/domain/entities/song_single_presentation.dart';
import '../../domain/moments/new_release_eligibility.dart';

/// Release classifications new-release debuts check (App Update 1.3): the
/// stated release kind (soundtrack, cast recording, compilation) and live
/// flag, by album id. Read-only.
class NewReleaseClassifications {
  const NewReleaseClassifications({
    this.kinds = const {},
    this.live = const {},
  });

  final Map<String, ReleaseKind> kinds;
  final Map<String, bool> live;
}

/// Each song's release facts, as NewReleaseEligibility reads them, built
/// from what the library stores. Import or date-added times are never used.
abstract final class NewReleaseLibraryFacts {
  /// [formatOf] gives a release's format as Moments read it: stated, null
  /// while it needs review, otherwise an Album.
  static Map<String, NewReleaseSongFacts> of({
    required Iterable<LibraryTrack> tracks,
    required Map<String, LibraryAlbum> albumsById,
    required ReleaseFormat? Function(String albumId) formatOf,
    required Iterable<LibraryReleaseEdition> editions,
    required Map<String, SongSinglePresentation> singles,
    required NewReleaseClassifications classifications,
  }) {
    final editionsByAlbum = <String, List<NewReleaseEditionFacts>>{};
    for (final release in editions) {
      final edition = release.edition;
      (editionsByAlbum[edition.albumId] ??= []).add(
        NewReleaseEditionFacts.fromStored(
          type: edition.type,
          releaseDate: edition.releaseDate,
          precision: edition.releaseDatePrecision,
          writtenAt: edition.updatedAt,
        ),
      );
    }

    NewReleaseAlbumFacts? albumOf(String albumId) {
      final album = albumsById[albumId];
      if (album == null) return null;
      return NewReleaseAlbumFacts(
        albumId: albumId,
        title: album.title,
        format: formatOf(albumId),
        kind: classifications.kinds[albumId],
        live: classifications.live[albumId],
        editions: List.unmodifiable(editionsByAlbum[albumId] ?? const []),
      );
    }

    return {
      for (final track in tracks)
        track.songId: NewReleaseSongFacts(
          songId: track.songId,
          isSingle: track.isSingle,
          singleReleaseDate: track.isSingle
              ? singles[track.songId]?.releaseDate
              : null,
          singleWrittenAt: track.isSingle
              ? singles[track.songId]?.updatedAt
              : null,
          album: albumOf(track.albumId),
        ),
    };
  }
}

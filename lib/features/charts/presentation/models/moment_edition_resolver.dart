import '../../../library/application/models/library_album.dart';
import '../../../library/application/models/library_album_edition.dart';
import '../../../library/application/models/library_release_edition.dart';
import '../../../library/application/models/library_track.dart';
import '../../../library/application/models/release_display_title.dart';
import '../../../library/application/models/song_edition_membership.dart';
import '../../../library/domain/entities/album_edition.dart';
import '../../../library/domain/entities/release_date.dart';
import 'chart_album_presentation.dart';

/// Which edition, and so which title and cover, a Moment shows
/// (App Update 1.1, Moments B). Presentation only: stored Moments, their
/// words and their chart records are never changed; only the picture and
/// the related release are chosen here, from the library as it is now.
///
/// - A song story shows the edition the song first appeared on
///   ([songEdition]), with that edition's cover ([songCover]).
/// - An album story shows the edition with the most songs
///   ([albumPresentation], the SN-50 rule of [ChartAlbumPresentation]).
///
/// Editions of different releases are never mixed: a song is only ever
/// matched with editions of its own album.
class MomentEditionResolver {
  MomentEditionResolver({
    required Iterable<LibraryReleaseEdition> editions,
    required Iterable<SongEditionMembership> memberships,
  }) : _editionsById = {
         for (final candidate in editions)
           candidate.edition.editionId: candidate.edition,
       },
       _editionIdsBySong = _groupMemberships(memberships);

  /// No editions or memberships known: every song shows its own artwork,
  /// then its album's cover, exactly as before App Update 1.1.
  MomentEditionResolver.empty()
    : this(editions: const [], memberships: const []);

  final Map<String, LibraryAlbumEdition> _editionsById;
  final Map<String, Set<String>> _editionIdsBySong;

  static Map<String, Set<String>> _groupMemberships(
    Iterable<SongEditionMembership> memberships,
  ) {
    final bySong = <String, Set<String>>{};
    for (final membership in memberships) {
      bySong.putIfAbsent(membership.songId, () => {}).add(membership.editionId);
    }
    return bySong;
  }

  /// The edition [track] first appeared on, or null when none is known.
  ///
  /// Candidates are the editions of the song's own album that list it.
  /// When none do (memberships not loaded, or the song is listed nowhere),
  /// the song's home edition (`songs.album_edition_id`) is used if it is
  /// known and of the same album; otherwise null.
  ///
  /// Among the candidates, the earliest release date wins. Dates are used
  /// as stored, with their precision; none is ever invented. The
  /// "possibly earliest" set is every candidate that no other candidate is
  /// certainly earlier than: "2026" and "2026-05-01" may be the same day,
  /// so neither is certainly earlier. If any candidate has no release date,
  /// no order can be trusted and every candidate is possibly earliest.
  ///
  /// When more than one edition is possibly earliest, the fallbacks apply
  /// in order, each narrowing the set only when it leaves someone:
  ///
  /// 1. a non-Deluxe edition (a Standard edition or the primary edition);
  /// 2. the primary edition (`is_primary`, or the album's primary id);
  /// 3. the song's home edition;
  /// 4. the edition added to the library first (oldest dateAdded);
  /// 5. the lowest edition id.
  ///
  /// A standalone single is its own album with its own edition, so the
  /// rule simply picks that edition.
  LibraryAlbumEdition? songEdition(LibraryTrack track, {LibraryAlbum? album}) {
    final candidates = [
      for (final id in _editionIdsBySong[track.songId] ?? const <String>{})
        if (_editionsById[id] case final edition?
            when edition.albumId == track.albumId)
          edition,
    ];

    if (candidates.isEmpty) {
      final home = _editionsById[track.albumEditionId];
      return home != null && home.albumId == track.albumId ? home : null;
    }

    if (candidates.length == 1) return candidates.single;

    var tied = _possiblyEarliest(candidates);
    if (tied.length == 1) return tied.single;

    bool isPrimary(LibraryAlbumEdition edition) =>
        edition.isPrimary ||
        (album != null && edition.editionId == album.primaryEditionId);

    tied = _narrow(
      tied,
      (edition) =>
          edition.type == AlbumEditionType.standard || isPrimary(edition),
    );
    tied = _narrow(tied, isPrimary);
    tied = _narrow(
      tied,
      (edition) => edition.editionId == track.albumEditionId,
    );

    return tied.reduce((a, b) {
      final byAdded = a.dateAdded.compareTo(b.dateAdded);
      if (byAdded != 0) return byAdded < 0 ? a : b;
      return a.editionId.compareTo(b.editionId) <= 0 ? a : b;
    });
  }

  /// The cover a song story shows:
  ///
  /// 1. the cover of the edition the song first appeared on ([songEdition]);
  /// 2. else the song's own artwork as the library shows it outside any
  ///    edition view ([LibraryTrack.artworkPath], SN-50 A-Q12);
  /// 3. else the album's cover ([LibraryAlbum.artworkPath], its primary
  ///    edition's cover);
  /// 4. else null: the placeholder.
  ///
  /// Without a known edition this is exactly the behaviour before App
  /// Update 1.1: the song's own artwork, then the album's cover.
  String? songCover(LibraryTrack track, {LibraryAlbum? album}) =>
      _nonEmpty(songEdition(track, album: album)?.artworkPath) ??
      _nonEmpty(track.artworkPath) ??
      _nonEmpty(album?.artworkPath);

  /// The display title of the edition a song story relates to, or null
  /// when no edition is known. The primary edition reads as the album
  /// does; another edition shows its own title unless that only names its
  /// type, such as "Deluxe" ([releaseDisplayTitle]).
  String? songEditionTitle(LibraryTrack track, {LibraryAlbum? album}) {
    final edition = songEdition(track, album: album);
    if (edition == null) return null;
    if (album != null && edition.editionId == album.primaryEditionId) {
      return album.displayTitle;
    }
    return releaseDisplayTitle(
      baseTitle: album?.title ?? track.albumTitle,
      editionTitle: edition.title,
    );
  }

  /// An album story's title and cover: the edition with the most songs
  /// (ties: the most recent Deluxe, then the primary edition, then the most
  /// recent; see [ChartAlbumPresentation.resolve]).
  static ChartAlbumPresentation albumPresentation(
    LibraryAlbum album,
    Iterable<LibraryReleaseEdition> editions,
  ) => ChartAlbumPresentation.resolve(album, editions);

  static List<LibraryAlbumEdition> _possiblyEarliest(
    List<LibraryAlbumEdition> candidates,
  ) {
    if (candidates.any((edition) => edition.releaseDate == null)) {
      return candidates;
    }

    return [
      for (final edition in candidates)
        if (!candidates.any(
          (other) => _certainlyEarlier(
            other.releaseDateValue!,
            edition.releaseDateValue!,
          ),
        ))
          edition,
    ];
  }

  /// Whether [a] is earlier than [b] whatever days their precision hides.
  static bool _certainlyEarlier(ReleaseDate a, ReleaseDate b) =>
      a.compareTo(b) < 0 && !a.isRefinedBy(b) && !b.isRefinedBy(a);

  static List<LibraryAlbumEdition> _narrow(
    List<LibraryAlbumEdition> editions,
    bool Function(LibraryAlbumEdition edition) test,
  ) {
    final kept = editions.where(test).toList();
    return kept.isEmpty ? editions : kept;
  }

  static String? _nonEmpty(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}

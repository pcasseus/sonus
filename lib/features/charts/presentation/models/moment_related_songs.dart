import '../../../../core/identity/text_normalizer.dart';
import '../../../library/application/models/library_track.dart';

/// The songs a Moment story's Related row suggests (App Update 1.3,
/// REF-1.3-03). It never suggests the story's own recording.
///
/// In order:
///
/// 1. other songs of the same album: first those listed on an edition the
///    story's song is listed on (its "relevant edition"), then the album's
///    other songs, each by disc and track number;
/// 2. only when the album has none: other songs by the same primary artist
///    (`songs.artist_id`), ranked songs first by all-time rank, then by
///    title;
/// 3. otherwise nothing.
///
/// Never suggested: the story's song id; another song that is the same
/// recording (the same music file, or the same title, version and primary
/// artist, such as a duplicate imported on another edition); a song that
/// cannot be played now (blocked, or without an available file); and a
/// second song of a recording already suggested.
abstract final class MomentRelatedSongs {
  static const int defaultLimit = 3;

  static List<LibraryTrack> select({
    required LibraryTrack current,
    required Iterable<LibraryTrack> library,
    Set<String> Function(String songId)? editionsOf,
    int? Function(String songId)? allTimeRankOf,
    int limit = defaultLimit,
  }) {
    if (limit <= 0) return const [];

    final excluded = <String>{_recordingKey(current)};
    final currentFile = _fileKey(current);
    final candidates = [
      for (final track in library)
        if (track.songId != current.songId &&
            !track.isBlocked &&
            track.hasAvailableFile &&
            (currentFile == null || _fileKey(track) != currentFile))
          track,
    ];

    final relevant = editionsOf?.call(current.songId) ?? const <String>{};
    bool onRelevantEdition(LibraryTrack track) =>
        track.albumEditionId == current.albumEditionId ||
        (editionsOf?.call(track.songId) ?? const <String>{}).any(
          relevant.contains,
        );

    final album =
        [
          for (final track in candidates)
            if (track.albumId == current.albumId) track,
        ]..sort((a, b) {
          final byEdition =
              (onRelevantEdition(a) ? 0 : 1) - (onRelevantEdition(b) ? 0 : 1);
          if (byEdition != 0) return byEdition;
          return _byPosition(a, b);
        });

    final fromAlbum = _distinct(album, excluded, limit);
    if (fromAlbum.isNotEmpty) return fromAlbum;

    final artist =
        [
          for (final track in candidates)
            if (track.artistId == current.artistId) track,
        ]..sort((a, b) {
          final rankA = allTimeRankOf?.call(a.songId);
          final rankB = allTimeRankOf?.call(b.songId);
          if (rankA != null && rankB != null && rankA != rankB) {
            return rankA.compareTo(rankB);
          }
          if ((rankA == null) != (rankB == null)) return rankA == null ? 1 : -1;
          return _byTitle(a, b);
        });
    return _distinct(artist, excluded, limit);
  }

  static List<LibraryTrack> _distinct(
    List<LibraryTrack> ordered,
    Set<String> excluded,
    int limit,
  ) {
    final seen = {...excluded};
    final chosen = <LibraryTrack>[];
    for (final track in ordered) {
      if (chosen.length == limit) break;
      if (seen.add(_recordingKey(track))) chosen.add(track);
    }
    return chosen;
  }

  /// The recording a song is, as the library's duplicate rules see it:
  /// title, version and primary artist.
  static String _recordingKey(LibraryTrack track) {
    final characteristics = [
      for (final c in track.versionCharacteristics) c.name,
    ]..sort();
    return [
      track.artistId,
      TextNormalizer.canonicalize(track.title),
      TextNormalizer.canonicalize(track.versionLabel ?? ''),
      characteristics.join(','),
    ].join('\u0000');
  }

  static String? _fileKey(LibraryTrack track) {
    final path = track.filePath?.trim();
    if (path == null || path.isEmpty) return null;
    return TextNormalizer.normalizePath(path);
  }

  static int _byPosition(LibraryTrack a, LibraryTrack b) {
    final byDisc = a.discNumber.compareTo(b.discNumber);
    if (byDisc != 0) return byDisc;
    final byTrack = a.trackNumber.compareTo(b.trackNumber);
    if (byTrack != 0) return byTrack;
    return _byTitle(a, b);
  }

  static int _byTitle(LibraryTrack a, LibraryTrack b) {
    final byTitle = a.title.toLowerCase().compareTo(b.title.toLowerCase());
    if (byTitle != 0) return byTitle;
    return a.songId.compareTo(b.songId);
  }
}

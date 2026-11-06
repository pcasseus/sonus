// ignore_for_file: prefer_initializing_formals

import '../../../../library/application/models/library_artist.dart';
import '../../../../library/application/models/library_track.dart';
import '../../../../library/application/repositories/library_query_repository.dart';
import '../../../domain/entities/playback_session.dart';
import '../../../domain/repositories/playback_session_repository.dart';
import '../../models/pulse/pulse_period_data.dart';

/// Where a ranked item stands in the library now (spec §6, decision 3).
enum PulseEntityStatus {
  /// In the library and playable.
  current,

  /// Blacklisted: still counted, labelled.
  blocked,

  /// In the library but its file can't be played.
  unavailable,

  /// No longer in the library: named from when it was played.
  historical,
}

/// How to show one ranked item.
class PulseEntityInfo {
  const PulseEntityInfo({
    required this.kind,
    required this.id,
    required this.title,
    required this.subtitle,
    required this.artworkPath,
    required this.status,
    this.track,
    this.artistId,
    this.albumId,
  });

  final PulseEntityKind kind;
  final String id;
  final String title;
  final String subtitle;
  final String? artworkPath;
  final PulseEntityStatus status;

  /// The library track, for playback; null for artists, releases and
  /// historical tracks.
  final LibraryTrack? track;

  /// For opening the artist profile.
  final String? artistId;

  /// For opening the release.
  final String? albumId;

  bool get isPlayable =>
      track != null &&
      status == PulseEntityStatus.current &&
      (track!.filePath?.trim().isNotEmpty ?? false);

  /// "BLACKLISTED", "UNAVAILABLE", "HISTORICAL" (the existing Insights
  /// labels), or null.
  String? get badge => switch (status) {
    PulseEntityStatus.current => null,
    PulseEntityStatus.blocked => 'BLACKLISTED',
    PulseEntityStatus.unavailable => 'UNAVAILABLE',
    PulseEntityStatus.historical => 'HISTORICAL',
  };
}

/// Names, artwork and status for a period's ranked items.
class PulseEntityDirectory {
  PulseEntityDirectory(this._entries);

  static final PulseEntityDirectory empty = PulseEntityDirectory(const {});

  final Map<(PulseEntityKind, String), PulseEntityInfo> _entries;

  /// [id]'s info, or a neutral placeholder that never invents a name.
  PulseEntityInfo infoFor(PulseEntityKind kind, String id) =>
      _entries[(kind, id)] ??
      PulseEntityInfo(
        kind: kind,
        id: id,
        title: switch (kind) {
          PulseEntityKind.track => 'Unknown track',
          PulseEntityKind.artist => 'Unknown artist',
          PulseEntityKind.release => 'Unknown release',
        },
        subtitle: '',
        artworkPath: null,
        status: PulseEntityStatus.historical,
      );

  /// The playable library tracks among [songIds], in order.
  List<LibraryTrack> playableTracks(Iterable<String> songIds) => [
    for (final id in songIds)
      if (infoFor(PulseEntityKind.track, id) case final info
          when info.isPlayable)
        info.track!,
  ];
}

/// Loads a period's [PulseEntityDirectory].
abstract interface class PulseDirectoryLoader {
  Future<PulseEntityDirectory> load(PulsePeriodData data);
}

/// Builds a [PulseEntityDirectory] from the library, with names from the
/// latest play in the period for anything no longer in it (the existing
/// Insights rule).
class PulseEntityDirectoryService implements PulseDirectoryLoader {
  const PulseEntityDirectoryService({
    required LibraryQueryRepository library,
    required PlaybackSessionRepository playbackSessions,
    Future<Map<String, String>> Function()? statedReleaseFormats,
  }) : _library = library,
       _playbackSessions = playbackSessions,
       _statedReleaseFormats = statedReleaseFormats;

  final LibraryQueryRepository _library;
  final PlaybackSessionRepository _playbackSessions;

  /// Release formats the person (or an accepted suggestion) stated, as
  /// labels ("EP", "Album") by album id. Releases without a stated format
  /// get no label: Pulse never assumes one.
  final Future<Map<String, String>> Function()? _statedReleaseFormats;

  @override
  Future<PulseEntityDirectory> load(PulsePeriodData data) async {
    final window = data.period.window;
    final tracksFuture = _library.getTracks();
    final artistsFuture = _library.getArtists();
    final albumsFuture = _library.getAlbums();
    final sessionsFuture = _playbackSessions.getAll(
      startedAtOrAfter: window.startUtc,
      startedBefore: window.endUtc,
    );

    final tracks = {for (final t in await tracksFuture) t.songId: t};
    final artists = {for (final a in await artistsFuture) a.artistId: a};
    final albums = {for (final a in await albumsFuture) a.albumId: a};
    final latest = _Latest(await sessionsFuture);
    var formats = const <String, String>{};
    try {
      formats = await _statedReleaseFormats?.call() ?? const {};
    } catch (_) {
      // Formats are decoration only: without them, releases show the owner.
    }

    final entries = <(PulseEntityKind, String), PulseEntityInfo>{};

    // Only an artist still in the library can be opened (S2): a play's
    // artist may since have been removed or merged away. The row keeps
    // its historical name and totals; it just offers no profile.
    final existingArtistIds = <String, bool>{};
    Future<String?> openableArtist(String? id) async {
      if (id == null) return null;
      final exists = existingArtistIds[id] ??=
          artists.containsKey(id) || await _library.getArtistById(id) != null;
      return exists ? id : null;
    }

    for (final id in _ids(data, PulseEntityKind.track)) {
      final track = tracks[id];
      final snapshot = latest.songs[id];
      entries[(PulseEntityKind.track, id)] = PulseEntityInfo(
        kind: PulseEntityKind.track,
        id: id,
        title: _name(track?.title, snapshot?.songTitle, 'Unknown track'),
        subtitle: _name(
          track?.artistName,
          snapshot?.artistName,
          'Unknown artist',
        ),
        artworkPath: track?.artworkPath,
        status: track == null
            ? PulseEntityStatus.historical
            : track.isBlocked
            ? PulseEntityStatus.blocked
            : !track.isAvailable
            ? PulseEntityStatus.unavailable
            : PulseEntityStatus.current,
        track: track,
        artistId: await openableArtist(
          data.artistOfTrack(id) ?? track?.artistId,
        ),
        albumId: track?.albumId ?? data.releaseOfTrack(id),
      );
    }

    for (final id in _ids(data, PulseEntityKind.artist)) {
      final artist = artists[id] ?? await _library.getArtistById(id);
      final snapshot = latest.artists[id];
      entries[(PulseEntityKind.artist, id)] = PulseEntityInfo(
        kind: PulseEntityKind.artist,
        id: id,
        title: _name(artist?.name, snapshot?.artistName, 'Unknown artist'),
        subtitle: artist == null ? 'Historical artist' : _artistLine(artist),
        artworkPath: _artistArt(artist),
        status: artist == null
            ? PulseEntityStatus.historical
            : PulseEntityStatus.current,
        artistId: artist?.artistId,
      );
    }

    for (final id in _ids(data, PulseEntityKind.release)) {
      final album = albums[id];
      final snapshot = latest.albums[id];
      entries[(PulseEntityKind.release, id)] = PulseEntityInfo(
        kind: PulseEntityKind.release,
        id: id,
        title: _name(album?.title, snapshot?.albumTitle, 'Unknown release'),
        subtitle: [
          _name(album?.artistName, snapshot?.artistName, 'Unknown artist'),
          ?formats[id],
        ].join(' · '),
        artworkPath: album?.artworkPath,
        status: album == null
            ? PulseEntityStatus.historical
            : PulseEntityStatus.current,
        artistId: album?.artistId,
        albumId: album?.albumId,
      );
    }

    return PulseEntityDirectory(entries);
  }

  static Iterable<String> _ids(PulsePeriodData data, PulseEntityKind kind) => {
    for (final measure in PulseMeasure.values)
      for (final entry in data.ranking(kind, measure)) entry.id,
    if (kind == PulseEntityKind.release)
      for (final entry in data.ranking(
        PulseEntityKind.track,
        PulseMeasure.allPlays,
      ))
        ?data.releaseOfTrack(entry.id),
  };

  static String _artistLine(LibraryArtist artist) {
    final songs = artist.songCount == 1 ? 'song' : 'songs';
    final albums = artist.albumCount == 1 ? 'release' : 'releases';
    return '${artist.songCount} $songs · ${artist.albumCount} $albums';
  }

  static String? _artistArt(LibraryArtist? artist) {
    if (artist == null) return null;
    final top = artist.topArtistsArtworkPath?.trim();
    if (top != null && top.isNotEmpty) return top;
    return artist.headerArtworkPath;
  }

  static String _name(String? current, String? snapshot, String fallback) {
    final now = current?.trim();
    if (now != null && now.isNotEmpty) return now;
    final then = snapshot?.trim();
    if (then != null && then.isNotEmpty) return then;
    return fallback;
  }
}

class _Latest {
  _Latest(List<PlaybackSession> sessions) {
    for (final s in sessions) {
      _keep(songs, s.songId, s);
      _keep(artists, s.artistId, s);
      _keep(albums, s.albumId, s);
    }
  }

  final songs = <String, PlaybackSession>{};
  final artists = <String, PlaybackSession>{};
  final albums = <String, PlaybackSession>{};

  static void _keep(
    Map<String, PlaybackSession> target,
    String id,
    PlaybackSession candidate,
  ) {
    final current = target[id];
    if (current == null || candidate.startedAt.isAfter(current.startedAt)) {
      target[id] = candidate;
    }
  }
}

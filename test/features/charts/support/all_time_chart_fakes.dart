import 'package:sonus_next/features/analytics/domain/entities/playback_session.dart';
import 'package:sonus_next/features/analytics/domain/entities/qualified_play.dart';
import 'package:sonus_next/features/analytics/domain/models/listening_history_cursor.dart';
import 'package:sonus_next/features/analytics/domain/repositories/playback_session_repository.dart';
import 'package:sonus_next/features/analytics/domain/repositories/qualified_play_repository.dart';
import 'package:sonus_next/features/library/application/models/library_album.dart';
import 'package:sonus_next/features/library/application/models/library_artist.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/application/models/library_track_order.dart';
import 'package:sonus_next/features/library/application/repositories/library_query_repository.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';

QualifiedPlay qualifiedPlay({
  required String id,
  required String songId,
  required String albumId,
  required DateTime qualifiedAt,
  String? albumEditionId,
}) {
  return QualifiedPlay(
    id: id,
    playbackSessionId: 'session-$id',
    songId: songId,
    artistId: 'artist-$albumId',
    albumId: albumId,
    albumEditionId: albumEditionId ?? 'edition-$albumId',
    qualifiedAt: qualifiedAt,
    listenedDuration: const Duration(seconds: 30),
    trackDuration: const Duration(minutes: 3),
    createdAt: qualifiedAt,
  );
}

/// [count] plays of one song, a minute apart from [from].
List<QualifiedPlay> qualifiedPlays(
  String songId,
  String albumId,
  int count,
  DateTime from, {
  String? albumEditionId,
}) => [
  for (var i = 0; i < count; i++)
    qualifiedPlay(
      id: '$songId-${from.toIso8601String()}-$i',
      songId: songId,
      albumId: albumId,
      albumEditionId: albumEditionId,
      qualifiedAt: from.add(Duration(minutes: i)),
    ),
];

LibraryTrack libraryTrack(
  String songId,
  String albumId, {
  bool blocked = false,
  bool available = true,
  String? albumEditionId,
}) {
  return LibraryTrack(
    songId: songId,
    title: 'Title $songId',
    artistId: 'artist-$albumId',
    artistName: 'Artist $albumId',
    albumId: albumId,
    albumTitle: 'Album $albumId',
    albumEditionId: albumEditionId ?? 'edition-$albumId',
    albumEditionTitle: 'Album $albumId',
    albumEditionType: AlbumEditionType.standard,
    trackNumber: 1,
    durationSeconds: 180,
    isSingle: false,
    featuredArtists: const [],
    dateAdded: DateTime.utc(2026, 9, 1),
    isAvailable: available,
    isSongBlocked: blocked,
  );
}

LibraryAlbum libraryAlbum(String albumId) {
  return LibraryAlbum(
    albumId: albumId,
    title: 'Album $albumId',
    artistId: 'artist-$albumId',
    artistName: 'Artist $albumId',
    trackCount: 1,
    dateAdded: DateTime.utc(2026, 9, 1),
  );
}

class FakeQualifiedPlayRepository implements QualifiedPlayRepository {
  FakeQualifiedPlayRepository(this.plays);

  final List<QualifiedPlay> plays;
  int getAllCalls = 0;

  @override
  Future<List<QualifiedPlay>> getAll({
    DateTime? qualifiedAtOrAfter,
    DateTime? qualifiedBefore,
  }) async {
    getAllCalls++;
    return plays
        .where(
          (play) =>
              (qualifiedAtOrAfter == null ||
                  !play.qualifiedAt.isBefore(qualifiedAtOrAfter)) &&
              (qualifiedBefore == null ||
                  play.qualifiedAt.isBefore(qualifiedBefore)),
        )
        .toList(growable: false);
  }

  @override
  Future<void> create(QualifiedPlay play) => throw UnimplementedError();

  @override
  Future<QualifiedPlay?> getById(String id) => throw UnimplementedError();

  @override
  Future<QualifiedPlay?> getByPlaybackSessionId(String playbackSessionId) =>
      throw UnimplementedError();

  @override
  Future<List<QualifiedPlay>> getByPlaybackSessionIds(
    Iterable<String> playbackSessionIds,
  ) => throw UnimplementedError();

  @override
  Future<void> save(QualifiedPlay play) => throw UnimplementedError();
}

class FakeChartLibrary implements LibraryQueryRepository {
  FakeChartLibrary({required this.tracks, required this.albums});

  final List<LibraryTrack> tracks;
  final List<LibraryAlbum> albums;

  @override
  Future<List<LibraryTrack>> getTracks({
    LibraryTrackOrder order = LibraryTrackOrder.title,
  }) async => tracks;

  @override
  Future<List<LibraryAlbum>> getAlbums() async => albums;

  @override
  Future<LibraryAlbum?> getAlbumById(String albumId) =>
      throw UnimplementedError();

  @override
  Future<List<LibraryAlbum>> getAlbumsByArtistId(String artistId) =>
      throw UnimplementedError();

  @override
  Future<LibraryArtist?> getArtistById(String artistId) =>
      throw UnimplementedError();

  @override
  Future<List<LibraryArtist>> getArtists() async => const [];

  @override
  Future<List<LibraryAlbum>> getRecentlyAddedAlbums(int limit) =>
      throw UnimplementedError();

  @override
  Future<List<LibraryTrack>> getRecentlyAddedTracks(int limit) =>
      throw UnimplementedError();

  @override
  Future<LibraryTrack?> getTrackById(String songId) =>
      throw UnimplementedError();

  @override
  Future<List<LibraryTrack>> getTracksByAlbumId(String albumId) =>
      throw UnimplementedError();

  @override
  Future<List<LibraryTrack>> getTracksByArtistId(
    String artistId, {
    LibraryTrackOrder order = LibraryTrackOrder.title,
  }) => throw UnimplementedError();
}

/// The session behind each of [plays], titled as heard: "Heard" and its id.
class FakePlaybackSessions implements PlaybackSessionRepository {
  FakePlaybackSessions(List<QualifiedPlay> plays)
    : _sessions = {
        for (final play in plays)
          play.playbackSessionId: PlaybackSession(
            id: play.playbackSessionId,
            songId: play.songId,
            artistId: play.artistId,
            albumId: play.albumId,
            albumEditionId: play.albumEditionId,
            songTitle: 'Heard ${play.songId}',
            artistName: 'Heard ${play.artistId}',
            albumTitle: 'Heard ${play.albumId}',
            albumEditionTitle: 'Heard ${play.albumId}',
            startedAt: play.qualifiedAt,
            endedAt: play.qualifiedAt,
            listenedDuration: play.listenedDuration,
            trackDuration: play.trackDuration,
            finalPosition: play.trackDuration,
            createdAt: play.qualifiedAt,
            updatedAt: play.qualifiedAt,
          ),
      };

  final Map<String, PlaybackSession> _sessions;

  @override
  Future<List<PlaybackSession>> getByIds(Iterable<String> ids) async => [
    for (final id in ids.toSet()) ?_sessions[id],
  ];

  @override
  Future<void> create(PlaybackSession session) => throw UnimplementedError();

  @override
  Future<void> save(PlaybackSession session) => throw UnimplementedError();

  @override
  Future<PlaybackSession?> getById(String id) => throw UnimplementedError();

  @override
  Future<List<PlaybackSession>> getOpen() => throw UnimplementedError();

  @override
  Future<List<PlaybackSession>> getAll({
    DateTime? startedAtOrAfter,
    DateTime? startedBefore,
  }) => throw UnimplementedError();

  @override
  Future<List<PlaybackSession>> getHistoryPage({
    DateTime? startedAtOrAfter,
    DateTime? startedBefore,
    ListeningHistoryCursor? before,
    required int limit,
  }) => throw UnimplementedError();
}

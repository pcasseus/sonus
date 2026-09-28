import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/analytics/domain/entities/qualified_play.dart';
import 'package:sonus_next/features/analytics/domain/repositories/qualified_play_repository.dart';
import 'package:sonus_next/features/charts/application/services/chart_snapshot_builder_service.dart';
import 'package:sonus_next/features/charts/application/services/live_chart_service.dart';
import 'package:sonus_next/features/charts/domain/entities/chart_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_type.dart';
import 'package:sonus_next/features/charts/domain/models/chart_view_size.dart';
import 'package:sonus_next/features/charts/domain/repositories/chart_repository.dart';
import 'package:sonus_next/features/library/application/models/library_album.dart';
import 'package:sonus_next/features/library/application/models/library_artist.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/application/models/library_track_order.dart';
import 'package:sonus_next/features/library/application/repositories/library_query_repository.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';

void main() {
  test('loads live Sunday to Saturday song chart', () async {
    final plays = <QualifiedPlay>[
      _play(
        id: '1',
        songId: 'song-a',
        albumId: 'album-a',
        qualifiedAt: DateTime.utc(2026, 9, 27, 14),
      ),
      _play(
        id: '2',
        songId: 'song-a',
        albumId: 'album-a',
        qualifiedAt: DateTime.utc(2026, 9, 28, 14),
      ),
    ];

    final builder = ChartSnapshotBuilderService(
      qualifiedPlays: _QualifiedPlayRepository(plays),
      library: _LibraryRepository(
        tracks: [_track('song-a', 'album-a')],
        albums: [_album('album-a')],
      ),
      charts: _ChartRepository(),
    );

    final service = LiveChartService(builder: builder);

    final snapshot = await service.load(
      chartType: ChartType.songs,
      referenceLocal: DateTime(2026, 9, 28, 10),
    );

    expect(snapshot.isLive, isTrue);
    expect(snapshot.chartType, ChartType.songs);
    expect(snapshot.entries, hasLength(1));
    expect(snapshot.entries.single.entity.entityId, 'song-a');
    expect(snapshot.entries.single.qualifiedStreamCount, 2);

    expect(snapshot.weekStartUtc, DateTime(2026, 9, 27).toUtc());

    expect(snapshot.weekEndUtc, DateTime(2026, 10, 4).toUtc());
  });

  test('view size limits visible standings without changing ranks', () async {
    final plays = <QualifiedPlay>[];
    final tracks = <LibraryTrack>[];
    final albums = <LibraryAlbum>[];

    for (var index = 0; index < 25; index++) {
      final songId = 'song-$index';
      final albumId = 'album-$index';

      tracks.add(_track(songId, albumId));
      albums.add(_album(albumId));

      plays.add(
        _play(
          id: 'play-$index',
          songId: songId,
          albumId: albumId,
          qualifiedAt: DateTime.utc(2026, 9, 28, 12, index),
        ),
      );
    }

    final builder = ChartSnapshotBuilderService(
      qualifiedPlays: _QualifiedPlayRepository(plays),
      library: _LibraryRepository(tracks: tracks, albums: albums),
      charts: _ChartRepository(),
    );

    final service = LiveChartService(builder: builder);

    final snapshot = await service.load(
      chartType: ChartType.songs,
      referenceLocal: DateTime(2026, 9, 28, 10),
      viewSize: ChartViewSize.top10,
    );

    expect(snapshot.entries, hasLength(10));

    expect(snapshot.entries.map((entry) => entry.rank), [
      1,
      2,
      3,
      4,
      5,
      6,
      7,
      8,
      9,
      10,
    ]);
  });

  test('Top 200 view exposes off-chart standings', () async {
    final plays = <QualifiedPlay>[];
    final tracks = <LibraryTrack>[];
    final albums = <LibraryAlbum>[];

    for (var index = 0; index < 101; index++) {
      final songId = 'song-$index';
      final albumId = 'album-$index';

      tracks.add(_track(songId, albumId));
      albums.add(_album(albumId));

      plays.add(
        _play(
          id: 'play-$index',
          songId: songId,
          albumId: albumId,
          qualifiedAt: DateTime.utc(2026, 9, 28, 12, index),
        ),
      );
    }

    final builder = ChartSnapshotBuilderService(
      qualifiedPlays: _QualifiedPlayRepository(plays),
      library: _LibraryRepository(tracks: tracks, albums: albums),
      charts: _ChartRepository(),
    );

    final service = LiveChartService(builder: builder);

    final snapshot = await service.load(
      chartType: ChartType.songs,
      referenceLocal: DateTime(2026, 9, 28, 10),
      viewSize: ChartViewSize.top200,
    );

    expect(snapshot.entries, hasLength(101));
    expect(snapshot.entries.last.rank, 101);
    expect(snapshot.entries.last.isOffChartStanding, isTrue);
  });
}

QualifiedPlay _play({
  required String id,
  required String songId,
  required String albumId,
  required DateTime qualifiedAt,
}) {
  return QualifiedPlay(
    id: id,
    playbackSessionId: 'session-$id',
    songId: songId,
    artistId: 'artist-$albumId',
    albumId: albumId,
    albumEditionId: 'edition-$albumId',
    qualifiedAt: qualifiedAt,
    listenedDuration: const Duration(seconds: 30),
    trackDuration: const Duration(minutes: 3),
    createdAt: qualifiedAt,
  );
}

LibraryTrack _track(String songId, String albumId) {
  return LibraryTrack(
    songId: songId,
    title: 'Title $songId',
    artistId: 'artist-$albumId',
    artistName: 'Artist $albumId',
    albumId: albumId,
    albumTitle: 'Album $albumId',
    albumEditionId: 'edition-$albumId',
    albumEditionTitle: 'Album $albumId',
    albumEditionType: AlbumEditionType.standard,
    trackNumber: 1,
    durationSeconds: 180,
    isSingle: false,
    featuredArtists: const [],
    dateAdded: DateTime.utc(2026, 9, 1),
    isAvailable: true,
  );
}

LibraryAlbum _album(String albumId) {
  return LibraryAlbum(
    albumId: albumId,
    title: 'Album $albumId',
    artistId: 'artist-$albumId',
    artistName: 'Artist $albumId',
    trackCount: 1,
    dateAdded: DateTime.utc(2026, 9, 1),
  );
}

class _QualifiedPlayRepository implements QualifiedPlayRepository {
  _QualifiedPlayRepository(this.plays);

  final List<QualifiedPlay> plays;

  @override
  Future<List<QualifiedPlay>> getAll({
    DateTime? qualifiedAtOrAfter,
    DateTime? qualifiedBefore,
  }) async {
    return plays
        .where((play) {
          final qualifiedAt = play.qualifiedAt.toUtc();

          if (qualifiedAtOrAfter != null &&
              qualifiedAt.isBefore(qualifiedAtOrAfter.toUtc())) {
            return false;
          }

          if (qualifiedBefore != null &&
              !qualifiedAt.isBefore(qualifiedBefore.toUtc())) {
            return false;
          }

          return true;
        })
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

class _LibraryRepository implements LibraryQueryRepository {
  _LibraryRepository({required this.tracks, required this.albums});

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
  Future<List<LibraryArtist>> getArtists() => throw UnimplementedError();

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

class _ChartRepository implements ChartRepository {
  @override
  Future<List<ChartSnapshot>> getHistory(
    ChartType chartType, {
    int? limit,
  }) async => const [];

  @override
  Future<ChartSnapshot?> getById(String id) => throw UnimplementedError();

  @override
  Future<ChartSnapshot?> getForWeek({
    required ChartType chartType,
    required DateTime weekStartUtc,
  }) => throw UnimplementedError();

  @override
  Future<void> replaceSnapshot(ChartSnapshot snapshot) =>
      throw UnimplementedError();
}

import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/analytics/domain/entities/playback_session.dart';
import 'package:sonus_next/features/analytics/domain/entities/qualified_play.dart';
import 'package:sonus_next/features/analytics/domain/models/listening_history_cursor.dart';
import 'package:sonus_next/features/analytics/domain/repositories/playback_session_repository.dart';
import 'package:sonus_next/features/analytics/domain/repositories/qualified_play_repository.dart';
import 'package:sonus_next/features/charts/application/services/chart_finalization_service.dart';
import 'package:sonus_next/features/charts/application/services/chart_snapshot_builder_service.dart';
import 'package:sonus_next/features/charts/domain/entities/chart_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_type.dart';
import 'package:sonus_next/features/charts/domain/models/chart_week.dart';
import 'package:sonus_next/features/charts/domain/repositories/chart_repository.dart';
import 'package:sonus_next/features/library/application/models/library_album.dart';
import 'package:sonus_next/features/library/application/models/library_artist.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/application/models/library_track_order.dart';
import 'package:sonus_next/features/library/application/repositories/library_query_repository.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';

void main() {
  QualifiedPlay play({
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

  LibraryTrack track({required String songId, required String albumId}) {
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

  LibraryAlbum album(String albumId) {
    return LibraryAlbum(
      albumId: albumId,
      title: 'Album $albumId',
      artistId: 'artist-$albumId',
      artistName: 'Artist $albumId',
      trackCount: 1,
      dateAdded: DateTime.utc(2026, 9, 1),
    );
  }

  ChartFinalizationService createService({
    required _MutableQualifiedPlayRepository qualifiedPlays,
    required _RecordingChartRepository charts,
  }) {
    final library = _FakeLibraryQueryRepository(
      tracks: [
        track(songId: 'song-a', albumId: 'album-a'),
        track(songId: 'song-b', albumId: 'album-b'),
      ],
      albums: [album('album-a'), album('album-b')],
    );

    final builder = ChartSnapshotBuilderService(
      qualifiedPlays: qualifiedPlays,
      library: library,
      charts: charts,
      playbackSessions: _PlaybackSessionRepository(qualifiedPlays),
    );

    return ChartFinalizationService(
      builder: builder,
      charts: charts,
      qualifiedPlays: qualifiedPlays,
    );
  }

  test('finalizes songs and albums for completed week', () async {
    final qualifiedPlays = _MutableQualifiedPlayRepository([
      play(
        id: '1',
        songId: 'song-a',
        albumId: 'album-a',
        qualifiedAt: DateTime.utc(2026, 9, 28, 10),
      ),
      play(
        id: '2',
        songId: 'song-a',
        albumId: 'album-a',
        qualifiedAt: DateTime.utc(2026, 9, 29, 10),
      ),
      play(
        id: '3',
        songId: 'song-b',
        albumId: 'album-b',
        qualifiedAt: DateTime.utc(2026, 9, 30, 10),
      ),
    ]);

    final charts = _RecordingChartRepository();

    final service = createService(
      qualifiedPlays: qualifiedPlays,
      charts: charts,
    );

    final snapshots = await service.reconcileCompletedWeek(
      ChartWeek(
        startUtc: DateTime.utc(2026, 9, 27),
        endUtc: DateTime.utc(2026, 10, 4),
      ),
    );

    expect(snapshots, hasLength(2));

    final songs = snapshots.singleWhere(
      (snapshot) => snapshot.chartType == ChartType.songs,
    );

    final albums = snapshots.singleWhere(
      (snapshot) => snapshot.chartType == ChartType.albums,
    );

    expect(songs.isFinalized, isTrue);
    expect(albums.isFinalized, isTrue);

    expect(songs.revision, 1);
    expect(albums.revision, 1);

    expect(songs.entries.first.entity.entityId, 'song-a');
    expect(songs.entries.first.qualifiedStreamCount, 2);

    expect(albums.entries.first.entity.entityId, 'album-a');
    expect(albums.entries.first.qualifiedStreamCount, 2);

    expect(charts.replaceCalls, 2);
  });

  test('unchanged reconciliation is idempotent and does not rewrite', () async {
    final qualifiedPlays = _MutableQualifiedPlayRepository([
      play(
        id: '1',
        songId: 'song-a',
        albumId: 'album-a',
        qualifiedAt: DateTime.utc(2026, 9, 28, 10),
      ),
    ]);

    final charts = _RecordingChartRepository();

    final service = createService(
      qualifiedPlays: qualifiedPlays,
      charts: charts,
    );

    final week = ChartWeek(
      startUtc: DateTime.utc(2026, 9, 27),
      endUtc: DateTime.utc(2026, 10, 4),
    );

    final first = await service.reconcileCompletedWeek(week);

    expect(charts.replaceCalls, 2);

    final second = await service.reconcileCompletedWeek(week);

    expect(charts.replaceCalls, 2);

    expect(
      second
          .singleWhere((snapshot) => snapshot.chartType == ChartType.songs)
          .revision,
      1,
    );

    expect(
      second
          .singleWhere((snapshot) => snapshot.chartType == ChartType.albums)
          .revision,
      1,
    );

    expect(first.length, second.length);
  });

  test(
    'late qualified play rebuilds finalized week with next revision',
    () async {
      final qualifiedPlays = _MutableQualifiedPlayRepository([
        play(
          id: '1',
          songId: 'song-a',
          albumId: 'album-a',
          qualifiedAt: DateTime.utc(2026, 9, 28, 10),
        ),
      ]);

      final charts = _RecordingChartRepository();

      final service = createService(
        qualifiedPlays: qualifiedPlays,
        charts: charts,
      );

      final week = ChartWeek(
        startUtc: DateTime.utc(2026, 9, 27),
        endUtc: DateTime.utc(2026, 10, 4),
      );

      await service.reconcileCompletedWeek(week);

      qualifiedPlays.plays.add(
        play(
          id: '2',
          songId: 'song-a',
          albumId: 'album-a',
          qualifiedAt: DateTime.utc(2026, 9, 30, 10),
        ),
      );

      final rebuilt = await service.reconcileCompletedWeek(week);

      final songs = rebuilt.singleWhere(
        (snapshot) => snapshot.chartType == ChartType.songs,
      );

      final albums = rebuilt.singleWhere(
        (snapshot) => snapshot.chartType == ChartType.albums,
      );

      expect(songs.revision, 2);
      expect(albums.revision, 2);

      expect(songs.entries.single.qualifiedStreamCount, 2);
      expect(albums.entries.single.qualifiedStreamCount, 2);

      expect(charts.replaceCalls, 4);
    },
  );

  test(
    'catch-up finalizes every completed play week oldest to newest and skips live week',
    () async {
      final qualifiedPlays = _MutableQualifiedPlayRepository([
        play(
          id: 'week-1',
          songId: 'song-a',
          albumId: 'album-a',
          qualifiedAt: DateTime(2026, 9, 21, 12).toUtc(),
        ),
        play(
          id: 'week-2',
          songId: 'song-a',
          albumId: 'album-a',
          qualifiedAt: DateTime(2026, 9, 28, 12).toUtc(),
        ),
        play(
          id: 'live-week',
          songId: 'song-b',
          albumId: 'album-b',
          qualifiedAt: DateTime(2026, 10, 5, 12).toUtc(),
        ),
      ]);

      final charts = _RecordingChartRepository();

      final service = createService(
        qualifiedPlays: qualifiedPlays,
        charts: charts,
      );

      final snapshots = await service.finalizeCompletedWeeks(
        referenceLocal: DateTime(2026, 10, 5, 18),
      );

      expect(snapshots, hasLength(4));

      expect(snapshots.map((snapshot) => snapshot.chartType).toList(), [
        ChartType.songs,
        ChartType.albums,
        ChartType.songs,
        ChartType.albums,
      ]);

      expect(snapshots[0].weekStartUtc, DateTime(2026, 9, 20).toUtc());

      expect(snapshots[2].weekStartUtc, DateTime(2026, 9, 27).toUtc());

      expect(snapshots.every((snapshot) => snapshot.isFinalized), isTrue);

      expect(
        snapshots.any(
          (snapshot) => snapshot.weekStartUtc == DateTime(2026, 10, 4).toUtc(),
        ),
        isFalse,
      );

      final secondWeekSongs = snapshots[2];

      expect(secondWeekSongs.entries.single.previousFinalRank, 1);

      expect(secondWeekSongs.entries.single.weeksOnChart, 2);

      expect(charts.replaceCalls, 4);
    },
  );
  test('previous completed week resolves from local reference date', () async {
    final qualifiedPlays = _MutableQualifiedPlayRepository([
      play(
        id: '1',
        songId: 'song-a',
        albumId: 'album-a',
        qualifiedAt: DateTime.utc(2026, 9, 22, 10),
      ),
    ]);

    final charts = _RecordingChartRepository();

    final service = createService(
      qualifiedPlays: qualifiedPlays,
      charts: charts,
    );

    final snapshots = await service.finalizePreviousCompletedWeek(
      referenceLocal: DateTime(2026, 9, 28, 9),
    );

    final songs = snapshots.singleWhere(
      (snapshot) => snapshot.chartType == ChartType.songs,
    );

    expect(songs.weekStartUtc, DateTime(2026, 9, 20).toUtc());

    expect(songs.weekEndUtc, DateTime(2026, 9, 27).toUtc());
  });
}

class _MutableQualifiedPlayRepository implements QualifiedPlayRepository {
  _MutableQualifiedPlayRepository(List<QualifiedPlay> plays)
    : plays = List<QualifiedPlay>.from(plays);

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
  Future<void> create(QualifiedPlay play) {
    throw UnimplementedError();
  }

  @override
  Future<QualifiedPlay?> getById(String id) {
    throw UnimplementedError();
  }

  @override
  Future<QualifiedPlay?> getByPlaybackSessionId(String playbackSessionId) {
    throw UnimplementedError();
  }

  @override
  Future<List<QualifiedPlay>> getByPlaybackSessionIds(
    Iterable<String> playbackSessionIds,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<void> save(QualifiedPlay play) {
    throw UnimplementedError();
  }
}

class _FakeLibraryQueryRepository implements LibraryQueryRepository {
  _FakeLibraryQueryRepository({required this.tracks, required this.albums});

  final List<LibraryTrack> tracks;
  final List<LibraryAlbum> albums;

  @override
  Future<List<LibraryTrack>> getTracks({
    LibraryTrackOrder order = LibraryTrackOrder.title,
  }) async {
    return tracks;
  }

  @override
  Future<List<LibraryAlbum>> getAlbums() async {
    return albums;
  }

  @override
  Future<LibraryAlbum?> getAlbumById(String albumId) {
    throw UnimplementedError();
  }

  @override
  Future<List<LibraryAlbum>> getAlbumsByArtistId(String artistId) {
    throw UnimplementedError();
  }

  @override
  Future<LibraryArtist?> getArtistById(String artistId) {
    throw UnimplementedError();
  }

  @override
  Future<List<LibraryArtist>> getArtists() {
    throw UnimplementedError();
  }

  @override
  Future<List<LibraryAlbum>> getRecentlyAddedAlbums(int limit) {
    throw UnimplementedError();
  }

  @override
  Future<List<LibraryTrack>> getRecentlyAddedTracks(int limit) {
    throw UnimplementedError();
  }

  @override
  Future<LibraryTrack?> getTrackById(String songId) {
    throw UnimplementedError();
  }

  @override
  Future<List<LibraryTrack>> getTracksByAlbumId(String albumId) {
    throw UnimplementedError();
  }

  @override
  Future<List<LibraryTrack>> getTracksByArtistId(
    String artistId, {
    LibraryTrackOrder order = LibraryTrackOrder.title,
  }) {
    throw UnimplementedError();
  }
}

class _RecordingChartRepository implements ChartRepository {
  final List<ChartSnapshot> _snapshots = [];

  int replaceCalls = 0;

  @override
  Future<void> replaceSnapshot(ChartSnapshot snapshot) async {
    replaceCalls++;

    _snapshots.removeWhere(
      (existing) =>
          existing.chartType == snapshot.chartType &&
          existing.weekStartUtc.toUtc() == snapshot.weekStartUtc.toUtc(),
    );

    _snapshots.add(snapshot);
  }

  @override
  Future<ChartSnapshot?> getById(String id) async {
    for (final snapshot in _snapshots) {
      if (snapshot.id == id) {
        return snapshot;
      }
    }

    return null;
  }

  @override
  Future<ChartSnapshot?> getForWeek({
    required ChartType chartType,
    required DateTime weekStartUtc,
  }) async {
    for (final snapshot in _snapshots) {
      if (snapshot.chartType == chartType &&
          snapshot.weekStartUtc.toUtc() == weekStartUtc.toUtc()) {
        return snapshot;
      }
    }

    return null;
  }

  @override
  Future<List<ChartSnapshot>> getHistory(
    ChartType chartType, {
    int? limit,
  }) async {
    final results =
        _snapshots
            .where(
              (snapshot) =>
                  snapshot.chartType == chartType && snapshot.isFinalized,
            )
            .toList(growable: false)
          ..sort((a, b) => b.weekStartUtc.compareTo(a.weekStartUtc));

    if (limit == null || results.length <= limit) {
      return List<ChartSnapshot>.unmodifiable(results);
    }

    return List<ChartSnapshot>.unmodifiable(results.take(limit));
  }
}

class _PlaybackSessionRepository implements PlaybackSessionRepository {
  _PlaybackSessionRepository(this.qualifiedPlays);

  final _MutableQualifiedPlayRepository qualifiedPlays;

  @override
  Future<List<PlaybackSession>> getByIds(Iterable<String> ids) async {
    final requested = ids.toSet();

    return qualifiedPlays.plays
        .where((play) => requested.contains(play.playbackSessionId))
        .map(
          (play) => PlaybackSession(
            id: play.playbackSessionId,
            songId: play.songId,
            artistId: play.artistId,
            albumId: play.albumId,
            albumEditionId: play.albumEditionId,
            songTitle: 'Title ${play.songId}',
            artistName: 'Artist ${play.albumId}',
            albumTitle: 'Album ${play.albumId}',
            albumEditionTitle: 'Album ${play.albumId}',
            startedAt: play.qualifiedAt,
            endedAt: play.qualifiedAt.add(const Duration(minutes: 3)),
            listenedDuration: const Duration(minutes: 3),
            trackDuration: const Duration(minutes: 3),
            finalPosition: const Duration(minutes: 3),
            createdAt: play.qualifiedAt,
            updatedAt: play.qualifiedAt.add(const Duration(minutes: 3)),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> create(PlaybackSession session) {
    throw UnimplementedError();
  }

  @override
  Future<PlaybackSession?> getById(String id) {
    throw UnimplementedError();
  }

  @override
  Future<List<PlaybackSession>> getOpen() {
    throw UnimplementedError();
  }

  @override
  Future<List<PlaybackSession>> getAll({
    DateTime? startedAtOrAfter,
    DateTime? startedBefore,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<PlaybackSession>> getHistoryPage({
    DateTime? startedAtOrAfter,
    DateTime? startedBefore,
    ListeningHistoryCursor? before,
    required int limit,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> save(PlaybackSession session) {
    throw UnimplementedError();
  }
}

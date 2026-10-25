import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/library_mutation_coordinator.dart';
import 'package:sonus_next/features/analytics/domain/entities/qualified_play.dart';
import 'package:sonus_next/features/analytics/domain/repositories/qualified_play_repository.dart';
import 'package:sonus_next/features/charts/application/services/all_time_moment_service.dart';
import 'package:sonus_next/features/charts/data/repositories/sqlite_chart_moment_repository.dart';
import 'package:sonus_next/features/charts/domain/models/chart_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_scope.dart';
import 'package:sonus_next/features/library/application/models/library_album.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/application/models/library_track_order.dart';
import 'package:sonus_next/features/library/application/repositories/library_query_repository.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';

/// Tuesday 2026-10-27, mid-morning in the test's local zone.
final _today = DateTime(2026, 10, 27, 10);

void main() {
  sqfliteFfiInit();

  late AppDatabase database;
  late SqliteChartMomentRepository moments;
  late _Plays plays;
  late _Library library;
  var restoreGeneration = 0;

  setUp(() async {
    database = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    await database.database;
    moments = SqliteChartMomentRepository(database);
    plays = _Plays();
    library = _Library();
    restoreGeneration = 0;
  });

  tearDown(() => database.close());

  AllTimeMomentService service({DateTime? activation}) => AllTimeMomentService(
    qualifiedPlays: plays,
    library: library,
    moments: moments,
    activationUtc: activation ?? DateTime.utc(2026, 1, 1),
    now: () => _today,
    restoreGeneration: () => restoreGeneration,
  );

  Future<List<ChartMomentEvent>> saved() => moments.getRecent();

  test('a play that takes #1 is a Moment right away', () async {
    library.add('a');
    library.add('b');
    plays.add('a', _today.subtract(const Duration(hours: 2)));
    plays.add('b', _today.subtract(const Duration(hours: 1)));
    plays.add('b', _today.subtract(const Duration(minutes: 30)));

    await service().record(referenceLocal: _today);

    final songs = (await saved())
        .where((e) => e.chartType == ChartType.songs)
        .toList();
    final bTakesTop = songs.singleWhere(
      (e) =>
          e.entity.entityId == 'song-b' &&
          e.eventType == ChartMomentEventType.firstNumberOne,
    );
    expect(bTakesTop.scope, ChartMomentScope.allTime);
    expect(bTakesTop.currentRank, 1);
    expect(bTakesTop.previousRank, 2);
    expect(bTakesTop.threshold, 1);
    expect(bTakesTop.qualifiedStreamCount, 2);
    expect(bTakesTop.entity.title, 'Song b');
    expect(bTakesTop.sourceId, plays.all.last.id);
  });

  test('both all-time charts are covered', () async {
    library.add('a');
    plays.add('a', _today.subtract(const Duration(hours: 1)));

    await service().record(referenceLocal: _today);

    final charts = {for (final e in await saved()) e.chartType};
    expect(charts, {ChartType.songs, ChartType.albums});
  });

  test('recording again, or after restarting, adds nothing', () async {
    library.add('a');
    library.add('b');
    plays.add('a', _today.subtract(const Duration(hours: 3)));
    plays.add('b', _today.subtract(const Duration(hours: 2)));
    plays.add('b', _today.subtract(const Duration(hours: 1)));

    await service().record(referenceLocal: _today);
    final first = await saved();

    await service().record(referenceLocal: _today);
    await service().record(
      referenceLocal: _today.add(const Duration(hours: 1)),
    );

    final again = await saved();
    expect(again.map((e) => e.id), first.map((e) => e.id));
    expect(first, isNotEmpty);
  });

  test('a new play adds only what it achieved', () async {
    library.add('a');
    library.add('b');
    plays.add('a', _today.subtract(const Duration(hours: 3)));
    plays.add('a', _today.subtract(const Duration(hours: 2)));
    plays.add('b', _today.subtract(const Duration(hours: 1)));
    await service().record(referenceLocal: _today);
    final before = (await saved()).length;

    plays.add('b', _today.subtract(const Duration(minutes: 10)));
    plays.add('b', _today.subtract(const Duration(minutes: 5)));
    final added = await service().record(referenceLocal: _today);

    final newIds = (await saved()).length - before;
    expect(newIds, greaterThan(0));
    expect(
      added.where(
        (e) =>
            e.entity.entityId == 'song-b' &&
            e.eventType == ChartMomentEventType.firstNumberOne,
      ),
      isNotEmpty,
    );
  });

  test('the past is not replayed as news', () async {
    library.add('old');
    library.add('new');
    plays.add('old', _today.subtract(const Duration(days: 30)));
    plays.add('new', _today.subtract(const Duration(hours: 1)));

    await service().record(referenceLocal: _today);

    final entities = {for (final e in await saved()) e.entity.entityId};
    expect(entities, isNot(contains('song-old')));
    expect(entities, contains('song-new'));
  });

  test('nothing before activation is news', () async {
    library.add('a');
    plays.add('a', _today.subtract(const Duration(hours: 5)));

    await service(
      activation: _today.subtract(const Duration(hours: 1)).toUtc(),
    ).record(referenceLocal: _today);

    expect(await saved(), isEmpty);
  });

  test('blocked songs are not stories, but their albums still are', () async {
    library.add('hidden', blocked: true);
    plays.add('hidden', _today.subtract(const Duration(hours: 1)));

    await service().record(referenceLocal: _today);

    final events = await saved();
    expect(events.where((e) => e.chartType == ChartType.songs), isEmpty);
    expect(events.where((e) => e.chartType == ChartType.albums), isNotEmpty);
  });

  test('a debut outside the Top 100 waits until it gets there', () async {
    for (var i = 0; i < 100; i++) {
      final id = 'f${i.toString().padLeft(3, '0')}';
      library.add(id);
      plays.add(id, _today.subtract(Duration(minutes: 400 - i)));
      plays.add(id, _today.subtract(Duration(minutes: 300 - i)));
      if (i < 20) {
        for (var extra = 0; extra < 3; extra++) {
          plays.add(id, _today.subtract(Duration(minutes: 200 - i)));
        }
      }
    }
    library.add('late');
    plays.add('late', _today.subtract(const Duration(minutes: 20)));

    await service().record(referenceLocal: _today);
    expect(
      (await saved()).where((e) => e.entity.entityId == 'song-late'),
      isEmpty,
    );

    plays.add('late', _today.subtract(const Duration(minutes: 10)));
    plays.add('late', _today.subtract(const Duration(minutes: 5)));
    await service().record(referenceLocal: _today);

    final late = (await saved())
        .where(
          (e) =>
              e.entity.entityId == 'song-late' &&
              e.chartType == ChartType.songs,
        )
        .toList();
    expect(late.map((e) => e.eventType), [
      ChartMomentEventType.firstThresholdEntry,
    ]);
    expect(late.single.threshold, 100);
  });

  test('weekly Moments are left alone', () async {
    library.add('a');
    plays.add('a', _today.subtract(const Duration(hours: 1)));
    await service().record(referenceLocal: _today);

    await moments.replaceFinalizedForWeek(
      chartType: ChartType.songs,
      weekStartUtc: DateTime.utc(2026, 10, 18, 4),
      events: const [],
    );

    expect(await saved(), isNotEmpty);
    expect(
      (await saved()).every((e) => e.scope == ChartMomentScope.allTime),
      isTrue,
    );
  });

  test('a pass that spans a restore writes nothing', () async {
    library.add('a');
    plays.add('a', _today.subtract(const Duration(hours: 1)));
    plays.onRead = () => restoreGeneration++;

    await expectLater(
      service().record(referenceLocal: _today),
      throwsA(isA<LibraryMutationUnavailable>()),
    );
    expect(await saved(), isEmpty);
  });
}

class _Plays implements QualifiedPlayRepository {
  final List<QualifiedPlay> all = [];
  void Function()? onRead;

  void add(String song, DateTime atLocal) {
    final id = 'play-${all.length + 1}';
    all.add(
      QualifiedPlay(
        id: id,
        playbackSessionId: 'session-$id',
        songId: 'song-$song',
        artistId: 'artist-$song',
        albumId: 'album-$song',
        albumEditionId: 'edition-$song',
        qualifiedAt: atLocal.toUtc(),
        listenedDuration: const Duration(minutes: 2),
        trackDuration: const Duration(minutes: 3),
        createdAt: atLocal.toUtc(),
      ),
    );
  }

  @override
  Future<List<QualifiedPlay>> getAll({
    DateTime? qualifiedAtOrAfter,
    DateTime? qualifiedBefore,
  }) async {
    onRead?.call();
    return List.of(all);
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

class _Library implements LibraryQueryRepository {
  final List<LibraryTrack> tracks = [];
  final List<LibraryAlbum> albums = [];

  void add(String id, {bool blocked = false}) {
    tracks.add(
      LibraryTrack(
        songId: 'song-$id',
        title: 'Song $id',
        artistId: 'artist-$id',
        artistName: 'Artist $id',
        albumId: 'album-$id',
        albumTitle: 'Album $id',
        albumEditionId: 'edition-$id',
        albumEditionTitle: 'Album $id',
        albumEditionType: AlbumEditionType.standard,
        trackNumber: 1,
        durationSeconds: 180,
        isSingle: false,
        featuredArtists: const [],
        dateAdded: DateTime.utc(2026, 9, 1),
        isAvailable: true,
        isSongBlocked: blocked,
      ),
    );
    albums.add(
      LibraryAlbum(
        albumId: 'album-$id',
        title: 'Album $id',
        artistId: 'artist-$id',
        artistName: 'Artist $id',
        trackCount: 1,
        dateAdded: DateTime.utc(2026, 9, 1),
      ),
    );
  }

  @override
  Future<List<LibraryTrack>> getTracks({
    LibraryTrackOrder order = LibraryTrackOrder.title,
  }) async => tracks;

  @override
  Future<List<LibraryAlbum>> getAlbums() async => albums;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

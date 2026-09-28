import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/library/application/models/library_album.dart';
import 'package:sonus_next/features/library/application/models/library_artist.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/application/models/library_track_order.dart';
import 'package:sonus_next/features/library/application/repositories/library_query_repository.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/presentation/pages/album_profile_page.dart';
import 'package:provider/provider.dart';
import 'package:sonus_next/features/charts/application/services/chart_finalization_service.dart';
import 'package:sonus_next/features/charts/application/services/live_chart_service.dart';
import 'package:sonus_next/features/charts/domain/entities/chart_entry.dart';
import 'package:sonus_next/features/charts/domain/entities/chart_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_entity_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_movement.dart';
import 'package:sonus_next/features/charts/domain/models/chart_type.dart';
import 'package:sonus_next/features/charts/domain/models/chart_view_size.dart';
import 'package:sonus_next/features/charts/domain/repositories/chart_repository.dart';
import 'package:sonus_next/features/charts/domain/models/chart_week.dart';
import 'package:sonus_next/features/charts/presentation/controllers/charts_controller.dart';
import 'package:sonus_next/features/charts/presentation/pages/charts_page.dart';

void main() {
  testWidgets('renders branded Hot 100 controls and live chart', (
    tester,
  ) async {
    final controller = await _controller();

    await _pumpPage(tester, controller);

    expect(find.text('SONUS'), findsOneWidget);
    expect(find.text('Hot 100'), findsOneWidget);

    expect(find.text('Songs'), findsWidgets);
    expect(find.text('Albums'), findsOneWidget);

    expect(find.text('Top 10'), findsOneWidget);
    expect(find.text('Top 25'), findsOneWidget);
    expect(find.text('Top 50'), findsOneWidget);
    expect(find.text('Top 75'), findsOneWidget);
    expect(find.text('Top 100'), findsOneWidget);
    expect(find.text('Top 200'), findsOneWidget);

    expect(find.text('LIVE'), findsOneWidget);
    expect(find.text('Song 1'), findsOneWidget);
    expect(find.text('Artist 1 • Album 1'), findsOneWidget);
    expect(find.text('12 streams'), findsOneWidget);
    expect(find.text('Peak #1'), findsOneWidget);
  });

  testWidgets('older week control shows finalized chart', (tester) async {
    final controller = await _controller(
      history: [
        _snapshot(
          id: 'historical',
          start: DateTime.utc(2026, 9, 20),
          finalized: true,
        ),
      ],
    );

    await _pumpPage(tester, controller);

    await tester.tap(find.byKey(const ValueKey<String>('charts-older-week')));

    await tester.pump();

    expect(find.text('FINAL'), findsOneWidget);
  });

  testWidgets('album segment switches chart type', (tester) async {
    final controller = await _controller();

    await _pumpPage(tester, controller);

    await tester.tap(find.text('Albums'));
    await tester.pumpAndSettle();

    expect(controller.chartType, ChartType.albums);
  });

  testWidgets('empty chart renders empty state', (tester) async {
    final controller = await _controller(
      live: ChartSnapshot(
        id: 'empty',
        chartType: ChartType.songs,
        weekStartUtc: DateTime.utc(2026, 9, 27),
        weekEndUtc: DateTime.utc(2026, 10, 4),
        entries: const [],
      ),
    );

    await _pumpPage(tester, controller);

    expect(find.text('No chart entries yet'), findsOneWidget);
  });

  testWidgets('live song tap opens chart track actions', (tester) async {
    final controller = await _controller();

    await _pumpPage(tester, controller);

    await tester.tap(
      find.byKey(const ValueKey<String>('charts-entry-songs_1')),
    );

    await tester.pumpAndSettle();

    expect(find.text('Play'), findsOneWidget);
    expect(find.text('Play next'), findsOneWidget);
    expect(find.text('Add to queue'), findsOneWidget);
    expect(find.text('Go to album'), findsOneWidget);
    expect(find.text('Go to artist'), findsOneWidget);
  });

  testWidgets('historical song row remains display-only', (tester) async {
    final controller = await _controller(
      history: [
        _snapshot(
          id: 'historical',
          start: DateTime.utc(2026, 9, 20),
          finalized: true,
        ),
      ],
    );

    await _pumpPage(tester, controller);

    controller.showOlderWeek();
    await tester.pump();

    await tester.tap(
      find.byKey(const ValueKey<String>('charts-entry-songs_1')),
    );

    await tester.pumpAndSettle();

    expect(find.text('Play next'), findsNothing);
    expect(find.text('Add to queue'), findsNothing);
  });
  testWidgets('blocked live song stays visible but is not interactive', (
    tester,
  ) async {
    final controller = await _controller(tracks: [_track(isBlocked: true)]);

    await _pumpPage(tester, controller);

    expect(find.text('Song 1'), findsOneWidget);
    expect(find.text('BLACKLISTED'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('charts-entry-songs_1')),
    );

    await tester.pumpAndSettle();

    expect(find.text('Play next'), findsNothing);
    expect(find.text('Add to queue'), findsNothing);
  });

  testWidgets('unavailable live song stays visible but is not interactive', (
    tester,
  ) async {
    final controller = await _controller(
      tracks: [_track(isAvailable: false, filePath: null)],
    );

    await _pumpPage(tester, controller);

    expect(find.text('Song 1'), findsOneWidget);
    expect(find.text('UNAVAILABLE'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('charts-entry-songs_1')),
    );

    await tester.pumpAndSettle();

    expect(find.text('Play next'), findsNothing);
    expect(find.text('Add to queue'), findsNothing);
  });

  testWidgets('deleted historical song still renders snapshot identity', (
    tester,
  ) async {
    final controller = await _controller(
      tracks: const [],
      history: [
        _snapshot(
          id: 'historical-deleted-song',
          start: DateTime.utc(2026, 9, 20),
          finalized: true,
        ),
      ],
    );

    await _pumpPage(tester, controller);

    controller.showOlderWeek();
    await tester.pump();

    expect(find.text('Song 1'), findsOneWidget);
    expect(find.text('Artist 1 • Album 1'), findsOneWidget);
    expect(find.text('HISTORICAL'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('charts-entry-songs_1')),
    );

    await tester.pumpAndSettle();

    expect(find.text('Play next'), findsNothing);
  });

  testWidgets('deleted historical album still renders snapshot identity', (
    tester,
  ) async {
    final historicalAlbum = _snapshot(
      id: 'historical-deleted-album',
      start: DateTime.utc(2026, 9, 20),
      chartType: ChartType.albums,
      finalized: true,
    );

    final controller = await _controller(
      albums: const [],
      history: [historicalAlbum],
    );

    await _pumpPage(tester, controller);

    await controller.selectChartType(ChartType.albums);
    controller.showOlderWeek();
    await tester.pump();

    expect(find.text('Album 1'), findsOneWidget);
    expect(find.text('Artist 1'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('charts-entry-albums_1')),
    );

    await tester.pumpAndSettle();

    expect(find.byType(AlbumProfilePage), findsNothing);
  });

  testWidgets('live album row opens album profile', (tester) async {
    final controller = await _controller();

    await _pumpPage(tester, controller);

    await controller.selectChartType(ChartType.albums);
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('charts-entry-albums_1')),
    );

    await tester.pumpAndSettle();

    expect(find.byType(AlbumProfilePage), findsOneWidget);
  });
  testWidgets('Top 200 explains extended standings', (tester) async {
    final controller = await _controller();

    await _pumpPage(tester, controller);

    await tester.tap(find.byKey(const ValueKey<String>('charts-size-200')));

    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('charts-extended-notice')),
      findsOneWidget,
    );

    expect(
      find.text(
        'Top 100 is the official chart. Positions 101\u2013200 are extended standings.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('calendar opens when finalized chart weeks exist', (
    tester,
  ) async {
    final controller = await _controller(
      history: [
        _snapshot(
          id: 'historical-1',
          start: DateTime.utc(2026, 9, 20),
          finalized: true,
        ),
        _snapshot(
          id: 'historical-2',
          start: DateTime.utc(2026, 9, 13),
          finalized: true,
        ),
      ],
    );

    await _pumpPage(tester, controller);

    await tester.tap(find.byKey(const ValueKey<String>('charts-calendar')));

    await tester.pumpAndSettle();

    expect(find.byType(DatePickerDialog), findsOneWidget);
    expect(find.text('Choose a Sonus Hot 100 week'), findsOneWidget);
  });
  testWidgets('missing controller renders initializing state', (tester) async {
    await tester.pumpWidget(
      Provider<ChartsController?>.value(
        value: null,
        child: MaterialApp(home: Scaffold(body: ChartsPage())),
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('charts-initializing')),
      findsOneWidget,
    );
  });
}

Future<ChartsController> _controller({
  ChartSnapshot? live,
  List<ChartSnapshot> history = const [],
  List<LibraryTrack>? tracks,
  List<LibraryAlbum>? albums,
}) async {
  final resolvedLive =
      live ?? _snapshot(id: 'live', start: DateTime.utc(2026, 9, 27));

  final controller = ChartsController(
    liveCharts: _FakeLiveChartService(
      songs: resolvedLive,
      albums: _snapshot(
        id: 'albums',
        start: DateTime.utc(2026, 9, 27),
        chartType: ChartType.albums,
      ),
    ),
    finalization: _FakeChartFinalizationService(),
    charts: _FakeChartRepository(history: history),
    library: _FakeLibraryQueryRepository(
      tracks: tracks ?? [_track()],
      albums: albums ?? [_album()],
    ),
    now: () => DateTime(2026, 9, 28, 12),
  );

  await controller.load();

  return controller;
}

Future<void> _pumpPage(WidgetTester tester, ChartsController controller) async {
  await tester.binding.setSurfaceSize(const Size(800, 1600));

  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ChangeNotifierProvider<ChartsController?>.value(
      value: controller,
      child: const MaterialApp(home: Scaffold(body: ChartsPage())),
    ),
  );

  await tester.pumpAndSettle();
}

LibraryTrack _track({
  bool isAvailable = true,
  bool isBlocked = false,
  String? filePath = 'C:/Music/song_1.mp3',
}) {
  return LibraryTrack(
    songId: 'songs_1',
    title: 'Song 1',
    artistId: 'artist_1',
    artistName: 'Artist 1',
    albumId: 'album_1',
    albumTitle: 'Album 1',
    albumEditionId: 'edition_1',
    albumEditionTitle: 'Standard',
    albumEditionType: AlbumEditionType.standard,
    trackNumber: 1,
    durationSeconds: 180,
    isSingle: false,
    featuredArtists: const [],
    dateAdded: DateTime.utc(2026, 9, 1),
    isAvailable: isAvailable,
    isSongBlocked: isBlocked,
    filePath: filePath,
  );
}

LibraryAlbum _album() {
  return LibraryAlbum(
    albumId: 'albums_1',
    title: 'Album 1',
    artistId: 'artist_1',
    artistName: 'Artist 1',
    trackCount: 1,
    dateAdded: DateTime.utc(2026, 9, 1),
  );
}

ChartSnapshot _snapshot({
  required String id,
  required DateTime start,
  ChartType chartType = ChartType.songs,
  bool finalized = false,
}) {
  return ChartSnapshot(
    id: id,
    chartType: chartType,
    weekStartUtc: start,
    weekEndUtc: start.add(const Duration(days: 7)),
    finalizedAt: finalized ? start.add(const Duration(days: 7)) : null,
    entries: [
      ChartEntry(
        entity: ChartEntitySnapshot(
          entityId: '${chartType.name}_1',
          title: chartType == ChartType.songs ? 'Song 1' : 'Album 1',
          artistName: 'Artist 1',
          albumTitle: 'Album 1',
        ),
        rank: 1,
        qualifiedStreamCount: 12,
        lastQualifiedAt: start.add(const Duration(days: 2)),
        previousFinalRank: 3,
        peakRank: 1,
        peakAchievedAt: start,
        weeksOnChart: 4,
        movement: ChartMovement.up,
      ),
    ],
  );
}

class _FakeLiveChartService implements LiveChartService {
  _FakeLiveChartService({required this.songs, required this.albums});

  final ChartSnapshot songs;
  final ChartSnapshot albums;

  @override
  Future<ChartSnapshot> load({
    required ChartType chartType,
    required DateTime referenceLocal,
    ChartViewSize viewSize = ChartViewSize.top100,
  }) async {
    return chartType == ChartType.songs ? songs : albums;
  }
}

class _FakeChartFinalizationService implements ChartFinalizationService {
  @override
  Future<List<ChartSnapshot>> finalizeCompletedWeeks({
    required DateTime referenceLocal,
  }) async {
    return const [];
  }

  @override
  Future<List<ChartSnapshot>> finalizePreviousCompletedWeek({
    required DateTime referenceLocal,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<ChartSnapshot>> reconcileCompletedWeek(ChartWeek week) {
    throw UnimplementedError();
  }
}

class _FakeChartRepository implements ChartRepository {
  _FakeChartRepository({this.history = const []});

  final List<ChartSnapshot> history;

  @override
  Future<List<ChartSnapshot>> getHistory(
    ChartType chartType, {
    int? limit,
  }) async {
    final matching = history
        .where((snapshot) => snapshot.chartType == chartType)
        .toList(growable: false);

    if (limit == null || matching.length <= limit) {
      return matching;
    }

    return matching.take(limit).toList(growable: false);
  }

  @override
  Future<ChartSnapshot?> getById(String id) async => null;

  @override
  Future<ChartSnapshot?> getForWeek({
    required ChartType chartType,
    required DateTime weekStartUtc,
  }) async {
    return null;
  }

  @override
  Future<void> replaceSnapshot(ChartSnapshot snapshot) async {}
}

class _FakeLibraryQueryRepository implements LibraryQueryRepository {
  _FakeLibraryQueryRepository({this.tracks = const [], this.albums = const []});

  final List<LibraryTrack> tracks;
  final List<LibraryAlbum> albums;

  @override
  Future<List<LibraryTrack>> getTracks({
    LibraryTrackOrder order = LibraryTrackOrder.title,
  }) async {
    return tracks;
  }

  @override
  Future<List<LibraryTrack>> getRecentlyAddedTracks(int limit) async {
    return tracks.take(limit).toList(growable: false);
  }

  @override
  Future<LibraryTrack?> getTrackById(String songId) async {
    for (final track in tracks) {
      if (track.songId == songId) {
        return track;
      }
    }

    return null;
  }

  @override
  Future<List<LibraryTrack>> getTracksByArtistId(
    String artistId, {
    LibraryTrackOrder order = LibraryTrackOrder.title,
  }) async {
    return tracks
        .where((track) => track.artistId == artistId)
        .toList(growable: false);
  }

  @override
  Future<List<LibraryTrack>> getTracksByAlbumId(String albumId) async {
    return tracks
        .where((track) => track.albumId == albumId)
        .toList(growable: false);
  }

  @override
  Future<List<LibraryAlbum>> getAlbums() async {
    return albums;
  }

  @override
  Future<List<LibraryAlbum>> getRecentlyAddedAlbums(int limit) async {
    return albums.take(limit).toList(growable: false);
  }

  @override
  Future<LibraryAlbum?> getAlbumById(String albumId) async {
    for (final album in albums) {
      if (album.albumId == albumId) {
        return album;
      }
    }

    return null;
  }

  @override
  Future<List<LibraryAlbum>> getAlbumsByArtistId(String artistId) async {
    return albums
        .where((album) => album.artistId == artistId)
        .toList(growable: false);
  }

  @override
  Future<List<LibraryArtist>> getArtists() async {
    return const [];
  }

  @override
  Future<LibraryArtist?> getArtistById(String artistId) async {
    return null;
  }
}

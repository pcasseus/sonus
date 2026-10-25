import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/core/events/library_change_signal.dart';
import 'package:sonus_next/features/analytics/domain/entities/playback_session.dart';
import 'package:sonus_next/features/analytics/domain/entities/qualified_play.dart';
import 'package:sonus_next/features/analytics/domain/models/listening_history_cursor.dart';
import 'package:sonus_next/features/analytics/domain/repositories/playback_session_repository.dart';
import 'package:sonus_next/features/analytics/domain/repositories/qualified_play_repository.dart';
import 'package:sonus_next/features/charts/presentation/pages/charts_page.dart';
import 'package:sonus_next/features/charts/presentation/scopes/charts_scope.dart';
import 'package:sonus_next/features/library/application/repositories/library_query_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/all_time_chart_fakes.dart';

// Data-1 (Charts): the all-time Hot 100 used to stay empty after new
// qualified plays until it was pulled to refresh. The Charts scope now
// reloads on the shared change signal, which is sent once a qualified play
// is recorded, never for playback progress.
void main() {
  sqfliteFfiInit();

  final now = DateTime(2026, 10, 7, 12);
  final thisWeek = DateTime(2026, 10, 6, 9);

  late AppDatabase database;
  late List<QualifiedPlay> plays;
  late FakeQualifiedPlayRepository playRepository;
  late LibraryChangeSignal signal;

  setUp(() {
    database = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    plays = <QualifiedPlay>[];
    playRepository = FakeQualifiedPlayRepository(plays);
    signal = LibraryChangeSignal();
  });

  tearDown(() => database.close());

  Future<void> pumpCharts(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AppDatabase>.value(value: database),
          Provider<LibraryQueryRepository?>.value(
            value: FakeChartLibrary(
              tracks: [libraryTrack('s1', 'a1')],
              albums: [libraryAlbum('a1')],
            ),
          ),
          Provider<QualifiedPlayRepository?>.value(value: playRepository),
          Provider<PlaybackSessionRepository?>.value(
            value: _EmptyPlaybackSessions(),
          ),
        ],
        child: MaterialApp(
          theme: SonusThemeFactory.build(const SonusAppearanceSpec()),
          home: Scaffold(
            body: ChartsScope(
              now: () => now,
              changes: signal,
              child: const ChartsPage(),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  testWidgets('new qualified plays appear on the Hot 100 without a manual '
      'refresh', (tester) async {
    await pumpCharts(tester);
    expect(find.text('No chart entries yet'), findsOneWidget);

    plays.addAll(qualifiedPlays('s1', 'a1', 3, thisWeek));
    signal.notify(LibraryChangeKind.listeningRecorded);
    await settle(tester);

    expect(find.text('Title s1'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('3 lifetime streams,')),
      findsOneWidget,
    );

    plays.addAll(qualifiedPlays('s1', 'a1', 2, thisWeek.add(_hour)));
    signal.notify(LibraryChangeKind.listeningRecorded);
    await settle(tester);

    expect(
      find.bySemanticsLabel(RegExp('5 lifetime streams,')),
      findsOneWidget,
    );
  });

  testWidgets('a burst of changes reloads once, and nothing after dispose', (
    tester,
  ) async {
    await pumpCharts(tester);
    final afterOpening = playRepository.getAllCalls;

    plays.addAll(qualifiedPlays('s1', 'a1', 1, thisWeek));
    for (var i = 0; i < 4; i++) {
      signal.notify(LibraryChangeKind.listeningRecorded);
    }
    await settle(tester);

    final perLoad = afterOpening;
    expect(playRepository.getAllCalls, afterOpening + perLoad);
    expect(find.bySemanticsLabel(RegExp('1 lifetime stream,')), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    final afterDispose = playRepository.getAllCalls;
    signal.notify(LibraryChangeKind.listeningRecorded);
    await settle(tester);

    expect(playRepository.getAllCalls, afterDispose);
  });
}

const _hour = Duration(hours: 1);

/// Fires the refresher's debounce (fake time), then lets the database work
/// finish (real time), then builds the result.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 400));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
  }
  await tester.pump();
}

class _EmptyPlaybackSessions implements PlaybackSessionRepository {
  @override
  Future<void> create(PlaybackSession session) async {}

  @override
  Future<void> save(PlaybackSession session) async {}

  @override
  Future<PlaybackSession?> getById(String id) async => null;

  @override
  Future<List<PlaybackSession>> getByIds(Iterable<String> ids) async =>
      const [];

  @override
  Future<List<PlaybackSession>> getOpen() async => const [];

  @override
  Future<List<PlaybackSession>> getAll({
    DateTime? startedAtOrAfter,
    DateTime? startedBefore,
  }) async => const [];

  @override
  Future<List<PlaybackSession>> getHistoryPage({
    DateTime? startedAtOrAfter,
    DateTime? startedBefore,
    ListeningHistoryCursor? before,
    required int limit,
  }) async => const [];
}

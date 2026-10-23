import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' show Theme;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sonus_next/app/app_restart_scope.dart';
import 'package:sonus_next/app/sonus_app.dart';
import 'package:sonus_next/core/design/sonus_theme_catalog.dart';
import 'package:sonus_next/core/design/sonus_theme_id.dart';
import 'package:sonus_next/core/design/sonus_tokens.dart';
import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/player/application/controllers/playback_coordinator.dart';
import 'package:sonus_next/features/player/domain/models/playback_repeat_mode.dart';
import 'package:sonus_next/features/player/domain/models/playback_state.dart';
import 'package:sonus_next/features/player/domain/models/playback_track.dart';
import 'package:sonus_next/features/player/domain/repositories/track_lyrics_repository.dart';
import 'package:sonus_next/features/player/domain/services/playback_engine.dart';
import 'package:sonus_next/features/player/presentation/controllers/lyrics_controller.dart';
import 'package:sonus_next/features/player/presentation/controllers/playback_state_controller.dart';
import 'package:sonus_next/features/settings/application/controllers/appearance_controller.dart';
import 'package:sonus_next/features/settings/data/appearance_preferences_store.dart';
import 'package:sonus_next/features/settings/domain/models/appearance_preferences.dart';

class FakePlaybackEngine implements PlaybackEngine {
  final StreamController<PlaybackState> _controller =
      StreamController<PlaybackState>.broadcast();

  int disposeCalls = 0;

  @override
  PlaybackState get currentState => const PlaybackState();

  @override
  Stream<PlaybackState> get states => _controller.stream;

  @override
  Future<void> loadQueue(
    List<PlaybackTrack> tracks, {
    int startIndex = 0,
    bool autoPlay = false,
  }) async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> skipNext() async {}

  @override
  Future<void> skipPrevious() async {}

  @override
  Future<void> skipToIndex(int index) async {}

  @override
  Future<void> insertTrack(PlaybackTrack track, {required int index}) async {}

  @override
  Future<void> appendTrack(PlaybackTrack track) async {}

  @override
  Future<void> removeTrackAt(int index) async {}

  @override
  Future<void> moveTrack({
    required int oldIndex,
    required int newIndex,
  }) async {}

  @override
  Future<void> setShuffleEnabled(bool enabled) async {}

  @override
  Future<void> setRepeatMode(PlaybackRepeatMode mode) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {
    disposeCalls++;

    if (!_controller.isClosed) {
      await _controller.close();
    }
  }
}

class TestDatabaseFixture {
  TestDatabaseFixture({required this.database, required this.directory});

  final AppDatabase database;
  final Directory directory;

  Future<void> dispose() async {
    await database.close();

    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }
}

Future<TestDatabaseFixture> createTestDatabase() async {
  final directory = await Directory.systemTemp.createTemp('sonus_widget_test_');

  final databasePath = '${directory.path}${Platform.pathSeparator}sonus.db';

  final database = AppDatabase(
    databaseFactory: databaseFactoryFfiNoIsolate,
    databasePath: databasePath,
  );

  await database.database;

  return TestDatabaseFixture(database: database, directory: directory);
}

Future<TestDatabaseFixture> createTestDatabaseFor(WidgetTester tester) async {
  late TestDatabaseFixture fixture;

  await tester.runAsync(() async {
    fixture = await createTestDatabase();
  });

  return fixture;
}

void addDatabaseTearDown(WidgetTester tester, TestDatabaseFixture fixture) {
  addTearDown(() async {
    await tester.runAsync(fixture.dispose);
  });
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  testWidgets('Sonus app exposes one playback coordinator', (tester) async {
    final engine = FakePlaybackEngine();
    final fixture = await createTestDatabaseFor(tester);
    final database = fixture.database;

    addDatabaseTearDown(tester, fixture);

    var factoryCalls = 0;

    await tester.pumpWidget(
      SonusApp(
        libraryDatabase: database,
        playbackEngineFactory: () {
          factoryCalls++;
          return engine;
        },
      ),
    );

    expect(find.text('Sonus'), findsOneWidget);
    expect(factoryCalls, 1);

    final sonusContext = tester.element(find.text('Sonus'));

    final coordinator = Provider.of<PlaybackCoordinator>(
      sonusContext,
      listen: false,
    );

    expect(coordinator, isNotNull);

    final playbackStateController = Provider.of<PlaybackStateController>(
      sonusContext,
      listen: false,
    );

    expect(playbackStateController, isNotNull);

    await tester.pump();

    expect(factoryCalls, 1);
  });

  testWidgets('Sonus app wires playback lyrics dependencies', (tester) async {
    final engine = FakePlaybackEngine();
    final fixture = await createTestDatabaseFor(tester);
    final database = fixture.database;

    addDatabaseTearDown(tester, fixture);

    await tester.pumpWidget(
      SonusApp(libraryDatabase: database, playbackEngineFactory: () => engine),
    );

    await tester.pump();
    await tester.pump();

    final sonusContext = tester.element(find.text('Sonus'));

    final providedDatabase = Provider.of<AppDatabase>(
      sonusContext,
      listen: false,
    );

    final coordinator = Provider.of<PlaybackCoordinator>(
      sonusContext,
      listen: false,
    );

    final playbackStateController = Provider.of<PlaybackStateController>(
      sonusContext,
      listen: false,
    );

    final lyricsRepository = Provider.of<TrackLyricsRepository?>(
      sonusContext,
      listen: false,
    );

    final lyricsController = Provider.of<LyricsController?>(
      sonusContext,
      listen: false,
    );

    expect(providedDatabase, same(database));
    expect(coordinator, isNotNull);
    expect(playbackStateController, isNotNull);
    expect(lyricsRepository, isNotNull);
    expect(lyricsController, isNotNull);
    expect(lyricsController!.state.songId, isNull);
  });

  testWidgets('playback engine survives rebuilds', (tester) async {
    final engine = FakePlaybackEngine();
    final fixture = await createTestDatabaseFor(tester);
    final database = fixture.database;

    addDatabaseTearDown(tester, fixture);

    var factoryCalls = 0;

    await tester.pumpWidget(
      SonusApp(
        libraryDatabase: database,
        playbackEngineFactory: () {
          factoryCalls++;
          return engine;
        },
      ),
    );

    expect(factoryCalls, 1);

    await tester.pump();

    expect(factoryCalls, 1);

    await tester.pump();

    expect(factoryCalls, 1);
  });

  testWidgets('Sonus app applies the stored appearance and keeps it across '
      'a restore reload', (tester) async {
    final engine = FakePlaybackEngine();
    final fixture = await createTestDatabaseFor(tester);
    addDatabaseTearDown(tester, fixture);

    final storage = {
      AppearancePreferencesStore.preferencesKey: jsonEncode(
        const AppearancePreferences(theme: SonusThemeId.kickflip).toJson(),
      ),
    };
    final appearance = AppearanceController(
      store: AppearancePreferencesStore.forTesting(
        getString: (key) async => storage[key],
        setString: (key, value) async => storage[key] = value,
      ),
    );
    addTearDown(appearance.dispose);
    await appearance.load();

    await tester.pumpWidget(
      SonusApp(
        libraryDatabase: fixture.database,
        playbackEngineFactory: () => engine,
        appearanceController: appearance,
      ),
    );
    await tester.pump();

    final kickflip = SonusThemeCatalog.of(SonusThemeId.kickflip).palette;
    SonusColors colors() =>
        Theme.of(tester.element(find.text('Sonus'))).extension<SonusColors>()!;

    expect(colors().background, kickflip.background);

    AppRestartScope.restart(tester.element(find.text('Sonus')));
    await tester.pump();
    await tester.pump();

    expect(colors().background, kickflip.background);
    expect(
      Provider.of<AppearanceController>(
        tester.element(find.text('Sonus')),
        listen: false,
      ),
      same(appearance),
    );
  });

  testWidgets('playback engine is disposed with app scope', (tester) async {
    final engine = FakePlaybackEngine();
    final fixture = await createTestDatabaseFor(tester);
    final database = fixture.database;

    addDatabaseTearDown(tester, fixture);

    await tester.pumpWidget(
      SonusApp(libraryDatabase: database, playbackEngineFactory: () => engine),
    );

    expect(engine.disposeCalls, 0);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(engine.disposeCalls, 1);
  });
}

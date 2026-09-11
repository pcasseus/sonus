import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sonus_next/app/sonus_app.dart';
import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/player/application/controllers/playback_coordinator.dart';
import 'package:sonus_next/features/player/domain/models/playback_repeat_mode.dart';
import 'package:sonus_next/features/player/domain/models/playback_state.dart';
import 'package:sonus_next/features/player/domain/models/playback_track.dart';
import 'package:sonus_next/features/player/domain/services/playback_engine.dart';
import 'package:sonus_next/features/player/presentation/controllers/playback_state_controller.dart';

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

AppDatabase createTestDatabase() {
  return AppDatabase(
    databaseFactory: databaseFactoryFfi,
    databasePath: inMemoryDatabasePath,
  );
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  testWidgets('Sonus app exposes one playback coordinator', (tester) async {
    final engine = FakePlaybackEngine();
    final database = createTestDatabase();

    addTearDown(database.close);

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

  testWidgets('playback engine survives rebuilds', (tester) async {
    final engine = FakePlaybackEngine();
    final database = createTestDatabase();

    addTearDown(database.close);

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

  testWidgets('playback engine is disposed with app scope', (tester) async {
    final engine = FakePlaybackEngine();
    final database = createTestDatabase();

    addTearDown(database.close);

    await tester.pumpWidget(
      SonusApp(libraryDatabase: database, playbackEngineFactory: () => engine),
    );

    expect(engine.disposeCalls, 0);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(engine.disposeCalls, 1);
  });
}

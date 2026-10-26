import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/design/widgets/playback/sonus_playing_indicator.dart';
import 'package:sonus_next/features/player/application/controllers/playback_coordinator.dart';
import 'package:sonus_next/features/player/domain/models/playback_queue.dart';
import 'package:sonus_next/features/player/domain/models/playback_repeat_mode.dart';
import 'package:sonus_next/features/player/domain/models/playback_state.dart';
import 'package:sonus_next/features/player/domain/models/playback_track.dart';
import 'package:sonus_next/features/player/domain/services/playback_engine.dart';
import 'package:sonus_next/features/player/presentation/models/now_playing_mark.dart';

import 'album_profile_page_test.dart' as base;

class _Engine implements PlaybackEngine {
  final _states = StreamController<PlaybackState>.broadcast();
  PlaybackState _state = const PlaybackState();

  void emit(
    String songId,
    PlaybackStatus status, {
    Duration position = Duration.zero,
  }) {
    _state = PlaybackState(
      status: status,
      position: position,
      queue: PlaybackQueue(
        tracks: [
          PlaybackTrack(
            songId: songId,
            title: 'x',
            artistId: 'artist-1',
            artistName: 'Artist',
            albumId: 'album-1',
            albumTitle: 'Album',
            filePath: '/m/$songId.mp3',
            duration: const Duration(minutes: 3),
          ),
        ],
        currentIndex: 0,
      ),
    );
    _states.add(_state);
  }

  @override
  Stream<PlaybackState> get states => _states.stream;

  @override
  PlaybackState get currentState => _state;

  @override
  Future<void> dispose() => _states.close();

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
}

void main() {
  late _Engine engine;

  setUp(() => engine = _Engine());
  tearDown(() => engine.dispose());

  Future<void> pumpAlbum(WidgetTester tester) async {
    await tester.pumpWidget(
      base.buildSubject(
        repository: base.FakeLibraryQueryRepository(
          album: base.createAlbum(),
          tracks: [
            base.createTrack(songId: 'one', title: 'Same Title'),
            base.createTrack(
              songId: 'two',
              title: 'Same Title',
              trackNumber: 2,
            ),
          ],
        ),
        playbackCoordinator: PlaybackCoordinator(engine: engine),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder playingRow(String songId) =>
      find.byKey(ValueKey<String>('album-track-playing-$songId'));

  testWidgets('the playing song is marked by its ID, not its title', (
    tester,
  ) async {
    await pumpAlbum(tester);
    expect(find.byType(SonusPlayingIndicator), findsNothing);

    engine.emit('two', PlaybackStatus.playing);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(playingRow('two'), findsOneWidget);
    expect(playingRow('one'), findsNothing);
    expect(find.bySemanticsLabel(RegExp('Now playing')), findsOneWidget);
  });

  testWidgets('paused keeps the mark, still; stopped clears it', (
    tester,
  ) async {
    await pumpAlbum(tester);

    engine.emit('one', PlaybackStatus.paused);
    await tester.pumpAndSettle(); // Settles: nothing animates while paused.
    expect(playingRow('one'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Paused')), findsOneWidget);

    engine.emit('one', PlaybackStatus.idle);
    await tester.pumpAndSettle();
    expect(find.byType(SonusPlayingIndicator), findsNothing);
  });

  testWidgets('the row keeps its height when it becomes current', (
    tester,
  ) async {
    await pumpAlbum(tester);
    final row = find.byKey(const ValueKey<String>('album-track-one'));
    final before = tester.getSize(row);

    engine.emit('one', PlaybackStatus.paused);
    await tester.pumpAndSettle();

    expect(tester.getSize(row), before);
  });

  testWidgets('with reduced motion the bars stay still', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pumpAlbum(tester);

    engine.emit('one', PlaybackStatus.playing);
    await tester.pumpAndSettle(); // Would time out if the bars moved.

    expect(playingRow('one'), findsOneWidget);
  });

  test('position updates never reach the lists', () async {
    final coordinator = PlaybackCoordinator(engine: engine);
    final marks = <NowPlayingMark>[];
    final subscription = NowPlayingMark.changes(coordinator).listen(marks.add);

    for (var second = 0; second < 30; second++) {
      engine.emit(
        'one',
        PlaybackStatus.playing,
        position: Duration(seconds: second),
      );
    }
    engine.emit('one', PlaybackStatus.paused);
    await pumpEventQueue();
    await subscription.cancel();

    expect(marks, const [
      NowPlayingMark(songId: 'one', isPlaying: true),
      NowPlayingMark(songId: 'one'),
    ]);
  });
}

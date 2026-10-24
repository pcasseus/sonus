import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:sonus_next/features/player/application/controllers/playback_coordinator.dart';
import 'package:sonus_next/features/player/domain/models/lyric_line.dart';
import 'package:sonus_next/features/player/domain/models/playback_queue.dart';
import 'package:sonus_next/features/player/domain/models/playback_repeat_mode.dart';
import 'package:sonus_next/features/player/domain/models/playback_state.dart';
import 'package:sonus_next/features/player/domain/models/playback_track.dart';
import 'package:sonus_next/features/player/domain/models/track_lyrics.dart';
import 'package:sonus_next/features/player/domain/repositories/track_lyrics_repository.dart';
import 'package:sonus_next/features/player/domain/services/playback_engine.dart';
import 'package:sonus_next/features/player/presentation/controllers/lyrics_controller.dart';
import 'package:sonus_next/features/player/presentation/controllers/lyrics_state.dart';
import 'package:sonus_next/features/player/presentation/controllers/playback_state_controller.dart';
import 'package:sonus_next/features/player/presentation/pages/lyrics_page.dart';

class FakePlaybackEngine implements PlaybackEngine {
  FakePlaybackEngine({PlaybackState? initialState})
    : _state = initialState ?? const PlaybackState();

  final StreamController<PlaybackState> _states =
      StreamController<PlaybackState>.broadcast();

  PlaybackState _state;

  Duration? lastSeekPosition;

  @override
  PlaybackState get currentState => _state;

  @override
  Stream<PlaybackState> get states => _states.stream;

  void emit(PlaybackState state) {
    _state = state;
    _states.add(state);
  }

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
  Future<void> seek(Duration position) async {
    lastSeekPosition = position;
  }

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
    if (!_states.isClosed) {
      await _states.close();
    }
  }
}

class FakeTrackLyricsRepository implements TrackLyricsRepository {
  final Map<String, TrackLyrics?> lyricsBySongId = <String, TrackLyrics?>{};
  final Map<String, Object> errorsBySongId = <String, Object>{};
  final Map<String, Completer<TrackLyrics?>> pendingBySongId =
      <String, Completer<TrackLyrics?>>{};

  final List<String> requestedSongIds = <String>[];

  @override
  Future<TrackLyrics?> getBySongId(String songId) {
    requestedSongIds.add(songId);

    final pending = pendingBySongId[songId];
    if (pending != null) {
      return pending.future;
    }

    final error = errorsBySongId[songId];
    if (error != null) {
      return Future<TrackLyrics?>.error(error);
    }

    return Future<TrackLyrics?>.value(lyricsBySongId[songId]);
  }

  @override
  Future<void> save({
    required String songId,
    String? plainText,
    String? syncedText,
  }) async {}

  @override
  Future<void> deleteBySongId(String songId) async {}
}

const track1 = PlaybackTrack(
  songId: 'song-1',
  title: 'First Song',
  artistId: 'artist-1',
  artistName: 'First Artist',
  albumId: 'album-1',
  albumTitle: 'First Album',
  filePath: '/music/first.mp3',
  duration: Duration(minutes: 3),
);

PlaybackState playbackState({Duration position = Duration.zero}) {
  return PlaybackState(
    queue: const PlaybackQueue(
      tracks: <PlaybackTrack>[track1],
      currentIndex: 0,
    ),
    status: PlaybackStatus.playing,
    position: position,
    duration: const Duration(minutes: 3),
  );
}

class TestHarness {
  TestHarness({
    required this.engine,
    required this.coordinator,
    required this.playbackController,
    required this.repository,
    this.lyricsController,
  });

  final FakePlaybackEngine engine;
  final PlaybackCoordinator coordinator;
  final PlaybackStateController playbackController;
  final FakeTrackLyricsRepository repository;
  final LyricsController? lyricsController;

  Future<void> dispose() async {
    lyricsController?.dispose();
    playbackController.dispose();
    await engine.dispose();
  }
}

TestHarness createHarness({
  PlaybackState? initialState,
  void Function(FakeTrackLyricsRepository repository)? configureRepository,
  bool provideLyricsController = true,
}) {
  final engine = FakePlaybackEngine(
    initialState: initialState ?? playbackState(),
  );

  final coordinator = PlaybackCoordinator(engine: engine);
  final playbackController = PlaybackStateController(coordinator: coordinator);
  final repository = FakeTrackLyricsRepository();

  configureRepository?.call(repository);

  final lyricsController = provideLyricsController
      ? LyricsController(
          playbackCoordinator: coordinator,
          repository: repository,
        )
      : null;

  return TestHarness(
    engine: engine,
    coordinator: coordinator,
    playbackController: playbackController,
    repository: repository,
    lyricsController: lyricsController,
  );
}

Widget buildSubject(TestHarness harness) {
  return MultiProvider(
    providers: [
      Provider<PlaybackCoordinator>.value(value: harness.coordinator),
      ChangeNotifierProvider<PlaybackStateController>.value(
        value: harness.playbackController,
      ),
      ChangeNotifierProvider<LyricsController?>.value(
        value: harness.lyricsController,
      ),
    ],
    child: const MaterialApp(home: LyricsPage()),
  );
}

Future<void> pumpSubject(WidgetTester tester, TestHarness harness) async {
  await tester.binding.setSurfaceSize(const Size(430, 932));
  await tester.pumpWidget(buildSubject(harness));
  await tester.pump();
  await tester.pump();
}

void main() {
  tearDown(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  testWidgets('shows initialization state before lyrics controller is ready', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final harness = createHarness(provideLyricsController: false);
    addTearDown(harness.dispose);

    await tester.pumpWidget(buildSubject(harness));
    await tester.pump();

    expect(find.byKey(const ValueKey<String>('lyrics-page')), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('lyrics-initializing')),
      findsOneWidget,
    );
    expect(find.text('First Song'), findsOneWidget);
  });

  testWidgets('shows loading while lyrics request is pending', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final completer = Completer<TrackLyrics?>();

    final harness = createHarness(
      configureRepository: (repository) {
        repository.pendingBySongId['song-1'] = completer;
      },
    );
    addTearDown(harness.dispose);

    await pumpSubject(tester, harness);

    expect(
      find.byKey(const ValueKey<String>('lyrics-loading')),
      findsOneWidget,
    );
    expect(harness.repository.requestedSongIds, <String>['song-1']);

    completer.complete(null);
    await tester.pump();
    await tester.pump();
  });

  testWidgets('renders synced lyrics and highlights current line', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final harness = createHarness(
      initialState: playbackState(position: const Duration(seconds: 12)),
      configureRepository: (repository) {
        repository.lyricsBySongId['song-1'] = const TrackLyrics(
          songId: 'song-1',
          syncedLines: <LyricLine>[
            LyricLine(timestamp: Duration(seconds: 5), text: 'First lyric'),
            LyricLine(timestamp: Duration(seconds: 10), text: 'Second lyric'),
            LyricLine(timestamp: Duration(seconds: 15), text: 'Third lyric'),
          ],
        );
      },
    );
    addTearDown(harness.dispose);

    await pumpSubject(tester, harness);

    expect(
      find.byKey(const ValueKey<String>('synced-lyrics-list')),
      findsOneWidget,
    );
    expect(find.text('First lyric'), findsOneWidget);
    expect(find.text('Second lyric'), findsOneWidget);
    expect(find.text('Third lyric'), findsOneWidget);

    final activeText = tester.widget<Text>(
      find.byKey(const ValueKey<String>('lyrics-active-line')),
    );

    expect(activeText.data, 'Second lyric');
  });

  testWidgets('active synced line follows playback position', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final harness = createHarness(
      initialState: playbackState(position: const Duration(seconds: 6)),
      configureRepository: (repository) {
        repository.lyricsBySongId['song-1'] = const TrackLyrics(
          songId: 'song-1',
          syncedLines: <LyricLine>[
            LyricLine(timestamp: Duration(seconds: 5), text: 'First lyric'),
            LyricLine(timestamp: Duration(seconds: 10), text: 'Second lyric'),
            LyricLine(timestamp: Duration(seconds: 15), text: 'Third lyric'),
          ],
        );
      },
    );
    addTearDown(harness.dispose);

    await pumpSubject(tester, harness);

    Text activeText = tester.widget<Text>(
      find.byKey(const ValueKey<String>('lyrics-active-line')),
    );

    expect(activeText.data, 'First lyric');

    harness.engine.emit(playbackState(position: const Duration(seconds: 12)));

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    activeText = tester.widget<Text>(
      find.byKey(const ValueKey<String>('lyrics-active-line')),
    );

    expect(activeText.data, 'Second lyric');
  });

  testWidgets('follows long wrapping lyrics on a narrow screen (SN-44)', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const lineCount = 40;
    final harness = createHarness(
      initialState: playbackState(position: const Duration(seconds: 1)),
      configureRepository: (repository) {
        repository.lyricsBySongId['song-1'] = TrackLyrics(
          songId: 'song-1',
          syncedLines: <LyricLine>[
            for (var i = 0; i < lineCount; i++)
              LyricLine(
                timestamp: Duration(seconds: i * 5),
                text:
                    'Line $i keeps going long enough that it has to wrap '
                    'across several rows on a small phone screen',
              ),
          ],
        );
      },
    );
    addTearDown(harness.dispose);

    await tester.binding.setSurfaceSize(const Size(320, 640));
    await tester.pumpWidget(buildSubject(harness));
    await tester.pump();
    await tester.pump();

    for (final target in [12, 24, 35]) {
      harness.engine.emit(
        playbackState(position: Duration(seconds: target * 5 + 1)),
      );
      await tester.pumpAndSettle();

      final line = find.byKey(
        ValueKey<String>('lyrics-line-container-$target'),
      );
      expect(line, findsOneWidget, reason: 'line $target was never built');

      final list = tester.getRect(
        find.byKey(const ValueKey<String>('synced-lyrics-list')),
      );
      final rect = tester.getRect(line);
      expect(
        rect.top >= list.top && rect.bottom <= list.bottom,
        isTrue,
        reason: 'active line $target at $rect is outside the list $list',
      );
    }
  });

  testWidgets('follows the active line without animating when motion is '
      'reduced', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final harness = createHarness(
      initialState: playbackState(position: const Duration(seconds: 1)),
      configureRepository: (repository) {
        repository.lyricsBySongId['song-1'] = TrackLyrics(
          songId: 'song-1',
          syncedLines: <LyricLine>[
            for (var i = 0; i < 40; i++)
              LyricLine(
                timestamp: Duration(seconds: i * 5),
                text: 'Line $i',
              ),
          ],
        );
      },
    );
    addTearDown(harness.dispose);

    await tester.binding.setSurfaceSize(const Size(320, 640));
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: buildSubject(harness),
      ),
    );
    await tester.pump();
    await tester.pump();

    harness.engine.emit(playbackState(position: const Duration(seconds: 151)));
    await tester.pump();
    // One frame for the post-frame scroll; no animation time passes.
    await tester.pump();

    final list = tester.getRect(
      find.byKey(const ValueKey<String>('synced-lyrics-list')),
    );
    final rect = tester.getRect(
      find.byKey(const ValueKey<String>('lyrics-line-container-30')),
    );
    expect(rect.top >= list.top && rect.bottom <= list.bottom, isTrue);
  });

  group('follows the playback authority (SN-44)', () {
    const firstLines = <LyricLine>[
      LyricLine(timestamp: Duration(seconds: 5), text: 'First lyric'),
      LyricLine(timestamp: Duration(seconds: 10), text: 'Second lyric'),
      LyricLine(timestamp: Duration(seconds: 15), text: 'Third lyric'),
    ];

    // Engine states arrive through a broadcast stream (a microtask), so
    // the page shows them on the frame after delivery.
    Future<void> deliver(WidgetTester tester) async {
      await tester.pump();
      await tester.pump();
    }

    String activeLine(WidgetTester tester) => tester
        .widget<Text>(find.byKey(const ValueKey<String>('lyrics-active-line')))
        .data!;

    testWidgets('pausing freezes the highlighted line', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final harness = createHarness(
        initialState: playbackState(position: const Duration(seconds: 12)),
        configureRepository: (repository) {
          repository.lyricsBySongId['song-1'] = const TrackLyrics(
            songId: 'song-1',
            syncedLines: firstLines,
          );
        },
      );
      addTearDown(harness.dispose);
      await pumpSubject(tester, harness);

      harness.engine.emit(
        PlaybackState(
          queue: playbackState().queue,
          status: PlaybackStatus.paused,
          position: const Duration(seconds: 12),
          duration: const Duration(minutes: 3),
        ),
      );
      await deliver(tester);
      // Time passes with no position updates: nothing advances.
      await tester.pump(const Duration(seconds: 10));

      expect(activeLine(tester), 'Second lyric');
    });

    testWidgets('seeking selects the matching line at once', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final harness = createHarness(
        initialState: playbackState(position: const Duration(seconds: 16)),
        configureRepository: (repository) {
          repository.lyricsBySongId['song-1'] = const TrackLyrics(
            songId: 'song-1',
            syncedLines: firstLines,
          );
        },
      );
      addTearDown(harness.dispose);
      await pumpSubject(tester, harness);
      expect(activeLine(tester), 'Third lyric');

      harness.engine.emit(playbackState(position: const Duration(seconds: 6)));
      await deliver(tester);

      expect(activeLine(tester), 'First lyric');
    });

    testWidgets('skipping never shows the previous song\'s lyrics', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final nextLyrics = Completer<TrackLyrics?>();
      final harness = createHarness(
        initialState: playbackState(position: const Duration(seconds: 12)),
        configureRepository: (repository) {
          repository.lyricsBySongId['song-1'] = const TrackLyrics(
            songId: 'song-1',
            syncedLines: firstLines,
          );
          repository.pendingBySongId['song-2'] = nextLyrics;
        },
      );
      addTearDown(harness.dispose);
      await pumpSubject(tester, harness);
      expect(activeLine(tester), 'Second lyric');

      const track2 = PlaybackTrack(
        songId: 'song-2',
        title: 'Second Song',
        artistId: 'artist-1',
        artistName: 'First Artist',
        albumId: 'album-1',
        albumTitle: 'First Album',
        filePath: '/music/second.mp3',
        duration: Duration(minutes: 3),
      );
      harness.engine.emit(
        const PlaybackState(
          queue: PlaybackQueue(
            tracks: <PlaybackTrack>[track1, track2],
            currentIndex: 1,
          ),
          status: PlaybackStatus.playing,
          duration: Duration(minutes: 3),
        ),
      );
      await deliver(tester);

      expect(find.text('Second lyric'), findsNothing);
      expect(find.text('First lyric'), findsNothing);

      nextLyrics.complete(
        const TrackLyrics(
          songId: 'song-2',
          syncedLines: <LyricLine>[
            LyricLine(timestamp: Duration.zero, text: 'New song opening'),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(activeLine(tester), 'New song opening');
      expect(find.text('Second lyric'), findsNothing);
    });
  });

  testWidgets('tapping synced lyric seeks to its timestamp', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final harness = createHarness(
      initialState: playbackState(position: const Duration(seconds: 6)),
      configureRepository: (repository) {
        repository.lyricsBySongId['song-1'] = const TrackLyrics(
          songId: 'song-1',
          syncedLines: <LyricLine>[
            LyricLine(timestamp: Duration(seconds: 5), text: 'First lyric'),
            LyricLine(timestamp: Duration(seconds: 10), text: 'Second lyric'),
            LyricLine(timestamp: Duration(seconds: 15), text: 'Third lyric'),
          ],
        );
      },
    );
    addTearDown(harness.dispose);

    await pumpSubject(tester, harness);

    await tester.tap(find.byKey(const ValueKey<String>('lyrics-line-2')));
    await tester.pump();

    expect(harness.engine.lastSeekPosition, const Duration(seconds: 15));
  });

  testWidgets('position changes do not reload lyrics', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final harness = createHarness(
      initialState: playbackState(position: const Duration(seconds: 6)),
      configureRepository: (repository) {
        repository.lyricsBySongId['song-1'] = const TrackLyrics(
          songId: 'song-1',
          syncedLines: <LyricLine>[
            LyricLine(timestamp: Duration(seconds: 5), text: 'First lyric'),
            LyricLine(timestamp: Duration(seconds: 10), text: 'Second lyric'),
          ],
        );
      },
    );
    addTearDown(harness.dispose);

    await pumpSubject(tester, harness);

    // Opening the page reads the current song's lyrics again (SN-44);
    // only reads for this song are allowed, and position ticks add none.
    expect(harness.repository.requestedSongIds.toSet(), <String>{'song-1'});
    final readsAfterOpening = harness.repository.requestedSongIds.length;

    harness.engine.emit(playbackState(position: const Duration(seconds: 12)));

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(harness.repository.requestedSongIds, hasLength(readsAfterOpening));
  });

  testWidgets('opening the page shows lyrics saved while the song played '
      '(SN-44)', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final harness = createHarness();
    addTearDown(harness.dispose);
    // The controller finds nothing before the page is ever opened.
    await tester.pump();
    expect(harness.lyricsController!.state.status, LyricsStatus.empty);

    harness.repository.lyricsBySongId['song-1'] = const TrackLyrics(
      songId: 'song-1',
      plainText: 'Imported while playing',
    );
    await pumpSubject(tester, harness);
    await tester.pump();

    expect(find.text('Imported while playing'), findsOneWidget);
  });

  testWidgets('Try again retries a failed lyrics read (SN-44)', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final harness = createHarness(
      configureRepository: (repository) {
        repository.errorsBySongId['song-1'] = StateError('busy');
      },
    );
    addTearDown(harness.dispose);
    await pumpSubject(tester, harness);
    await tester.pump();
    expect(find.byKey(const ValueKey<String>('lyrics-error')), findsOneWidget);

    harness.repository.errorsBySongId.remove('song-1');
    harness.repository.lyricsBySongId['song-1'] = const TrackLyrics(
      songId: 'song-1',
      plainText: 'Second attempt',
    );
    await tester.tap(find.byKey(const ValueKey<String>('lyrics-retry')));
    await tester.pump();
    await tester.pump();

    expect(find.text('Second attempt'), findsOneWidget);
  });

  testWidgets('uses plain lyrics when synced lyrics are unavailable', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final harness = createHarness(
      configureRepository: (repository) {
        repository.lyricsBySongId['song-1'] = const TrackLyrics(
          songId: 'song-1',
          plainText: 'First plain line\nSecond plain line',
        );
      },
    );
    addTearDown(harness.dispose);

    await pumpSubject(tester, harness);

    expect(
      find.byKey(const ValueKey<String>('plain-lyrics-scroll')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('plain-lyrics-text')),
      findsOneWidget,
    );
    expect(find.text('First plain line\nSecond plain line'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('synced-lyrics-list')),
      findsNothing,
    );
  });

  testWidgets('prefers synced lyrics when both forms exist', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final harness = createHarness(
      initialState: playbackState(position: const Duration(seconds: 6)),
      configureRepository: (repository) {
        repository.lyricsBySongId['song-1'] = const TrackLyrics(
          songId: 'song-1',
          plainText: 'Plain fallback',
          syncedLines: <LyricLine>[
            LyricLine(timestamp: Duration(seconds: 5), text: 'Synced lyric'),
          ],
        );
      },
    );
    addTearDown(harness.dispose);

    await pumpSubject(tester, harness);

    expect(
      find.byKey(const ValueKey<String>('synced-lyrics-list')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('plain-lyrics-text')),
      findsNothing,
    );
    expect(find.text('Synced lyric'), findsOneWidget);
  });

  testWidgets('shows empty state when lyrics are missing', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final harness = createHarness();
    addTearDown(harness.dispose);

    await pumpSubject(tester, harness);

    expect(find.byKey(const ValueKey<String>('lyrics-empty')), findsOneWidget);
    expect(find.text('No lyrics available'), findsOneWidget);
  });

  testWidgets('shows failure state when lyrics cannot load', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final harness = createHarness(
      configureRepository: (repository) {
        repository.errorsBySongId['song-1'] = StateError(
          'Lyrics could not load',
        );
      },
    );
    addTearDown(harness.dispose);

    await pumpSubject(tester, harness);

    expect(find.byKey(const ValueKey<String>('lyrics-error')), findsOneWidget);
    expect(find.text('Lyrics unavailable'), findsOneWidget);
  });

  testWidgets('shows no-track state when playback queue is empty', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final harness = createHarness(initialState: const PlaybackState());
    addTearDown(harness.dispose);

    await pumpSubject(tester, harness);

    expect(
      find.byKey(const ValueKey<String>('lyrics-no-track')),
      findsOneWidget,
    );
    expect(find.text('Nothing is playing'), findsOneWidget);
  });
}

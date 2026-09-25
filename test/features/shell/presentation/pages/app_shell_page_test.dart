import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:sonus_next/features/player/application/controllers/playback_coordinator.dart';
import 'package:sonus_next/features/player/domain/models/playback_repeat_mode.dart';
import 'package:sonus_next/features/player/domain/models/playback_state.dart';
import 'package:sonus_next/features/player/domain/models/playback_track.dart';
import 'package:sonus_next/features/player/domain/services/playback_engine.dart';
import 'package:sonus_next/features/player/presentation/controllers/playback_state_controller.dart';
import 'package:sonus_next/features/shell/presentation/pages/app_shell_page.dart';

void main() {
  Widget buildSubject() {
    final engine = _FakePlaybackEngine();
    final coordinator = PlaybackCoordinator(engine: engine);
    final stateController = PlaybackStateController(coordinator: coordinator);

    return MultiProvider(
      providers: [
        Provider<PlaybackCoordinator>.value(value: coordinator),
        ChangeNotifierProvider<PlaybackStateController>.value(
          value: stateController,
        ),
      ],
      child: const MaterialApp(home: AppShellPage()),
    );
  }

  testWidgets('shows all five primary destinations', (tester) async {
    await tester.pumpWidget(buildSubject());

    expect(find.text('Home'), findsWidgets);
    expect(find.text('Hot 100'), findsOneWidget);
    expect(find.text('Tracks'), findsOneWidget);
    expect(find.text('Library'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('opens search from the global top bar', (tester) async {
    await tester.pumpWidget(buildSubject());

    await tester.tap(find.byKey(const ValueKey<String>('shell-search-button')));

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byKey(const ValueKey<String>('search-page')), findsOneWidget);
  });

  testWidgets('opens imports from the global top bar', (tester) async {
    await tester.pumpWidget(buildSubject());

    await tester.tap(find.byKey(const ValueKey<String>('shell-import-button')));

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byKey(const ValueKey<String>('imports-page')), findsOneWidget);
  });

  testWidgets('settings button selects settings destination', (tester) async {
    await tester.pumpWidget(buildSubject());

    await tester.tap(
      find.byKey(const ValueKey<String>('shell-settings-button')),
    );

    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('settings-account-unavailable')),
      findsOneWidget,
    );
  });

  testWidgets('tapping a tab changes the visible destination', (tester) async {
    await tester.pumpWidget(buildSubject());

    await tester.tap(find.byKey(const ValueKey<String>('app-tab-tracks')));

    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('app-destination-tracks')),
      findsOneWidget,
    );
  });

  testWidgets('swiping changes the visible destination', (tester) async {
    await tester.pumpWidget(buildSubject());

    await tester.drag(find.byType(PageView), const Offset(-500, 0));

    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('app-destination-hot100')),
      findsOneWidget,
    );
  });

  testWidgets('keeps the playback slot mounted across destinations', (
    tester,
  ) async {
    await tester.pumpWidget(buildSubject());

    expect(
      find.byKey(const ValueKey<String>('shell-playback-slot')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey<String>('app-tab-library')));

    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('shell-playback-slot')),
      findsOneWidget,
    );
  });

  testWidgets('returns to the selected destination after closing search', (
    tester,
  ) async {
    await tester.pumpWidget(buildSubject());

    await tester.tap(find.byKey(const ValueKey<String>('app-tab-tracks')));

    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('app-destination-tracks')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey<String>('shell-search-button')));

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byKey(const ValueKey<String>('search-page')), findsOneWidget);

    Navigator.of(
      tester.element(find.byKey(const ValueKey<String>('search-page'))),
    ).pop();

    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('app-destination-tracks')),
      findsOneWidget,
    );
  });

  testWidgets('returns to the selected destination after closing imports', (
    tester,
  ) async {
    await tester.pumpWidget(buildSubject());

    await tester.tap(find.byKey(const ValueKey<String>('app-tab-library')));

    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('shell-import-button')));

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byKey(const ValueKey<String>('imports-page')), findsOneWidget);

    Navigator.of(
      tester.element(find.byKey(const ValueKey<String>('imports-page'))),
    ).pop();

    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('app-destination-library')),
      findsOneWidget,
    );
  });
}

class _FakePlaybackEngine implements PlaybackEngine {
  final StreamController<PlaybackState> _states =
      StreamController<PlaybackState>.broadcast();

  final PlaybackState _state = const PlaybackState();

  @override
  Stream<PlaybackState> get states => _states.stream;

  @override
  PlaybackState get currentState => _state;

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
    await _states.close();
  }
}

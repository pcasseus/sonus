import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/core/design/sonus_theme_id.dart';
import 'package:sonus_next/core/design/sonus_tokens.dart';
import 'package:sonus_next/core/design/widgets/sonus_brand_mark.dart';

import 'package:sonus_next/features/player/application/controllers/playback_coordinator.dart';
import 'package:sonus_next/features/player/domain/models/playback_repeat_mode.dart';
import 'package:sonus_next/features/player/domain/models/playback_state.dart';
import 'package:sonus_next/features/player/domain/models/playback_track.dart';
import 'package:sonus_next/features/player/domain/services/playback_engine.dart';
import 'package:sonus_next/features/player/presentation/controllers/playback_state_controller.dart';
import 'package:sonus_next/features/shell/presentation/pages/app_shell_page.dart';

void main() {
  Widget buildSubject({ThemeData? theme}) {
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
      child: MaterialApp(theme: theme, home: const AppShellPage()),
    );
  }

  testWidgets('shows all six primary destinations', (tester) async {
    await tester.pumpWidget(buildSubject());

    expect(find.text('Home'), findsWidgets);
    expect(find.text('Hot 100'), findsOneWidget);
    expect(find.text('Tracks'), findsOneWidget);
    expect(find.text('Library'), findsOneWidget);
    expect(find.text('Playlists'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });

  SonusBrandMarkPainter markPainter(WidgetTester tester) {
    return tester
            .widget<CustomPaint>(
              find.descendant(
                of: find.byKey(const ValueKey<String>('sonus-app-mark')),
                matching: find.byType(CustomPaint),
              ),
            )
            .painter!
        as SonusBrandMarkPainter;
  }

  testWidgets('shows the Waveform S brand mark beside the wordmark', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildSubject(theme: SonusThemeFactory.build(const SonusAppearanceSpec())),
    );

    final mark = tester.widget<SonusBrandMark>(
      find.byKey(const ValueKey<String>('sonus-app-mark')),
    );
    expect(mark.concept, SonusBrandConcept.waveformS);
    expect(SonusBrandConcept.selected, SonusBrandConcept.waveformS);
    expect(
      find.byKey(const ValueKey<String>('sonus-app-title')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.graphic_eq_rounded), findsNothing);
  });

  testWidgets('the brand mark takes its colours from the active theme', (
    tester,
  ) async {
    for (final themeId in [
      SonusThemeId.concreteSpray,
      SonusThemeId.monochrome,
      SonusThemeId.evergreen,
    ]) {
      final theme = SonusThemeFactory.build(
        SonusAppearanceSpec(themeId: themeId),
      );
      final colors = theme.extension<SonusColors>()!;

      await tester.pumpWidget(buildSubject(theme: theme));
      // Let the theme transition finish before reading the colours.
      await tester.pumpAndSettle();

      expect(markPainter(tester).primary, colors.accentPrimary);
      expect(markPainter(tester).secondary, colors.accentSecondary);
    }
  });

  testWidgets('the header announces "Sonus" only once', (tester) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      buildSubject(theme: SonusThemeFactory.build(const SonusAppearanceSpec())),
    );

    final appBar = find.byType(AppBar);
    expect(
      find.descendant(of: appBar, matching: find.bySemanticsLabel('Sonus')),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('the brand mark fits the header at 320px with 2x text', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 640),
          textScaler: TextScaler.linear(2),
        ),
        child: buildSubject(
          theme: SonusThemeFactory.build(const SonusAppearanceSpec()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final mark = tester.getRect(
      find.byKey(const ValueKey<String>('sonus-app-mark')),
    );
    expect(mark.size, const Size(30, 30));
    expect(mark.left, greaterThanOrEqualTo(0));
    expect(
      mark.right,
      lessThanOrEqualTo(
        tester
            .getRect(find.byKey(const ValueKey<String>('shell-search-button')))
            .left,
      ),
    );
  });

  testWidgets('tabs stay scrollable and readable in every theme at 320px', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    for (final themeId in SonusThemeId.values) {
      await tester.pumpWidget(
        buildSubject(
          theme: SonusThemeFactory.build(SonusAppearanceSpec(themeId: themeId)),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: themeId.label);
      expect(tester.widget<TabBar>(find.byType(TabBar)).isScrollable, isTrue);
    }
  });

  testWidgets('reduced motion switches destinations without sliding', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildSubject(
        theme: SonusThemeFactory.build(
          const SonusAppearanceSpec(reduceMotion: true),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey<String>('app-tab-library')));
    await tester.pump();

    final pageView = tester.widget<PageView>(find.byType(PageView));
    expect(pageView.controller!.page, 4);
    expect(
      find.byKey(const ValueKey<String>('app-destination-library')),
      findsOneWidget,
    );
  });

  testWidgets('normal motion still animates between destinations', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildSubject(theme: SonusThemeFactory.build(const SonusAppearanceSpec())),
    );

    await tester.tap(find.byKey(const ValueKey<String>('app-tab-library')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final controller = tester
        .widget<PageView>(find.byType(PageView))
        .controller;
    expect(controller!.page, greaterThan(0));
    expect(controller.page, lessThan(4));

    await tester.pumpAndSettle();
  });

  testWidgets('opens search from the global top bar', (tester) async {
    await tester.pumpWidget(buildSubject());

    await tester.tap(find.byKey(const ValueKey<String>('shell-search-button')));

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byKey(const ValueKey<String>('search-page')), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('shell-playback-slot')),
      findsOneWidget,
    );
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

  testWidgets('tapping playlists shows playlists destination', (tester) async {
    await tester.pumpWidget(buildSubject());

    await tester.tap(find.byKey(const ValueKey<String>('app-tab-playlists')));

    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('app-destination-playlists')),
      findsOneWidget,
    );
  });

  testWidgets('swiping changes the visible destination', (tester) async {
    await tester.pumpWidget(buildSubject());

    await tester.drag(find.byType(PageView), const Offset(-500, 0));

    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('charts-initializing')),
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

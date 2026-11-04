// The saved Library view: the Artist Roster by default, the Film Reel when
// chosen, switchable from the Library and from Settings, kept on the device
// (SharedPreferences, no database change).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/features/import/application/services/import_review_service.dart';
import 'package:sonus_next/features/import/application/services/import_workflow_service.dart';
import 'package:sonus_next/features/library/application/models/library_artist.dart';
import 'package:sonus_next/features/library/application/repositories/library_query_repository.dart';
import 'package:sonus_next/features/library/data/services/library_view_preferences_store.dart';
import 'package:sonus_next/features/library/presentation/controllers/library_view_controller.dart';
import 'package:sonus_next/features/library/presentation/models/artist_library_statistics.dart';
import 'package:sonus_next/features/library/presentation/pages/library_page.dart';
import 'package:sonus_next/features/library/presentation/services/artist_library_statistics_service.dart';
import 'package:sonus_next/features/library/presentation/widgets/library_view_switch.dart';
import 'package:sonus_next/features/settings/presentation/pages/library_settings_page.dart';

import 'library_page_test.dart' as base;

Finder byKey(String key) => find.byKey(ValueKey<String>(key));

/// An in-memory SharedPreferences.
class _Prefs {
  _Prefs([Map<String, String>? values]) : values = {...?values};

  final Map<String, String> values;
  int writes = 0;
  Object? failReads;
  Object? failWrites;
  Completer<void>? readGate;

  LibraryViewPreferencesStore store() => LibraryViewPreferencesStore.forTesting(
    getString: (key) async {
      await readGate?.future;
      if (failReads != null) throw failReads!;
      return values[key];
    },
    setString: (key, value) async {
      if (failWrites != null) throw failWrites!;
      writes++;
      values[key] = value;
    },
  );
}

class _Stats implements ArtistLibraryStatisticsService {
  _Stats(this.artists);

  final List<LibraryArtist> artists;

  @override
  Future<ArtistLibraryStatisticsSnapshot> load() async =>
      ArtistLibraryStatisticsSnapshot([
        for (final (index, artist) in artists.indexed)
          ArtistLibraryStatistics(
            artist: artist,
            rank: index + 1,
            qualifiedStreams: 10 - index,
            listened: Duration(minutes: 10 - index),
          ),
      ]);
}

void main() {
  const key = LibraryViewPreferencesStore.key;

  group('LibraryViewPreferencesStore', () {
    test('defaults to the Artist Roster', () async {
      expect(await _Prefs().store().load(), LibraryView.roster);
    });

    test('round-trips both views under library.view', () async {
      final prefs = _Prefs();
      final store = prefs.store();

      await store.save(LibraryView.filmReel);
      expect(prefs.values, {key: 'filmReel'});
      expect(await store.load(), LibraryView.filmReel);

      await store.save(LibraryView.roster);
      expect(prefs.values, {key: 'roster'});
      expect(await store.load(), LibraryView.roster);
    });

    test('an unknown value means the Roster', () async {
      final prefs = _Prefs({key: 'grid'});
      expect(await prefs.store().load(), LibraryView.roster);
      expect(prefs.values, {key: 'grid'}, reason: 'read-only');
    });

    test('never throws: failed reads mean the Roster, failed writes are '
        'dropped', () async {
      final prefs = _Prefs({key: 'filmReel'})
        ..failReads = StateError('locked')
        ..failWrites = StateError('full');
      final store = prefs.store();

      expect(await store.load(), LibraryView.roster);
      await store.save(LibraryView.filmReel);
      expect(prefs.writes, 0);
    });
  });

  group('LibraryViewController', () {
    test('starts on the Roster and loads the saved view', () async {
      final prefs = _Prefs({key: 'filmReel'});
      final controller = LibraryViewController(store: prefs.store());
      addTearDown(controller.dispose);
      var notified = 0;
      controller.addListener(() => notified++);

      expect(controller.view, LibraryView.roster);
      expect(controller.isLoaded, isFalse);

      await controller.load();

      expect(controller.view, LibraryView.filmReel);
      expect(controller.isLoaded, isTrue);
      expect(notified, 1);
    });

    test('choosing saves the view; choosing it again does nothing', () async {
      final prefs = _Prefs();
      final controller = LibraryViewController(store: prefs.store());
      addTearDown(controller.dispose);
      await controller.load();
      var notified = 0;
      controller.addListener(() => notified++);

      controller.choose(LibraryView.filmReel);
      await pumpEventQueue();
      controller.choose(LibraryView.filmReel);
      await pumpEventQueue();

      expect(controller.view, LibraryView.filmReel);
      expect(prefs.values, {key: 'filmReel'});
      expect(prefs.writes, 1);
      expect(notified, 1);
    });

    test('a choice made while loading wins over the saved view', () async {
      final prefs = _Prefs({key: 'filmReel'})..readGate = Completer<void>();
      final controller = LibraryViewController(store: prefs.store());
      addTearDown(controller.dispose);

      final loading = controller.load();
      controller.choose(LibraryView.filmReel);
      controller.choose(LibraryView.roster);
      prefs.readGate!.complete();
      await loading;
      await pumpEventQueue();

      expect(controller.view, LibraryView.roster);
      expect(prefs.values, {key: 'roster'});
    });
  });

  group('the Library follows the saved view', () {
    final ada = base.createArtist(artistId: 'ada', name: 'Ada Lune');
    final zed = base.createArtist(artistId: 'zed', name: 'Zed Night');
    final artists = [ada, zed];

    Future<void> pump(
      WidgetTester tester,
      LibraryViewController controller,
    ) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<LibraryViewController>.value(
              value: controller,
            ),
            Provider<LibraryQueryRepository?>.value(
              value: base.FakeLibraryQueryRepository(artists: artists),
            ),
            Provider<ArtistLibraryStatisticsService?>.value(
              value: _Stats(artists),
            ),
          ],
          child: MaterialApp(
            theme: SonusThemeFactory.build(const SonusAppearanceSpec()),
            home: const Scaffold(body: LibraryPage()),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<LibraryViewController> loaded(_Prefs prefs) async {
      final controller = LibraryViewController(store: prefs.store());
      await controller.load();
      return controller;
    }

    testWidgets('no saved view: the Roster', (tester) async {
      final controller = await tester.runAsync(() => loaded(_Prefs()));
      addTearDown(controller!.dispose);
      await pump(tester, controller);

      expect(byKey('artist-roster'), findsOneWidget);
      expect(byKey('film-reel-pages'), findsNothing);
    });

    testWidgets('a saved Film Reel opens on the Film Reel', (tester) async {
      final prefs = _Prefs({key: 'filmReel'});
      final controller = await tester.runAsync(() => loaded(prefs));
      addTearDown(controller!.dispose);
      await pump(tester, controller);

      expect(byKey('film-reel-pages'), findsOneWidget);
      expect(byKey('artist-roster'), findsNothing);
    });

    testWidgets('switching in the Library is saved', (tester) async {
      final prefs = _Prefs();
      final controller = await tester.runAsync(() => loaded(prefs));
      addTearDown(controller!.dispose);
      await pump(tester, controller);

      await tester.tap(byKey('library-view-reel'));
      await tester.pumpAndSettle();
      expect(byKey('film-reel-pages'), findsOneWidget);
      expect(controller.view, LibraryView.filmReel);
      expect(prefs.values, {key: 'filmReel'});

      await tester.tap(byKey('library-view-roster'));
      await tester.pumpAndSettle();
      expect(byKey('artist-roster'), findsOneWidget);
      expect(prefs.values, {key: 'roster'});
    });

    testWidgets('a change made in Settings shows in the Library, with the '
        'selection kept', (tester) async {
      final controller = await tester.runAsync(() => loaded(_Prefs()));
      addTearDown(controller!.dispose);
      await pump(tester, controller);
      await tester.tap(byKey('roster-tile-zed'));
      await tester.pumpAndSettle();

      controller.choose(LibraryView.filmReel);
      await tester.pumpAndSettle();

      expect(byKey('film-reel-pages'), findsOneWidget);
      expect(find.text('#2'), findsOneWidget, reason: 'Zed is centred');
    });

    testWidgets('finding an artist from the Film Reel keeps the Film Reel '
        'and the saved view', (tester) async {
      final prefs = _Prefs({key: 'filmReel'});
      final controller = await tester.runAsync(() => loaded(prefs));
      addTearDown(controller!.dispose);
      await pump(tester, controller);

      await tester.tap(byKey('library-search-button'));
      await tester.pumpAndSettle();
      expect(byKey('artist-finder-page'), findsOneWidget);
      await tester.tap(byKey('artist-finder-zed'));
      await tester.pumpAndSettle();

      expect(byKey('film-reel-pages'), findsOneWidget);
      expect(controller.view, LibraryView.filmReel);
      expect(prefs.writes, 0, reason: 'nothing was chosen');
    });
  });

  group('Settings › Library & Imports › Library view', () {
    Widget app(LibraryViewController? controller, {double textScale = 1}) {
      return MultiProvider(
        providers: [
          if (controller != null)
            ChangeNotifierProvider<LibraryViewController>.value(
              value: controller,
            ),
          Provider<LibraryQueryRepository?>.value(value: null),
          Provider<ImportWorkflowService?>.value(value: null),
          Provider<ImportReviewService?>.value(value: null),
        ],
        child: MaterialApp(
          theme: SonusThemeFactory.build(const SonusAppearanceSpec()),
          themeAnimationDuration: Duration.zero,
          builder: (context, child) => MediaQuery.withClampedTextScaling(
            minScaleFactor: textScale,
            maxScaleFactor: textScale,
            child: child!,
          ),
          home: const LibrarySettingsPage(),
        ),
      );
    }

    testWidgets('shows the saved view and saves a new choice', (tester) async {
      final prefs = _Prefs();
      final controller = LibraryViewController(store: prefs.store());
      addTearDown(controller.dispose);
      await tester.runAsync(controller.load);

      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();

      expect(find.text('Library view'), findsOneWidget);
      final selector = byKey('library-settings-view');
      expect(selector, findsOneWidget);
      expect(
        tester
            .widget<SegmentedButton<LibraryView>>(
              find.descendant(
                of: selector,
                matching: find.byType(SegmentedButton<LibraryView>),
              ),
            )
            .selected,
        {LibraryView.roster},
      );

      await tester.tap(find.text('Film Reel'));
      await tester.pumpAndSettle();

      expect(controller.view, LibraryView.filmReel);
      expect(prefs.values, {key: 'filmReel'});
      expect(
        tester
            .widget<SegmentedButton<LibraryView>>(
              find.byType(SegmentedButton<LibraryView>),
            )
            .selected,
        {LibraryView.filmReel},
      );
    });

    testWidgets('fits at 320dp with 2x text', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = LibraryViewController(store: _Prefs().store());
      addTearDown(controller.dispose);

      await tester.pumpWidget(app(controller, textScale: 2));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Artist Roster'), findsOneWidget);
      expect(find.text('Film Reel'), findsOneWidget);
    });

    testWidgets('hidden where the view is not saved', (tester) async {
      await tester.pumpWidget(app(null));
      await tester.pumpAndSettle();

      expect(find.text('Library view'), findsNothing);
      expect(byKey('library-settings-view'), findsNothing);
    });
  });
}

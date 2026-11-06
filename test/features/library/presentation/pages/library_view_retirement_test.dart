// App Update 1.1: the Film Reel is retired from the Library. The Artist
// Roster is the only artist view; the old saved view ("library.view",
// SharedPreferences) is no longer read, so a saved Film Reel falls back to
// the Roster, and it is left as it was (no user data is changed).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/features/import/application/services/import_review_service.dart';
import 'package:sonus_next/features/import/application/services/import_workflow_service.dart';
import 'package:sonus_next/features/library/application/models/library_artist.dart';
import 'package:sonus_next/features/library/application/repositories/library_query_repository.dart';
import 'package:sonus_next/features/library/presentation/models/artist_library_statistics.dart';
import 'package:sonus_next/features/library/presentation/pages/library_page.dart';
import 'package:sonus_next/features/library/presentation/services/artist_library_statistics_service.dart';
import 'package:sonus_next/features/settings/presentation/pages/library_settings_page.dart';

import 'library_page_test.dart' as base;

Finder byKey(String key) => find.byKey(ValueKey<String>(key));

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
  /// The retired preference, as Sonus 1.0 and earlier 1.1 builds saved it.
  const retiredKey = 'library.view';

  final ada = base.createArtist(artistId: 'ada', name: 'Ada Lune');
  final zed = base.createArtist(artistId: 'zed', name: 'Zed Night');
  final artists = [ada, zed];

  Future<void> pumpLibrary(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
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

  for (final saved in <String?>[null, 'roster', 'filmReel', 'unknown']) {
    testWidgets('saved view ${saved ?? 'none'}: the Library opens on the '
        'Roster, Page 1, first artist', (tester) async {
      SharedPreferences.setMockInitialValues({retiredKey: ?saved});
      await pumpLibrary(tester);

      expect(byKey('artist-roster'), findsOneWidget);
      expect(byKey('film-reel-pages'), findsNothing);
      expect(byKey('library-view-reel'), findsNothing);
      expect(byKey('library-view-roster'), findsNothing);
      expect(
        tester.widget<Text>(byKey('roster-featured-name')).data,
        'ADA LUNE',
      );
      expect(find.text('Page 1 of 1'), findsOneWidget);

      // The old preference is not touched.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(retiredKey), saved);
    });
  }

  testWidgets('Settings › Library & Imports has no Library view choice', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({retiredKey: 'filmReel'});
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<LibraryQueryRepository?>.value(value: null),
          Provider<ImportWorkflowService?>.value(value: null),
          Provider<ImportReviewService?>.value(value: null),
        ],
        child: MaterialApp(
          theme: SonusThemeFactory.build(const SonusAppearanceSpec()),
          home: const LibrarySettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Library view'), findsNothing);
    expect(byKey('library-settings-view'), findsNothing);
    expect(find.text('Film Reel'), findsNothing);
    expect(find.text('Manage'), findsOneWidget, reason: 'the rest stays');
  });
}

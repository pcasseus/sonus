// App Update 1.1: the Film Reel is retired from the Library and kept as a
// component for the future Sonus Wrapped; its tests pump it on its own.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/design/sonus_count_label.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/features/library/application/models/library_artist.dart';
import 'package:sonus_next/features/library/presentation/models/artist_library_statistics.dart';
import 'package:sonus_next/features/library/presentation/widgets/film_reel/artist_film_reel.dart';

/// Pumps the Film Reel over [artists] (statistics loaded, unranked unless
/// [statistics] says otherwise); its profile action opens a stand-in page
/// keyed `artist-profile-page`.
Future<void> pumpFilmReel(
  WidgetTester tester, {
  required List<LibraryArtist> artists,
  ArtistLibraryStatisticsSnapshot? statistics,
  SonusAppearanceSpec spec = const SonusAppearanceSpec(),
  ThemeData? theme,
  Size size = const Size(411, 900),
  double textScale = 1,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? SonusThemeFactory.build(spec),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => ArtistFilmReel(
            artists: artists,
            statistics:
                statistics ??
                ArtistLibraryStatisticsSnapshot([
                  for (final artist in artists)
                    ArtistLibraryStatistics(artist: artist),
                ]),
            statisticsLoaded: true,
            countLabel: sonusCount(artists.length, 'artist'),
            onSelected: (_) {},
            onOpenArtist: (_) => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => Scaffold(
                  key: const ValueKey<String>('artist-profile-page'),
                  appBar: AppBar(),
                  body: const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

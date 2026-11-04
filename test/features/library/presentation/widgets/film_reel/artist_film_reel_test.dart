// UI redesign L1: the Library's artist Film Reel, through the real
// LibraryPage, with a counting fake of the D1 statistics service.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/core/events/library_change_signal.dart';
import 'package:sonus_next/features/library/application/models/library_artist.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/application/repositories/library_query_repository.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/presentation/models/artist_library_statistics.dart';
import 'package:sonus_next/features/library/presentation/models/artist_profile_sections.dart';
import 'package:sonus_next/features/library/presentation/pages/library_page.dart';
import 'package:sonus_next/features/library/presentation/services/artist_library_statistics_service.dart';

import '../../pages/library_page_test.dart' as base;

Finder byKey(String key) => find.byKey(ValueKey<String>(key));

LibraryTrack topSong(String artistId, String title) => LibraryTrack(
  songId: 'top-$artistId',
  title: title,
  artistId: artistId,
  artistName: artistId,
  albumId: 'album-$artistId',
  albumTitle: 'Album',
  albumEditionId: 'edition-$artistId',
  albumEditionTitle: 'Standard',
  albumEditionType: AlbumEditionType.standard,
  trackNumber: 1,
  durationSeconds: 180,
  isSingle: false,
  featuredArtists: const [],
  dateAdded: DateTime(2026),
  isAvailable: true,
);

class _Stats implements ArtistLibraryStatisticsService {
  _Stats(this.byArtist, {this.gate});

  final Map<String, ArtistLibraryStatistics Function(LibraryArtist)> byArtist;
  final Completer<void>? gate;
  List<LibraryArtist> artists = const [];
  int loads = 0;

  @override
  Future<ArtistLibraryStatisticsSnapshot> load() async {
    loads++;
    await gate?.future;
    return ArtistLibraryStatisticsSnapshot([
      for (final artist in artists)
        byArtist[artist.artistId]?.call(artist) ??
            ArtistLibraryStatistics(artist: artist, listened: Duration.zero),
    ]);
  }
}

void main() {
  final ada = base.createArtist(
    artistId: 'ada',
    name: 'Ada Lune',
    albumCount: 2,
    songCount: 18,
  );
  final ben = base.createArtist(
    artistId: 'ben',
    name: 'Ben Vale',
    albumCount: 1,
    songCount: 4,
  );
  final cyd = base.createArtist(
    artistId: 'cyd',
    name: 'Cyd',
    albumCount: 3,
    songCount: 30,
  );

  _Stats statsFor(List<LibraryArtist> artists, {Completer<void>? gate}) =>
      _Stats({
        'ada': (artist) => ArtistLibraryStatistics(
          artist: artist,
          rank: 1,
          qualifiedStreams: 64,
          listened: const Duration(hours: 3, minutes: 19),
          topTrack: ArtistTopTrack(
            track: topSong('ada', 'Angel Wings'),
            streamCount: 20,
          ),
        ),
        'ben': (artist) =>
            ArtistLibraryStatistics(artist: artist, listened: Duration.zero),
        'cyd': (artist) => ArtistLibraryStatistics(
          artist: artist,
          rank: 2,
          qualifiedStreams: 7,
          listened: const Duration(minutes: 12),
        ),
      }, gate: gate)..artists = artists;

  Future<void> pump(
    WidgetTester tester, {
    required List<LibraryArtist> artists,
    required _Stats stats,
    LibraryChangeSignal? signal,
    Size size = const Size(411, 900),
    bool settle = true,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<LibraryQueryRepository?>.value(
            value: base.FakeLibraryQueryRepository(artists: artists),
          ),
          Provider<ArtistLibraryStatisticsService?>.value(value: stats),
        ],
        child: MaterialApp(
          theme: SonusThemeFactory.build(const SonusAppearanceSpec()),
          home: Scaffold(body: LibraryPage(changes: signal)),
        ),
      ),
    );
    if (settle) await tester.pumpAndSettle();
  }

  testWidgets('the centred artist\'s statistics fill both panels', (
    tester,
  ) async {
    final artists = [ada, ben, cyd];
    await pump(tester, artists: artists, stats: statsFor(artists));

    expect(find.text('Ada Lune'), findsOneWidget);
    // Left: releases, songs, rank.
    expect(find.bySemanticsLabel('2 releases'), findsOneWidget);
    expect(find.bySemanticsLabel('18 songs'), findsOneWidget);
    expect(find.text('#1'), findsOneWidget);
    // Right: streams, listening time, top track.
    expect(find.text('64'), findsOneWidget);
    expect(find.text('3h 19m'), findsOneWidget);
    expect(find.text('Angel Wings'), findsOneWidget);
    expect(find.text('Top Track'), findsOneWidget);
  });

  testWidgets('an artist without streams is Unranked, with no top track', (
    tester,
  ) async {
    final artists = [ben];
    await pump(tester, artists: artists, stats: statsFor(artists));

    expect(find.text('Unranked'), findsOneWidget);
    expect(find.text('0'), findsOneWidget, reason: 'no streams');
    expect(find.bySemanticsLabel('No listening time yet'), findsOneWidget);
    expect(find.bySemanticsLabel('No top track yet'), findsOneWidget);
  });

  testWidgets('before statistics arrive, values read as not yet known', (
    tester,
  ) async {
    final gate = Completer<void>();
    final artists = [ada];
    await pump(
      tester,
      artists: artists,
      stats: statsFor(artists, gate: gate),
      settle: false,
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Ada Lune'), findsOneWidget);
    expect(find.bySemanticsLabel('Rank loading'), findsOneWidget);
    expect(find.text('#1'), findsNothing);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('#1'), findsOneWidget);
  });

  testWidgets('swiping up centres the next artist and shows its numbers', (
    tester,
  ) async {
    final artists = [ada, ben, cyd];
    await pump(tester, artists: artists, stats: statsFor(artists));

    await tester.drag(byKey('film-reel-pages'), const Offset(0, -500));
    await tester.pumpAndSettle();

    expect(find.text('Unranked'), findsOneWidget, reason: 'Ben is centred');

    await tester.drag(byKey('film-reel-pages'), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('#2'), findsOneWidget, reason: 'Cyd is centred');
    expect(find.text('12 min'), findsOneWidget);
  });

  testWidgets('tapping a neighbour centres it; tapping the centre opens it', (
    tester,
  ) async {
    final artists = [ada, ben];
    await pump(tester, artists: artists, stats: statsFor(artists));

    await tester.tap(byKey('artist-open-ben'));
    await tester.pumpAndSettle();
    expect(byKey('artist-profile-page'), findsNothing);
    expect(find.text('Unranked'), findsOneWidget, reason: 'Ben is centred');

    await tester.tap(byKey('artist-open-ben'));
    await tester.pumpAndSettle();
    expect(byKey('artist-profile-page'), findsOneWidget);
  });

  testWidgets('the centred artist is kept after the Artist Profile, and the '
      'statistics are not reloaded', (tester) async {
    final artists = [ada, ben, cyd];
    final stats = statsFor(artists);
    await pump(tester, artists: artists, stats: stats);

    await tester.tap(byKey('film-reel-next'));
    await tester.pumpAndSettle();
    await tester.tap(byKey('film-reel-next'));
    await tester.pumpAndSettle();
    await tester.tap(byKey('artist-open-cyd'));
    await tester.pumpAndSettle();
    expect(byKey('artist-profile-page'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('#2'), findsOneWidget, reason: 'Cyd is still centred');
    expect(stats.loads, 1);
  });

  testWidgets('statistics load once, not while scrolling; recorded '
      'listening reloads them and keeps the centred artist', (tester) async {
    final artists = [ada, ben, cyd];
    final stats = statsFor(artists);
    final signal = LibraryChangeSignal();
    await pump(tester, artists: artists, stats: stats, signal: signal);

    for (var i = 0; i < 2; i++) {
      await tester.tap(byKey('film-reel-next'));
      await tester.pumpAndSettle();
    }
    await tester.tap(byKey('film-reel-previous'));
    await tester.pumpAndSettle();
    expect(stats.loads, 1);

    signal.notify(LibraryChangeKind.listeningRecorded);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(stats.loads, 2);
    expect(find.text('Unranked'), findsOneWidget, reason: 'Ben still');
  });

  testWidgets('a reload that adds an artist ahead keeps the same one centred', (
    tester,
  ) async {
    final artists = [ben, cyd];
    final stats = statsFor(artists);
    final signal = LibraryChangeSignal();
    await pump(tester, artists: artists, stats: stats, signal: signal);
    await tester.tap(byKey('film-reel-next'));
    await tester.pumpAndSettle();
    expect(find.text('#2'), findsOneWidget, reason: 'Cyd');

    artists.insert(0, ada);
    stats.artists = artists;
    signal.notify(LibraryChangeKind.importCompleted);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('3 artists'), findsOneWidget);
    expect(find.text('#2'), findsOneWidget, reason: 'Cyd still centred');
  });

  testWidgets('an artist without artwork shows initials', (tester) async {
    final artists = [ada];
    await pump(tester, artists: artists, stats: statsFor(artists));

    expect(byKey('film-reel-initials'), findsOneWidget);
    expect(find.text('AL'), findsOneWidget);
  });

  testWidgets('the Roster and search buttons are in the header', (
    tester,
  ) async {
    final artists = [ada];
    await pump(tester, artists: artists, stats: statsFor(artists));

    final roster = tester.widget<IconButton>(byKey('library-roster-button'));
    expect(roster.onPressed, isNotNull);
    expect(roster.tooltip, 'Artist Roster');
    final search = tester.widget<IconButton>(byKey('library-search-button'));
    expect(search.tooltip, 'Search artists');
  });

  testWidgets('a single artist has no chevrons to move with', (tester) async {
    final artists = [ada];
    await pump(tester, artists: artists, stats: statsFor(artists));

    expect(byKey('film-reel-next'), findsNothing);
    expect(byKey('film-reel-previous'), findsNothing);
  });

  testWidgets('2,000 artists: only the cards near the centre are built', (
    tester,
  ) async {
    final artists = [
      for (var i = 0; i < 2000; i++)
        base.createArtist(
          artistId: 'artist-$i',
          name: 'Artist ${i.toString().padLeft(4, '0')}',
          albumCount: 1,
          songCount: 1,
        ),
    ];
    final stats = statsFor(artists);
    await pump(tester, artists: artists, stats: stats);

    int builtCards() => find
        .byWidgetPredicate(
          (widget) =>
              widget.key is ValueKey<String> &&
              (widget.key! as ValueKey<String>).value.startsWith(
                'artist-open-',
              ),
        )
        .evaluate()
        .length;

    expect(find.text('2000 artists'), findsOneWidget);
    expect(builtCards(), lessThanOrEqualTo(5));

    for (var i = 0; i < 25; i++) {
      await tester.drag(byKey('film-reel-pages'), const Offset(0, -400));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();

    expect(builtCards(), lessThanOrEqualTo(5));
    expect(stats.loads, 1, reason: 'scrolling never reloads statistics');
    expect(tester.takeException(), isNull);
  });
}

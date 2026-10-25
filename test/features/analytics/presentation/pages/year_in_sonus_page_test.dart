import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sonus_next/features/analytics/application/models/analytics_behavior_metrics.dart';
import 'package:sonus_next/features/analytics/application/models/analytics_peak_day.dart';
import 'package:sonus_next/features/analytics/application/models/analytics_period.dart';
import 'package:sonus_next/features/analytics/application/models/analytics_summary.dart';
import 'package:sonus_next/features/analytics/application/models/analytics_time_window.dart';
import 'package:sonus_next/features/analytics/application/models/year_in_sonus/year_in_sonus_album_row.dart';
import 'package:sonus_next/features/analytics/application/models/year_in_sonus/year_in_sonus_artist_row.dart';
import 'package:sonus_next/features/analytics/application/models/year_in_sonus/year_in_sonus_month.dart';
import 'package:sonus_next/features/analytics/application/models/year_in_sonus/year_in_sonus_month_row.dart';
import 'package:sonus_next/features/analytics/application/models/year_in_sonus/year_in_sonus_presentation_data.dart';
import 'package:sonus_next/features/analytics/application/models/year_in_sonus/year_in_sonus_ranked_entity.dart';
import 'package:sonus_next/features/analytics/application/models/year_in_sonus/year_in_sonus_recap.dart';
import 'package:sonus_next/features/analytics/application/models/year_in_sonus/year_in_sonus_track_row.dart';
import 'package:sonus_next/features/analytics/application/services/year_in_sonus/year_in_sonus_enrichment_service.dart';
import 'package:sonus_next/features/analytics/application/services/year_in_sonus/year_in_sonus_service.dart';
import 'package:sonus_next/features/analytics/presentation/controllers/year_in_sonus_controller.dart';
import 'package:sonus_next/features/analytics/presentation/pages/year_in_sonus_page.dart';
import 'package:sonus_next/features/library/application/models/library_album.dart';
import 'package:sonus_next/features/library/application/models/library_artist.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';

void main() {
  testWidgets(
    'shows initializing state when Year in Sonus controller is unavailable',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: YearInSonusPage())),
      );

      expect(
        find.byKey(const ValueKey<String>('year-in-sonus-initializing')),
        findsOneWidget,
      );

      expect(find.text('Year in Sonus is getting ready'), findsOneWidget);
    },
  );

  // Characterization (SN-48K1): pins what the recap shows today, so the
  // redesign cannot drop or change a statistic without failing.
  group('populated recap', () {
    testWidgets('header, navigation and year in numbers', (tester) async {
      final loader = _Loader({2026: _richRecap(2026)});

      await _pump(tester, _controller(loader));

      expect(find.text('Your 2026 in Sonus'), findsOneWidget);
      expect(find.text('Your listening story so far.'), findsOneWidget);
      expect(find.text('2026'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey<String>('year-in-sonus-next-year')),
            )
            .onPressed,
        isNull,
      );

      final headline = find.byKey(
        const ValueKey<String>('year-in-sonus-headline-summary'),
      );
      for (final text in ['STREAMS', '1,234', 'LISTENING', '82h 30m']) {
        expect(
          find.descendant(of: headline, matching: find.text(text)),
          findsOneWidget,
          reason: text,
        );
      }
      for (final (label, value) in [
        ('TRACKS', '300'),
        ('ARTISTS', '60'),
        ('ALBUMS', '80'),
      ]) {
        expect(
          find.descendant(of: headline, matching: find.text(label)),
          findsOneWidget,
        );
        expect(
          find.descendant(of: headline, matching: find.text(value)),
          findsOneWidget,
          reason: label,
        );
      }
    });

    testWidgets('highlights and signature use the recap values', (
      tester,
    ) async {
      final loader = _Loader({2026: _richRecap(2026)});

      await _pump(tester, _controller(loader));

      for (final text in [
        'Most active month',
        'March',
        '200 streams',
        'Longest streak',
        '12',
        'consecutive days',
        'New artists',
        'New albums',
        'Most active day',
        'Mar 14',
        '42 streams',
        'Active days',
        '150',
      ]) {
        expect(find.text(text), findsWidgets, reason: text);
      }
      expect(find.text('2'), findsWidgets);
      expect(find.text('3'), findsWidgets);

      // 90 / 1,234 and 150 / 1,234 streams; 300 songs / 60 artists.
      expect(
        find.byKey(const ValueKey<String>('year-in-sonus-signature')),
        findsOneWidget,
      );
      expect(find.text('7.3%'), findsOneWidget);
      expect(find.text('12.2%'), findsOneWidget);
      expect(find.text('5.0'), findsOneWidget);
    });

    testWidgets('champions are the first-ranked artist, track and album', (
      tester,
    ) async {
      final loader = _Loader({2026: _richRecap(2026)});

      await _pump(tester, _controller(loader));

      expect(find.text('#1 ARTIST'), findsOneWidget);
      expect(find.text('#1 TRACK'), findsOneWidget);
      expect(find.text('#1 ALBUM'), findsOneWidget);
      expect(find.text('Artist One'), findsWidgets);
      expect(find.text('Song One'), findsWidgets);
      expect(find.text('Album One'), findsWidgets);
      expect(find.text('Artist One • 90 streams'), findsWidgets);
      expect(find.text('Artist One • 70 streams'), findsWidgets);
    });

    testWidgets('timeline shows every month with its streams and leaders', (
      tester,
    ) async {
      final loader = _Loader({2026: _richRecap(2026)});

      await _pump(tester, _controller(loader));

      final timeline = find.byKey(
        const ValueKey<String>('year-in-sonus-timeline'),
      );
      for (final name in [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ]) {
        expect(
          find.descendant(of: timeline, matching: find.text(name)),
          findsOneWidget,
          reason: name,
        );
      }
      expect(
        find.descendant(of: timeline, matching: find.text('200')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: timeline,
          matching: find.text(
            'Song: Song One  •  Artist: Artist One  •  Listening: 10h',
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('rankings keep their titles and order', (tester) async {
      final loader = _Loader({2026: _richRecap(2026)});

      await _pump(tester, _controller(loader));

      for (final title in [
        'Top 10 Artists',
        'Top 25 Tracks',
        'Top 10 Albums',
      ]) {
        expect(find.text(title), findsOneWidget, reason: title);
      }

      final first = tester.getTopLeft(find.text('Song One').last).dy;
      final second = tester.getTopLeft(find.text('Song Two').last).dy;
      expect(first, lessThan(second));
      expect(find.text('Artist Two'), findsOneWidget);
      expect(find.text('40 streams'), findsOneWidget);
    });

    testWidgets('previous year loads the year before', (tester) async {
      final loader = _Loader({2026: _richRecap(2026), 2025: _emptyRecap(2025)});

      await _pump(tester, _controller(loader));

      await tester.tap(
        find.byKey(const ValueKey<String>('year-in-sonus-previous-year')),
      );
      await tester.pumpAndSettle();

      expect(loader.requestedYears, [2026, 2025]);
      expect(find.text('Your 2025 in Sonus'), findsOneWidget);
      expect(find.text('The music that defined your year.'), findsOneWidget);
    });
  });

  testWidgets('a year without listening shows the empty story', (tester) async {
    final loader = _Loader({2026: _emptyRecap(2026)});

    await _pump(tester, _controller(loader));

    expect(
      find.byKey(const ValueKey<String>('year-in-sonus-empty')),
      findsOneWidget,
    );
    expect(find.text('No listening story for 2026 yet'), findsOneWidget);
  });

  testWidgets('a failed first load offers a retry', (tester) async {
    final loader = _Loader(const {}, error: StateError('load failed'));

    await _pump(tester, _controller(loader));

    expect(
      find.byKey(const ValueKey<String>('year-in-sonus-error')),
      findsOneWidget,
    );
    expect(find.text('Year in Sonus could not be loaded'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}

YearInSonusController _controller(_Loader loader) {
  return YearInSonusController(
    service: loader,
    enrichment: _Enricher(),
    now: () => DateTime(2026, 10, 6),
  );
}

Future<void> _pump(
  WidgetTester tester,
  YearInSonusController controller,
) async {
  // Tall enough that every chapter of the recap is built.
  await tester.binding.setSurfaceSize(const Size(800, 9000));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ChangeNotifierProvider<YearInSonusController?>.value(
      value: controller,
      child: const MaterialApp(home: Scaffold(body: YearInSonusPage())),
    ),
  );

  await controller.load();
  await tester.pumpAndSettle();
}

const _windowless = AnalyticsTimeWindow(startUtc: null, endUtc: null);

YearInSonusRecap _richRecap(int year) {
  return YearInSonusRecap(
    year: year,
    summary: const AnalyticsSummary(
      period: AnalyticsPeriod.year,
      window: _windowless,
      qualifiedStreamCount: 1234,
      qualifiedListeningDuration: Duration(hours: 80),
      distinctSongCount: 300,
      distinctArtistCount: 60,
      distinctAlbumCount: 80,
      firstQualifiedAt: null,
      lastQualifiedAt: null,
    ),
    audibleListeningDuration: const Duration(hours: 82, minutes: 30),
    behavior: AnalyticsBehaviorMetrics(
      period: AnalyticsPeriod.year,
      window: _windowless,
      sessionCount: 1400,
      endedSessionCount: 1400,
      completedSessionCount: 1100,
      skippedSessionCount: 250,
      stoppedSessionCount: 50,
      replacedSessionCount: 0,
      interruptedSessionCount: 0,
      failedSessionCount: 0,
      firstSessionStartedAt: null,
      lastSessionStartedAt: null,
      activeQualifiedDayCount: 150,
      averageQualifiedStreamsPerActiveDay: 1234 / 150,
      averageQualifiedStreamsPerCalendarDay: 1234 / 365,
      peakDay: AnalyticsPeakDay(
        localDate: DateTime(year, 3, 14),
        qualifiedStreamCount: 42,
      ),
    ),
    topTracks: const [
      YearInSonusRankedEntity(entityId: 's1', rank: 1, streams: 90),
      YearInSonusRankedEntity(entityId: 's2', rank: 2, streams: 60),
    ],
    topArtists: const [
      YearInSonusRankedEntity(entityId: 'ar1', rank: 1, streams: 150),
      YearInSonusRankedEntity(entityId: 'ar2', rank: 2, streams: 40),
    ],
    topAlbums: const [
      YearInSonusRankedEntity(entityId: 'al1', rank: 1, streams: 70),
    ],
    months: [
      for (var month = 1; month <= 12; month++)
        YearInSonusMonth(
          month: DateTime(year, month),
          streams: month == 3 ? 200 : 80 + month,
          listeningDuration: month == 3
              ? const Duration(hours: 10)
              : Duration(hours: 5, minutes: month),
          topSongId: 's1',
          topArtistId: 'ar1',
        ),
    ],
    longestListeningStreakDays: 12,
    newArtistIds: const ['ar7', 'ar8'],
    newAlbumIds: const ['al7', 'al8', 'al9'],
  );
}

YearInSonusRecap _emptyRecap(int year) {
  return YearInSonusRecap(
    year: year,
    summary: const AnalyticsSummary(
      period: AnalyticsPeriod.year,
      window: _windowless,
      qualifiedStreamCount: 0,
      qualifiedListeningDuration: Duration.zero,
      distinctSongCount: 0,
      distinctArtistCount: 0,
      distinctAlbumCount: 0,
      firstQualifiedAt: null,
      lastQualifiedAt: null,
    ),
    audibleListeningDuration: Duration.zero,
    behavior: const AnalyticsBehaviorMetrics(
      period: AnalyticsPeriod.year,
      window: _windowless,
      sessionCount: 0,
      endedSessionCount: 0,
      completedSessionCount: 0,
      skippedSessionCount: 0,
      stoppedSessionCount: 0,
      replacedSessionCount: 0,
      interruptedSessionCount: 0,
      failedSessionCount: 0,
      firstSessionStartedAt: null,
      lastSessionStartedAt: null,
      activeQualifiedDayCount: 0,
      averageQualifiedStreamsPerActiveDay: 0,
      averageQualifiedStreamsPerCalendarDay: 0,
      peakDay: null,
    ),
    topTracks: const [],
    topArtists: const [],
    topAlbums: const [],
    months: const [],
    longestListeningStreakDays: 0,
  );
}

class _Loader implements YearInSonusLoader {
  _Loader(this.results, {this.error});

  final Map<int, YearInSonusRecap> results;
  final Object? error;
  final List<int> requestedYears = [];

  @override
  Future<YearInSonusRecap> load({required int year}) async {
    requestedYears.add(year);

    final failure = error;
    if (failure != null) {
      throw failure;
    }

    return results[year] ?? _emptyRecap(year);
  }
}

/// Builds rows the way the real enricher does: library entities when they
/// exist, ranking order from the recap.
class _Enricher implements YearInSonusEnricher {
  @override
  Future<YearInSonusPresentationData> enrich(YearInSonusRecap recap) async {
    return YearInSonusPresentationData(
      recap: recap,
      tracks: [
        for (final ranking in recap.topTracks)
          YearInSonusTrackRow(
            track: _track(ranking.entityId),
            title: ranking.entityId == 's1' ? 'Song One' : 'Song Two',
            artistName: 'Artist One',
            albumTitle: 'Album One',
            ranking: ranking,
          ),
      ],
      artists: [
        for (final ranking in recap.topArtists)
          YearInSonusArtistRow(
            artist: LibraryArtist(
              artistId: ranking.entityId,
              name: ranking.entityId == 'ar1' ? 'Artist One' : 'Artist Two',
              albumCount: 2,
              songCount: 10,
              dateAdded: DateTime(2026),
            ),
            name: ranking.entityId == 'ar1' ? 'Artist One' : 'Artist Two',
            ranking: ranking,
          ),
      ],
      albums: [
        for (final ranking in recap.topAlbums)
          YearInSonusAlbumRow(
            album: LibraryAlbum(
              albumId: ranking.entityId,
              title: 'Album One',
              artistId: 'ar1',
              artistName: 'Artist One',
              trackCount: 10,
              dateAdded: DateTime(2026),
            ),
            title: 'Album One',
            artistName: 'Artist One',
            ranking: ranking,
          ),
      ],
      months: [
        for (final month in recap.months)
          YearInSonusMonthRow(
            month: month,
            topSongTitle: 'Song One',
            topArtistName: 'Artist One',
          ),
      ],
    );
  }
}

LibraryTrack _track(String id) {
  return LibraryTrack(
    songId: id,
    title: id,
    artistId: 'ar1',
    artistName: 'Artist One',
    albumId: 'al1',
    albumTitle: 'Album One',
    albumEditionId: 'e1',
    albumEditionTitle: 'Standard',
    albumEditionType: AlbumEditionType.standard,
    trackNumber: 1,
    durationSeconds: 200,
    isSingle: false,
    featuredArtists: const [],
    dateAdded: DateTime(2026),
    isAvailable: true,
    isSongBlocked: false,
    filePath: '/music/$id.mp3',
  );
}

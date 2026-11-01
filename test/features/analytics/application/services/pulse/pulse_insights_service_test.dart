import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/core/database/schema/analytics_schema.dart';
import 'package:sonus_next/features/analytics/application/models/analytics_period.dart';
import 'package:sonus_next/features/analytics/application/models/pulse/pulse_period.dart';
import 'package:sonus_next/features/analytics/application/models/pulse/pulse_period_data.dart';
import 'package:sonus_next/features/analytics/application/services/analytics_listening_duration_service.dart';
import 'package:sonus_next/features/analytics/application/services/listening_artist_attribution.dart';
import 'package:sonus_next/features/analytics/application/services/pulse/pulse_insights_service.dart';
import 'package:sonus_next/features/analytics/data/daos/playback_listening_segment_dao.dart';
import 'package:sonus_next/features/analytics/data/repositories/sqlite_playback_listening_segment_repository.dart';
import 'package:sonus_next/features/analytics/data/repositories/sqlite_pulse_listening_records.dart';
import 'package:sonus_next/features/charts/domain/services/release_chart_eligibility.dart';

/// Disposable SQLite only. Times are built from local wall-clock values, so
/// the tests hold in any time zone.
void main() {
  sqfliteFfiInit();

  late Database db;
  var sessionCount = 0;
  var segmentCount = 0;

  setUp(() async {
    sessionCount = 0;
    segmentCount = 0;
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) => AnalyticsSchema.create(db),
      ),
    );
  });

  tearDown(() => db.close());

  /// One play of [song]: an audible session from [startLocal] for
  /// [listened] (one segment), qualified after 30 s when [qualifies].
  /// Returns the session id.
  Future<String> play({
    required DateTime startLocal,
    required Duration listened,
    String song = 'song_a',
    String artist = 'artist_a',
    String album = 'album_a',
    String edition = 'edition_a',
    bool qualifies = true,
    Duration qualifiedSnapshot = const Duration(seconds: 30),
    int segments = 1,
  }) async {
    final id = 'session_${sessionCount++}';
    final start = startLocal.toUtc();
    final end = start.add(listened);
    final now = start.toIso8601String();
    await db.insert(DatabaseTables.playbackSessions, {
      'id': id,
      'song_id': song,
      'artist_id': artist,
      'album_id': album,
      'album_edition_id': edition,
      'song_title': song,
      'artist_name': artist,
      'album_title': album,
      'album_edition_title': edition,
      'started_at': start.toIso8601String(),
      'ended_at': end.toIso8601String(),
      'listened_duration_ms': listened.inMilliseconds,
      'track_duration_ms': 200000,
      'final_position_ms': listened.inMilliseconds,
      'end_reason': 'completed',
      'created_at': now,
      'updated_at': now,
    });
    if (listened > Duration.zero) {
      final part = Duration(milliseconds: listened.inMilliseconds ~/ segments);
      for (var i = 0; i < segments; i++) {
        final segStart = start.add(part * i);
        await db.insert(DatabaseTables.playbackListeningSegments, {
          'id': 'segment_${segmentCount++}',
          'playback_session_id': id,
          'started_at': segStart.toIso8601String(),
          'ended_at': segStart.add(part).toIso8601String(),
          'listened_duration_ms': part.inMilliseconds,
          'created_at': now,
          'updated_at': now,
        });
      }
    }
    if (qualifies && listened >= const Duration(seconds: 30)) {
      await db.insert(DatabaseTables.qualifiedPlays, {
        'id': 'qualified_$id',
        'playback_session_id': id,
        'song_id': song,
        'artist_id': artist,
        'album_id': album,
        'album_edition_id': edition,
        'qualified_at': start
            .add(const Duration(seconds: 30))
            .toIso8601String(),
        'listened_duration_ms': qualifiedSnapshot.inMilliseconds,
        'track_duration_ms': 200000,
        'created_at': now,
      });
    }
    return id;
  }

  PulseInsightsService service({
    DateTime? now,
    ListeningArtistAttribution? attribution,
    ReleaseChartEligibility? eligibility,
  }) => PulseInsightsService(
    records: SqlitePulseListeningRecords(db),
    artistAttribution: attribution,
    releaseEligibility: eligibility,
    nowLocal: () => now ?? DateTime(2030),
  );

  PulseDay dayOf(PulsePeriodData data, int y, int m, int d) =>
      data.days.firstWhere((day) => day.localDate == DateTime(y, m, d));

  group('time buckets', () {
    test(
      'a play crossing local midnight is split between the two days',
      () async {
        await play(
          startLocal: DateTime(2026, 10, 14, 23, 50),
          listened: const Duration(minutes: 20),
        );

        final data = await service().load(PulsePeriod.month(2026, 10));

        expect(
          dayOf(data, 2026, 10, 14).metrics.listened,
          const Duration(minutes: 10),
        );
        expect(
          dayOf(data, 2026, 10, 15).metrics.listened,
          const Duration(minutes: 10),
        );
        expect(data.totals.listened, const Duration(minutes: 20));
        // The stream and the play count on the day they happened.
        expect(dayOf(data, 2026, 10, 14).metrics.streams, 1);
        expect(dayOf(data, 2026, 10, 14).metrics.allPlays, 1);
        expect(dayOf(data, 2026, 10, 15).metrics.streams, 0);
      },
    );

    test(
      'a play crossing the period edge counts only its inside part',
      () async {
        await play(
          startLocal: DateTime(2026, 9, 30, 23, 55),
          listened: const Duration(minutes: 15),
        );

        final october = await service().load(PulsePeriod.month(2026, 10));
        final september = await service().load(PulsePeriod.month(2026, 9));

        expect(october.totals.listened, const Duration(minutes: 10));
        expect(october.totals.streams, 0, reason: 'qualified in September');
        expect(september.totals.listened, const Duration(minutes: 5));
        expect(september.totals.streams, 1);
      },
    );

    test('a year has a bucket for every local day, and buckets add up to '
        'the totals (also across DST changes)', () async {
      await play(
        startLocal: DateTime(2026, 12, 31, 23, 45),
        listened: const Duration(minutes: 30),
      );
      for (final start in [
        DateTime(2026, 3, 8, 1, 30),
        DateTime(2026, 11, 1, 0, 30),
        DateTime(2026, 3, 29, 0, 30),
        DateTime(2026, 10, 25, 0, 30),
        DateTime(2026, 6, 1, 12),
      ]) {
        await play(startLocal: start, listened: const Duration(hours: 3));
      }

      final data = await service().load(PulsePeriod.year(2026));

      expect(data.days, hasLength(365));
      expect(data.days.first.localDate, DateTime(2026));
      expect(data.days.last.localDate, DateTime(2026, 12, 31));
      final daySum = data.days.fold(
        Duration.zero,
        (sum, day) => sum + day.metrics.listened,
      );
      final hourSum = data.hours.fold(
        Duration.zero,
        (sum, hour) => sum + hour.listened,
      );
      expect(daySum, data.totals.listened);
      expect(hourSum, data.totals.listened);
      expect(
        data.totals.listened,
        const Duration(hours: 15, minutes: 15),
        reason: '5 × 3 h plus the 15 min before the new year',
      );
      expect(data.days.fold(0, (sum, d) => sum + d.metrics.streams), 6);
      expect(data.hours.fold(0, (sum, h) => sum + h.streams), 6);
    });

    test('hours are bucketed by local hour', () async {
      await play(
        startLocal: DateTime(2026, 10, 3, 21, 30),
        listened: const Duration(hours: 1),
      );

      final data = await service().load(PulsePeriod.month(2026, 10));

      expect(data.hours[21].listened, const Duration(minutes: 30));
      expect(data.hours[22].listened, const Duration(minutes: 30));
      expect(data.hours[21].streams, 1);
    });
  });

  group('no history, zero and future', () {
    test('days before the first session have no history; later empty days '
        'are zero; days after today are future', () async {
      await play(
        startLocal: DateTime(2026, 10, 26, 19, 53),
        listened: const Duration(minutes: 4),
      );

      final data = await service(
        now: DateTime(2026, 10, 28, 12),
      ).load(PulsePeriod.month(2026, 10));

      expect(dayOf(data, 2026, 10, 25).state, PulseDayState.beforeHistory);
      expect(dayOf(data, 2026, 10, 26).state, PulseDayState.recorded);
      expect(dayOf(data, 2026, 10, 27).state, PulseDayState.recorded);
      expect(dayOf(data, 2026, 10, 27).metrics, PulseMetrics.zero);
      expect(dayOf(data, 2026, 10, 28).state, PulseDayState.recorded);
      expect(dayOf(data, 2026, 10, 29).state, PulseDayState.future);
      expect(data.startsBeforeHistory, isTrue);
      expect(data.firstHistoryAt, DateTime(2026, 10, 26, 19, 53).toUtc());
    });

    test(
      'with no history at all, nothing is zero and nothing compares',
      () async {
        final data = await service(
          now: DateTime(2026, 10, 28),
        ).load(PulsePeriod.month(2026, 10));

        expect(data.firstHistoryAt, isNull);
        expect(data.totals, PulseMetrics.zero);
        expect(
          data.days.where((d) => d.state == PulseDayState.recorded),
          isEmpty,
        );
        expect(data.previous.isAvailable, isFalse);
        expect(data.samePeriodLastYear.isAvailable, isFalse);
        expect(
          data.ranking(PulseEntityKind.track, PulseMeasure.streams),
          isEmpty,
        );
      },
    );
  });

  group('comparisons', () {
    test('eligible only when the comparison period starts on or after the '
        'first recorded day', () {
      final firstDay = DateTime(2026, 9, 1);
      expect(
        PulseInsightsService.comparisonEligible(
          PulsePeriod.month(2026, 9),
          firstDay,
        ),
        isTrue,
        reason: 'starts on the exact first-play day',
      );
      expect(
        PulseInsightsService.comparisonEligible(
          PulsePeriod.month(2026, 8),
          firstDay,
        ),
        isFalse,
      );
      expect(
        PulseInsightsService.comparisonEligible(
          PulsePeriod.month(2026, 9),
          DateTime(2026, 9, 2),
        ),
        isFalse,
        reason: 'history starts after the period does',
      );
      expect(
        PulseInsightsService.comparisonEligible(
          PulsePeriod.month(2026, 9),
          null,
        ),
        isFalse,
      );
    });

    test('previous month with full history compares; same month last year '
        'without history does not', () async {
      await play(
        startLocal: DateTime(2026, 9, 1, 0, 5),
        listened: const Duration(minutes: 3),
      );
      await play(
        startLocal: DateTime(2026, 9, 20, 10),
        listened: const Duration(minutes: 2),
      );
      await play(
        startLocal: DateTime(2026, 10, 5, 10),
        listened: const Duration(minutes: 6),
      );

      final data = await service().load(PulsePeriod.month(2026, 10));

      expect(data.previous.period, PulsePeriod.month(2026, 9));
      expect(data.previous.isAvailable, isTrue);
      expect(
        data.previous.totals,
        const PulseMetrics(
          listened: Duration(minutes: 5),
          streams: 2,
          allPlays: 2,
        ),
      );
      expect(data.samePeriodLastYear.period, PulsePeriod.month(2025, 10));
      expect(
        data.samePeriodLastYear.availability,
        PulseComparisonAvailability.notEnoughHistory,
      );
      expect(data.samePeriodLastYear.totals, isNull);
      expect(data.startsBeforeHistory, isFalse);
    });

    test('a year compares with the previous year once', () async {
      await play(
        startLocal: DateTime(2025, 1, 1, 0, 1),
        listened: const Duration(minutes: 1),
      );

      final data = await service().load(PulsePeriod.year(2026));

      expect(data.previous.isAvailable, isTrue);
      expect(identical(data.previous, data.samePeriodLastYear), isTrue);
    });
  });

  group('measures stay separate', () {
    test(
      'minutes come from segments, never from qualified snapshots',
      () async {
        await play(
          startLocal: DateTime(2026, 10, 2, 9),
          listened: const Duration(minutes: 3),
          qualifiedSnapshot: const Duration(seconds: 30),
          segments: 3,
        );

        final data = await service().load(PulsePeriod.month(2026, 10));

        expect(data.totals.listened, const Duration(minutes: 3));
        expect(data.totals.streams, 1);
      },
    );

    test('all plays count audible sessions only; short plays add minutes '
        'and plays but no stream', () async {
      await play(
        startLocal: DateTime(2026, 10, 2, 9),
        listened: const Duration(seconds: 12),
      );
      await play(
        startLocal: DateTime(2026, 10, 2, 10),
        listened: Duration.zero,
      );

      final data = await service().load(PulsePeriod.month(2026, 10));

      expect(
        data.totals,
        const PulseMetrics(
          listened: Duration(seconds: 12),
          streams: 0,
          allPlays: 1,
        ),
      );
    });

    test(
      'the bounded query gives the same minutes as the existing service',
      () async {
        await play(
          startLocal: DateTime(2024, 5, 1, 9),
          listened: const Duration(hours: 2),
        );
        await play(
          startLocal: DateTime(2026, 9, 30, 23, 30),
          listened: const Duration(hours: 1),
        );
        await play(
          startLocal: DateTime(2026, 10, 18, 7, 59),
          listened: const Duration(minutes: 47),
          segments: 4,
        );
        await play(
          startLocal: DateTime(2026, 10, 31, 23, 40),
          listened: const Duration(minutes: 50),
        );
        await play(
          startLocal: DateTime(2027, 1, 3, 9),
          listened: const Duration(minutes: 9),
        );
        final existing = AnalyticsListeningDurationService(
          listeningSegments: SqlitePlaybackListeningSegmentRepository(
            PlaybackListeningSegmentDao(db),
          ),
        );

        for (final (period, analytics, reference) in [
          (
            PulsePeriod.month(2026, 10),
            AnalyticsPeriod.month,
            DateTime(2026, 10, 9),
          ),
          (
            PulsePeriod.month(2026, 9),
            AnalyticsPeriod.month,
            DateTime(2026, 9, 9),
          ),
          (PulsePeriod.year(2026), AnalyticsPeriod.year, DateTime(2026, 6)),
          (PulsePeriod.year(2024), AnalyticsPeriod.year, DateTime(2024, 6)),
        ]) {
          final pulse = await service().load(period);
          final old = await existing.load(
            period: analytics,
            referenceLocal: reference,
          );
          expect(
            pulse.totals.listened,
            old.totalAudibleListeningDuration,
            reason: '$period',
          );
        }
      },
    );
  });

  group('rankings', () {
    test('editions of one release and one song count once; Singles leave '
        'the release ranking but not the totals', () async {
      for (final edition in ['standard', 'deluxe']) {
        await play(
          startLocal: DateTime(2026, 10, 3, 10),
          listened: const Duration(minutes: 3),
          album: 'album_lp',
          edition: edition,
        );
      }
      await play(
        startLocal: DateTime(2026, 10, 4, 10),
        listened: const Duration(minutes: 3),
        song: 'song_single',
        album: 'album_single',
      );

      final data = await service(
        eligibility: const _Excluding({'album_single'}),
      ).load(PulsePeriod.month(2026, 10));

      final releases = data.ranking(
        PulseEntityKind.release,
        PulseMeasure.streams,
      );
      expect(releases.map((r) => (r.id, r.metrics.streams)), [('album_lp', 2)]);
      final tracks = data.ranking(PulseEntityKind.track, PulseMeasure.streams);
      expect(tracks.first.id, 'song_a');
      expect(tracks.first.metrics.streams, 2);
      expect(data.totals.streams, 3);
      expect(
        data.totalsFor(PulseEntityKind.release, 'album_single').streams,
        1,
        reason: 'the Single is still counted, only not ranked',
      );
    });

    test('rank by each measure; ties go to the most recent', () async {
      // song_long: 1 stream, 30 minutes. song_many: 3 short streams.
      await play(
        startLocal: DateTime(2026, 10, 1, 8),
        listened: const Duration(minutes: 30),
        song: 'song_long',
      );
      for (var i = 0; i < 3; i++) {
        await play(
          startLocal: DateTime(2026, 10, 2, 8 + i),
          listened: const Duration(minutes: 1),
          song: 'song_many',
        );
      }
      await play(
        startLocal: DateTime(2026, 10, 1, 9),
        listened: const Duration(minutes: 1),
        song: 'tie_old',
      );
      await play(
        startLocal: DateTime(2026, 10, 9, 9),
        listened: const Duration(minutes: 1),
        song: 'tie_new',
      );

      final data = await service().load(PulsePeriod.month(2026, 10));

      List<String> ids(PulseMeasure measure) => [
        for (final entry in data.ranking(PulseEntityKind.track, measure))
          entry.id,
      ];
      expect(ids(PulseMeasure.minutes).first, 'song_long');
      expect(ids(PulseMeasure.streams).take(2), ['song_many', 'tie_new']);
      expect(ids(PulseMeasure.streams).skip(2), [
        'tie_old',
        'song_long',
      ], reason: 'song_long ties with tie_old and is older');
      expect(ids(PulseMeasure.allPlays).first, 'song_many');
      expect(
        data.ranking(PulseEntityKind.track, PulseMeasure.streams, limit: 2),
        hasLength(2),
      );
    });

    test('artists follow the lead-artist attribution', () async {
      await play(
        startLocal: DateTime(2026, 10, 3, 10),
        listened: const Duration(minutes: 3),
        artist: 'contributor',
        album: 'project_album',
      );
      await play(
        startLocal: DateTime(2026, 10, 3, 11),
        listened: const Duration(minutes: 3),
        artist: 'owner',
        album: 'project_album',
      );

      final data = await service(
        attribution: const _ProjectOwner(),
      ).load(PulsePeriod.month(2026, 10));

      final artists = data.ranking(
        PulseEntityKind.artist,
        PulseMeasure.streams,
      );
      expect(artists.map((a) => (a.id, a.metrics.streams)), [('owner', 2)]);
    });
  });

  group('per-item contribution', () {
    test('every item is within its day in every measure, and absent on '
        'days without it', () async {
      final starts = [
        DateTime(2026, 10, 1, 23, 40),
        DateTime(2026, 10, 2, 8),
        DateTime(2026, 10, 2, 9),
        DateTime(2026, 10, 9, 18),
        DateTime(2026, 10, 31, 23, 50),
      ];
      for (var i = 0; i < starts.length; i++) {
        await play(
          startLocal: starts[i],
          listened: Duration(minutes: 5 + 9 * i),
          song: 'song_${i % 2}',
          artist: 'artist_${i % 3}',
          album: 'album_${i % 2}',
          segments: 1 + i % 3,
        );
      }

      final data = await service().load(PulsePeriod.month(2026, 10));

      for (final kind in PulseEntityKind.values) {
        for (final measure in PulseMeasure.values) {
          for (final entity in data.ranking(kind, measure)) {
            final series = data.daySeriesFor(kind, entity.id);
            expect(series, hasLength(data.days.length));
            var sum = PulseMetrics.zero;
            for (var i = 0; i < series.length; i++) {
              final item = series[i];
              final day = data.days[i].metrics;
              expect(item.listened <= day.listened, isTrue);
              expect(item.streams <= day.streams, isTrue);
              expect(item.allPlays <= day.allPlays, isTrue);
              sum = PulseMetrics(
                listened: sum.listened + item.listened,
                streams: sum.streams + item.streams,
                allPlays: sum.allPlays + item.allPlays,
              );
            }
            expect(sum, data.totalsFor(kind, entity.id));
          }
        }
      }

      final song1 = data.daySeriesFor(PulseEntityKind.track, 'song_1');
      expect(song1[0], PulseMetrics.zero, reason: 'song_1 not played Oct 1');
      expect(
        data
            .daySeriesFor(PulseEntityKind.track, 'unknown')
            .every((m) => m == PulseMetrics.zero),
        isTrue,
      );
    });
  });
}

class _Excluding implements ReleaseChartEligibility {
  const _Excluding(this.ids);

  final Set<String> ids;

  @override
  Future<Set<String>> excludedAlbumIds() async => ids;
}

/// Plays by a contributor to project_album count for its owner.
class _ProjectOwner implements ListeningArtistAttribution {
  const _ProjectOwner();

  @override
  Future<ArtistAttributor> load() async => ArtistAttributor(
    (artistId, albumId) => albumId == 'project_album' ? 'owner' : artistId,
  );
}

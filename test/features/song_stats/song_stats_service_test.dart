import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/core/database/schema/analytics_schema.dart';
import 'package:sonus_next/features/analytics/application/services/pulse/pulse_listening_records.dart';
import 'package:sonus_next/features/charts/application/services/this_week_chart_service.dart';
import 'package:sonus_next/features/charts/data/repositories/sqlite_chart_repository.dart';
import 'package:sonus_next/features/charts/domain/entities/all_time_chart.dart';
import 'package:sonus_next/features/charts/domain/entities/chart_entry.dart';
import 'package:sonus_next/features/charts/domain/entities/chart_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_entity_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_movement.dart';
import 'package:sonus_next/features/charts/domain/models/chart_type.dart';
import 'package:sonus_next/features/charts/domain/repositories/chart_entity_history_reader.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/application/repositories/library_query_repository.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/song_stats/application/song_listening_records.dart';
import 'package:sonus_next/features/song_stats/application/song_stats_models.dart';
import 'package:sonus_next/features/song_stats/application/song_stats_service.dart';
import 'package:sonus_next/features/song_stats/data/sqlite_song_listening_records.dart';

/// A local Sunday-midnight chart week start, [weeks] after Oct 4, 2026.
DateTime week(int weeks) => DateTime(2026, 10, 4 + 7 * weeks).toUtc();

ChartEntry entry(String id, int rank, {String title = 'Stored title'}) =>
    ChartEntry(
      entity: ChartEntitySnapshot(
        entityId: id,
        title: title,
        artistName: 'Stored artist',
        albumTitle: 'Stored album',
      ),
      rank: rank,
      qualifiedStreamCount: 10,
      lastQualifiedAt: DateTime.utc(2026, 10, 5),
      peakRank: rank,
      peakAchievedAt: DateTime.utc(2026, 10, 5),
      weeksOnChart: 1,
      movement: ChartMovement.same,
    );

ChartEntityWeek stored(int weeks, int rank) => ChartEntityWeek(
  weekStartUtc: week(weeks),
  weekEndUtc: week(weeks + 1),
  finalizedAt: week(weeks + 1),
  entry: entry('song', rank),
);

LibraryTrack track({
  bool blocked = false,
  bool available = true,
  String? filePath = 'C:/Music/song.mp3',
}) => LibraryTrack(
  songId: 'song',
  title: 'Library title',
  artistId: 'artist',
  artistName: 'Library artist',
  albumId: 'album',
  albumTitle: 'Library album',
  albumEditionId: 'edition',
  albumEditionTitle: 'Standard',
  albumEditionType: AlbumEditionType.standard,
  trackNumber: 1,
  durationSeconds: 200,
  isSingle: false,
  featuredArtists: const [],
  dateAdded: DateTime.utc(2026, 10, 1),
  isAvailable: available,
  isSongBlocked: blocked,
  filePath: filePath,
);

class _Charts implements ChartEntityHistoryReader {
  _Charts(this.weeks);

  final List<ChartEntityWeek> weeks;

  @override
  Future<List<ChartEntityWeek>> finalizedWeeksFor(
    ChartType chartType,
    String entityId,
  ) async => chartType == ChartType.songs ? weeks : const [];
}

class _Records implements SongListeningRecords {
  _Records({
    this.segments = const [],
    this.streams = const [],
    this.plays = const [],
    this.playedAs,
    this.historyStart,
  });

  final List<PulseSegmentRecord> segments;
  final List<PulsePlayRecord> streams;
  final List<PulsePlayRecord> plays;
  final SongPlayedIdentity? playedAs;
  final DateTime? historyStart;

  @override
  Future<List<PulsePlayRecord>> audibleSessionsForSong(String songId) async =>
      plays;

  @override
  Future<DateTime?> firstSessionStartedAt() async => historyStart;

  @override
  Future<SongPlayedIdentity?> lastPlayedIdentity(String songId) async =>
      playedAs;

  @override
  Future<List<PulsePlayRecord>> qualifiedPlaysForSong(String songId) async =>
      streams;

  @override
  Future<List<PulseSegmentRecord>> segmentsForSong(String songId) async =>
      segments;
}

class _Library implements LibraryQueryRepository {
  _Library([this.track]);

  final LibraryTrack? track;

  @override
  Future<LibraryTrack?> getTrackById(String songId) async =>
      track?.songId == songId ? track : null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

PulsePlayRecord play(DateTime at) =>
    PulsePlayRecord(at: at, songId: 'song', artistId: 'a', albumId: 'r');

PulseSegmentRecord segment(DateTime start, DateTime? end, Duration listened) =>
    PulseSegmentRecord(
      startedAt: start,
      endedAt: end,
      listenedDuration: listened,
      songId: 'song',
      artistId: 'a',
      albumId: 'r',
    );

SongStatsService _service({
  List<ChartEntityWeek> weeks = const [],
  _Records? records,
  LibraryTrack? libraryTrack,
  Future<ProvisionalWeekChart?> Function()? live,
  Future<AllTimeChart?> Function()? career,
  DateTime? now,
}) => SongStatsService(
  charts: _Charts(weeks),
  records: () async => records ?? _Records(),
  library: _Library(libraryTrack),
  liveSongs: live,
  careerSongs: career,
  nowLocal: () => now ?? DateTime(2026, 11, 18, 12),
);

void main() {
  group('chart weeks', () {
    test('debut, same-chart moves, re-entry, peaks and weeks', () {
      final weeks = SongStatsService.chartWeeks([
        stored(4, 40), // re-entry after weeks 2-3 off (out of order on input)
        stored(0, 150),
        stored(1, 90),
        stored(5, 40),
        stored(6, 120),
      ]);

      expect(weeks.map((w) => w.rank), [150, 90, 40, 40, 120]);
      expect(weeks.map((w) => w.event), [
        SongChartWeekEvent.debut,
        SongChartWeekEvent.promoted,
        SongChartWeekEvent.reentry,
        SongChartWeekEvent.same,
        SongChartWeekEvent.demoted,
      ]);
      // Cross-chart moves keep the real previous position and no count.
      expect(weeks[1].previousRank, 150);
      expect(weeks[1].positions, isNull);
      expect(weeks[4].previousRank, 40);
      expect(weeks[4].positions, isNull);
      // A re-entry has no previous rank and counts the weeks off.
      expect(weeks[2].previousRank, isNull);
      expect(weeks[2].weeksOff, 2);
      expect(weeks[3].positions, 0);
      // New peaks never on a debut; the Hot 100 debut is its first week in.
      expect(weeks.map((w) => w.newPeak), [false, true, true, false, false]);
      expect(weeks.map((w) => w.hot100Debut), [
        false,
        true,
        false,
        false,
        false,
      ]);

      final history = SongChartHistory(weeks: weeks);
      expect(history.peakRank, 40);
      expect(history.weeksAtPeak, 2);
      expect(history.firstPeakWeek!.weekStartUtc, week(4));
      expect(history.hot100Weeks, 3);
      expect(history.bubblingUnderWeeks, 2);
      expect(history.reentries, 1);
      expect(history.debut!.rank, 150);
      expect(history.hot100Debut!.rank, 90);
      expect(history.lastFinalized!.rank, 120);
    });

    test('up and down within one chart count positions', () {
      final weeks = SongStatsService.chartWeeks([
        stored(0, 30),
        stored(1, 12),
        stored(2, 19),
        stored(3, 140),
        stored(4, 110),
      ]);
      expect(weeks.map((w) => w.event), [
        SongChartWeekEvent.debut,
        SongChartWeekEvent.up,
        SongChartWeekEvent.down,
        SongChartWeekEvent.demoted,
        SongChartWeekEvent.up,
      ]);
      expect(weeks.map((w) => w.positions), [null, 18, -7, null, 30]);
      expect(weeks.first.hot100Debut, isTrue);
    });
  });

  group('SongStatsService', () {
    test('live week stays provisional and never sets the peak', () async {
      final live = ProvisionalWeekChart(
        snapshot: ChartSnapshot(
          id: 'live',
          chartType: ChartType.songs,
          weekStartUtc: week(2),
          weekEndUtc: week(3),
          entries: [entry('other', 1), entry('song', 3)],
        ),
        bestSoFarRanks: const {'song': 2},
      );
      final stats = await _service(
        weeks: [stored(0, 20), stored(1, 9)],
        live: () async => live,
      ).load('song');

      expect(stats.chart.live!.rank, 3);
      expect(stats.chart.live!.bestSoFarRank, 2);
      expect(stats.chart.peakRank, 9, reason: 'finalized weeks only');
      expect(stats.chart.weeks, hasLength(2));
    });

    // SN-50 device QA ("lovergirl"): #133 in the career standings, which
    // the Charts page opens on, and #2 on this week's live chart, with no
    // finalized week: three different charts, each shown under its name.
    test('career standings and the live week are separate charts', () async {
      final live = ProvisionalWeekChart(
        snapshot: ChartSnapshot(
          id: 'live',
          chartType: ChartType.songs,
          weekStartUtc: week(2),
          weekEndUtc: week(3),
          entries: [entry('other', 1), entry('song', 2)],
        ),
        bestSoFarRanks: const {},
      );
      final career = AllTimeChart(
        chartType: ChartType.songs,
        comparisonStartUtc: week(2),
        entries: [
          for (var rank = 1; rank <= 132; rank++) entry('s$rank', rank),
          entry('song', 133),
        ],
      );
      final stats = await _service(
        live: () async => live,
        career: () async => career,
      ).load('song');

      expect(stats.chart.career!.rank, 133);
      expect(stats.chart.career!.isHot100, isFalse);
      expect(stats.chart.live!.rank, 2);
      expect(stats.chart.hasFinalized, isFalse);
      expect(stats.chart.peakRank, isNull, reason: 'neither sets a peak');
      expect(stats.chart.isEmpty, isFalse);
    });

    test('an albums career chart or a failing one is not used', () async {
      final albums = AllTimeChart(
        chartType: ChartType.albums,
        comparisonStartUtc: week(2),
        entries: [entry('song', 1)],
      );
      expect(
        (await _service(career: () async => albums).load('song')).chart.career,
        isNull,
      );
      expect(
        (await _service(
          career: () async => throw StateError('boom'),
          weeks: [stored(0, 20)],
        ).load('song')).chart.career,
        isNull,
      );
    });

    test('a failing live chart still shows finalized history', () async {
      final stats = await _service(
        weeks: [stored(0, 20)],
        live: () async => throw StateError('boom'),
      ).load('song');

      expect(stats.chart.live, isNull);
      expect(stats.chart.weeks.single.rank, 20);
    });

    test('no recorded chart history is empty, not invented', () async {
      final stats = await _service().load('song');
      expect(stats.chart.isEmpty, isTrue);
      expect(stats.chart.peakRank, isNull);
      expect(stats.listening.hasAny, isFalse);
    });

    test('listening follows the Pulse definitions', () async {
      final start = DateTime(2026, 11, 2, 10).toUtc();
      final stats = await _service(
        records: _Records(
          historyStart: DateTime(2026, 10, 26, 9).toUtc(),
          segments: [
            // Closed: 3 minutes of wall time.
            segment(
              start,
              start.add(const Duration(minutes: 3)),
              Duration.zero,
            ),
            // Open: its start plus the time recorded so far.
            segment(
              DateTime(2026, 11, 16, 8).toUtc(),
              null,
              const Duration(minutes: 2),
            ),
          ],
          streams: [
            play(start.add(const Duration(minutes: 1))),
            play(DateTime(2026, 11, 16, 8, 1).toUtc()),
          ],
          plays: [
            play(start),
            play(DateTime(2026, 11, 16, 8).toUtc()),
            play(DateTime(2026, 10, 27, 8).toUtc()),
          ],
        ),
      ).load('song');

      final listening = stats.listening;
      expect(listening.listened, const Duration(minutes: 5));
      expect(listening.streams, 2);
      expect(listening.allPlays, 3);
      expect(listening.firstPlayedAt, DateTime(2026, 10, 27, 8).toUtc());
      expect(listening.lastPlayedAt, DateTime(2026, 11, 16, 8).toUtc());

      // Weeks from the one history began in (Oct 25) to the current one.
      expect(listening.weeks.map((w) => w.weekStartLocal), [
        DateTime(2026, 10, 25),
        DateTime(2026, 11, 1),
        DateTime(2026, 11, 8),
        DateTime(2026, 11, 15),
      ]);
      expect(listening.weeks.map((w) => w.listened.inMinutes), [0, 3, 0, 2]);
      expect(listening.weeks.map((w) => w.streams), [0, 1, 0, 1]);
      expect(listening.weeks.map((w) => w.allPlays), [1, 1, 0, 1]);
      expect(listening.weeks.map((w) => w.inProgress), [
        false,
        false,
        false,
        true,
      ]);
    });

    test('a segment across a week boundary is split between weeks', () async {
      final boundary = DateTime(2026, 11, 15).toUtc();
      final stats = await _service(
        records: _Records(
          historyStart: DateTime(2026, 11, 1).toUtc(),
          segments: [
            segment(
              boundary.subtract(const Duration(minutes: 4)),
              boundary.add(const Duration(minutes: 6)),
              Duration.zero,
            ),
          ],
        ),
      ).load('song');
      final byWeek = {
        for (final w in stats.listening.weeks)
          w.weekStartLocal: w.listened.inMinutes,
      };
      expect(byWeek[DateTime(2026, 11, 8)], 4);
      expect(byWeek[DateTime(2026, 11, 15)], 6);
      expect(stats.listening.listened, const Duration(minutes: 10));
    });

    test('identity: library first, then last play, then chart', () async {
      final current = await _service(libraryTrack: track()).load('song');
      expect(current.identity.title, 'Library title');
      expect(current.identity.status, SongStatsStatus.current);
      expect(current.identity.isPlayable, isTrue);

      final played = await _service(
        weeks: [stored(0, 5)],
        records: _Records(
          playedAs: const SongPlayedIdentity(
            title: 'Played title',
            artistName: 'Played artist',
            albumTitle: 'Played album',
          ),
        ),
      ).load('song');
      expect(played.identity.title, 'Played title');
      expect(played.identity.artistLine, 'Played artist');
      expect(played.identity.status, SongStatsStatus.historical);
      expect(played.identity.status.badge, 'HISTORICAL');
      expect(played.identity.isPlayable, isFalse);

      final charted = await _service(weeks: [stored(0, 5)]).load('song');
      expect(charted.identity.title, 'Stored title');

      final unknown = await _service().load('song');
      expect(unknown.identity.title, 'Unknown track');
      expect(unknown.identity.artistLine, '');
    });

    test('blacklisted and unavailable songs are labelled, not playable', () {
      expect(SongStatsStatus.of(track(blocked: true)).badge, 'BLACKLISTED');
      expect(SongStatsStatus.of(track(available: false)).badge, 'UNAVAILABLE');
      expect(SongStatsStatus.of(track(filePath: ' ')).badge, 'UNAVAILABLE');
      expect(SongStatsStatus.of(null).badge, 'HISTORICAL');
      expect(SongStatsStatus.of(track()).badge, isNull);
    });
  });

  group('SQLite', () {
    sqfliteFfiInit();

    test('finalizedWeeksFor reads only finalized song weeks, oldest '
        'first, without writing', () async {
      final database = AppDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      addTearDown(database.close);
      final charts = SqliteChartRepository(database);

      ChartSnapshot snapshot(
        String id,
        int weeks, {
        bool finalized = true,
        ChartType type = ChartType.songs,
        required List<ChartEntry> entries,
      }) => ChartSnapshot(
        id: id,
        chartType: type,
        weekStartUtc: week(weeks),
        weekEndUtc: week(weeks + 1),
        finalizedAt: finalized ? week(weeks + 1) : null,
        entries: entries,
      );

      await charts.replaceSnapshot(
        snapshot('w1', 1, entries: [entry('other', 1), entry('song', 140)]),
      );
      await charts.replaceSnapshot(
        snapshot('w0', 0, entries: [entry('song', 12)]),
      );
      await charts.replaceSnapshot(
        snapshot('w2', 2, finalized: false, entries: [entry('song', 1)]),
      );
      await charts.replaceSnapshot(
        snapshot('a0', 0, type: ChartType.albums, entries: [entry('song', 2)]),
      );

      final db = await database.database;
      final before = await db.rawQuery(
        'SELECT COUNT(*) AS n FROM ${DatabaseTables.chartEntries}',
      );

      final weeks = await charts.finalizedWeeksFor(ChartType.songs, 'song');
      expect(weeks.map((w) => w.entry.rank), [12, 140]);
      expect(weeks.map((w) => w.weekStartUtc), [week(0), week(1)]);
      expect(weeks.first.finalizedAt, week(1));
      expect(weeks.first.entry.entity.title, 'Stored title');

      final after = await db.rawQuery(
        'SELECT COUNT(*) AS n FROM ${DatabaseTables.chartEntries}',
      );
      expect(after, before);
    });

    test('song listening records read one song only', () async {
      final db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) => AnalyticsSchema.create(db),
        ),
      );
      addTearDown(db.close);

      Future<void> session(
        String id,
        String song,
        DateTime start,
        int listenedMs,
        String title,
      ) => db.insert(DatabaseTables.playbackSessions, {
        'id': id,
        'song_id': song,
        'artist_id': 'artist',
        'album_id': 'album',
        'album_edition_id': 'edition',
        'song_title': title,
        'artist_name': 'Artist',
        'album_title': 'Album',
        'album_edition_title': 'Standard',
        'started_at': start.toUtc().toIso8601String(),
        'listened_duration_ms': listenedMs,
        'created_at': start.toUtc().toIso8601String(),
        'updated_at': start.toUtc().toIso8601String(),
      });

      final t0 = DateTime.utc(2026, 10, 27, 10);
      await session('s1', 'song', t0, 60000, 'Old name');
      await session('s2', 'song', t0.add(const Duration(days: 1)), 0, 'New');
      await session('s3', 'other', t0, 60000, 'Other');
      await db.insert(DatabaseTables.playbackListeningSegments, {
        'id': 'g1',
        'playback_session_id': 's1',
        'started_at': t0.toIso8601String(),
        'ended_at': t0.add(const Duration(minutes: 1)).toIso8601String(),
        'listened_duration_ms': 60000,
        'created_at': t0.toIso8601String(),
        'updated_at': t0.toIso8601String(),
      });
      await db.insert(DatabaseTables.playbackListeningSegments, {
        'id': 'g3',
        'playback_session_id': 's3',
        'started_at': t0.toIso8601String(),
        'ended_at': t0.add(const Duration(minutes: 1)).toIso8601String(),
        'listened_duration_ms': 60000,
        'created_at': t0.toIso8601String(),
        'updated_at': t0.toIso8601String(),
      });
      for (final (id, session, song) in [
        ('q1', 's1', 'song'),
        ('q3', 's3', 'other'),
      ]) {
        await db.insert(DatabaseTables.qualifiedPlays, {
          'id': id,
          'playback_session_id': session,
          'song_id': song,
          'artist_id': 'artist',
          'album_id': 'album',
          'album_edition_id': 'edition',
          'qualified_at': t0.add(const Duration(seconds: 40)).toIso8601String(),
          'listened_duration_ms': 40000,
          'track_duration_ms': 200000,
          'created_at': t0.toIso8601String(),
        });
      }

      final records = SqliteSongListeningRecords(db);
      expect(await records.segmentsForSong('song'), hasLength(1));
      expect(await records.qualifiedPlaysForSong('song'), hasLength(1));
      expect((await records.audibleSessionsForSong('song')).map((p) => p.at), [
        t0,
      ], reason: 'the session without audible time is not a play');
      expect((await records.lastPlayedIdentity('song'))!.title, 'New');
      expect(await records.lastPlayedIdentity('missing'), isNull);
      expect(await records.firstSessionStartedAt(), t0);
    });
  });
}

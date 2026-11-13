// App Update 1.2: Sonus Wrapped is built only from recorded listening
// (Sonus Pulse's period data) and stored charts, on a disposable database
// with a fixed clock. Nothing is estimated, backfilled or written.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/core/database/schema/analytics_schema.dart';
import 'package:sonus_next/core/database/schema/chart_schema.dart';
import 'package:sonus_next/features/analytics/application/models/pulse/pulse_period.dart';
import 'package:sonus_next/features/analytics/application/models/pulse/pulse_period_data.dart';
import 'package:sonus_next/features/analytics/application/services/pulse/pulse_entity_directory.dart';
import 'package:sonus_next/features/analytics/application/services/pulse/pulse_insights_service.dart';
import 'package:sonus_next/features/analytics/data/repositories/sqlite_pulse_listening_records.dart';
import 'package:sonus_next/features/wrapped/application/wrapped_service.dart';
import 'package:sonus_next/features/wrapped/application/wrapped_summary.dart';
import 'package:sonus_next/features/wrapped/data/sqlite_wrapped_history_reader.dart';

/// Names for whatever a period holds; Pulse's own directory is tested with
/// Pulse.
class _Directory implements PulseDirectoryLoader {
  @override
  Future<PulseEntityDirectory> load(PulsePeriodData data) async =>
      PulseEntityDirectory({
        for (final kind in PulseEntityKind.values)
          for (final entity in data.ranking(kind, PulseMeasure.minutes))
            (kind, entity.id): PulseEntityInfo(
              kind: kind,
              id: entity.id,
              title: 'Title ${entity.id}',
              subtitle: '',
              artworkPath: null,
              status: PulseEntityStatus.current,
            ),
        for (final kind in PulseEntityKind.values)
          for (final entity in data.ranking(kind, PulseMeasure.streams))
            (kind, entity.id): PulseEntityInfo(
              kind: kind,
              id: entity.id,
              title: 'Title ${entity.id}',
              subtitle: '',
              artworkPath: null,
              status: PulseEntityStatus.current,
            ),
      });
}

void main() {
  sqfliteFfiInit();
  late Database db;
  var now = DateTime(2027, 3, 15, 12);

  setUp(() async {
    now = DateTime(2027, 3, 15, 12);
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        // As the app does: deleting a session takes its segments and play.
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) async {
          await AnalyticsSchema.create(db);
          await ChartSchema.create(db);
          // Only what Wrapped reads of editions: the genre.
          await db.execute('''
            CREATE TABLE ${DatabaseTables.albumEditions} (
              id TEXT PRIMARY KEY, album_id TEXT NOT NULL,
              genre TEXT, is_primary INTEGER NOT NULL DEFAULT 0
            )
          ''');
        },
      ),
    );
  });
  tearDown(() => db.close());

  WrappedService service() {
    final records = SqlitePulseListeningRecords(db);
    return WrappedService(
      pulse: PulseInsightsService(records: records, nowLocal: () => now),
      directory: _Directory(),
      history: SqliteWrappedHistoryReader(db),
      nowLocal: () => now,
    );
  }

  var ids = 0;

  /// One listen of [song] starting at [startLocal] for [listened]; it
  /// qualifies when [qualifies] (at 30 s in).
  Future<void> listen(
    String song,
    DateTime startLocal, {
    String artist = 'artist-a',
    String album = 'album-a',
    String edition = 'edition-a',
    Duration listened = const Duration(minutes: 3),
    bool qualifies = true,
  }) async {
    final id = 'session-${ids++}';
    final start = startLocal.toUtc();
    final end = start.add(listened);
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
      'created_at': start.toIso8601String(),
      'updated_at': end.toIso8601String(),
    });
    await db.insert(DatabaseTables.playbackListeningSegments, {
      'id': 'segment-$id',
      'playback_session_id': id,
      'started_at': start.toIso8601String(),
      'ended_at': end.toIso8601String(),
      'listened_duration_ms': listened.inMilliseconds,
      'created_at': start.toIso8601String(),
      'updated_at': end.toIso8601String(),
    });
    if (qualifies) {
      final at = start.add(const Duration(seconds: 30));
      await db.insert(DatabaseTables.qualifiedPlays, {
        'id': 'play-$id',
        'playback_session_id': id,
        'song_id': song,
        'artist_id': artist,
        'album_id': album,
        'album_edition_id': edition,
        'qualified_at': at.toIso8601String(),
        'listened_duration_ms': 30000,
        'track_duration_ms': 180000,
        'created_at': at.toIso8601String(),
      });
    }
  }

  Future<void> edition(
    String id,
    String album, {
    String? genre,
    bool primary = false,
  }) => db.insert(DatabaseTables.albumEditions, {
    'id': id,
    'album_id': album,
    'genre': genre,
    'is_primary': primary ? 1 : 0,
  });

  group('periods and states', () {
    test('an empty library: no archive, and nothing invented', () async {
      expect((await service().archive()).isEmpty, isTrue);
      final summary = await service().load(PulsePeriod.month(2027, 2));
      expect(summary.state, WrappedPeriodState.beforeHistory);
      expect(summary.hasListening, isFalse);
      expect(summary.topSongs, isEmpty);
      expect(summary.genres, isEmpty);
      expect(summary.milestones, isEmpty);
      expect(summary.comparison.isAvailable, isFalse);
      expect(summary.days.every((d) => !d.recorded), isTrue);
    });

    test('history starting mid-month makes that month partial; the month '
        'running now is in progress', () async {
      await listen('song-1', DateTime(2027, 2, 10, 9));
      final february = await service().load(PulsePeriod.month(2027, 2));
      expect(february.state, WrappedPeriodState.complete);
      expect(february.historyStartLocal, DateTime(2027, 2, 10, 9));
      expect(february.isPartial, isTrue);
      expect(
        february.days.where((d) => d.recorded).first.startLocal,
        DateTime(2027, 2, 10),
        reason: 'days before history are never shown as zero listening',
      );

      final march = await service().load(PulsePeriod.month(2027, 3));
      expect(march.state, WrappedPeriodState.inProgress);
      expect(march.isPartial, isTrue);
      expect(
        (await service().load(PulsePeriod.month(2027, 4))).state,
        WrappedPeriodState.future,
      );
    });

    test('the current year is in progress, never a finished Wrapped; its '
        'future months are marked future', () async {
      await listen('song-1', DateTime(2027, 1, 5, 9));
      final year = await service().load(PulsePeriod.year(2027));
      expect(year.state, WrappedPeriodState.inProgress);
      expect(year.months, hasLength(12));
      expect(
        year.months.skip(3).every((m) => m.state == WrappedPeriodState.future),
        isTrue,
      );
      expect(year.months.first.state, WrappedPeriodState.complete);
    });

    test('the archive lists every month and year since history began, '
        'newest first', () async {
      await listen('song-1', DateTime(2026, 11, 20, 9));
      final archive = await service().archive();
      expect(archive.years, [PulsePeriod.year(2027), PulsePeriod.year(2026)]);
      expect(archive.months, [
        PulsePeriod.month(2027, 3),
        PulsePeriod.month(2027, 2),
        PulsePeriod.month(2027, 1),
        PulsePeriod.month(2026, 12),
        PulsePeriod.month(2026, 11),
      ]);
    });
  });

  group('boundaries', () {
    test(
      'local month and year boundaries decide where a play counts',
      () async {
        await listen('song-1', DateTime(2026, 12, 31, 23, 58));
        await listen('song-2', DateTime(2027, 1, 1, 0, 1));
        expect(
          (await service().load(PulsePeriod.month(2026, 12))).totals.streams,
          1,
        );
        expect(
          (await service().load(PulsePeriod.year(2026))).totals.streams,
          1,
        );
        expect(
          (await service().load(PulsePeriod.month(2027, 1))).totals.streams,
          1,
        );
      },
    );

    test('a listen crossing midnight into a new month splits its minutes; '
        'its stream counts once, where it qualified', () async {
      await listen(
        'song-1',
        DateTime(2027, 1, 31, 23, 50),
        listened: const Duration(minutes: 20),
      );
      final january = await service().load(PulsePeriod.month(2027, 1));
      final february = await service().load(PulsePeriod.month(2027, 2));
      expect(january.totals.listened, const Duration(minutes: 10));
      expect(february.totals.listened, const Duration(minutes: 10));
      expect(january.totals.streams + february.totals.streams, 1);
      expect(january.totals.streams, 1);
    });

    test('daylight saving months keep every local day, once', () async {
      now = DateTime(2027, 12, 1);
      await listen('song-1', DateTime(2027, 3, 14, 1, 30));
      await listen('song-2', DateTime(2027, 11, 7, 1, 30));
      final march = await service().load(PulsePeriod.month(2027, 3));
      final november = await service().load(PulsePeriod.month(2027, 11));
      expect(march.days, hasLength(31));
      expect(november.days, hasLength(30));
      expect(march.totals.streams, 1);
      expect(november.totals.streams, 1);
    });
  });

  group('what counts', () {
    test('a skip is a play, not a stream; Repeat One loops and duplicate '
        'queue entries are separate streams of one song', () async {
      await listen('song-1', DateTime(2027, 2, 1, 9));
      await listen('song-1', DateTime(2027, 2, 1, 9, 4)); // Repeat One loop
      await listen('song-1', DateTime(2027, 2, 1, 9, 8)); // queued twice
      await listen(
        'song-2',
        DateTime(2027, 2, 1, 9, 12),
        listened: const Duration(seconds: 12),
        qualifies: false,
      );
      final summary = await service().load(PulsePeriod.month(2027, 2));
      expect(summary.totals.streams, 3);
      expect(summary.totals.allPlays, 4);
      expect(summary.totals.songs, 1, reason: 'only streamed songs count');
      expect(summary.topSongs.single.streams, 3);
    });

    test(
      'editions of one release count as one album, and each play once',
      () async {
        await listen('song-1', DateTime(2027, 2, 1, 9), edition: 'standard');
        await listen('song-1', DateTime(2027, 2, 2, 9), edition: 'deluxe');
        await listen('song-2', DateTime(2027, 2, 3, 9), edition: 'deluxe');
        final summary = await service().load(PulsePeriod.month(2027, 2));
        expect(summary.totals.albums, 1);
        expect(summary.topAlbums.single.streams, 3);
        expect(summary.totals.streams, 3);
      },
    );

    test('artists are the artist each play counts for; ties rank the most '
        'recently heard first, then by id, every time', () async {
      await listen('s1', DateTime(2027, 2, 1, 9), artist: 'artist-b');
      await listen('s2', DateTime(2027, 2, 2, 9), artist: 'artist-a');
      await listen('s3', DateTime(2027, 2, 3, 9), artist: 'artist-c');
      final first = await service().load(PulsePeriod.month(2027, 2));
      final again = await service().load(PulsePeriod.month(2027, 2));
      expect(
        [for (final a in first.topArtists) a.id],
        ['artist-c', 'artist-a', 'artist-b'],
      );
      expect(
        [for (final a in again.topArtists) a.id],
        [for (final a in first.topArtists) a.id],
      );
      expect(first.mostPlayedArtist?.id, 'artist-c');
    });

    test('top lists hold ten at most', () async {
      for (var i = 0; i < 14; i++) {
        await listen('song-$i', DateTime(2027, 2, 1, 9, i * 4));
      }
      final summary = await service().load(PulsePeriod.month(2027, 2));
      expect(summary.topSongs, hasLength(10));
      expect(summary.totals.songs, 14);
    });
  });

  group('genres', () {
    test('aliases merge into one category, spellings differing in case into '
        'one genre; the played edition decides, then the primary; no genre '
        'is never guessed', () async {
      await edition('deluxe', 'album-a', genre: 'hip hop');
      await edition('standard', 'album-a', genre: 'Hip-Hop', primary: true);
      await edition('plain', 'album-b');
      await edition('folk', 'album-c', genre: 'Indie Folk');
      await edition('folk-2', 'album-d', genre: 'indie folk');
      await edition('none', 'album-e', primary: true);
      await listen('s1', DateTime(2027, 2, 1, 9), edition: 'deluxe');
      // An edition without a genre falls back to its release's primary.
      await listen('s2', DateTime(2027, 2, 2, 9), edition: 'no-row');
      await listen(
        's3',
        DateTime(2027, 2, 3, 9),
        album: 'album-c',
        edition: 'folk',
      );
      await listen(
        's4',
        DateTime(2027, 2, 4, 9),
        album: 'album-d',
        edition: 'folk-2',
      );
      await listen(
        's5',
        DateTime(2027, 2, 5, 9),
        album: 'album-e',
        edition: 'none',
      );
      final summary = await service().load(PulsePeriod.month(2027, 2));
      expect(
        [for (final g in summary.genres) (g.genre, g.streams)],
        [('Hip-Hop/Rap', 2), ('Indie Folk', 2)],
      );
      expect(summary.streamsWithoutGenre, 1);
      expect(summary.genres.first.share, 0.5);
    });
  });

  group('comparison', () {
    test('only when the previous period is fully recorded', () async {
      await listen('s1', DateTime(2027, 1, 10, 9));
      await listen('s2', DateTime(2027, 2, 10, 9));
      await listen('s3', DateTime(2027, 2, 11, 9));
      final january = await service().load(PulsePeriod.month(2027, 1));
      expect(january.comparison.isAvailable, isFalse);
      expect(january.comparison.state, WrappedComparisonState.notEnoughHistory);

      await listen('s0', DateTime(2026, 12, 20, 9));
      final february = await service().load(PulsePeriod.month(2027, 2));
      expect(february.comparison.isAvailable, isTrue);
      expect(february.comparison.totals?.streams, 1);
      expect(february.totals.streams, 2);
    });
  });

  group('the year', () {
    test('its months are each counted as their own Wrapped, and add up to '
        'the year', () async {
      now = DateTime(2028, 1, 10);
      await listen('s1', DateTime(2027, 1, 10, 9));
      await listen('s2', DateTime(2027, 6, 10, 9));
      await listen('s3', DateTime(2027, 6, 11, 9));
      await listen('s1', DateTime(2027, 12, 31, 22));
      final year = await service().load(PulsePeriod.year(2027));
      expect(year.state, WrappedPeriodState.complete);
      expect(
        year.months.map((m) => m.totals.streams).fold(0, (a, b) => a + b),
        year.totals.streams,
      );
      final june = await service().load(PulsePeriod.month(2027, 6));
      expect(year.months[5].totals.streams, june.totals.streams);
      expect(year.months[5].totals.listened, june.totals.listened);
      expect(year.mostActiveMonth?.period, PulsePeriod.month(2027, 6));
      expect(year.months[5].topSong?.id, june.topSongs.first.id);
    });
  });

  group('milestones', () {
    test('lifetime streams reached in the period, the longest streak and '
        'the busiest day; never across periods', () async {
      for (var i = 0; i < 98; i++) {
        await listen(
          'old',
          DateTime(2027, 1, 1, 9).add(Duration(minutes: i * 4)),
        );
      }
      await listen('s1', DateTime(2027, 2, 3, 9));
      await listen('s2', DateTime(2027, 2, 4, 9));
      await listen('s3', DateTime(2027, 2, 4, 10));
      await listen('s4', DateTime(2027, 2, 5, 9));
      final february = await service().load(PulsePeriod.month(2027, 2));
      final byKind = {for (final m in february.milestones) m.kind: m};
      expect(byKind[WrappedMilestoneKind.lifetimeStreams]?.value, 100);
      expect(
        byKind[WrappedMilestoneKind.lifetimeStreams]?.atLocal,
        DateTime(2027, 2, 4, 9, 0, 30),
        reason: 'the 100th stream qualified then',
      );
      expect(byKind[WrappedMilestoneKind.longestStreak]?.value, 3);
      expect(
        byKind[WrappedMilestoneKind.longestStreak]?.atLocal,
        DateTime(2027, 2, 3),
      );
      expect(
        byKind[WrappedMilestoneKind.busiestDay]?.atLocal,
        DateTime(2027, 2, 4),
      );
      final january = await service().load(PulsePeriod.month(2027, 1));
      expect(
        january.milestones.where(
          (m) => m.kind == WrappedMilestoneKind.lifetimeStreams,
        ),
        isEmpty,
        reason: '98 streams reach no milestone',
      );

      // March, after the 100th: that milestone is never told again.
      await listen('s5', DateTime(2027, 3, 2, 9));
      final march = await service().load(PulsePeriod.month(2027, 3));
      expect(
        march.milestones.where(
          (m) => m.kind == WrappedMilestoneKind.lifetimeStreams,
        ),
        isEmpty,
      );
    });
  });

  group('chart highlights', () {
    Future<void> week(DateTime startLocal, String song, String title) async {
      final start = startLocal.toUtc();
      final end = start.add(const Duration(days: 7));
      final id = 'chart_songs_${start.millisecondsSinceEpoch}';
      await db.insert(DatabaseTables.chartSnapshots, {
        'id': id,
        'chart_type': 'songs',
        'week_start_utc': start.toIso8601String(),
        'week_end_utc': end.toIso8601String(),
        'finalized_at': end.toIso8601String(),
        'revision': 1,
        'created_at': end.toIso8601String(),
        'updated_at': end.toIso8601String(),
      });
      await db.insert(DatabaseTables.chartEntries, {
        'id': '$id-1',
        'chart_snapshot_id': id,
        'entity_id': song,
        'title': title,
        'artist_id': 'artist-a',
        'artist_name': 'Artist A',
        'rank': 1,
        'qualified_stream_count': 5,
        'peak_rank': 1,
        'peak_achieved_at': end.toIso8601String(),
        'weeks_on_chart': 1,
        'movement': 'newEntry',
        'last_qualified_at': end.toIso8601String(),
        'created_at': end.toIso8601String(),
        'updated_at': end.toIso8601String(),
      });
    }

    test('stored weekly #1s of weeks that ended in the period; a week '
        'belongs to the period it ends in', () async {
      await listen('s1', DateTime(2027, 1, 20, 9));
      await week(DateTime(2027, 1, 24), 'song-x', 'X');
      await week(DateTime(2027, 1, 31), 'song-x', 'X');
      await week(DateTime(2027, 2, 7), 'song-y', 'Y');
      // Ends 31 Jan: January's week.
      final january = await service().load(PulsePeriod.month(2027, 1));
      expect(january.chartWeeks, 1);
      expect(january.chartNumberOnes.single.title, 'X');
      final february = await service().load(PulsePeriod.month(2027, 2));
      expect(february.chartWeeks, 2);
      expect(
        [for (final n in february.chartNumberOnes) (n.title, n.weeks)],
        [('X', 1), ('Y', 1)],
      );
    });
  });

  group('history changes', () {
    test('merges and deletions are reflected on the next load; nothing is '
        'kept stale', () async {
      await listen('song-old', DateTime(2027, 2, 1, 9));
      await listen('song-new', DateTime(2027, 2, 2, 9));
      expect(
        (await service().load(PulsePeriod.month(2027, 2))).totals.songs,
        2,
      );
      // A merge repoints history to the surviving Song ID.
      for (final table in [
        DatabaseTables.playbackSessions,
        DatabaseTables.qualifiedPlays,
      ]) {
        await db.update(
          table,
          {'song_id': 'song-new'},
          where: 'song_id = ?',
          whereArgs: ['song-old'],
        );
      }
      final merged = await service().load(PulsePeriod.month(2027, 2));
      expect(merged.totals.songs, 1);
      expect(merged.topSongs.single.streams, 2);

      // A permanent deletion removes the song's history.
      await db.delete(DatabaseTables.playbackSessions);
      final deleted = await service().load(PulsePeriod.month(2027, 2));
      expect(deleted.totals.streams, 0);
      expect(deleted.hasListening, isFalse);
    });

    test('restored history reads exactly as it was recorded', () async {
      await edition('e', 'album-a', genre: 'Pop', primary: true);
      await listen('s1', DateTime(2027, 2, 1, 9), edition: 'e');
      await listen('s2', DateTime(2027, 2, 2, 9), edition: 'e');
      final before = await service().load(PulsePeriod.month(2027, 2));
      // A restore re-inserts the same rows (Wrapped stores nothing itself).
      final rows = {
        for (final t in [
          DatabaseTables.playbackSessions,
          DatabaseTables.playbackListeningSegments,
          DatabaseTables.qualifiedPlays,
          DatabaseTables.albumEditions,
        ])
          t: await db.query(t),
      };
      await db.delete(DatabaseTables.playbackSessions);
      await db.delete(DatabaseTables.albumEditions);
      for (final MapEntry(key: table, value: list) in rows.entries) {
        for (final row in list) {
          await db.insert(table, row);
        }
      }
      final after = await service().load(PulsePeriod.month(2027, 2));
      expect(after.totals.streams, before.totals.streams);
      expect(after.totals.listened, before.totals.listened);
      expect(after.genres.single.genre, 'Pop');
    });

    test('loading never writes', () async {
      await listen('s1', DateTime(2027, 2, 1, 9));
      Future<Map<String, int>> counts() async => {
        for (final row in await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table'",
        ))
          row['name']! as String:
              (await db.rawQuery(
                    'SELECT COUNT(*) AS n FROM "${row['name']}"',
                  )).single['n']!
                  as int,
      };
      final before = await counts();
      await service().load(PulsePeriod.year(2027));
      await service().load(PulsePeriod.month(2027, 2));
      await service().archive();
      expect(await counts(), before);
    });
  });

  test('a large history stays quick: a year of 20,000 streams', () async {
    now = DateTime(2028, 1, 2);
    final batch = db.batch();
    final start = DateTime(2027, 1, 1, 8).toUtc();
    for (var i = 0; i < 20000; i++) {
      final at = start.add(Duration(minutes: i * 26));
      final id = 'bulk-$i';
      final song = 'song-${i % 700}';
      final artist = 'artist-${i % 90}';
      final album = 'album-${i % 150}';
      batch.insert(DatabaseTables.playbackSessions, {
        'id': id,
        'song_id': song,
        'artist_id': artist,
        'album_id': album,
        'album_edition_id': 'edition-$album',
        'song_title': song,
        'artist_name': artist,
        'album_title': album,
        'album_edition_title': album,
        'started_at': at.toIso8601String(),
        'ended_at': at.add(const Duration(minutes: 3)).toIso8601String(),
        'listened_duration_ms': 180000,
        'created_at': at.toIso8601String(),
        'updated_at': at.toIso8601String(),
      });
      batch.insert(DatabaseTables.playbackListeningSegments, {
        'id': 'seg-$id',
        'playback_session_id': id,
        'started_at': at.toIso8601String(),
        'ended_at': at.add(const Duration(minutes: 3)).toIso8601String(),
        'listened_duration_ms': 180000,
        'created_at': at.toIso8601String(),
        'updated_at': at.toIso8601String(),
      });
      batch.insert(DatabaseTables.qualifiedPlays, {
        'id': 'play-$id',
        'playback_session_id': id,
        'song_id': song,
        'artist_id': artist,
        'album_id': album,
        'album_edition_id': 'edition-$album',
        'qualified_at': at.add(const Duration(seconds: 30)).toIso8601String(),
        'listened_duration_ms': 30000,
        'track_duration_ms': 180000,
        'created_at': at.toIso8601String(),
      });
    }
    await batch.commit(noResult: true);

    final watch = Stopwatch()..start();
    final year = await service().load(PulsePeriod.year(2027));
    watch.stop();
    // ignore: avoid_print
    print('Wrapped year of 20,000 streams: ${watch.elapsedMilliseconds} ms');
    expect(year.totals.streams, 20000);
    expect(
      year.months.map((m) => m.totals.streams).fold(0, (a, b) => a + b),
      20000,
    );
    expect(year.topSongs, hasLength(10));
    expect(watch.elapsed, lessThan(const Duration(seconds: 30)));
  });
}

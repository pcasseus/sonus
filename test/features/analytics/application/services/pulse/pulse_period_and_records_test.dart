import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/core/database/schema/analytics_schema.dart';
import 'package:sonus_next/features/analytics/application/models/pulse/pulse_period.dart';
import 'package:sonus_next/features/analytics/application/services/pulse/pulse_insights_service.dart';
import 'package:sonus_next/features/analytics/data/repositories/sqlite_pulse_listening_records.dart';

void main() {
  group('PulsePeriod', () {
    test('months wrap across years and know their neighbours', () {
      final january = PulsePeriod.month(2027, 1);
      expect(january.previous, PulsePeriod.month(2026, 12));
      expect(PulsePeriod.month(2026, 12).next, january);
      expect(january.samePeriodLastYear, PulsePeriod.month(2026, 1));
      expect(PulsePeriod.month(2026, 13), january, reason: 'normalized');
    });

    test('days cover the period in local days, DST months included', () {
      expect(PulsePeriod.month(2026, 2).days, hasLength(28));
      expect(PulsePeriod.month(2028, 2).days, hasLength(29));
      expect(PulsePeriod.month(2026, 3).days, hasLength(31));
      expect(PulsePeriod.month(2026, 11).days, hasLength(30));
      expect(PulsePeriod.year(2028).days, hasLength(366));
      for (final day in PulsePeriod.month(2026, 3).days) {
        expect(day.hour, 0, reason: 'every day starts at local midnight');
      }
    });

    test('a year compares with the year before, both ways', () {
      final year = PulsePeriod.year(2026);
      expect(year.previous, PulsePeriod.year(2025));
      expect(year.samePeriodLastYear, PulsePeriod.year(2025));
      expect(
        PulsePeriod.containing(PulsePeriodKind.year, DateTime(2026, 7, 4)),
        year,
      );
    });
  });

  group('SqlitePulseListeningRecords', () {
    sqfliteFfiInit();
    late Database db;

    setUp(() async {
      db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) => AnalyticsSchema.create(db),
        ),
      );
    });
    tearDown(() => db.close());

    Future<void> session(String id, DateTime start) =>
        db.insert(DatabaseTables.playbackSessions, {
          'id': id,
          'song_id': 'song',
          'artist_id': 'artist',
          'album_id': 'album',
          'album_edition_id': 'edition',
          'song_title': 's',
          'artist_name': 'a',
          'album_title': 'r',
          'album_edition_title': 'e',
          'started_at': start.toUtc().toIso8601String(),
          'listened_duration_ms': 60000,
          'created_at': start.toUtc().toIso8601String(),
          'updated_at': start.toUtc().toIso8601String(),
        });

    Future<void> segment(
      String id,
      String sessionId,
      DateTime start,
      DateTime? end,
      Duration listened,
    ) => db.insert(DatabaseTables.playbackListeningSegments, {
      'id': id,
      'playback_session_id': sessionId,
      'started_at': start.toUtc().toIso8601String(),
      'ended_at': end?.toUtc().toIso8601String(),
      'listened_duration_ms': listened.inMilliseconds,
      'created_at': start.toUtc().toIso8601String(),
      'updated_at': start.toUtc().toIso8601String(),
    });

    test('reads only rows near the window; open segments are kept and '
        'clipped', () async {
      final old = DateTime(2023, 4, 2, 10);
      final inside = DateTime(2026, 10, 3, 10);
      final open = DateTime(2026, 10, 31, 23, 30);
      await session('old', old);
      await session('inside', inside);
      await session('open', open);
      await segment(
        'old_seg',
        'old',
        old,
        old.add(const Duration(minutes: 3)),
        const Duration(minutes: 3),
      );
      await segment(
        'inside_seg',
        'inside',
        inside,
        inside.add(const Duration(minutes: 3)),
        const Duration(minutes: 3),
      );
      // Still playing: no end yet, 50 minutes recorded so far.
      await segment(
        'open_seg',
        'open',
        open,
        null,
        const Duration(minutes: 50),
      );

      final records = SqlitePulseListeningRecords(db);
      final october = PulsePeriod.month(2026, 10);

      final rows = await records.segmentsOverlapping(october.window);
      expect(rows.map((r) => r.startedAt), [
        inside.toUtc(),
        open.toUtc(),
      ], reason: 'the 2023 segment is not read for October 2026');
      expect(await records.firstSessionStartedAt(), old.toUtc());

      final totals = await PulseInsightsService(
        records: records,
      ).totalsFor(october);
      expect(
        totals.listened,
        const Duration(minutes: 33),
        reason: '3 inside + 30 of the open segment before November',
      );
    });
  });
}

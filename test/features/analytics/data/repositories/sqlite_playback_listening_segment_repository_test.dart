import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/core/database/schema/analytics_schema.dart';
import 'package:sonus_next/features/analytics/data/daos/playback_listening_segment_dao.dart';
import 'package:sonus_next/features/analytics/data/repositories/sqlite_playback_listening_segment_repository.dart';
import 'package:sonus_next/features/analytics/domain/entities/playback_listening_segment.dart';

void main() {
  sqfliteFfiInit();

  late Database database;
  late SqlitePlaybackListeningSegmentRepository repository;

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          await AnalyticsSchema.create(db);
        },
      ),
    );

    repository = SqlitePlaybackListeningSegmentRepository(
      PlaybackListeningSegmentDao(database),
    );

    await database.insert(DatabaseTables.playbackSessions, {
      'id': 'session_1',
      'song_id': 'song_1',
      'artist_id': 'artist_1',
      'album_id': 'album_1',
      'album_edition_id': 'edition_1',
      'song_title': 'Segment Test Song',
      'artist_name': 'Segment Test Artist',
      'album_title': 'Segment Test Album',
      'album_edition_title': 'Segment Test Edition',
      'started_at': '2026-09-25T12:00:00.000Z',
      'ended_at': null,
      'listened_duration_ms': 0,
      'track_duration_ms': 180000,
      'final_position_ms': 0,
      'end_reason': null,
      'source_context': 'library',
      'created_at': '2026-09-25T12:00:00.000Z',
      'updated_at': '2026-09-25T12:00:00.000Z',
    });
  });

  tearDown(() async {
    await database.close();
  });

  PlaybackListeningSegment segment({
    required String id,
    required DateTime startedAt,
    DateTime? endedAt,
    Duration listenedDuration = Duration.zero,
  }) {
    return PlaybackListeningSegment(
      id: id,
      playbackSessionId: 'session_1',
      startedAt: startedAt,
      endedAt: endedAt,
      listenedDuration: listenedDuration,
      createdAt: startedAt,
      updatedAt: endedAt ?? startedAt,
    );
  }

  test('creates and reads listening segment', () async {
    final value = segment(
      id: 'segment_1',
      startedAt: DateTime.utc(2026, 9, 25, 12),
    );

    await repository.create(value);

    final stored = await repository.getById('segment_1');

    expect(stored, isNotNull);
    expect(stored!.playbackSessionId, 'session_1');
    expect(stored.startedAt, DateTime.utc(2026, 9, 25, 12));
    expect(stored.endedAt, isNull);
    expect(stored.listenedDuration, Duration.zero);
  });

  test('updates an existing listening segment', () async {
    final startedAt = DateTime.utc(2026, 9, 25, 12);

    await repository.create(
      segment(id: 'segment_update', startedAt: startedAt),
    );

    final updated = segment(
      id: 'segment_update',
      startedAt: startedAt,
      endedAt: startedAt.add(const Duration(seconds: 20)),
      listenedDuration: const Duration(seconds: 20),
    );

    await repository.save(updated);

    final stored = await repository.getById('segment_update');

    expect(stored!.endedAt, DateTime.utc(2026, 9, 25, 12, 0, 20));
    expect(stored.listenedDuration, const Duration(seconds: 20));
  });

  test('finds open segment for playback session', () async {
    final startedAt = DateTime.utc(2026, 9, 25, 12);

    await repository.create(
      segment(
        id: 'closed',
        startedAt: startedAt,
        endedAt: startedAt.add(const Duration(seconds: 10)),
        listenedDuration: const Duration(seconds: 10),
      ),
    );

    await repository.create(
      segment(
        id: 'open',
        startedAt: startedAt.add(const Duration(seconds: 20)),
      ),
    );

    final open = await repository.getOpenForSession('session_1');

    expect(open, isNotNull);
    expect(open!.id, 'open');
    expect(open.isEnded, isFalse);
  });

  test('startedBefore uses an exclusive boundary', () async {
    await repository.create(
      segment(
        id: 'before',
        startedAt: DateTime.utc(2026, 9, 25, 11, 59),
        endedAt: DateTime.utc(2026, 9, 25, 11, 59, 30),
        listenedDuration: const Duration(seconds: 30),
      ),
    );

    await repository.create(
      segment(
        id: 'boundary',
        startedAt: DateTime.utc(2026, 9, 25, 12),
        endedAt: DateTime.utc(2026, 9, 25, 12, 0, 30),
        listenedDuration: const Duration(seconds: 30),
      ),
    );

    final values = await repository.getAll(
      startedBefore: DateTime.utc(2026, 9, 25, 12),
    );

    expect(values.map((value) => value.id), ['before']);
  });

  test('deleting playback session cascades listening segments', () async {
    await repository.create(
      segment(id: 'segment_cascade', startedAt: DateTime.utc(2026, 9, 25, 12)),
    );

    await database.delete(
      DatabaseTables.playbackSessions,
      where: 'id = ?',
      whereArgs: ['session_1'],
    );

    final rows = await database.query(DatabaseTables.playbackListeningSegments);

    expect(rows, isEmpty);
  });

  test('rejects segment for missing playback session', () async {
    final value = PlaybackListeningSegment(
      id: 'segment_invalid',
      playbackSessionId: 'missing_session',
      startedAt: DateTime.utc(2026, 9, 25, 12),
      listenedDuration: Duration.zero,
      createdAt: DateTime.utc(2026, 9, 25, 12),
      updatedAt: DateTime.utc(2026, 9, 25, 12),
    );

    await expectLater(repository.create(value), throwsA(anything));
  });
}

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/features/analytics/presentation/scopes/analytics_scope.dart';
import 'package:sonus_next/features/player/application/controllers/playback_coordinator.dart';
import 'package:sonus_next/features/player/domain/models/playback_queue.dart';
import 'package:sonus_next/features/player/domain/models/playback_repeat_mode.dart';
import 'package:sonus_next/features/player/domain/models/playback_state.dart';
import 'package:sonus_next/features/player/domain/models/playback_track.dart';
import 'package:sonus_next/features/player/domain/services/playback_engine.dart';

class FakePlaybackEngine implements PlaybackEngine {
  final StreamController<PlaybackState> _controller =
      StreamController<PlaybackState>.broadcast(sync: true);

  PlaybackState state = const PlaybackState();

  @override
  PlaybackState get currentState => state;

  @override
  Stream<PlaybackState> get states => _controller.stream;

  void emit(PlaybackState value) {
    state = value;
    _controller.add(value);
  }

  @override
  Future<void> loadQueue(
    List<PlaybackTrack> tracks, {
    int startIndex = 0,
    bool autoPlay = false,
  }) async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> skipNext() async {}

  @override
  Future<void> skipPrevious() async {}

  @override
  Future<void> skipToIndex(int index) async {}

  @override
  Future<void> insertTrack(PlaybackTrack track, {required int index}) async {}

  @override
  Future<void> appendTrack(PlaybackTrack track) async {}

  @override
  Future<void> removeTrackAt(int index) async {}

  @override
  Future<void> moveTrack({
    required int oldIndex,
    required int newIndex,
  }) async {}

  @override
  Future<void> setShuffleEnabled(bool enabled) async {}

  @override
  Future<void> setRepeatMode(PlaybackRepeatMode mode) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }
}

void main() {
  sqfliteFfiInit();

  late AppDatabase appDatabase;
  late FakePlaybackEngine engine;
  late PlaybackCoordinator coordinator;

  setUp(() {
    appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );

    engine = FakePlaybackEngine();
    coordinator = PlaybackCoordinator(engine: engine);
  });

  tearDown(() async {
    await appDatabase.close();
    await engine.dispose();
  });

  test(
    'AnalyticsRuntime persists real playback session and qualified play',
    () async {
      var now = DateTime.utc(2026, 9, 25, 12);

      final runtime = await AnalyticsRuntime.create(
        appDatabase: appDatabase,
        playbackCoordinator: coordinator,
        now: () => now,
      );

      const track = PlaybackTrack(
        songId: 'song_scope',
        title: 'Scope Song',
        artistId: 'artist_scope',
        artistName: 'Scope Artist',
        albumId: 'album_scope',
        albumTitle: 'Scope Album',
        albumEditionId: 'edition_scope',
        albumEditionTitle: 'Scope Album',
        filePath: 'C:/Music/scope_song.mp3',
        duration: Duration(minutes: 3),
      );

      final queue = const PlaybackQueue().replace(tracks: const [track]);

      engine.emit(
        PlaybackState(
          queue: queue,
          status: PlaybackStatus.playing,
          position: Duration.zero,
          duration: const Duration(minutes: 3),
        ),
      );

      await runtime.controller.settled;

      now = now.add(const Duration(seconds: 31));

      engine.emit(
        PlaybackState(
          queue: queue,
          status: PlaybackStatus.paused,
          position: const Duration(seconds: 31),
          duration: const Duration(minutes: 3),
        ),
      );

      await runtime.controller.settled;

      engine.emit(
        PlaybackState(
          queue: queue,
          status: PlaybackStatus.completed,
          position: const Duration(minutes: 3),
          duration: const Duration(minutes: 3),
        ),
      );

      await runtime.controller.settled;

      final database = await appDatabase.database;

      final sessions = await database.query(
        DatabaseTables.playbackSessions,
        where: 'song_id = ?',
        whereArgs: ['song_scope'],
      );

      final listeningSegments = await database.query(
        DatabaseTables.playbackListeningSegments,
        where: 'playback_session_id = ?',
        whereArgs: [sessions.single['id']],
      );
      final qualifiedPlays = await database.query(
        DatabaseTables.qualifiedPlays,
        where: 'song_id = ?',
        whereArgs: ['song_scope'],
      );

      expect(sessions, hasLength(1));
      expect(listeningSegments, hasLength(1));
      expect(qualifiedPlays, hasLength(1));

      final session = sessions.single;
      final listeningSegment = listeningSegments.single;
      final qualifiedPlay = qualifiedPlays.single;

      expect(session['artist_id'], 'artist_scope');
      expect(session['album_id'], 'album_scope');
      expect(session['album_edition_id'], 'edition_scope');
      expect(session['listened_duration_ms'], 31000);
      expect(session['end_reason'], 'completed');
      expect(session['ended_at'], isNotNull);
      expect(listeningSegment['playback_session_id'], session['id']);
      expect(listeningSegment['listened_duration_ms'], 31000);
      expect(listeningSegment['ended_at'], isNotNull);
      expect(listeningSegment['playback_session_id'], session['id']);
      expect(listeningSegment['listened_duration_ms'], 31000);
      expect(listeningSegment['ended_at'], isNotNull);

      expect(qualifiedPlay['playback_session_id'], session['id']);
      expect(qualifiedPlay['artist_id'], 'artist_scope');
      expect(qualifiedPlay['album_id'], 'album_scope');
      expect(qualifiedPlay['album_edition_id'], 'edition_scope');
      expect(qualifiedPlay['listened_duration_ms'], 31000);

      await runtime.dispose();
    },
  );

  test(
    'AnalyticsRuntime recovers stale session before attaching controller',
    () async {
      final database = await appDatabase.database;

      const startedAt = '2026-09-25T10:00:00.000Z';
      const truthfulEndedAt = '2026-09-25T10:02:00.000Z';
      const misleadingUpdatedAt = '2026-09-25T10:05:00.000Z';

      await database.insert(DatabaseTables.playbackSessions, {
        'id': 'session_stale_scope',
        'song_id': 'song_stale_scope',
        'artist_id': 'artist_stale_scope',
        'album_id': 'album_stale_scope',
        'album_edition_id': 'edition_stale_scope',
        'song_title': 'Stale Scope Song',
        'artist_name': 'Stale Scope Artist',
        'album_title': 'Stale Scope Album',
        'album_edition_title': 'Stale Scope Edition',
        'started_at': startedAt,
        'ended_at': null,
        'listened_duration_ms': 120000,
        'track_duration_ms': 240000,
        'final_position_ms': 120000,
        'end_reason': null,
        'source_context': null,
        'created_at': startedAt,
        'updated_at': misleadingUpdatedAt,
      });

      await database.insert(DatabaseTables.playbackListeningSegments, {
        'id': 'segment_stale_scope',
        'playback_session_id': 'session_stale_scope',
        'started_at': startedAt,
        'ended_at': null,
        'listened_duration_ms': 120000,
        'created_at': startedAt,
        'updated_at': misleadingUpdatedAt,
      });
      final runtime = await AnalyticsRuntime.create(
        appDatabase: appDatabase,
        playbackCoordinator: coordinator,
      );

      final rows = await database.query(
        DatabaseTables.playbackSessions,
        where: 'id = ?',
        whereArgs: ['session_stale_scope'],
      );

      final segmentRows = await database.query(
        DatabaseTables.playbackListeningSegments,
        where: 'id = ?',
        whereArgs: ['segment_stale_scope'],
      );

      expect(rows, hasLength(1));
      expect(segmentRows, hasLength(1));

      final recovered = rows.single;
      final recoveredSegment = segmentRows.single;

      expect(recovered['end_reason'], 'interrupted');
      expect(recovered['ended_at'], truthfulEndedAt);
      expect(recovered['updated_at'], truthfulEndedAt);
      expect(recovered['listened_duration_ms'], 120000);
      expect(recovered['ended_at'], isNot(misleadingUpdatedAt));

      expect(recoveredSegment['ended_at'], truthfulEndedAt);
      expect(recoveredSegment['updated_at'], truthfulEndedAt);
      expect(recoveredSegment['listened_duration_ms'], 120000);
      expect(recoveredSegment['ended_at'], isNot(misleadingUpdatedAt));

      await runtime.dispose();
    },
  );
}

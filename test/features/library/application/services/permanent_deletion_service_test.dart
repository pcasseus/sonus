// App Update 1.2: user-directed permanent deletion. Synthetic fixtures and
// disposable databases only; never the user's library.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/core/events/library_change_signal.dart';
import 'package:sonus_next/features/analytics/data/daos/playback_session_dao.dart';
import 'package:sonus_next/features/analytics/data/daos/qualified_play_dao.dart';
import 'package:sonus_next/features/analytics/data/repositories/sqlite_playback_session_repository.dart';
import 'package:sonus_next/features/analytics/data/repositories/sqlite_qualified_play_repository.dart';
import 'package:sonus_next/features/charts/application/services/chart_finalization_service.dart';
import 'package:sonus_next/features/charts/application/services/chart_snapshot_builder_service.dart';
import 'package:sonus_next/features/charts/data/repositories/sqlite_chart_moment_repository.dart';
import 'package:sonus_next/features/charts/data/repositories/sqlite_chart_repository.dart';
import 'package:sonus_next/features/import/application/services/atomic_library_importer.dart';
import 'package:sonus_next/features/import/domain/models/audio_metadata.dart';
import 'package:sonus_next/features/import/domain/models/import_candidate.dart';
import 'package:sonus_next/features/import/domain/models/import_result.dart';
import 'package:sonus_next/features/library/application/services/permanent_deletion_service.dart';
import 'package:sonus_next/features/library/data/daos/library_query_dao.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_deletion_journal_reader.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_library_query_repository.dart';
import 'package:sonus_next/features/library/domain/deletion/permanent_deletion_impact.dart';
import 'package:sonus_next/features/sync/application/services/inbound_cloud_record_applier.dart';
import 'package:sonus_next/features/sync/data/repositories/sync_mutation_transaction_runner.dart';
import 'package:sonus_next/features/sync/data/services/sqlite_cloud_archive_store.dart';
import 'package:sonus_next/features/sync/domain/models/cloud_archive_record.dart';
import 'package:sonus_next/features/sync/domain/models/cloud_records.dart';

void main() {
  sqfliteFfiInit();

  late Directory dir;
  late AppDatabase appDatabase;
  late Database db;
  late PermanentDeletionService service;
  var linked = false;
  Set<String>? deletedFromQueue;
  var ids = 0;
  final now = DateTime.utc(2026, 10, 30, 12);
  final stamp = now.toIso8601String();

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('sonus_permanent_deletion_');
    appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: p.join(dir.path, 'library.db'),
    );
    db = await appDatabase.database;
    linked = false;
    deletedFromQueue = null;
    service = PermanentDeletionService(
      appDatabase: appDatabase,
      userId: 'user_1',
      isCloudLinked: (_) async => linked,
      now: () => now,
      generateOutboxId: () => 'outbox_${++ids}',
      generateOperationId: () => 'operation_${++ids}',
      changes: LibraryChangeSignal(),
      onSongsDeleted: (songIds) async => deletedFromQueue = songIds,
    );
  });

  tearDown(() async {
    await appDatabase.close();
    await dir.delete(recursive: true);
  });

  Future<int> count(
    String table, [
    String where = '1',
    List<Object?>? args,
  ]) async =>
      (await db.rawQuery(
            'SELECT COUNT(*) AS n FROM $table WHERE $where',
            args,
          )).single['n']!
          as int;

  Future<void> artist(String id) => db.insert(DatabaseTables.artists, {
    'id': id,
    'name': id,
    'canonical_name': id,
    'created_at': stamp,
    'updated_at': stamp,
  });

  Future<void> album(String id, String owner, List<String> editions) async {
    await db.insert(DatabaseTables.albums, {
      'id': id,
      'artist_id': owner,
      'title': id,
      'canonical_title': id,
      'created_at': stamp,
      'updated_at': stamp,
    });
    for (final (index, edition) in editions.indexed) {
      await db.insert(DatabaseTables.albumEditions, {
        'id': edition,
        'album_id': id,
        'title': edition,
        'type': index == 0 ? 'standard' : 'deluxe',
        'is_primary': index == 0 ? 1 : 0,
        'created_at': stamp,
        'updated_at': stamp,
      });
    }
  }

  Future<void> song(
    String id, {
    required String artistId,
    required String albumId,
    required String home,
    List<String>? listedOn,
    List<String> featuring = const [],
  }) async {
    await db.insert(DatabaseTables.songs, {
      'id': id,
      'artist_id': artistId,
      'album_id': albumId,
      'album_edition_id': home,
      'title': id,
      'canonical_title': id,
      'track_number': 1,
      'duration_seconds': 200,
      'created_at': stamp,
      'updated_at': stamp,
    });
    for (final (index, edition) in (listedOn ?? [home]).indexed) {
      await db.insert(DatabaseTables.albumEditionTracks, {
        'album_edition_id': edition,
        'song_id': id,
        'sort_position': index,
        'created_at': stamp,
        'updated_at': stamp,
      });
    }
    for (final (index, credited) in [artistId, ...featuring].indexed) {
      await db.insert(DatabaseTables.songArtistCredits, {
        'id': 'credit_${id}_$index',
        'song_id': id,
        'artist_id': credited,
        'credited_name': credited,
        'canonical_credited_name': credited,
        'role': index == 0 ? 'primary' : 'featured',
        'position': index,
        'created_at': stamp,
        'updated_at': stamp,
      });
    }
    await db.insert(DatabaseTables.mediaFileBindings, {
      'id': 'binding_$id',
      'song_id': id,
      'file_path': '/music/$id.mp3',
      'normalized_path': '/music/$id.mp3',
      'created_at': stamp,
      'updated_at': stamp,
    });
    await db.insert('sync_cloud_revision_baselines', {
      'user_id': 'user_1',
      'entity_type': 'song',
      'entity_id': id,
      'server_revision': 1,
    });
  }

  var playCount = 0;
  Future<void> play(String songId, DateTime at) async {
    final s = (await db.query(
      DatabaseTables.songs,
      where: 'id = ?',
      whereArgs: [songId],
    )).single;
    final id = '${++playCount}';
    final iso = at.toIso8601String();
    await db.insert(DatabaseTables.playbackSessions, {
      'id': 'session_$id',
      'song_id': songId,
      'artist_id': s['artist_id'],
      'album_id': s['album_id'],
      'album_edition_id': s['album_edition_id'],
      'song_title': songId,
      'artist_name': s['artist_id'],
      'album_title': s['album_id'],
      'album_edition_title': s['album_edition_id'],
      'started_at': iso,
      'ended_at': iso,
      'listened_duration_ms': 180000,
      'track_duration_ms': 180000,
      'created_at': iso,
      'updated_at': iso,
    });
    await db.insert(DatabaseTables.playbackListeningSegments, {
      'id': 'segment_$id',
      'playback_session_id': 'session_$id',
      'started_at': iso,
      'ended_at': iso,
      'listened_duration_ms': 180000,
      'created_at': iso,
      'updated_at': iso,
    });
    await db.insert(DatabaseTables.qualifiedPlays, {
      'id': 'play_$id',
      'playback_session_id': 'session_$id',
      'song_id': songId,
      'artist_id': s['artist_id'],
      'album_id': s['album_id'],
      'album_edition_id': s['album_edition_id'],
      'qualified_at': iso,
      'listened_duration_ms': 180000,
      'track_duration_ms': 180000,
      'created_at': iso,
    });
  }

  /// Nova (one release, Standard + Deluxe), Lumen featuring Nova on "glow",
  /// Echo unrelated.
  Future<void> seedWorld() async {
    for (final a in ['nova', 'lumen', 'echo']) {
      await artist(a);
    }
    await album('nova_album', 'nova', ['nova_std', 'nova_dlx']);
    await album('lights', 'lumen', ['lights_std']);
    await album('echoes', 'echo', ['echoes_std']);
    await song(
      'opening',
      artistId: 'nova',
      albumId: 'nova_album',
      home: 'nova_std',
      listedOn: ['nova_std', 'nova_dlx'],
    );
    await song(
      'bonus',
      artistId: 'nova',
      albumId: 'nova_album',
      home: 'nova_dlx',
    );
    await song(
      'glow',
      artistId: 'lumen',
      albumId: 'lights',
      home: 'lights_std',
      featuring: ['nova'],
    );
    await song('echo', artistId: 'echo', albumId: 'echoes', home: 'echoes_std');
    await db.insert(DatabaseTables.playlists, {
      'id': 'road',
      'name': 'Road',
      'created_at': stamp,
      'updated_at': stamp,
    });
    for (final (position, songId) in ['opening', 'glow', 'echo'].indexed) {
      await db.insert(DatabaseTables.playlistItems, {
        'id': 'item_$songId',
        'playlist_id': 'road',
        'song_id': songId,
        'position': position,
        'created_at': stamp,
        'updated_at': stamp,
      });
    }
  }

  test('a song: its history, links and listings go; files stay', () async {
    await seedWorld();
    await play('opening', DateTime.utc(2026, 10, 5, 10));
    await play('opening', DateTime.utc(2026, 10, 6, 10));
    await play('echo', DateTime.utc(2026, 10, 6, 11));

    final preview = await service.preview(
      const PermanentDeletionTarget.song('opening'),
    );
    expect(preview.canProceed, isTrue);
    await service.delete(preview);

    expect(await count(DatabaseTables.songs, "id = 'opening'"), 0);
    expect(await count(DatabaseTables.playbackSessions), 1);
    expect(await count(DatabaseTables.playbackListeningSegments), 1);
    expect(await count(DatabaseTables.qualifiedPlays), 1);
    expect(await count(DatabaseTables.mediaFileBindings), 3);
    expect(
      await count(DatabaseTables.albumEditionTracks, "song_id = 'opening'"),
      0,
    );
    // The release, its editions and the artist stay.
    expect(await count(DatabaseTables.albums, "id = 'nova_album'"), 1);
    expect(await count(DatabaseTables.artists, "id = 'nova'"), 1);
    // The playlist closes the gap.
    final items = await db.query(
      DatabaseTables.playlistItems,
      orderBy: 'position',
    );
    expect(items.map((i) => (i['song_id'], i['position'])), [
      ('glow', 0),
      ('echo', 1),
    ]);
    // Remembered so nothing brings it back; the cloud is told.
    expect(
      await count(
        DatabaseTables.libraryDeletionLedger,
        "entity_type = 'mediaFile' AND entity_id = '/music/opening.mp3'",
      ),
      1,
    );
    expect(
      await count(
        DatabaseTables.syncOutbox,
        "entity_type = 'song' AND entity_id = 'opening' AND operation = 'delete'",
      ),
      1,
    );
    expect(await count(DatabaseTables.libraryDeletionJournal), 1);
    expect(deletedFromQueue, {'opening'});
  });

  test('nothing brings a deleted song back', () async {
    await seedWorld();
    await play('opening', DateTime.utc(2026, 10, 5, 10));
    final preview = await service.preview(
      const PermanentDeletionTarget.song('opening'),
    );
    await service.delete(preview);

    // A rescan of its file.
    final rescan = await AtomicLibraryImporter(appDatabase: appDatabase).import(
      candidate: ImportCandidate(
        filePath: '/music/opening.mp3',
        normalizedPath: '/music/opening.mp3',
        discoveredAt: now,
      ),
      metadata: const AudioMetadata(
        title: 'opening',
        artistName: 'nova',
        albumTitle: 'nova_album',
        durationSeconds: 200,
        trackNumber: 1,
        discNumber: 1,
        isSingle: false,
        featuredArtists: [],
      ),
    );
    expect(rescan.skipReason, ImportSkipReason.deletedFromLibrary);
    expect(await count(DatabaseTables.songs, "canonical_title = 'opening'"), 0);

    // An older cloud copy of the song.
    final outcome =
        await SyncMutationTransactionRunner(
          appDatabase: appDatabase,
          changes: LibraryChangeSignal(),
        ).run(
          (context) => const InboundCloudRecordApplier().apply(
            record: CloudSongRecord(
              id: 'opening',
              userId: 'user_1',
              artistId: 'nova',
              albumId: 'nova_album',
              albumEditionId: 'nova_std',
              title: 'opening',
              canonicalTitle: 'opening',
              trackNumber: 1,
              durationSeconds: 200,
              isSingle: false,
              featuredArtists: const [],
              createdAt: now,
              updatedAt: now,
            ),
            context: context,
          ),
        );
    expect(outcome.isDeferred, isFalse);
    expect(await count(DatabaseTables.songs, "id = 'opening'"), 0);

    // Its listening, downloaded again from the cloud archive.
    await SqliteCloudArchiveStore(
      appDatabase: appDatabase,
      changes: LibraryChangeSignal(),
    ).apply(
      CloudArchiveRecord(
        kind: CloudArchiveKind.listeningSession,
        key: 'session_1',
        clientUpdatedAt: now,
        payload: {
          'session': {
            'id': 'session_1',
            'song_id': 'opening',
            'artist_id': 'nova',
            'album_id': 'nova_album',
            'album_edition_id': 'nova_std',
            'song_title': 'opening',
            'artist_name': 'nova',
            'album_title': 'nova_album',
            'album_edition_title': 'nova_std',
            'started_at': stamp,
            'ended_at': stamp,
            'listened_duration_ms': 180000,
            'track_duration_ms': 180000,
            'created_at': stamp,
            'updated_at': stamp,
          },
          'segments': const [],
          'qualified_play': {
            'id': 'play_1',
            'playback_session_id': 'session_1',
            'song_id': 'opening',
            'artist_id': 'nova',
            'album_id': 'nova_album',
            'album_edition_id': 'nova_std',
            'qualified_at': stamp,
            'listened_duration_ms': 180000,
            'track_duration_ms': 180000,
            'created_at': stamp,
          },
        },
      ),
    );
    expect(await count(DatabaseTables.playbackSessions), 0);
    expect(await count(DatabaseTables.qualifiedPlays), 0);
  });

  test('a Deluxe edition: its own song goes, shared songs move', () async {
    await seedWorld();
    // Make Deluxe primary and "opening" homed on it, then delete Deluxe.
    await db.update(DatabaseTables.albumEditions, {'is_primary': 0});
    await db.update(DatabaseTables.albumEditions, {
      'is_primary': 1,
    }, where: "id = 'nova_dlx'");
    await db.update(DatabaseTables.songs, {
      'album_edition_id': 'nova_dlx',
    }, where: "id = 'opening'");
    await play('opening', DateTime.utc(2026, 10, 5, 10));

    final preview = await service.preview(
      const PermanentDeletionTarget.edition('nova_dlx'),
    );
    expect(preview.songIds, {'bonus'});
    expect(preview.songsKeptLosingListing, {'opening'});
    await service.delete(preview);

    final opening = (await db.query(
      DatabaseTables.songs,
      where: "id = 'opening'",
    )).single;
    expect(opening['album_edition_id'], 'nova_std');
    final playRow = (await db.query(DatabaseTables.qualifiedPlays)).single;
    expect(playRow['album_edition_id'], 'nova_std', reason: 'history kept');
    final standard = (await db.query(
      DatabaseTables.albumEditions,
      where: "id = 'nova_std'",
    )).single;
    expect(standard['is_primary'], 1);
    expect(await count(DatabaseTables.albumEditions, "id = 'nova_dlx'"), 0);
    expect(await count(DatabaseTables.songs, "id = 'bonus'"), 0);
  });

  test('a release: every edition and track', () async {
    await seedWorld();
    await play('bonus', DateTime.utc(2026, 10, 5, 10));
    final preview = await service.preview(
      const PermanentDeletionTarget.album('nova_album'),
    );
    await service.delete(preview);

    expect(await count(DatabaseTables.albums, "id = 'nova_album'"), 0);
    expect(
      await count(DatabaseTables.albumEditions, "album_id = 'nova_album'"),
      0,
    );
    expect(await count(DatabaseTables.songs, "album_id = 'nova_album'"), 0);
    expect(await count(DatabaseTables.qualifiedPlays), 0);
    expect(await count(DatabaseTables.artists, "id = 'nova'"), 1);
  });

  test('an artist: collaborations stay, credited by name', () async {
    await seedWorld();
    // A recording of Nova's on Lumen's release blocks until confirmed.
    await song(
      'guest',
      artistId: 'nova',
      albumId: 'lights',
      home: 'lights_std',
    );

    final blocked = await service.preview(
      const PermanentDeletionTarget.artist('nova'),
    );
    expect(
      blocked.blockers,
      contains(PermanentDeletionBlocker.sharedRecordingsNotConfirmed),
    );
    await expectLater(service.delete(blocked), throwsA(isA<DeletionBlocked>()));
    expect(await count(DatabaseTables.artists, "id = 'nova'"), 1);

    const confirm = PermanentDeletionOptions(includeSharedRecordings: true);
    final preview = await service.preview(
      const PermanentDeletionTarget.artist('nova'),
      options: confirm,
    );
    await service.delete(preview, options: confirm);

    expect(await count(DatabaseTables.artists, "id = 'nova'"), 0);
    expect(
      await count(DatabaseTables.songs, "id IN ('opening', 'bonus', 'guest')"),
      0,
    );
    // Lumen's song stays; Nova is still printed in its credits.
    final credit = (await db.query(
      DatabaseTables.songArtistCredits,
      where: "song_id = 'glow' AND role = 'featured'",
    )).single;
    expect(credit['credited_name'], 'nova');
    expect(credit['artist_id'], isNull);
    expect(
      await count(
        DatabaseTables.syncOutbox,
        "entity_id = 'glow' AND operation = 'upsert'",
      ),
      1,
    );
  });

  test(
    'a changed library makes the preview stale; nothing is deleted',
    () async {
      await seedWorld();
      final preview = await service.preview(
        const PermanentDeletionTarget.album('nova_album'),
      );
      await play('opening', DateTime.utc(2026, 10, 7, 10));

      await expectLater(
        service.delete(preview),
        throwsA(isA<StaleDeletionPreview>()),
      );
      expect(await count(DatabaseTables.albums, "id = 'nova_album'"), 1);
      expect(await count(DatabaseTables.qualifiedPlays), 1);
    },
  );

  test('a failure part-way changes nothing', () async {
    await seedWorld();
    await play('opening', DateTime.utc(2026, 10, 5, 10));
    Future<List<int>> snapshot() async => [
      for (final table in [
        DatabaseTables.songs,
        DatabaseTables.albums,
        DatabaseTables.mediaFileBindings,
        DatabaseTables.playbackSessions,
        DatabaseTables.qualifiedPlays,
        DatabaseTables.playlistItems,
        DatabaseTables.libraryDeletionLedger,
        DatabaseTables.syncOutbox,
      ])
        await count(table),
    ];
    final before = await snapshot();
    await db.execute('''
      CREATE TRIGGER fail_artist_delete BEFORE DELETE ON albums
      BEGIN SELECT RAISE(ABORT, 'injected failure'); END
    ''');

    final preview = await service.preview(
      const PermanentDeletionTarget.album('nova_album'),
    );
    await expectLater(service.delete(preview), throwsA(anything));

    expect(await snapshot(), before);
  });

  test('blocked while the library is linked to cloud sync', () async {
    await seedWorld();
    linked = true;
    final preview = await service.preview(
      const PermanentDeletionTarget.song('opening'),
    );
    expect(preview.blockers, {
      PermanentDeletionBlocker.cloudDeletionUnavailable,
    });
    await expectLater(service.delete(preview), throwsA(isA<DeletionBlocked>()));
    expect(await count(DatabaseTables.songs, "id = 'opening'"), 1);
  });

  test('charts are rebuilt without gaps, and no story is invented', () async {
    await seedWorld();
    // Two finished weeks: "opening" leads both.
    final w1 = DateTime.utc(2026, 10, 6, 12);
    final w2 = DateTime.utc(2026, 10, 13, 12);
    for (final (songId, at, times) in [
      ('opening', w1, 3),
      ('glow', w1, 2),
      ('echo', w1, 1),
      ('opening', w2, 3),
      ('glow', w2, 1),
      ('echo', w2, 2),
    ]) {
      for (var i = 0; i < times; i++) {
        await play(songId, at.add(Duration(minutes: i)));
      }
    }

    ChartFinalizationService finalization() {
      final plays = SqliteQualifiedPlayRepository(QualifiedPlayDao(db));
      final charts = SqliteChartRepository(appDatabase);
      return ChartFinalizationService(
        builder: ChartSnapshotBuilderService(
          qualifiedPlays: plays,
          library: SqliteLibraryQueryRepository(LibraryQueryDao(db)),
          charts: charts,
          playbackSessions: SqlitePlaybackSessionRepository(
            PlaybackSessionDao(db),
          ),
        ),
        charts: charts,
        qualifiedPlays: plays,
        moments: SqliteChartMomentRepository(appDatabase),
        momentsActivationWeekStartUtc: DateTime.utc(2026, 9, 20),
        now: () => now,
        weekFinalizer: charts,
        isRecalculatedWeek: SqliteDeletionJournalReader(
          () async => db,
        ).isRecalculatedWeek,
      );
    }

    final referenceLocal = DateTime(2026, 10, 30, 12);
    await finalization().finalizeCompletedWeeks(referenceLocal: referenceLocal);

    Future<List<(Object?, Object?)>> songChart(String weekStart) async => [
      for (final row in await db.rawQuery(
        'SELECT e.entity_id, e.rank FROM ${DatabaseTables.chartEntries} e '
        'JOIN ${DatabaseTables.chartSnapshots} s '
        'ON s.id = e.chart_snapshot_id '
        "WHERE s.chart_type = 'songs' AND s.week_start_utc LIKE ? "
        'ORDER BY e.rank',
        ['$weekStart%'],
      ))
        (row['entity_id'], row['rank']),
    ];
    final weeks = [
      for (final row in await db.query(
        DatabaseTables.chartSnapshots,
        columns: ['week_start_utc'],
        where: "chart_type = 'songs'",
        orderBy: 'week_start_utc',
      ))
        (row['week_start_utc']! as String).substring(0, 10),
    ];
    expect(weeks, hasLength(2));
    expect((await songChart(weeks[0])).first, ('opening', 1));
    final momentsBefore = await count(DatabaseTables.chartMomentEvents);
    expect(momentsBefore, greaterThan(0));
    final openingMoments = await count(
      DatabaseTables.chartMomentEvents,
      "entity_id = 'opening' OR related_entity_id = 'opening'",
    );

    final preview = await service.preview(
      const PermanentDeletionTarget.song('opening'),
    );
    expect(preview.chartEntryIds, hasLength(2));
    await service.delete(preview);
    expect(await count(DatabaseTables.chartSnapshots), 0);
    // The hardest case: every surviving weekly story of those weeks was
    // also about the deleted song, so nothing stops re-publication except
    // the recalculated-week rule.
    await db.delete(
      DatabaseTables.chartMomentEvents,
      where: "scope = 'finalized'",
    );
    final momentsAfterDeletion = await count(DatabaseTables.chartMomentEvents);

    await finalization().finalizeCompletedWeeks(referenceLocal: referenceLocal);

    // Re-ranked from the remaining plays: no gap, nobody invented.
    expect(await songChart(weeks[0]), [('glow', 1), ('echo', 2)]);
    expect(await songChart(weeks[1]), [('echo', 1), ('glow', 2)]);
    // The deleted song's stories are gone; the rebuilt weeks told nothing
    // new.
    expect(
      await count(
        DatabaseTables.chartMomentEvents,
        "entity_id = 'opening' OR related_entity_id = 'opening'",
      ),
      0,
    );
    expect(openingMoments, greaterThan(0));
    expect(
      await count(DatabaseTables.chartMomentEvents),
      momentsAfterDeletion,
      reason: 'a recalculated week publishes no new story',
    );
  });

  Future<void> moment(
    String id, {
    required String entity,
    required String artistId,
    String chartType = 'songs',
    String? related,
    String? relatedArtistId,
  }) => db.insert(DatabaseTables.chartMomentEvents, {
    'id': id,
    'deduplication_key': id,
    'chart_type': chartType,
    'scope': 'allTime',
    'event_type': 'debut',
    'entity_id': entity,
    'entity_title': entity,
    'entity_artist_id': artistId,
    'entity_artist_name': artistId,
    'related_entity_id': related,
    'related_entity_title': related,
    'related_entity_artist_id': relatedArtistId,
    'related_entity_artist_name': related == null ? null : relatedArtistId,
    'week_start_utc': '2026-10-04T04:00:00.000Z',
    'week_end_utc': '2026-10-11T04:00:00.000Z',
    'occurred_at': stamp,
    'created_at': stamp,
  });

  test('artwork only the deleted records use goes; shared art stays', () async {
    await seedWorld();
    for (final id in ['art_own', 'art_shared']) {
      await db.insert(DatabaseTables.artworkAssets, {
        'id': id,
        'file_path': '/art/$id.jpg',
        'normalized_path': '/art/$id.jpg',
        'created_at': stamp,
        'updated_at': stamp,
      });
    }
    await db.update(DatabaseTables.albumEditions, {
      'artwork_id': 'art_own',
    }, where: "album_id = 'nova_album'");
    await db.update(DatabaseTables.songs, {
      'artwork_id': 'art_shared',
    }, where: "id IN ('opening', 'echo')");

    final preview = await service.preview(
      const PermanentDeletionTarget.album('nova_album'),
    );
    expect(preview.artworkAssetIds, {'art_own'});
    expect(preview.targetArtworkId, 'art_own');
    await service.delete(preview);

    expect(await count(DatabaseTables.artworkAssets, "id = 'art_own'"), 0);
    expect(await count(DatabaseTables.artworkAssets, "id = 'art_shared'"), 1);
    final echo = (await db.query(
      DatabaseTables.songs,
      where: "id = 'echo'",
    )).single;
    expect(echo['artwork_id'], 'art_shared');
  });

  test('deleting the same thing twice changes nothing more', () async {
    await seedWorld();
    final preview = await service.preview(
      const PermanentDeletionTarget.song('opening'),
    );
    await service.delete(preview);
    final ledger = await count(DatabaseTables.libraryDeletionLedger);
    final journal = await count(DatabaseTables.libraryDeletionJournal);

    await expectLater(
      service.delete(preview),
      throwsA(isA<StaleDeletionPreview>()),
    );
    final again = await service.preview(
      const PermanentDeletionTarget.song('opening'),
    );
    expect(again.blockers, {PermanentDeletionBlocker.notFound});
    await expectLater(service.delete(again), throwsA(isA<DeletionBlocked>()));
    expect(await count(DatabaseTables.libraryDeletionLedger), ledger);
    expect(await count(DatabaseTables.libraryDeletionJournal), journal);
  });

  test(
    'an artist: their stories go, others naming them go, the rest stay',
    () async {
      await seedWorld();
      await moment('m_opening', entity: 'opening', artistId: 'nova');
      await moment(
        'm_album',
        entity: 'nova_album',
        artistId: 'nova',
        chartType: 'albums',
      );
      await moment(
        'm_glow_passes_nova',
        entity: 'glow',
        artistId: 'lumen',
        related: 'opening',
        relatedArtistId: 'nova',
      );
      await moment('m_echo', entity: 'echo', artistId: 'echo');

      final preview = await service.preview(
        const PermanentDeletionTarget.artist('nova'),
      );
      expect(preview.momentIdsAboutTarget, {'m_opening', 'm_album'});
      expect(preview.momentIdsMentioningTarget, {'m_glow_passes_nova'});
      await service.delete(preview);

      final left = await db.query(DatabaseTables.chartMomentEvents);
      expect(left.map((m) => m['id']), ['m_echo']);
      // Lumen's song and its own listening are untouched.
      expect(await count(DatabaseTables.songs, "id = 'glow'"), 1);
    },
  );

  test("a release: its stories and its songs' stories go", () async {
    await seedWorld();
    await moment('m_bonus', entity: 'bonus', artistId: 'nova');
    await moment(
      'm_album',
      entity: 'nova_album',
      artistId: 'nova',
      chartType: 'albums',
    );
    await moment('m_glow', entity: 'glow', artistId: 'lumen');

    final preview = await service.preview(
      const PermanentDeletionTarget.album('nova_album'),
    );
    await service.delete(preview);

    final left = await db.query(DatabaseTables.chartMomentEvents);
    expect(left.map((m) => m['id']), ['m_glow']);
    expect(await count(DatabaseTables.artists, "id = 'nova'"), 1);
  });
}

// App Update 1.2 staging harness: simulated devices running the app's real
// sync stack (SyncComposition) against the isolated local Supabase stack.
// Synthetic users and records only.
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/core/identity/entity_id.dart';
import 'package:sonus_next/features/analytics/data/daos/playback_session_dao.dart';
import 'package:sonus_next/features/analytics/data/daos/qualified_play_dao.dart';
import 'package:sonus_next/features/analytics/data/repositories/sqlite_playback_session_repository.dart';
import 'package:sonus_next/features/analytics/data/repositories/sqlite_qualified_play_repository.dart';
import 'package:sonus_next/features/charts/application/services/chart_finalization_service.dart';
import 'package:sonus_next/features/charts/application/services/chart_snapshot_builder_service.dart';
import 'package:sonus_next/features/charts/data/repositories/sqlite_chart_moment_repository.dart';
import 'package:sonus_next/features/charts/data/repositories/sqlite_chart_repository.dart';
import 'package:sonus_next/features/library/application/services/duplicate_album_reconciliation_service.dart';
import 'package:sonus_next/features/library/application/services/permanent_deletion_service.dart';
import 'package:sonus_next/features/library/data/daos/library_query_dao.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_deletion_journal_reader.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_library_query_repository.dart';
import 'package:sonus_next/features/sync/application/services/cloud_library_first_link_guard.dart';
import 'package:sonus_next/features/sync/application/services/sync_service.dart';
import 'package:sonus_next/features/sync/data/daos/local_sync_dao.dart';
import 'package:sonus_next/features/sync/data/repositories/sqlite_local_sync_repository.dart';
import 'package:sonus_next/features/sync/data/services/sync_status_store.dart';
import 'package:sonus_next/features/sync/domain/models/sync_data_contract.dart';
import 'package:sonus_next/features/sync/presentation/scopes/sync_composition.dart';

import 'staging_guard.dart';

/// Sends requests to the staging server, with faults on demand:
/// - [offline]: every request fails before it is sent;
/// - [refuse]: matching requests fail before they are sent;
/// - [loseResponse]: matching requests reach the server (and commit
///   there), then the response is lost.
class FaultyHttpClient extends http.BaseClient {
  final http.Client _inner = http.Client();

  bool offline = false;
  bool Function(http.BaseRequest request, String body)? refuse;
  bool Function(http.BaseRequest request, String body)? loseResponse;
  int refused = 0;
  int lost = 0;

  void clearFaults() {
    offline = false;
    refuse = null;
    loseResponse = null;
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = request is http.Request ? request.body : '';
    if (offline || (refuse?.call(request, body) ?? false)) {
      refused++;
      throw http.ClientException('staging fault: not sent', request.url);
    }
    final response = await _inner.send(request);
    if (loseResponse?.call(request, body) ?? false) {
      await response.stream.drain<void>();
      lost++;
      throw http.ClientException('staging fault: response lost', request.url);
    }
    return response;
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}

/// The service-role view of the staging server, for setup and for reading
/// what really reached the cloud.
class StagingAdmin {
  StagingAdmin(this.config)
    : client = SupabaseClient(
        config.url.toString(),
        config.serviceKey,
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );

  final StagingConfig config;
  final SupabaseClient client;

  /// The server must carry the staging marker, which no other database
  /// has: proof, from the server itself, that this is the staging stack.
  Future<void> assertStagingServer() async {
    final List<dynamic> rows;
    try {
      rows = await client
          .from('sonus_staging_marker')
          .select('name')
          .eq('name', stagingMarkerName);
    } on Object catch (error) {
      throw StagingRefused(['the staging marker is not readable: $error']);
    }
    if (rows.length != 1) {
      throw StagingRefused(['the server has no staging marker']);
    }
  }

  Future<String> createUser(String email, String password) async {
    final response = await client.auth.admin.createUser(
      AdminUserAttributes(email: email, password: password, emailConfirm: true),
    );
    return response.user!.id;
  }

  Future<Map<String, dynamic>?> libraryRow(String table, String id) async {
    final List<dynamic> rows = await client.from(table).select().eq('id', id);
    return rows.isEmpty ? null : rows.single as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> archive(
    String userId, {
    String? kind,
    String? key,
  }) async {
    var query = client
        .from('sonus_archive_records')
        .select()
        .eq('user_id', userId);
    if (kind != null) query = query.eq('kind', kind);
    if (key != null) query = query.eq('record_key', key);
    final List<dynamic> rows = await query;
    return rows.cast<Map<String, dynamic>>();
  }
}

class _GrantedConsent implements CloudLibraryConsentStore {
  @override
  Future<bool> hasConsent(String userId) async => true;

  @override
  Future<void> grant(String userId) async {}
}

final _stamp = DateTime.utc(2026, 10, 1, 12).toIso8601String();

/// One simulated device: its own database file, its own signed-in client
/// and the app's real sync stack.
class StagingDevice {
  StagingDevice._(this.name, this.dir, this.config, this.userId, this.http);

  final String name;
  final Directory dir;
  final StagingConfig config;
  final String userId;
  final FaultyHttpClient http;
  late AppDatabase database;
  late SupabaseClient client;
  late SyncComposition sync;
  final Map<String, String> _status = {};

  static Future<StagingDevice> open({
    required String name,
    required Directory root,
    required StagingConfig config,
    required String email,
    required String password,
    required String userId,
  }) async {
    final dir = await Directory(p.join(root.path, name)).create();
    final device = StagingDevice._(
      name,
      dir,
      config,
      userId,
      FaultyHttpClient(),
    );
    device.client = SupabaseClient(
      config.url.toString(),
      config.anonKey,
      httpClient: device.http,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    final session = await device.client.auth.signInWithPassword(
      email: email,
      password: password,
    );
    if (session.user?.id != userId) {
      throw StateError('$name signed in as the wrong user');
    }
    await device._compose();
    return device;
  }

  Future<void> _compose() async {
    database = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: p.join(dir.path, 'sonus.db'),
    );
    sync = await SyncComposition.build(
      database: database,
      client: client,
      consentStore: _GrantedConsent(),
      syncStatusStore: SyncStatusStore.forTesting(
        getString: (key) async => _status[key],
        setString: (key, value) async => _status[key] = value,
      ),
    );
  }

  /// The app is closed and opened again: a new database connection and a
  /// new sync stack over the same file. Nothing in memory survives.
  Future<void> restart() async {
    await database.close();
    await _compose();
  }

  Future<void> close() async {
    await database.close();
    await client.dispose();
    http.close();
  }

  Future<Database> get db => database.database;

  Future<SyncRunResult> syncNow() => sync.service.synchronize(userId);

  /// As the app composes it for the Library: the default account-link
  /// check and the server capability probe.
  PermanentDeletionService deletion() => PermanentDeletionService(
    appDatabase: database,
    userId: userId,
    cloudDeletionReady: sync.deletionReadiness.isReady,
  );

  DuplicateAlbumReconciliationService reconciliation() =>
      DuplicateAlbumReconciliationService(
        appDatabase: database,
        userId: userId,
      );

  Future<int> count(
    String table, [
    String where = '1',
    List<Object?>? args,
  ]) async =>
      (await (await db).rawQuery(
            'SELECT COUNT(*) AS n FROM $table WHERE $where',
            args,
          )).single['n']!
          as int;

  Future<int> pendingOutbox() async => (await SqliteLocalSyncRepository(
    dao: LocalSyncDao(await db),
    generateId: EntityId.syncOutbox,
    now: DateTime.now,
  ).getPending(userId)).length;

  Future<void> _queue(CloudDataEntity entity, String id) async =>
      SqliteLocalSyncRepository(
        dao: LocalSyncDao(await db),
        generateId: EntityId.syncOutbox,
        now: DateTime.now,
      ).recordUpsert(userId: userId, entityType: entity, entityId: id);

  // Library fixtures, written as the app writes them, then queued for the
  // cloud.

  Future<void> artist(String id) async {
    await (await db).insert(DatabaseTables.artists, {
      'id': id,
      'name': id,
      'canonical_name': id,
      'created_at': _stamp,
      'updated_at': _stamp,
    });
    await _queue(CloudDataEntity.artist, id);
  }

  Future<void> album(
    String id,
    String owner,
    List<String> editions, {
    String? title,
  }) async {
    final d = await db;
    await d.insert(DatabaseTables.albums, {
      'id': id,
      'artist_id': owner,
      'title': title ?? id,
      'canonical_title': (title ?? id).toLowerCase(),
      'created_at': _stamp,
      'updated_at': _stamp,
    });
    await _queue(CloudDataEntity.album, id);
    for (final (index, edition) in editions.indexed) {
      await addEdition(edition, id, primary: index == 0);
    }
  }

  Future<void> addEdition(
    String id,
    String albumId, {
    bool primary = false,
  }) async {
    await (await db).insert(DatabaseTables.albumEditions, {
      'id': id,
      'album_id': albumId,
      'title': primary ? 'Standard' : 'Deluxe',
      'type': primary ? 'standard' : 'deluxe',
      'is_primary': primary ? 1 : 0,
      'created_at': _stamp,
      'updated_at': _stamp,
    });
    await _queue(CloudDataEntity.albumEdition, id);
  }

  Future<void> song(
    String id, {
    required String artistId,
    required String albumId,
    required String home,
    List<String>? listedOn,
    List<String> featuring = const [],
    String? title,
    int track = 1,
  }) async {
    final d = await db;
    await d.insert(DatabaseTables.songs, {
      'id': id,
      'artist_id': artistId,
      'album_id': albumId,
      'album_edition_id': home,
      'title': title ?? id,
      'canonical_title': (title ?? id).toLowerCase(),
      'track_number': track,
      'duration_seconds': 200,
      'created_at': _stamp,
      'updated_at': _stamp,
    });
    for (final (index, edition) in (listedOn ?? [home]).indexed) {
      await d.insert(DatabaseTables.albumEditionTracks, {
        'album_edition_id': edition,
        'song_id': id,
        'sort_position': index,
        'created_at': _stamp,
        'updated_at': _stamp,
      });
    }
    for (final (index, credited) in [artistId, ...featuring].indexed) {
      await d.insert(DatabaseTables.songArtistCredits, {
        'id': 'credit_${id}_$index',
        'song_id': id,
        'artist_id': credited,
        'credited_name': credited,
        'canonical_credited_name': credited,
        'role': index == 0 ? 'primary' : 'featured',
        'position': index,
        'created_at': _stamp,
        'updated_at': _stamp,
      });
    }
    await d.insert(DatabaseTables.mediaFileBindings, {
      'id': 'binding_$id',
      'song_id': id,
      'file_path': '/staging/$name/$id.mp3',
      'normalized_path': '/staging/$name/$id.mp3',
      'created_at': _stamp,
      'updated_at': _stamp,
    });
    await _queue(CloudDataEntity.song, id);
  }

  /// A local edit of a song's title, queued for the cloud as the app does.
  Future<void> renameSong(String id, String title) async {
    await (await db).update(
      DatabaseTables.songs,
      {
        'title': title,
        'canonical_title': title.toLowerCase(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    await _queue(CloudDataEntity.song, id);
  }

  var _plays = 0;

  /// A finished, qualified play. Returns the session id.
  Future<String> play(String songId, DateTime at) async {
    final d = await db;
    final s = (await d.query(
      DatabaseTables.songs,
      where: 'id = ?',
      whereArgs: [songId],
    )).single;
    final id =
        '${name}_${songId}_${DateTime.now().microsecondsSinceEpoch}_${++_plays}';
    final iso = at.toUtc().toIso8601String();
    await d.insert(DatabaseTables.playbackSessions, {
      'id': 'session_$id',
      'song_id': songId,
      'artist_id': s['artist_id'],
      'album_id': s['album_id'],
      'album_edition_id': s['album_edition_id'],
      'song_title': s['title'],
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
    await d.insert(DatabaseTables.playbackListeningSegments, {
      'id': 'segment_$id',
      'playback_session_id': 'session_$id',
      'started_at': iso,
      'ended_at': iso,
      'listened_duration_ms': 180000,
      'created_at': iso,
      'updated_at': iso,
    });
    await d.insert(DatabaseTables.qualifiedPlays, {
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
    return 'session_$id';
  }

  /// An all-time Moment (archived to the cloud).
  Future<void> moment(
    String id, {
    required String entity,
    required String artistId,
    String chartType = 'songs',
    String? related,
    String? relatedArtistId,
  }) async => (await db).insert(DatabaseTables.chartMomentEvents, {
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
    'occurred_at': _stamp,
    'created_at': _stamp,
  });

  /// Weekly chart finalization, as the Charts feature runs it.
  Future<void> finalizeCharts(DateTime referenceLocal) async {
    final d = await db;
    final plays = SqliteQualifiedPlayRepository(QualifiedPlayDao(d));
    final charts = SqliteChartRepository(database);
    await ChartFinalizationService(
      builder: ChartSnapshotBuilderService(
        qualifiedPlays: plays,
        library: SqliteLibraryQueryRepository(LibraryQueryDao(d)),
        charts: charts,
        playbackSessions: SqlitePlaybackSessionRepository(
          PlaybackSessionDao(d),
        ),
      ),
      charts: charts,
      qualifiedPlays: plays,
      moments: SqliteChartMomentRepository(database),
      momentsActivationWeekStartUtc: DateTime.utc(2026, 9, 20),
      now: DateTime.now,
      weekFinalizer: charts,
      isRecalculatedWeek: SqliteDeletionJournalReader(
        () async => d,
      ).isRecalculatedWeek,
    ).finalizeCompletedWeeks(referenceLocal: referenceLocal);
  }

  /// Song chart of the week starting on [weekStart] (yyyy-mm-dd), ranked.
  Future<List<(String, int)>> songChart(String weekStart) async => [
    for (final row in await (await db).rawQuery(
      'SELECT e.entity_id, e.rank FROM ${DatabaseTables.chartEntries} e '
      'JOIN ${DatabaseTables.chartSnapshots} s ON s.id = e.chart_snapshot_id '
      "WHERE s.chart_type = 'songs' AND s.week_start_utc LIKE ? "
      'ORDER BY e.rank',
      ['$weekStart%'],
    ))
      (row['entity_id']! as String, row['rank']! as int),
  ];

  Future<List<String>> songChartWeeks() async => [
    for (final row in await (await db).rawQuery(
      'SELECT DISTINCT s.week_start_utc FROM ${DatabaseTables.chartSnapshots} s '
      'JOIN ${DatabaseTables.chartEntries} e ON e.chart_snapshot_id = s.id '
      "WHERE s.chart_type = 'songs' ORDER BY s.week_start_utc",
    ))
      (row['week_start_utc']! as String).substring(0, 10),
  ];
}

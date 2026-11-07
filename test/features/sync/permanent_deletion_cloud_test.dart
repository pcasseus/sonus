// App Update 1.2: a permanent deletion (or duplicate merge) made on one
// device holds on every device, including one that connects later, and no
// stale device or old cloud copy brings it back. Disposable databases and
// an in-memory cloud only.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/core/events/library_change_signal.dart';
import 'package:sonus_next/features/library/application/services/duplicate_album_reconciliation_service.dart';
import 'package:sonus_next/features/library/application/services/permanent_deletion_service.dart';
import 'package:sonus_next/features/library/domain/deletion/permanent_deletion_impact.dart';
import 'package:sonus_next/features/sync/application/services/cloud_archive_sync_service.dart';
import 'package:sonus_next/features/sync/application/services/inbound_cloud_record_applier.dart';
import 'package:sonus_next/features/sync/data/repositories/sync_mutation_transaction_runner.dart';
import 'package:sonus_next/features/sync/data/services/sqlite_cloud_archive_store.dart';
import 'package:sonus_next/features/sync/domain/models/cloud_archive_record.dart';
import 'package:sonus_next/features/sync/domain/models/cloud_records.dart';

import '../../support/in_memory_cloud_archive.dart';

const _user = 'user_1';
final _stamp = DateTime.utc(2026, 11, 1, 12).toIso8601String();

class _Device {
  _Device(this.name, this.dir, this.cloud);

  final String name;
  final Directory dir;
  final InMemoryCloudArchive cloud;
  late final AppDatabase database = AppDatabase(
    databaseFactory: databaseFactoryFfi,
    databasePath: p.join(dir.path, '$name.db'),
  );

  Future<Database> get db => database.database;

  CloudArchiveSyncService get archive => CloudArchiveSyncService(
    gateway: cloud,
    store: SqliteCloudArchiveStore(
      appDatabase: database,
      changes: LibraryChangeSignal(),
    ),
    queueArtworkUpload: ({required userId, required artworkId}) async {},
  );

  Future<void> sync() => archive.synchronize(_user);

  PermanentDeletionService deletion() => PermanentDeletionService(
    appDatabase: database,
    userId: _user,
    isCloudLinked: (_) async => true,
    cloudDeletionReady: cloud.supportsPermanentDeletion,
    changes: LibraryChangeSignal(),
  );

  Future<int> count(String table, [String where = '1']) async =>
      (await (await db).rawQuery(
            'SELECT COUNT(*) AS n FROM $table WHERE $where',
          )).single['n']!
          as int;

  /// The same library on every device (as library sync would make it):
  /// "nova" with two songs, "lumen" with one.
  Future<void> seedLibrary() async {
    final d = await db;
    for (final artist in ['nova', 'lumen']) {
      await d.insert(DatabaseTables.artists, {
        'id': artist,
        'name': artist,
        'canonical_name': artist,
        'created_at': _stamp,
        'updated_at': _stamp,
      });
    }
    for (final (album, artist) in [
      ('nova_album', 'nova'),
      ('lights', 'lumen'),
    ]) {
      await d.insert(DatabaseTables.albums, {
        'id': album,
        'artist_id': artist,
        'title': album,
        'canonical_title': album,
        'created_at': _stamp,
        'updated_at': _stamp,
      });
      await d.insert(DatabaseTables.albumEditions, {
        'id': '${album}_std',
        'album_id': album,
        'title': album,
        'type': 'standard',
        'is_primary': 1,
        'created_at': _stamp,
        'updated_at': _stamp,
      });
    }
    for (final (index, (song, artist, album)) in [
      ('opening', 'nova', 'nova_album'),
      ('second', 'nova', 'nova_album'),
      ('glow', 'lumen', 'lights'),
    ].indexed) {
      await d.insert(DatabaseTables.songs, {
        'id': song,
        'artist_id': artist,
        'album_id': album,
        'album_edition_id': '${album}_std',
        'title': song,
        'canonical_title': song,
        'track_number': index + 1,
        'duration_seconds': 200,
        'created_at': _stamp,
        'updated_at': _stamp,
      });
    }
  }

  Future<void> play(String song, String id) async {
    final d = await db;
    final row = (await d.query(
      DatabaseTables.songs,
      where: 'id = ?',
      whereArgs: [song],
    )).single;
    await d.insert(DatabaseTables.playbackSessions, {
      'id': 'session_$id',
      'song_id': song,
      'artist_id': row['artist_id'],
      'album_id': row['album_id'],
      'album_edition_id': row['album_edition_id'],
      'song_title': song,
      'artist_name': '${row['artist_id']}',
      'album_title': '${row['album_id']}',
      'album_edition_title': '${row['album_edition_id']}',
      'started_at': _stamp,
      'ended_at': _stamp,
      'listened_duration_ms': 200000,
      'track_duration_ms': 200000,
      'created_at': _stamp,
      'updated_at': _stamp,
    });
    await d.insert(DatabaseTables.qualifiedPlays, {
      'id': 'play_$id',
      'playback_session_id': 'session_$id',
      'song_id': song,
      'artist_id': row['artist_id'],
      'album_id': row['album_id'],
      'album_edition_id': row['album_edition_id'],
      'qualified_at': _stamp,
      'listened_duration_ms': 200000,
      'track_duration_ms': 200000,
      'created_at': _stamp,
    });
  }

  Future<void> story(String key, String entity, String artist) async =>
      (await db).insert(DatabaseTables.chartMomentEvents, {
        'id': key,
        'deduplication_key': key,
        'chart_type': 'songs',
        'scope': 'allTime',
        'event_type': 'debut',
        'entity_id': entity,
        'entity_title': entity,
        'entity_artist_id': artist,
        'entity_artist_name': artist,
        'week_start_utc': '2026-10-25T04:00:00.000Z',
        'week_end_utc': '2026-11-01T04:00:00.000Z',
        'occurred_at': _stamp,
        'created_at': _stamp,
      });

  Future<void> close() => database.close();
}

void main() {
  sqfliteFfiInit();

  late Directory dir;
  late InMemoryCloudArchive cloud;
  late _Device a;
  late _Device b;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('sonus_deletion_cloud_');
    cloud = InMemoryCloudArchive()..supportsDeletion = true;
    a = _Device('a', dir, cloud);
    b = _Device('b', dir, cloud);
    for (final device in [a, b]) {
      await device.seedLibrary();
    }
    // Listening and stories made on A, shared with B.
    await a.play('opening', 'a1');
    await a.play('glow', 'a2');
    await a.story('debut_opening', 'opening', 'nova');
    await a.story('debut_glow', 'glow', 'lumen');
    await a.sync();
    await b.sync();
  });

  tearDown(() async {
    await a.close();
    await b.close();
    await dir.delete(recursive: true);
  });

  Map<String, CloudArchiveRecord> rows() => cloud.rowsFor(_user);

  test('a deletion on one device holds on the other', () async {
    expect(await b.count(DatabaseTables.playbackSessions), 2);

    final service = a.deletion();
    await service.delete(
      await service.preview(const PermanentDeletionTarget.song('opening')),
    );
    await a.sync();

    // The cloud keeps no content of the deleted listening and story.
    final session = rows()['listening_session:session_a1']!;
    expect(session.isDeleted, isTrue);
    expect(session.payload, isEmpty);
    final story = rows()['all_time_moment:debut_opening']!;
    expect(story.isDeleted, isTrue);
    expect(story.payload, isEmpty);
    final deletion = rows().values.singleWhere(
      (r) => r.kind == CloudArchiveKind.libraryDeletion,
    );
    expect(deletion.payload['operation'], 'userDeletion');
    expect(
      (deletion.payload['entries']! as List).map((e) => (e as List).join(':')),
      containsAll(['song:opening', 'playbackSession:session_a1']),
    );

    await b.sync();

    expect(await b.count(DatabaseTables.songs, "id = 'opening'"), 0);
    expect(await b.count(DatabaseTables.playbackSessions), 1);
    expect(await b.count(DatabaseTables.qualifiedPlays), 1);
    expect(
      await b.count(DatabaseTables.chartMomentEvents),
      1,
      reason: 'only the unrelated story stays',
    );
    expect(
      await b.count(
        DatabaseTables.libraryDeletionLedger,
        "entity_type = 'song' AND entity_id = 'opening'",
      ),
      1,
    );

    // Syncing again changes nothing anywhere.
    final writes = cloud.writes;
    await a.sync();
    await b.sync();
    expect(cloud.writes, writes);
  });

  test('a device that connects later respects the deletion', () async {
    final service = a.deletion();
    await service.delete(
      await service.preview(const PermanentDeletionTarget.song('opening')),
    );
    await a.sync();

    final c = _Device('c', dir, cloud);
    addTearDown(c.close);
    await c.seedLibrary();
    await c.sync();

    expect(await c.count(DatabaseTables.songs, "id = 'opening'"), 0);
    expect(
      await c.count(DatabaseTables.playbackSessions, "song_id = 'opening'"),
      0,
    );
    expect(await c.count(DatabaseTables.playbackSessions), 1);

    // An old live copy of the song in the cloud's library tables is not
    // applied either.
    final result =
        await SyncMutationTransactionRunner(
          appDatabase: c.database,
          changes: LibraryChangeSignal(),
        ).run(
          (context) => const InboundCloudRecordApplier().apply(
            record: CloudSongRecord(
              id: 'opening',
              userId: _user,
              artistId: 'nova',
              albumId: 'nova_album',
              albumEditionId: 'nova_album_std',
              title: 'opening',
              canonicalTitle: 'opening',
              trackNumber: 1,
              durationSeconds: 200,
              isSingle: false,
              featuredArtists: const [],
              createdAt: DateTime.utc(2026, 11, 1),
              updatedAt: DateTime.utc(2026, 11, 1),
            ),
            context: context,
          ),
        );
    expect(result.isDeferred, isFalse);
    expect(await c.count(DatabaseTables.songs, "id = 'opening'"), 0);
  });

  test(
    'a stale device that played the song offline cannot bring it back',
    () async {
      // B goes offline and plays the song A is about to delete.
      await b.play('opening', 'b_offline');

      final service = a.deletion();
      await service.delete(
        await service.preview(const PermanentDeletionTarget.song('opening')),
      );
      await a.sync();

      // B reconnects: it uploads its new listening first, then learns of the
      // deletion, removes the song and that listening, and tells the cloud.
      await b.sync();
      expect(await b.count(DatabaseTables.songs, "id = 'opening'"), 0);
      expect(
        await b.count(DatabaseTables.playbackSessions, "song_id = 'opening'"),
        0,
      );
      await b.sync();
      final offline = rows()['listening_session:session_b_offline']!;
      expect(offline.isDeleted, isTrue);
      expect(offline.payload, isEmpty);

      // A never takes B's listening of the deleted song.
      await a.sync();
      expect(
        await a.count(DatabaseTables.playbackSessions, "song_id = 'opening'"),
        0,
      );
    },
  );

  test(
    'without the server capability, a linked device cannot delete',
    () async {
      cloud.supportsDeletion = false;

      final service = a.deletion();
      final preview = await service.preview(
        const PermanentDeletionTarget.song('opening'),
      );

      expect(preview.blockers, {
        PermanentDeletionBlocker.cloudDeletionUnavailable,
      });
      await expectLater(
        service.delete(preview),
        throwsA(isA<DeletionBlocked>()),
      );
      expect(await a.count(DatabaseTables.songs, "id = 'opening'"), 1);
    },
  );

  test('a lost response is recovered, and the record applies once', () async {
    final service = a.deletion();
    await service.delete(
      await service.preview(const PermanentDeletionTarget.song('opening')),
    );
    cloud.loseNextResponse = true;
    await expectLater(a.sync(), throwsA(isA<SocketException>()));
    await a.sync();
    await b.sync();
    await b.sync();

    expect(
      rows().values.where((r) => r.kind == CloudArchiveKind.libraryDeletion),
      hasLength(1),
    );
    expect(await b.count(DatabaseTables.libraryDeletionJournal), 1);
    expect(await b.count(DatabaseTables.songs, "id = 'opening'"), 0);
  });

  test('a duplicate merge reaches the other device', () async {
    // The same duplicate release on both devices (as library sync would
    // have brought it), and B listened to the duplicate.
    for (final device in [a, b]) {
      final d = await device.db;
      await d.insert(DatabaseTables.albums, {
        'id': 'nova_dup',
        'artist_id': 'nova',
        'title': 'nova_album',
        'canonical_title': 'nova_album',
        'created_at': '2026-11-02T00:00:00Z',
        'updated_at': '2026-11-02T00:00:00Z',
      });
      await d.insert(DatabaseTables.albumEditions, {
        'id': 'nova_dup_std',
        'album_id': 'nova_dup',
        'title': 'nova_album',
        'type': 'standard',
        'is_primary': 1,
        'created_at': _stamp,
        'updated_at': _stamp,
      });
      for (final (index, song) in ['opening', 'second'].indexed) {
        await d.insert(DatabaseTables.songs, {
          'id': '${song}_dup',
          'artist_id': 'nova',
          'album_id': 'nova_dup',
          'album_edition_id': 'nova_dup_std',
          'title': song,
          'canonical_title': song,
          'track_number': index + 1,
          'duration_seconds': 200,
          'created_at': _stamp,
          'updated_at': _stamp,
        });
      }
    }
    await b.play('second_dup', 'b_dup');

    final report = await DuplicateAlbumReconciliationService(
      appDatabase: a.database,
      changes: LibraryChangeSignal(),
    ).reconcile();
    expect(report.merged.single.duplicateAlbumId, 'nova_dup');
    await a.sync();
    await b.sync();

    expect(await b.count(DatabaseTables.albums, "id = 'nova_dup'"), 0);
    expect(await b.count(DatabaseTables.songs, "album_id = 'nova_dup'"), 0);
    final moved = (await (await b.db).query(
      DatabaseTables.qualifiedPlays,
      where: "id = 'play_b_dup'",
    )).single;
    expect(moved['song_id'], 'second', reason: 'the listening follows');
    expect(moved['album_id'], 'nova_album');
  });

  test('a deletion waits for what it depends on, then applies', () async {
    // A Deluxe edition of Nova's album on both devices; "opening" is homed
    // there and also listed on Standard; "bonus" is Deluxe only.
    for (final device in [a, b]) {
      final d = await device.db;
      await d.insert(DatabaseTables.albumEditions, {
        'id': 'nova_dlx',
        'album_id': 'nova_album',
        'title': 'nova_album (Deluxe)',
        'type': 'deluxe',
        'is_primary': 0,
        'created_at': _stamp,
        'updated_at': _stamp,
      });
      await d.update(DatabaseTables.songs, {
        'album_edition_id': 'nova_dlx',
      }, where: "id = 'opening'");
      for (final (edition, song) in [
        ('nova_album_std', 'opening'),
        ('nova_dlx', 'opening'),
      ]) {
        await d.insert(DatabaseTables.albumEditionTracks, {
          'album_edition_id': edition,
          'song_id': song,
          'sort_position': 0,
          'created_at': _stamp,
          'updated_at': _stamp,
        });
      }
      await d.insert(DatabaseTables.songs, {
        'id': 'bonus',
        'artist_id': 'nova',
        'album_id': 'nova_album',
        'album_edition_id': 'nova_dlx',
        'title': 'bonus',
        'canonical_title': 'bonus',
        'track_number': 9,
        'duration_seconds': 200,
        'created_at': _stamp,
        'updated_at': _stamp,
      });
    }

    final service = a.deletion();
    await service.delete(
      await service.preview(const PermanentDeletionTarget.edition('nova_dlx')),
    );
    await a.sync();

    // B has not yet received the song's new home (library sync): the
    // deletion waits, and B changes nothing.
    await b.sync();
    expect(await b.count(DatabaseTables.albumEditions, "id = 'nova_dlx'"), 1);
    expect(await b.count(DatabaseTables.songs, "id = 'bonus'"), 1);

    // The new home arrives; the next sync applies the waiting deletion.
    await (await b.db).update(DatabaseTables.songs, {
      'album_edition_id': 'nova_album_std',
    }, where: "id = 'opening'");
    await b.sync();
    expect(await b.count(DatabaseTables.albumEditions, "id = 'nova_dlx'"), 0);
    expect(await b.count(DatabaseTables.songs, "id = 'bonus'"), 0);
    expect(await b.count(DatabaseTables.songs, "id = 'opening'"), 1);
  });
}

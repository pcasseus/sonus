// App Update 1.2: a permanent deletion (or duplicate merge) made on one
// device holds on every device, including one that connects later, and no
// stale device or old cloud copy brings it back. Disposable databases and
// an in-memory cloud only.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/core/events/library_change_signal.dart';
import 'package:sonus_next/features/library/application/services/duplicate_album_reconciliation_service.dart';
import 'package:sonus_next/features/library/application/services/permanent_deletion_service.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_deletion_journal_reader.dart';
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

  // Found by the isolated staging run (2026-11-08).

  test(
    'a device that never had the deleted records still remembers them',
    () async {
      final service = a.deletion();
      await service.delete(
        await service.preview(const PermanentDeletionTarget.song('opening')),
      );
      await a.sync();

      // A new device with no library yet: the song, its listening and its
      // story never reach it, and it still remembers all of them, so no
      // stale copy, download or restored backup can bring them back later.
      final c = _Device('c', dir, cloud);
      addTearDown(c.close);
      await c.sync();
      Future<int> ledgered(String type, String id) => c.count(
        DatabaseTables.libraryDeletionLedger,
        "entity_type = '$type' AND entity_id = '$id' "
        "AND reason = 'userDeletion'",
      );
      expect(await c.count(DatabaseTables.songs), 0);
      expect(await ledgered('song', 'opening'), 1);
      expect(await ledgered('playbackSession', 'session_a1'), 1);
      expect(await ledgered('moment', 'debut_opening'), 1);
      expect(await c.count(DatabaseTables.libraryDeletionJournal), 1);
    },
  );

  Future<void> addDuplicate(_Device device) async {
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

  test('listening of a merged duplicate follows the kept release, whichever '
      'arrives first', () async {
    for (final device in [a, b]) {
      await addDuplicate(device);
    }
    // B plays the duplicate and uploads it before anyone merges.
    await b.play('second_dup', 'b_dup');
    await b.sync();
    final report = await DuplicateAlbumReconciliationService(
      appDatabase: a.database,
      changes: LibraryChangeSignal(),
    ).reconcile();
    expect(report.merged.single.duplicateAlbumId, 'nova_dup');
    await a.sync();

    Future<Map<String, Object?>> play(_Device device) async =>
        (await (await device.db).query(
          DatabaseTables.qualifiedPlays,
          where: "id = 'play_b_dup'",
        )).single;
    Future<Map<String, Object?>> session(_Device device) async =>
        (await (await device.db).query(
          DatabaseTables.playbackSessions,
          where: "id = 'session_b_dup'",
        )).single;

    // A received B's play after merging: it follows the merge.
    for (final row in [await play(a), await session(a)]) {
      expect(row['song_id'], 'second');
      expect(row['album_id'], 'nova_album');
      expect(row['album_edition_id'], 'nova_album_std');
    }

    // A device that never had the duplicate gets B's play first (it is
    // older), then the merge: the play is moved when the merge arrives.
    final c = _Device('c', dir, cloud);
    addTearDown(c.close);
    await c.seedLibrary();
    await c.sync();
    for (final row in [await play(c), await session(c)]) {
      expect(row['song_id'], 'second');
      expect(row['album_id'], 'nova_album');
    }
    expect(
      await c.count(
        DatabaseTables.playbackSessions,
        'song_id NOT IN (SELECT id FROM ${DatabaseTables.songs})',
      ),
      0,
    );
  });

  CloudArchiveRecord oldClientPlay(String key) => CloudArchiveRecord(
    kind: CloudArchiveKind.listeningSession,
    key: key,
    payload: {
      'session': {
        'id': key,
        'song_id': 'opening',
        'artist_id': 'nova',
        'album_id': 'nova_album',
        'album_edition_id': 'nova_album_std',
        'song_title': 'opening',
        'artist_name': 'nova',
        'album_title': 'nova_album',
        'album_edition_title': 'nova_album_std',
        'started_at': _stamp,
        'ended_at': _stamp,
        'listened_duration_ms': 200000,
        'track_duration_ms': 200000,
        'created_at': _stamp,
        'updated_at': _stamp,
      },
      'segments': const <Object>[],
      'qualified_play': null,
    },
    clientUpdatedAt: DateTime.utc(2026, 11, 5),
  );

  test('a play of a deleted song recorded later by an older version is '
      'removed from the cloud', () async {
    final service = a.deletion();
    await service.delete(
      await service.preview(const PermanentDeletionTarget.song('opening')),
    );
    await a.sync();
    await b.sync();

    // An App Update 1.1 device that never learned of the deletion keeps
    // playing its copy and uploads the play.
    await cloud.insertIfAbsent(userId: _user, record: oldClientPlay('late'));

    await b.sync();
    final row = rows()['listening_session:late']!;
    expect(row.isDeleted, isTrue);
    expect(row.payload, isEmpty);
    expect(await b.count(DatabaseTables.playbackSessions, "id = 'late'"), 0);

    // Done once: later syncs leave it alone.
    final writes = cloud.writes;
    await b.sync();
    await a.sync();
    expect(cloud.writes, writes);
    expect(await a.count(DatabaseTables.playbackSessions, "id = 'late'"), 0);
  });

  test(
    'without the server capability such a play is only left unapplied',
    () async {
      final service = a.deletion();
      await service.delete(
        await service.preview(const PermanentDeletionTarget.song('opening')),
      );
      await a.sync();
      await cloud.insertIfAbsent(userId: _user, record: oldClientPlay('late'));
      cloud.supportsDeletion = false;

      await a.sync();
      final row = rows()['listening_session:late']!;
      expect(row.isDeleted, isFalse);
      expect(await a.count(DatabaseTables.playbackSessions, "id = 'late'"), 0);
    },
  );

  // App Update 1.2 patches, Checkpoint 1.

  CloudArchiveRecord olderPlayOfDuplicate(String key) {
    final record = oldClientPlay(key);
    final session = {
      ...(record.payload['session']! as Map<String, Object?>),
      'song_id': 'second_dup',
      'album_id': 'nova_dup',
      'album_edition_id': 'nova_dup_std',
      'song_title': 'second',
    };
    return CloudArchiveRecord(
      kind: record.kind,
      key: key,
      payload: {...record.payload, 'session': session},
      clientUpdatedAt: record.clientUpdatedAt,
    );
  }

  test('BUG-00A: a play of a merged duplicate stays deleted once the song '
      'it became is deleted, on every device', () async {
    for (final device in [a, b]) {
      await addDuplicate(device);
    }
    final report = await DuplicateAlbumReconciliationService(
      appDatabase: a.database,
      changes: LibraryChangeSignal(),
    ).reconcile();
    expect(report.merged.single.duplicateAlbumId, 'nova_dup');
    final service = a.deletion();
    await service.delete(
      await service.preview(const PermanentDeletionTarget.song('second')),
    );
    await a.sync();

    // A device still on App Update 1.1, which never learned of the merge
    // or the deletion, uploads a play of its copy of the duplicate.
    await cloud.insertIfAbsent(
      userId: _user,
      record: olderPlayOfDuplicate('late_dup'),
    );

    await a.sync();
    expect(
      await a.count(DatabaseTables.playbackSessions, "id = 'late_dup'"),
      0,
    );
    expect(
      await a.count(DatabaseTables.qualifiedPlays),
      2,
      reason: 'only the setUp plays of opening and glow',
    );
    final row = rows()['listening_session:late_dup']!;
    expect(row.isDeleted, isTrue, reason: 'removed from the cloud');
    expect(row.payload, isEmpty);

    // A device that connects later, and never had the duplicate, keeps
    // none of it either, whatever order the records arrive in.
    final c = _Device('c', dir, cloud);
    addTearDown(c.close);
    await c.seedLibrary();
    await c.sync();
    expect(
      await c.count(DatabaseTables.playbackSessions, "id = 'late_dup'"),
      0,
    );
    expect(
      await c.count(
        DatabaseTables.playbackSessions,
        "song_id IN ('second', 'second_dup')",
      ),
      0,
    );

    // Done once: later syncs leave everything alone.
    final writes = cloud.writes;
    await a.sync();
    await c.sync();
    expect(cloud.writes, writes);
  });

  test('BUG-00B: a merge from another device carries this device\'s chart '
      'weeks and Moments to the record that stayed', () async {
    for (final device in [a, b]) {
      await addDuplicate(device);
    }
    // B listened to the duplicate, its stored weekly charts rank it, and it
    // published a story about it. A has none of that, so A's merge is
    // verified and automatic.
    await b.play('second_dup', 'b_dup');
    const earlier = '2026-10-18T04:00:00.000Z';
    const week = '2026-10-25T04:00:00.000Z';
    final bDb = await b.db;
    Future<void> chartWeek(
      String type,
      String start,
      String end,
      String entity,
    ) async {
      final snapshot = 'snapshot_${type}_$start';
      await bDb.insert(DatabaseTables.chartSnapshots, {
        'id': snapshot,
        'chart_type': type,
        'week_start_utc': start,
        'week_end_utc': end,
        'finalized_at': end,
        'created_at': end,
        'updated_at': end,
      });
      await bDb.insert(DatabaseTables.chartEntries, {
        'id': 'entry_${type}_$start',
        'chart_snapshot_id': snapshot,
        'entity_id': entity,
        'title': entity,
        'artist_id': 'nova',
        'artist_name': 'nova',
        'rank': 1,
        'qualified_stream_count': 1,
        'peak_rank': 1,
        'peak_achieved_at': end,
        'weeks_on_chart': 1,
        'movement': 'newEntry',
        'last_qualified_at': end,
        'created_at': end,
        'updated_at': end,
      });
    }

    await chartWeek('songs', earlier, week, 'glow');
    await chartWeek('songs', week, '2026-11-01T04:00:00.000Z', 'second_dup');
    await chartWeek('albums', week, '2026-11-01T04:00:00.000Z', 'nova_dup');
    await b.story('debut_second_dup', 'second_dup', 'nova');

    final report = await DuplicateAlbumReconciliationService(
      appDatabase: a.database,
      changes: LibraryChangeSignal(),
    ).reconcile();
    expect(report.merged.single.duplicateAlbumId, 'nova_dup');
    await a.sync();
    await b.sync();

    expect(await b.count(DatabaseTables.albums, "id = 'nova_dup'"), 0);
    // No stored chart row points at a merged record.
    expect(
      await b.count(
        DatabaseTables.chartEntries,
        "entity_id IN ('second_dup', 'opening_dup', 'nova_dup')",
      ),
      0,
    );
    // Both charts from that week on wait to be rebuilt from history (D3);
    // the earlier week is untouched.
    expect(
      await b.count(DatabaseTables.chartSnapshots, "week_start_utc >= '$week'"),
      0,
    );
    expect(await b.count(DatabaseTables.chartEntries, "entity_id = 'glow'"), 1);
    final journal = (await bDb.query(
      DatabaseTables.libraryDeletionJournal,
      where: "operation = 'duplicateMerge'",
    )).single;
    expect(
      (jsonDecode(journal['rebuilt_weeks']! as String) as List),
      containsAll(['songs:$week', 'albums:$week']),
    );
    // Those weeks publish no new Moments (D5).
    final reader = SqliteDeletionJournalReader(() async => bDb);
    expect(
      await reader.isRecalculatedWeek('songs', DateTime.parse(week)),
      isTrue,
    );
    expect(
      await reader.isRecalculatedWeek('songs', DateTime.parse(earlier)),
      isFalse,
    );
    // The story and the listening now name the song that stayed, on both
    // devices (A downloads B's story after the merge); none was deleted.
    await a.sync();
    for (final device in [a, b]) {
      final story = (await (await device.db).query(
        DatabaseTables.chartMomentEvents,
        where: "id = 'debut_second_dup'",
      )).single;
      expect(story['entity_id'], 'second', reason: device.name);
    }
    final moved = (await bDb.query(
      DatabaseTables.qualifiedPlays,
      where: "id = 'play_b_dup'",
    )).single;
    expect(moved['song_id'], 'second');

    // Settled: syncing again writes nothing.
    final writes = cloud.writes;
    await a.sync();
    await b.sync();
    expect(cloud.writes, writes);
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/core/database/schema/sync_schema.dart';
import 'package:sonus_next/core/events/library_change_signal.dart';
import 'package:sonus_next/features/sync/application/services/cloud_archive_sync_service.dart';
import 'package:sonus_next/features/sync/data/services/sqlite_cloud_archive_store.dart';

import '../../../../support/in_memory_cloud_archive.dart';
import '../../../../support/recovery_fixtures.dart';

const _user = 'user-1';

class _Device {
  _Device(
    this.database,
    InMemoryCloudArchive cloud, {
    required String Function() now,
  }) : store = SqliteCloudArchiveStore(
         appDatabase: database,
         changes: LibraryChangeSignal(),
       ) {
    service = CloudArchiveSyncService(
      gateway: cloud,
      store: store,
      queueArtworkUpload: ({required userId, required artworkId}) async =>
          queuedArtwork.add(artworkId),
      newId: () => 'copy-${++_copies}',
      now: () => DateTime.parse(now()),
      pageSize: 3,
    );
  }

  final AppDatabase database;
  final SqliteCloudArchiveStore store;
  late final CloudArchiveSyncService service;
  final queuedArtwork = <String>[];
  var _copies = 0;

  Future<Database> get db => database.database;

  Future<CloudArchiveSyncReport> sync() => service.synchronize(_user);

  Future<List<Map<String, Object?>>> rows(String table, String orderBy) async =>
      (await db).query(table, orderBy: orderBy);
}

/// The archive's tables, for comparing two devices.
const _archived = {
  DatabaseTables.playlists: 'id',
  DatabaseTables.playlistItems: 'id',
  DatabaseTables.playbackSessions: 'id',
  DatabaseTables.playbackListeningSegments: 'id',
  DatabaseTables.qualifiedPlays: 'id',
  DatabaseTables.trackLyrics: 'song_id',
  DatabaseTables.artworkCrops: 'target_type, target_id',
  DatabaseTables.albumReleaseClassifications: 'album_id',
  DatabaseTables.artistProjectAssignments: 'artist_id',
};

void main() {
  late Directory root;
  late InMemoryCloudArchive cloud;
  var stamp = '2026-10-22T00:00:00.000Z';

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    root = await Directory.systemTemp.createTemp('sonus_archive_');
    cloud = InMemoryCloudArchive();
    stamp = '2026-10-22T00:00:00.000Z';
  });

  tearDown(() async {
    await root.delete(recursive: true);
  });

  Future<_Device> device(String name) async {
    final database = fileAppDatabase(root, '$name.db');
    addTearDown(database.close);
    final db = await database.database;
    await seedConnectedLibrary(db, key: 'a', artworkPath: '/artwork/a.jpg');
    final song = (await db.query(DatabaseTables.songs)).single;
    await db.insert(DatabaseTables.songs, {
      ...song,
      'id': 'song-a2',
      'title': 'Second',
      'canonical_title': 'second',
      'track_number': 2,
    });
    await db.insert(DatabaseTables.playlistItems, {
      'id': 'item-a2',
      'playlist_id': 'playlist-a',
      'song_id': 'song-a2',
      'position': 1,
      'created_at': fixtureTimestamp,
      'updated_at': fixtureTimestamp,
    });
    return _Device(database, cloud, now: () => stamp);
  }

  /// A second device with the same library (as library sync leaves it) and
  /// none of the archive's records.
  Future<_Device> emptyDevice(String name) async {
    final b = await device(name);
    final db = await b.db;
    for (final table in [
      DatabaseTables.playlistItems,
      DatabaseTables.playlists,
      DatabaseTables.qualifiedPlays,
      DatabaseTables.playbackListeningSegments,
      DatabaseTables.playbackSessions,
      DatabaseTables.trackLyrics,
      DatabaseTables.chartMomentEvents,
    ]) {
      await db.delete(table);
    }
    return b;
  }

  Future<void> addOrganizationAndMoment(_Device device) async {
    final db = await device.db;
    await db.insert(DatabaseTables.albumReleaseClassifications, {
      'album_id': 'album-a',
      'kind': 'soundtrack',
      'authority': 'manual',
      'created_at': fixtureTimestamp,
      'updated_at': fixtureTimestamp,
    });
    await db.insert(DatabaseTables.artistProjectAssignments, {
      'artist_id': 'artist-a',
      'album_id': 'album-a',
      'mode': 'grouped',
      'created_at': fixtureTimestamp,
      'updated_at': fixtureTimestamp,
    });
    final moment = Map<String, Object?>.from(
      (await db.query(DatabaseTables.chartMomentEvents)).single,
    );
    await db.insert(DatabaseTables.chartMomentEvents, {
      ...moment,
      'id': 'moment-all-time',
      'deduplication_key': 'all-time:debut:song-a',
      'scope': 'allTime',
    });
  }

  Future<void> markArtworkInCloud(_Device device) async {
    await (await device.db).insert(SyncSchema.cloudRevisionBaselinesTable, {
      'user_id': _user,
      'entity_type': 'artworkAsset',
      'entity_id': 'artwork-a',
      'server_revision': 1,
    });
  }

  Future<void> addCrop(_Device device) async {
    await (await device.db).insert(DatabaseTables.artworkCrops, {
      'target_type': 'albumEdition',
      'target_id': 'edition-a',
      'source_artwork_id': 'artwork-a',
      'output_artwork_id': 'artwork-a',
      'crop_left': 0.1,
      'crop_top': 0.2,
      'crop_width': 0.5,
      'crop_height': 0.5,
      'created_at': fixtureTimestamp,
      'updated_at': fixtureTimestamp,
    });
  }

  test('a second device receives every archived record exactly', () async {
    final a = await device('a');
    await addOrganizationAndMoment(a);
    await markArtworkInCloud(a);
    await addCrop(a);
    final b = await emptyDevice('b');

    final pushed = await a.sync();
    expect(pushed.uploaded, 7);
    expect(
      cloud.rowsFor(_user).keys,
      containsAll([
        'playlist:playlist-a',
        'listening_session:session-a',
        'lyrics:song-a',
        'artwork_crop:albumEdition:edition-a',
        'release_classification:album-a',
        'project_assignment:artist-a',
        'all_time_moment:all-time:debut:song-a',
      ]),
    );
    expect(
      cloud.rowsFor(_user).keys,
      isNot(contains('all_time_moment:moment-a')),
      reason: 'weekly Moments are recomputed from plays, not archived',
    );

    final pulled = await b.sync();
    expect(pulled.downloaded, 7);
    for (final MapEntry(key: table, value: order) in _archived.entries) {
      expect(
        await b.rows(table, order),
        await a.rows(table, order),
        reason: table,
      );
    }
    expect(
      await (await b.db).query(
        DatabaseTables.chartMomentEvents,
        where: 'scope = ?',
        whereArgs: ['allTime'],
      ),
      await (await a.db).query(
        DatabaseTables.chartMomentEvents,
        where: 'scope = ?',
        whereArgs: ['allTime'],
      ),
    );
    expect(
      [
        for (final item in await b.rows(
          DatabaseTables.playlistItems,
          'position',
        ))
          item['id'],
      ],
      ['item-a', 'item-a2'],
      reason: 'playlist order is kept',
    );
  });

  test('syncing again writes nothing and duplicates nothing', () async {
    final a = await device('a');
    final b = await emptyDevice('b');
    await a.sync();
    await b.sync();
    final writes = cloud.writes;

    final again = await a.sync();
    final againB = await b.sync();

    expect(cloud.writes, writes);
    expect(again.uploaded + again.downloaded, 0);
    expect(againB.uploaded + againB.downloaded, 0);
    expect(await b.rows(DatabaseTables.qualifiedPlays, 'id'), hasLength(1));
    expect(
      cloud.rowsFor(_user)['listening_session:session-a']!.serverRevision,
      1,
    );
  });

  test('a lost response is recognised on retry, not written twice', () async {
    final a = await device('a');
    cloud.loseNextResponse = true;

    await expectLater(a.sync(), throwsA(isA<SocketException>()));
    final writes = cloud.writes;
    await a.sync();

    expect(cloud.rowsFor(_user), hasLength(3));
    expect(cloud.writes - writes, 2, reason: 'only the two not yet written');
    for (final row in cloud.rowsFor(_user).values) {
      expect(row.serverRevision, 1);
    }
  });

  test('listening history is immutable: the first copy stands', () async {
    final a = await device('a');
    final b = await device('b');
    await (await b.db).update(
      DatabaseTables.playbackSessions,
      {'listened_duration_ms': 1},
      where: 'id = ?',
      whereArgs: ['session-a'],
    );
    await a.sync();
    final before = cloud.rowsFor(_user)['listening_session:session-a']!;

    await b.sync();

    final after = cloud.rowsFor(_user)['listening_session:session-a']!;
    expect(after.serverRevision, before.serverRevision);
    expect(after.fingerprint, before.fingerprint);
    expect(
      (await b.rows(
        DatabaseTables.playbackSessions,
        'id',
      )).single['listened_duration_ms'],
      1,
      reason: 'nothing on the device is overwritten either',
    );
    expect(await b.rows(DatabaseTables.qualifiedPlays, 'id'), hasLength(1));
  });

  test('a playlist edited on two devices is kept twice', () async {
    final a = await device('a');
    final b = await emptyDevice('b');
    await a.sync();
    await b.sync();

    stamp = '2026-10-23T00:00:00.000Z';
    await (await a.db).update(DatabaseTables.playlists, {
      'name': 'Edited on A',
      'updated_at': stamp,
    });
    await (await b.db).delete(
      DatabaseTables.playlistItems,
      where: 'id = ?',
      whereArgs: ['item-a2'],
    );
    await (await b.db).update(DatabaseTables.playlists, {
      'name': 'Edited on B',
      'updated_at': '2026-10-24T00:00:00.000Z',
    });
    await a.sync();

    final report = await b.sync();

    expect(report.conflictsKeptBoth, 1);
    final playlists = await b.rows(DatabaseTables.playlists, 'id');
    expect(
      {for (final p in playlists) p['id']: p['name']},
      {'copy-1': 'Edited on B (this device)', 'playlist-a': 'Edited on A'},
    );
    expect(
      [
        for (final item in await b.rows(
          DatabaseTables.playlistItems,
          'position',
        ))
          if (item['playlist_id'] == 'playlist-a') item['id'],
      ],
      ['item-a', 'item-a2'],
    );
    expect(
      [
        for (final item in await b.rows(
          DatabaseTables.playlistItems,
          'position',
        ))
          if (item['playlist_id'] == 'copy-1') item['song_id'],
      ],
      ['song-a'],
    );
  });

  test('lyrics edited on two devices: the most recent edit wins', () async {
    final a = await device('a');
    final b = await device('b');
    await a.sync();
    await b.sync();

    await (await b.db).update(DatabaseTables.trackLyrics, {
      'plain_text': 'Newer from B',
      'updated_at': '2026-10-24T00:00:00.000Z',
    });
    await (await a.db).update(DatabaseTables.trackLyrics, {
      'plain_text': 'Older from A',
      'updated_at': '2026-10-23T00:00:00.000Z',
    });
    await a.sync();

    final report = await b.sync();
    await a.sync();

    expect(report.conflictsNewerWon, 1);
    expect(
      cloud.rowsFor(_user)['lyrics:song-a']!.payload['plain_text'],
      'Newer from B',
    );
    for (final d in [a, b]) {
      expect(
        (await d.rows(
          DatabaseTables.trackLyrics,
          'song_id',
        )).single['plain_text'],
        'Newer from B',
      );
    }
  });

  test(
    'a removal keeps the cloud content and removes nothing elsewhere',
    () async {
      final a = await device('a');
      final b = await device('b');
      await a.sync();
      await b.sync();

      await (await a.db).delete(DatabaseTables.trackLyrics);
      await a.sync();

      final removed = cloud.rowsFor(_user)['lyrics:song-a']!;
      expect(removed.isDeleted, isTrue);
      expect(removed.payload['plain_text'], 'Lyrics a');

      await b.sync();
      expect(await b.rows(DatabaseTables.trackLyrics, 'song_id'), hasLength(1));

      final writes = cloud.writes;
      await a.sync();
      await b.sync();
      expect(cloud.writes, writes, reason: 'neither device resends it');
      expect(await a.rows(DatabaseTables.trackLyrics, 'song_id'), isEmpty);

      await (await b.db).update(DatabaseTables.trackLyrics, {
        'plain_text': 'Brought back',
        'updated_at': '2026-10-25T00:00:00.000Z',
      });
      await b.sync();
      await a.sync();
      expect(cloud.rowsFor(_user)['lyrics:song-a']!.isDeleted, isFalse);
      expect(
        (await a.rows(
          DatabaseTables.trackLyrics,
          'song_id',
        )).single['plain_text'],
        'Brought back',
      );
    },
  );

  test('a record waits for its song, then applies', () async {
    final a = await device('a');
    await a.sync();

    final database = fileAppDatabase(root, 'c.db');
    addTearDown(database.close);
    final c = _Device(database, cloud, now: () => stamp);
    final report = await c.sync();

    expect(report.waitingForDependencies, 2, reason: 'lyrics and playlist');
    expect(await c.rows(DatabaseTables.trackLyrics, 'song_id'), isEmpty);
    expect(await c.rows(DatabaseTables.qualifiedPlays, 'id'), hasLength(1));

    // Library sync brings the library.
    for (final table in [
      DatabaseTables.artworkAssets,
      DatabaseTables.artists,
      DatabaseTables.albums,
      DatabaseTables.albumEditions,
      DatabaseTables.songs,
    ]) {
      for (final row in await a.rows(table, 'id')) {
        await (await c.db).insert(table, row);
      }
    }
    final retried = await c.sync();

    expect(retried.downloaded, 2);
    expect(
      (await c.rows(
        DatabaseTables.trackLyrics,
        'song_id',
      )).single['plain_text'],
      'Lyrics a',
    );
    expect(await c.rows(DatabaseTables.playlistItems, 'id'), hasLength(2));
  });

  test('a crop is sent only once its artwork is in the cloud', () async {
    final a = await device('a');
    await addCrop(a);

    await a.sync();
    expect(
      cloud.rowsFor(_user).keys,
      isNot(contains('artwork_crop:albumEdition:edition-a')),
    );
    expect(a.queuedArtwork, contains('artwork-a'));

    await markArtworkInCloud(a);
    await a.sync();
    expect(
      cloud.rowsFor(_user).keys,
      contains('artwork_crop:albumEdition:edition-a'),
    );
  });

  test('a server without the archive is skipped without writing', () async {
    final a = await device('a');
    cloud.available = false;

    final report = await a.sync();

    expect(report.skippedUnavailable, isTrue);
    expect(cloud.rowsFor(_user), isEmpty);
    expect(await (await a.db).query(DatabaseTables.cloudArchiveState), isEmpty);
  });
}

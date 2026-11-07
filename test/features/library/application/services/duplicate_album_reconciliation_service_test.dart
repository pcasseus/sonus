// App Update 1.2: verified duplicate releases are merged into one.
// Synthetic fixtures only; the main fixture mirrors the shape of the
// 2026-11-07 Zendaya duplicates (never the user's data).
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/core/events/library_change_signal.dart';
import 'package:sonus_next/features/library/application/services/duplicate_album_reconciliation_service.dart';

const _tracks = [
  ('Replay', 215),
  ('Fireflies', 260),
  ('Butterflies', 234),
  ('Putcha Body Down', 206),
  ('Heaven Lost an Angel', 197),
  ('Cry for Love', 236),
  ('Only When Youre Close', 231),
  ('Bottle You Up', 227),
  ('Scared', 185),
  ('Love You Forever', 255),
  ('My Baby', 194),
];

const _artist = 'artist_zendaya';
const _original = 'album_original';
const _typoCopy = 'album_typo_copy';
const _playableCopy = 'album_playable_copy';

void main() {
  sqfliteFfiInit();

  late AppDatabase appDatabase;
  late Database db;
  late DuplicateAlbumReconciliationService service;
  var outboxId = 0;
  final now = DateTime.utc(2026, 11, 7, 12);
  final stamp = now.toIso8601String();

  setUp(() async {
    appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    db = await appDatabase.database;
    service = DuplicateAlbumReconciliationService(
      appDatabase: appDatabase,
      userId: 'user_1',
      now: () => now,
      generateOutboxId: () => 'outbox_${++outboxId}',
      changes: LibraryChangeSignal(),
    );
    await db.insert(DatabaseTables.artists, {
      'id': _artist,
      'name': 'Zendaya',
      'canonical_name': 'zendaya',
      'created_at': stamp,
      'updated_at': stamp,
    });
  });

  tearDown(() => appDatabase.close());

  Future<void> knownToCloud(String type, String id) =>
      db.insert('sync_cloud_revision_baselines', {
        'user_id': 'user_1',
        'entity_type': type,
        'entity_id': id,
        'server_revision': 1,
      });

  /// One album with one Standard edition and the 11 tracks.
  Future<void> seedAlbum(
    String albumId, {
    required String createdAt,
    required String folder,
    required bool playable,
    String? releaseDate = '2013-01-01T05:00:00.000Z',
    String? precision = 'year',
    String? artworkId,
    String title = 'Zendaya',
    String editionType = 'standard',
    List<(String, int)> tracks = _tracks,
    bool cloud = true,
  }) async {
    await db.insert(DatabaseTables.albums, {
      'id': albumId,
      'artist_id': _artist,
      'title': title,
      'canonical_title': title.toLowerCase(),
      'created_at': createdAt,
      'updated_at': createdAt,
    });
    final editionId = 'edition_$albumId';
    await db.insert(DatabaseTables.albumEditions, {
      'id': editionId,
      'album_id': albumId,
      'title': title,
      'type': editionType,
      'is_primary': 1,
      'release_date': releaseDate,
      'release_date_precision': precision,
      'genre': 'Pop',
      'artwork_id': artworkId,
      'created_at': createdAt,
      'updated_at': createdAt,
    });
    if (cloud) {
      await knownToCloud('album', albumId);
      await knownToCloud('albumEdition', editionId);
    }
    for (final (index, (title, duration)) in tracks.indexed) {
      final songId = 'song_${albumId}_${index + 1}';
      await db.insert(DatabaseTables.songs, {
        'id': songId,
        'artist_id': _artist,
        'album_id': albumId,
        'album_edition_id': editionId,
        'title': title,
        'canonical_title': title.toLowerCase(),
        'track_number': index + 1,
        'disc_number': 1,
        'duration_seconds': duration,
        'created_at': createdAt,
        'updated_at': createdAt,
      });
      await db.insert(DatabaseTables.albumEditionTracks, {
        'album_edition_id': editionId,
        'song_id': songId,
        'disc_number': 1,
        'track_number': index + 1,
        'sort_position': index,
        'created_at': createdAt,
        'updated_at': createdAt,
      });
      await db.insert(DatabaseTables.songArtistCredits, {
        'id': 'credit_$songId',
        'song_id': songId,
        'artist_id': _artist,
        'credited_name': 'Zendaya',
        'canonical_credited_name': 'zendaya',
        'role': 'primary',
        'position': 0,
        'created_at': createdAt,
        'updated_at': createdAt,
      });
      final path = '$folder/${title.toLowerCase()}.mp3';
      await db.insert(DatabaseTables.mediaFileBindings, {
        'id': 'binding_$songId',
        'song_id': songId,
        'file_path': path,
        'normalized_path': path,
        'is_available': playable ? 1 : 0,
        'last_seen_at': createdAt,
        'created_at': createdAt,
        'updated_at': createdAt,
      });
      await db.insert(DatabaseTables.metadataFieldStates, {
        'entity_type': 'song',
        'entity_id': songId,
        'field_name': 'title',
        'authority': 'imported',
        'source': 'embeddedTag',
        'updated_at': createdAt,
      });
      if (cloud) await knownToCloud('song', songId);
    }
  }

  Future<void> play(String songId, String albumId, String id) async {
    await db.insert(DatabaseTables.playbackSessions, {
      'id': 'session_$id',
      'song_id': songId,
      'artist_id': _artist,
      'album_id': albumId,
      'album_edition_id': 'edition_$albumId',
      'song_title': 'x',
      'artist_name': 'Zendaya',
      'album_title': 'Zendaya',
      'album_edition_title': 'Zendaya',
      'started_at': stamp,
      'ended_at': stamp,
      'listened_duration_ms': 200000,
      'track_duration_ms': 200000,
      'created_at': stamp,
      'updated_at': stamp,
    });
    await db.insert(DatabaseTables.qualifiedPlays, {
      'id': 'play_$id',
      'playback_session_id': 'session_$id',
      'song_id': songId,
      'artist_id': _artist,
      'album_id': albumId,
      'album_edition_id': 'edition_$albumId',
      'qualified_at': stamp,
      'listened_duration_ms': 200000,
      'track_duration_ms': 200000,
      'created_at': stamp,
    });
  }

  Future<void> moment(String id, String entityId) =>
      db.insert(DatabaseTables.chartMomentEvents, {
        'id': id,
        'deduplication_key': id,
        'chart_type': 'songs',
        'scope': 'allTime',
        'event_type': 'debut',
        'entity_id': entityId,
        'entity_title': 'x',
        'entity_artist_id': _artist,
        'entity_artist_name': 'Zendaya',
        'week_start_utc': '2026-11-01T04:00:00.000Z',
        'week_end_utc': '2026-11-08T05:00:00.000Z',
        'occurred_at': stamp,
        'created_at': stamp,
      });

  /// The 2026-11-07 shape: the original (history, Moments, chosen artwork,
  /// MusicBrainz date; files moved away), a copy from the typo folder (files
  /// moved again) and a playable copy. Plus an unrelated single.
  Future<void> seedZendayaState() async {
    await db.insert(DatabaseTables.artworkAssets, {
      'id': 'artwork_chosen',
      'file_path': '/artwork/chosen.jpg',
      'normalized_path': '/artwork/chosen.jpg',
      'created_at': stamp,
      'updated_at': stamp,
    });
    await seedAlbum(
      _original,
      createdAt: '2026-10-26T23:48:46.727569Z',
      folder: '/music/zendaya',
      playable: false,
      releaseDate: '2013-09-17T00:00:00.000Z',
      precision: 'day',
      artworkId: 'artwork_chosen',
    );
    await db.insert(DatabaseTables.metadataFieldStates, {
      'entity_type': 'albumEdition',
      'entity_id': 'edition_$_original',
      'field_name': 'artworkId',
      'authority': 'manual',
      'source': 'user',
      'updated_at': stamp,
    });
    await seedAlbum(
      _typoCopy,
      createdAt: '2026-11-07T07:42:45.751101Z',
      folder: '/music/zendaya/zendayaa',
      playable: false,
    );
    await seedAlbum(
      _playableCopy,
      createdAt: '2026-11-07T07:43:56.746952Z',
      folder: '/music/zendaya/zendaya',
      playable: true,
    );
    await seedAlbum(
      'album_single',
      createdAt: '2026-11-07T07:42:45.751101Z',
      folder: '/music/zendaya/swag it out',
      playable: true,
      title: 'Swag It Out',
      releaseDate: null,
      precision: null,
      tracks: const [('Swag It Out', 189)],
    );
    await play('song_${_original}_1', _original, 'replay');
    await play('song_${_original}_11', _original, 'my_baby');
    for (final (index, entity) in [
      'song_${_original}_1',
      'song_${_original}_11',
      _original,
      _original,
      _original,
    ].indexed) {
      await moment('moment_$index', entity);
    }
  }

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

  test('Zendaya: one album keeps its identity, history and artwork', () async {
    await seedZendayaState();

    final plan = await service.plan();
    expect(plan.reviews, isEmpty);
    expect(plan.merges.map((m) => (m.keptAlbumId, m.duplicateAlbumId)), {
      (_original, _typoCopy),
      (_original, _playableCopy),
    });
    // Songs are paired by recording, not by title alone.
    final playable = plan.merges.firstWhere(
      (m) => m.duplicateAlbumId == _playableCopy,
    );
    expect(playable.songIdRemap, {
      for (var i = 1; i <= 11; i++)
        'song_${_playableCopy}_$i': 'song_${_original}_$i',
    });

    final report = await service.reconcile(approved: plan);
    expect(report.merged, hasLength(2));
    expect(report.stale, isEmpty);

    // One "Zendaya": the original identity. The single is untouched.
    final albums = await db.query(DatabaseTables.albums, orderBy: 'id');
    expect(albums.map((a) => a['id']), [_original, 'album_single']);

    // The same 11 songs, each playing from the renamed folder.
    final songs = await db.query(
      DatabaseTables.songs,
      where: 'album_id = ?',
      whereArgs: [_original],
      orderBy: 'track_number',
    );
    expect(songs.map((s) => s['id']), [
      for (var i = 1; i <= 11; i++) 'song_${_original}_$i',
    ]);
    for (final song in songs) {
      final bindings = await db.query(
        DatabaseTables.mediaFileBindings,
        where: 'song_id = ?',
        whereArgs: [song['id']],
      );
      expect(bindings, hasLength(1));
      expect(bindings.single['is_available'], 1);
      expect(
        bindings.single['normalized_path'],
        startsWith('/music/zendaya/zendaya/'),
      );
    }

    // Artwork and the precise release date are the original's.
    final edition = (await db.query(
      DatabaseTables.albumEditions,
    )).firstWhere((e) => e['album_id'] == _original);
    expect(edition['artwork_id'], 'artwork_chosen');
    expect(edition['release_date'], '2013-09-17T00:00:00.000Z');
    expect(edition['release_date_precision'], 'day');

    // History and Moments are untouched and still resolve.
    expect(await count(DatabaseTables.qualifiedPlays), 2);
    expect(
      await count(
        DatabaseTables.qualifiedPlays,
        'song_id IN (SELECT id FROM ${DatabaseTables.songs})',
      ),
      2,
    );
    expect(await count(DatabaseTables.chartMomentEvents), 5);

    // Nothing left behind for the duplicates.
    for (final (table, column) in [
      (DatabaseTables.albumEditions, 'id'),
      (DatabaseTables.songs, 'id'),
      (DatabaseTables.metadataFieldStates, 'entity_id'),
      (DatabaseTables.songArtistCredits, 'song_id'),
      (DatabaseTables.albumEditionTracks, 'song_id'),
    ]) {
      expect(await count(table, "$column LIKE '%copy%'"), 0, reason: table);
    }
    expect(await count(DatabaseTables.mediaFileBindings), 12);

    // The cloud is told: 22 songs, 2 editions and 2 albums deleted.
    final outbox = await db.query(DatabaseTables.syncOutbox);
    expect(outbox.every((o) => o['operation'] == 'delete'), isTrue);
    expect(outbox.map((o) => o['entity_type']).toList()..sort(), [
      ...List.filled(2, 'album'),
      ...List.filled(2, 'albumEdition'),
      ...List.filled(22, 'song'),
    ]);
  });

  test('reconciling again changes nothing', () async {
    await seedZendayaState();
    await service.reconcile();
    final outbox = await count(DatabaseTables.syncOutbox);
    final report = await service.reconcile();
    expect(report.merged, isEmpty);
    expect(await count(DatabaseTables.albums), 2);
    expect(await count(DatabaseTables.syncOutbox), outbox);
  });

  test('a duplicate\'s plays move to the kept songs, never doubled', () async {
    await seedAlbum(
      'album_a',
      createdAt: '2026-10-01T00:00:00Z',
      folder: '/a',
      playable: true,
    );
    await seedAlbum(
      'album_b',
      createdAt: '2026-10-02T00:00:00Z',
      folder: '/b',
      playable: true,
    );
    await play('song_album_a_1', 'album_a', 'a1');
    await play('song_album_a_2', 'album_a', 'a2');
    await play('song_album_b_1', 'album_b', 'b1');

    await service.reconcile();

    expect(await count(DatabaseTables.albums), 1);
    expect(await count(DatabaseTables.qualifiedPlays), 3);
    expect(await count(DatabaseTables.playbackSessions), 3);
    final plays = await db.query(
      DatabaseTables.qualifiedPlays,
      where: 'song_id = ?',
      whereArgs: ['song_album_a_1'],
    );
    expect(plays, hasLength(2), reason: 'both recordings of track 1');
    expect(plays.every((p) => p['album_id'] == 'album_a'), isTrue);
    // Both copies played, so both files keep playing the one song.
    expect(
      await count(DatabaseTables.mediaFileBindings, 'song_id = ?', [
        'song_album_a_1',
      ]),
      2,
    );
  });

  test('the album with the listening history stays, even if newer', () async {
    await seedAlbum(
      'album_old',
      createdAt: '2026-10-01T00:00:00Z',
      folder: '/old',
      playable: true,
    );
    await seedAlbum(
      'album_new',
      createdAt: '2026-11-01T00:00:00Z',
      folder: '/new',
      playable: true,
    );
    await play('song_album_new_4', 'album_new', 'n4');

    final plan = await service.plan();

    expect(plan.merges.single.keptAlbumId, 'album_new');
    expect(plan.merges.single.duplicateAlbumId, 'album_old');
  });

  test('playlists keep one entry per song, in order', () async {
    await seedAlbum(
      'album_a',
      createdAt: '2026-10-01T00:00:00Z',
      folder: '/a',
      playable: true,
    );
    await seedAlbum(
      'album_b',
      createdAt: '2026-10-02T00:00:00Z',
      folder: '/b',
      playable: true,
    );
    await db.insert(DatabaseTables.playlists, {
      'id': 'pl',
      'name': 'Road',
      'created_at': stamp,
      'updated_at': stamp,
    });
    for (final (position, song) in [
      'song_album_a_1',
      'song_album_b_1',
      'song_album_b_2',
    ].indexed) {
      await db.insert(DatabaseTables.playlistItems, {
        'id': 'item_$position',
        'playlist_id': 'pl',
        'song_id': song,
        'position': position,
        'created_at': stamp,
        'updated_at': stamp,
      });
    }

    await service.reconcile();

    final items = await db.query(
      DatabaseTables.playlistItems,
      orderBy: 'position',
    );
    expect(items.map((i) => (i['song_id'], i['position'])), [
      ('song_album_a_1', 0),
      ('song_album_a_2', 1),
    ]);
  });

  test('a duplicate with chart history is left for review', () async {
    await seedAlbum(
      'album_a',
      createdAt: '2026-10-01T00:00:00Z',
      folder: '/a',
      playable: true,
    );
    await seedAlbum(
      'album_b',
      createdAt: '2026-10-02T00:00:00Z',
      folder: '/b',
      playable: true,
    );
    // The listened album stays; the other has a Moment of its own.
    await play('song_album_a_1', 'album_a', 'a1');
    await moment('moment_b', 'song_album_b_3');

    final report = await service.reconcile();

    expect(report.merged, isEmpty);
    expect(report.reviews.single.reason, DuplicateReviewReason.hasChartHistory);
    expect(await count(DatabaseTables.albums), 2);
  });

  test('releases that do not pair exactly are never merged', () async {
    final variants = <String, Future<void> Function()>{
      'a missing track': () => seedAlbum(
        'album_b',
        createdAt: '2026-10-02T00:00:00Z',
        folder: '/b',
        playable: true,
        tracks: _tracks.take(10).toList(),
      ),
      'a different recording': () => seedAlbum(
        'album_b',
        createdAt: '2026-10-02T00:00:00Z',
        folder: '/b',
        playable: true,
        tracks: [..._tracks.take(10), ('My Baby', 260)],
      ),
      'another year': () => seedAlbum(
        'album_b',
        createdAt: '2026-10-02T00:00:00Z',
        folder: '/b',
        playable: true,
        releaseDate: '2015-01-01T05:00:00.000Z',
      ),
      'another edition': () => seedAlbum(
        'album_b',
        createdAt: '2026-10-02T00:00:00Z',
        folder: '/b',
        playable: true,
        editionType: 'deluxe',
      ),
    };

    for (final MapEntry(key: name, value: seedVariant) in variants.entries) {
      await db.delete(DatabaseTables.syncOutbox);
      for (final table in [
        DatabaseTables.mediaFileBindings,
        DatabaseTables.songs,
        DatabaseTables.albumEditions,
        DatabaseTables.albums,
        DatabaseTables.metadataFieldStates,
        'sync_cloud_revision_baselines',
      ]) {
        await db.delete(table);
      }
      await seedAlbum(
        'album_a',
        createdAt: '2026-10-01T00:00:00Z',
        folder: '/a',
        playable: true,
      );
      await seedVariant();

      final report = await service.reconcile();

      expect(report.merged, isEmpty, reason: name);
      expect(
        report.reviews.single.reason,
        DuplicateReviewReason.notVerified,
        reason: name,
      );
      expect(await count(DatabaseTables.albums), 2, reason: name);
    }
  });

  test('a changed library makes an approved plan stale', () async {
    await seedZendayaState();
    final plan = await service.plan();

    // A track appears on the playable copy after the preview.
    await db.insert(DatabaseTables.songs, {
      'id': 'song_late',
      'artist_id': _artist,
      'album_id': _playableCopy,
      'album_edition_id': 'edition_$_playableCopy',
      'title': 'Late',
      'canonical_title': 'late',
      'track_number': 12,
      'duration_seconds': 200,
      'created_at': stamp,
      'updated_at': stamp,
    });

    final report = await service.reconcile(approved: plan);

    expect(report.stale.map((m) => m.duplicateAlbumId), [_playableCopy]);
    expect(report.merged.map((m) => m.duplicateAlbumId), [_typoCopy]);
    expect(await count(DatabaseTables.albums, 'id = ?', [_playableCopy]), 1);
  });

  test('a failure part-way leaves the library exactly as it was', () async {
    await seedZendayaState();
    Future<Map<String, int>> snapshot() async => {
      for (final table in [
        DatabaseTables.albums,
        DatabaseTables.albumEditions,
        DatabaseTables.songs,
        DatabaseTables.mediaFileBindings,
        DatabaseTables.playbackSessions,
        DatabaseTables.qualifiedPlays,
        DatabaseTables.metadataFieldStates,
        DatabaseTables.syncOutbox,
      ])
        table: await count(table),
    };
    final before = await snapshot();
    final bindingsBefore = await db.query(
      DatabaseTables.mediaFileBindings,
      orderBy: 'id',
    );

    // Deleting an album fails after everything else has been changed.
    await db.execute('''
      CREATE TRIGGER fail_album_delete BEFORE DELETE ON albums
      BEGIN SELECT RAISE(ABORT, 'injected failure'); END
    ''');

    await expectLater(service.reconcile(), throwsA(anything));

    expect(await snapshot(), before);
    expect(
      await db.query(DatabaseTables.mediaFileBindings, orderBy: 'id'),
      bindingsBefore,
    );
  });

  test('a duplicate the cloud never saw is simply not sent', () async {
    await seedAlbum(
      'album_a',
      createdAt: '2026-10-01T00:00:00Z',
      folder: '/a',
      playable: true,
    );
    await seedAlbum(
      'album_b',
      createdAt: '2026-10-02T00:00:00Z',
      folder: '/b',
      playable: true,
      cloud: false,
    );
    await db.insert(DatabaseTables.syncOutbox, {
      'id': 'pending_b',
      'user_id': 'user_1',
      'entity_type': 'album',
      'entity_id': 'album_b',
      'operation': 'upsert',
      'created_at': stamp,
      'updated_at': stamp,
    });

    await service.reconcile();

    expect(await count(DatabaseTables.syncOutbox), 0);
  });
}

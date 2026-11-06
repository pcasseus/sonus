// UI redesign E1: Track Studio's credit editor saves the song's credits at
// once, in one transaction, against the stored song. Real SQLite, real
// mutation runner.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/features/library/application/services/song_artist_credit_service.dart';
import 'package:sonus_next/features/library/application/services/track_profile_editing_service.dart';
import 'package:sonus_next/features/library/domain/entities/song_artist_credit.dart';
import 'package:sonus_next/features/sync/data/repositories/sync_mutation_transaction_runner.dart';

const _created = '2026-10-01T00:00:00.000Z';

void main() {
  sqfliteFfiInit();

  late AppDatabase appDatabase;
  late Database db;
  late TrackProfileEditingService service;

  setUp(() async {
    appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    db = await appDatabase.database;
    var nextId = 0;
    service = TrackProfileEditingService(
      mutationRunner: SyncMutationTransactionRunner(
        appDatabase: appDatabase,
        generateId: () => 'outbox_${++nextId}',
        now: () => DateTime.utc(2026, 11, 5, 9),
      ),
    );

    for (final (id, name) in [
      ('artist_primary', 'Primary Artist'),
      ('artist_feature', 'Feature Artist'),
    ]) {
      await db.insert(DatabaseTables.artists, {
        'id': id,
        'name': name,
        'canonical_name': name.toLowerCase(),
        'is_blacklisted': 0,
        'created_at': _created,
        'updated_at': _created,
      });
    }
    await db.insert(DatabaseTables.albums, {
      'id': 'album_1',
      'artist_id': 'artist_primary',
      'title': 'Album',
      'canonical_title': 'album',
      'created_at': _created,
      'updated_at': _created,
    });
    await db.insert(DatabaseTables.albumEditions, {
      'id': 'edition_1',
      'album_id': 'album_1',
      'title': 'Album',
      'type': 'standard',
      'is_primary': 1,
      'created_at': _created,
      'updated_at': _created,
    });
    await db.insert(DatabaseTables.songs, {
      'id': 'song_1',
      'artist_id': 'artist_primary',
      'album_id': 'album_1',
      'album_edition_id': 'edition_1',
      'title': 'Stored Title',
      'canonical_title': 'stored title',
      'track_number': 4,
      'disc_number': 2,
      'duration_seconds': 180,
      'is_single': 1,
      'is_blocked': 0,
      'featured_artists': '["Old Feature"]',
      'created_at': _created,
      'updated_at': _created,
    });
  });

  tearDown(() async => appDatabase.close());

  Future<List<Map<String, Object?>>> credits() => db.query(
    DatabaseTables.songArtistCredits,
    where: 'song_id = ?',
    whereArgs: ['song_1'],
    orderBy: 'position ASC',
  );

  Future<Map<String, Object?>> song() async => (await db.query(
    DatabaseTables.songs,
    where: 'id = ?',
    whereArgs: ['song_1'],
  )).single;

  Future<List<Map<String, Object?>>> outbox() =>
      db.query(DatabaseTables.syncOutbox, orderBy: 'entity_type, entity_id');

  const featured = SongArtistCreditInput(
    creditedName: 'Feature Artist',
    role: SongArtistCreditRole.featured,
    artistId: 'artist_feature',
    linkByName: false,
  );
  const guest = SongArtistCreditInput(
    creditedName: 'Guest Name',
    role: SongArtistCreditRole.guest,
    linkByName: false,
  );

  Future<TrackCreditSaveResult> save(
    List<SongArtistCreditInput> additional, {
    String expected = 'artist_primary',
  }) => service.updateTrackCredits(
    userId: 'user_1',
    songId: 'song_1',
    expectedPrimaryArtistId: expected,
    additionalCredits: additional,
  );

  test('saves the credits once, and nothing else about the song', () async {
    final before = await song();

    final result = await save([featured, guest]);

    expect(result.changed, isTrue);
    final stored = await credits();
    expect(stored.map((row) => (row['role'], row['credited_name'])), [
      ('primary', 'Primary Artist'),
      ('featured', 'Feature Artist'),
      ('guest', 'Guest Name'),
    ]);
    expect(stored[1]['artist_id'], 'artist_feature');
    expect(result.credits, hasLength(3));

    // The legacy featured names follow the saved featured credits.
    final after = await song();
    expect(jsonDecode(after['featured_artists']! as String), [
      'Feature Artist',
    ]);
    // Every other field is untouched.
    for (final column in [
      'title',
      'canonical_title',
      'track_number',
      'disc_number',
      'is_single',
      'artist_id',
      'album_id',
      'album_edition_id',
    ]) {
      expect(after[column], before[column], reason: column);
    }
  });

  test(
    'marks the credits as the user\'s and queues the song for sync',
    () async {
      await save([featured]);

      final state = await db.query(
        DatabaseTables.metadataFieldStates,
        where: 'entity_id = ?',
        whereArgs: ['song_1'],
      );
      expect(state.map((row) => row['field_name']), ['artistCredits']);
      expect(state.single['authority'], 'manual');
      expect(state.single['source'], 'user');

      final queued = await outbox();
      expect(queued.map((row) => (row['entity_type'], row['entity_id'])), [
        ('song', 'song_1'),
      ]);
      expect(queued.single['operation'], 'upsert');
    },
  );

  test('a new co-primary artist is created in the same transaction', () async {
    await save([
      const SongArtistCreditInput(
        creditedName: 'Brand New Partner',
        role: SongArtistCreditRole.coPrimary,
        linkByName: false,
      ),
    ]);

    final partner = await db.query(
      DatabaseTables.artists,
      where: 'canonical_name = ?',
      whereArgs: ['brand new partner'],
    );
    expect(partner, hasLength(1));
    final stored = await credits();
    expect(stored[1]['artist_id'], partner.single['id']);
    expect(
      (await outbox()).map((row) => (row['entity_type'], row['entity_id'])),
      containsAll([('artist', partner.single['id']), ('song', 'song_1')]),
    );
  });

  test('removing every credit persists: only the primary remains', () async {
    await save([featured, guest]);
    await save(const []);

    final stored = await credits();
    expect(stored.map((row) => row['role']), ['primary']);
    expect(jsonDecode((await song())['featured_artists']! as String), []);
  });

  test('a primary artist that is not the stored one is refused, and '
      'nothing changes', () async {
    final before = await song();

    await expectLater(
      save([featured], expected: 'artist_feature'),
      throwsA(
        isA<TrackCreditPrimaryArtistChangedException>().having(
          (error) => error.storedPrimaryArtistId,
          'stored',
          'artist_primary',
        ),
      ),
    );

    expect(await credits(), isEmpty);
    expect(await song(), before);
    expect(await outbox(), isEmpty);
  });

  test('credits that already match write nothing', () async {
    await save([featured]);
    final queuedBefore = (await outbox()).length;
    final idsBefore = (await credits()).map((row) => row['id']).toList();

    final again = await save([featured]);

    expect(again.changed, isFalse);
    expect((await credits()).map((row) => row['id']), idsBefore);
    expect((await outbox()).length, queuedBefore);
  });

  test('the Studio\'s later Save with the saved credits keeps them, so a '
      'stale copy cannot overwrite them', () async {
    await save([featured, guest]);
    List<(Object?, Object?, Object?)> content(
      List<Map<String, Object?>> rows,
    ) => [
      for (final row in rows)
        (row['role'], row['credited_name'], row['artist_id']),
    ];
    final saved = content(await credits());

    // The main Save: the Studio sends its baseline (the saved credits)
    // with an edited title.
    final result = await service.updateTrackWithCredits(
      userId: 'user_1',
      songId: 'song_1',
      title: 'Edited Title',
      trackNumber: 4,
      discNumber: 2,
      additionalCredits: const [featured, guest],
      isSingle: true,
    );

    expect(result.changed, isTrue);
    expect((await song())['title'], 'Edited Title');
    // The main Save rewrites credit rows whenever any field changes (as
    // before E1); what matters is that they still say what was saved.
    expect(content(await credits()), saved, reason: 'saved credits kept');
  });
}

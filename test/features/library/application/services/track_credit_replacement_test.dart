import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/features/library/application/services/song_artist_credit_service.dart';
import 'package:sonus_next/features/library/application/services/track_profile_editing_service.dart';
import 'package:sonus_next/features/library/data/daos/library_query_dao.dart';
import 'package:sonus_next/features/library/data/daos/song_artist_credit_dao.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_song_artist_credit_repository.dart';
import 'package:sonus_next/features/library/domain/entities/song_artist_credit.dart';
import 'package:sonus_next/features/library/presentation/models/track_profile_edit_draft.dart';
import 'package:sonus_next/features/sync/data/repositories/sync_mutation_transaction_runner.dart';

/// SN-50 BUG-01: editing an existing credit in Track Studio replaces it.
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
    service = TrackProfileEditingService(
      mutationRunner: SyncMutationTransactionRunner(appDatabase: appDatabase),
    );

    await _insertArtist(db, id: 'artist_ada', name: 'Ada Vale');
    await _insertArtist(db, id: 'artist_ben', name: 'Ben Moor');
    await _insertArtist(db, id: 'artist_cy', name: 'Cy Lark');
    await _insertArtist(db, id: 'artist_dee', name: 'Dee Rune');
    await _insertAlbumStructure(db);
  });

  tearDown(() async {
    await appDatabase.close();
  });

  /// Opens the song the way Track Studio does and returns its drafts.
  Future<List<TrackProfileCreditDraft>> reopen() async {
    final track = (await LibraryQueryDao(db).findTrackById('song_1'))!;
    final credits = await SqliteSongArtistCreditRepository(
      SongArtistCreditDao(db),
    ).getBySongId('song_1');

    return trackStudioInitialCredits(
      credits: credits,
      legacyFeaturedArtists: track.featuredArtists,
      primaryArtistId: track.artistId,
      primaryArtistName: track.artistName,
    );
  }

  Future<TrackProfileEditResult> save(List<TrackProfileCreditDraft> drafts) {
    return service.updateTrackWithCredits(
      userId: null,
      songId: 'song_1',
      title: 'Night Song',
      trackNumber: 1,
      discNumber: 1,
      additionalCredits: drafts.map((draft) => draft.toInput()),
      isSingle: false,
    );
  }

  Future<List<String>> creditRows() async {
    final rows = await db.query(
      DatabaseTables.songArtistCredits,
      where: 'song_id = ?',
      whereArgs: ['song_1'],
      orderBy: 'position ASC',
    );

    return [
      for (final row in rows)
        '${row['role']}:${row['credited_name']}:${row['artist_id']}',
    ];
  }

  Future<List<String>> legacyFeatured() async {
    final rows = await db.query(
      DatabaseTables.songs,
      columns: ['featured_artists'],
      where: 'id = ?',
      whereArgs: ['song_1'],
    );

    return (jsonDecode(rows.single['featured_artists'] as String) as List)
        .cast<String>();
  }

  String describe(TrackProfileCreditDraft draft) =>
      '${draft.role.name}:${draft.creditedName}:${draft.artistId}';

  const featuredBen = TrackProfileCreditDraft(
    creditedName: 'Ben Moor',
    role: SongArtistCreditRole.featured,
    artistId: 'artist_ben',
  );
  const featuredCy = TrackProfileCreditDraft(
    creditedName: 'Cy Lark',
    role: SongArtistCreditRole.featured,
    artistId: 'artist_cy',
  );

  test('replacing featured A with a picked B removes A everywhere', () async {
    await save([featuredBen]);
    final drafts = await reopen();
    expect(drafts.map(describe), ['featured:Ben Moor:artist_ben']);

    await save([featuredCy]);

    expect(await creditRows(), [
      'primary:Ada Vale:artist_ada',
      'featured:Cy Lark:artist_cy',
    ]);
    expect(await legacyFeatured(), ['Cy Lark']);
    expect((await reopen()).map(describe), ['featured:Cy Lark:artist_cy']);

    final track = (await LibraryQueryDao(db).findTrackById('song_1'))!;
    expect(track.creditLine, 'Ada Vale Ft. Cy Lark');
  });

  test('a typed replacement stays unlinked, even when an artist has that '
      'name', () async {
    await save([featuredBen]);

    await save([
      const TrackProfileCreditDraft(
        creditedName: 'Cy Lark',
        role: SongArtistCreditRole.featured,
      ),
    ]);

    expect(await creditRows(), [
      'primary:Ada Vale:artist_ada',
      'featured:Cy Lark:null',
    ]);
    expect(await legacyFeatured(), ['Cy Lark']);
  });

  test('unlinking a credit under the same name is saved', () async {
    await save([featuredBen]);

    final result = await save([
      const TrackProfileCreditDraft(
        creditedName: 'Ben Moor',
        role: SongArtistCreditRole.featured,
      ),
    ]);

    expect(result.changed, isTrue);
    expect(await creditRows(), [
      'primary:Ada Vale:artist_ada',
      'featured:Ben Moor:null',
    ]);
  });

  test(
    'artists sharing a name stay apart: only the picked one is linked',
    () async {
      await _insertArtist(db, id: 'artist_ben_2', name: 'Ben Moor');

      await save([
        const TrackProfileCreditDraft(
          creditedName: 'Ben Moor',
          role: SongArtistCreditRole.featured,
          artistId: 'artist_ben_2',
        ),
      ]);

      expect(await creditRows(), [
        'primary:Ada Vale:artist_ada',
        'featured:Ben Moor:artist_ben_2',
      ]);

      await save([featuredBen]);

      expect(await creditRows(), [
        'primary:Ada Vale:artist_ada',
        'featured:Ben Moor:artist_ben',
      ]);
    },
  );

  test(
    'removing, reordering and changing roles persist and read back',
    () async {
      await save([
        featuredBen,
        featuredCy,
        const TrackProfileCreditDraft(
          creditedName: 'Eve Shore',
          role: SongArtistCreditRole.guest,
        ),
      ]);
      expect(await legacyFeatured(), ['Ben Moor', 'Cy Lark']);

      final drafts = await reopen();
      await save([
        drafts[1],
        TrackProfileCreditDraft(
          creditedName: drafts[0].creditedName,
          role: SongArtistCreditRole.coPrimary,
          artistId: drafts[0].artistId,
        ),
      ]);

      expect(await creditRows(), [
        'primary:Ada Vale:artist_ada',
        'featured:Cy Lark:artist_cy',
        'coPrimary:Ben Moor:artist_ben',
      ]);
      expect(await legacyFeatured(), ['Cy Lark']);
      expect((await reopen()).map(describe), [
        'featured:Cy Lark:artist_cy',
        'coPrimary:Ben Moor:artist_ben',
      ]);

      final track = (await LibraryQueryDao(db).findTrackById('song_1'))!;
      expect(track.creditLine, 'Ada Vale & Ben Moor Ft. Cy Lark');

      await save(const []);

      expect(await creditRows(), ['primary:Ada Vale:artist_ada']);
      expect(await legacyFeatured(), isEmpty);
    },
  );

  test('multiple featured names: replacing one keeps the others', () async {
    await save([featuredBen, featuredCy]);

    final drafts = await reopen();
    await save([
      drafts[0],
      const TrackProfileCreditDraft(
        creditedName: 'Dee Rune',
        role: SongArtistCreditRole.featured,
        artistId: 'artist_dee',
      ),
    ]);

    expect(await creditRows(), [
      'primary:Ada Vale:artist_ada',
      'featured:Ben Moor:artist_ben',
      'featured:Dee Rune:artist_dee',
    ]);
    expect(await legacyFeatured(), ['Ben Moor', 'Dee Rune']);
  });

  test('a song with only older featured names is replaced, not appended '
      'to', () async {
    await _setLegacyFeatured(db, ['Old Guest']);

    final drafts = await reopen();
    expect(drafts.map(describe), ['featured:Old Guest:null']);

    await save([
      const TrackProfileCreditDraft(
        creditedName: 'New Guest',
        role: SongArtistCreditRole.featured,
      ),
    ]);

    expect(await creditRows(), [
      'primary:Ada Vale:artist_ada',
      'featured:New Guest:null',
    ]);
    expect(await legacyFeatured(), ['New Guest']);
  });

  test('an older featured name the credits lack is shown before it can be '
      'dropped', () async {
    await save([featuredBen]);
    await _setLegacyFeatured(db, ['Ben Moor', 'Old Guest']);

    final drafts = await reopen();
    expect(drafts.map(describe), [
      'featured:Ben Moor:artist_ben',
      'featured:Old Guest:null',
    ]);

    await save(drafts);
    expect(await legacyFeatured(), ['Ben Moor', 'Old Guest']);

    await save([drafts[0]]);
    expect(await legacyFeatured(), ['Ben Moor']);
  });

  test(
    'editing credits leaves listening and chart history as it was',
    () async {
      const historyTables = [
        DatabaseTables.playbackSessions,
        DatabaseTables.qualifiedPlays,
        DatabaseTables.chartSnapshots,
        DatabaseTables.chartEntries,
        DatabaseTables.chartMomentEvents,
      ];
      const at = '2026-10-05T00:00:00.000Z';

      await save([featuredBen]);
      await db.insert(DatabaseTables.chartSnapshots, {
        'id': 'snapshot_1',
        'chart_type': 'songs',
        'week_start_utc': '2026-10-02T00:00:00.000Z',
        'week_end_utc': '2026-10-09T00:00:00.000Z',
        'finalized_at': at,
        'created_at': at,
        'updated_at': at,
      });
      await db.insert(DatabaseTables.chartEntries, {
        'id': 'entry_1',
        'chart_snapshot_id': 'snapshot_1',
        'entity_id': 'song_1',
        'title': 'Night Song',
        'artist_id': 'artist_ada',
        'artist_name': 'Ada Vale',
        'rank': 1,
        'qualified_stream_count': 3,
        'peak_rank': 1,
        'peak_achieved_at': at,
        'movement': 'newEntry',
        'last_qualified_at': at,
        'created_at': at,
        'updated_at': at,
      });

      Future<List<List<Map<String, Object?>>>> history() async => [
        for (final table in historyTables) await db.query(table),
      ];

      final before = await history();
      await save([featuredCy]);

      expect(await history(), before);
      expect(before[3], hasLength(1));
    },
  );

  test('the song credit service keeps the featured mirror in step', () async {
    await save([featuredBen]);

    await SongArtistCreditService(
      mutationRunner: SyncMutationTransactionRunner(appDatabase: appDatabase),
    ).replaceCredits(
      userId: null,
      songId: 'song_1',
      primaryArtistId: 'artist_ada',
      additionalCredits: const [
        SongArtistCreditInput(
          creditedName: 'Dee Rune',
          role: SongArtistCreditRole.featured,
          linkByName: false,
        ),
      ],
    );

    expect(await creditRows(), [
      'primary:Ada Vale:artist_ada',
      'featured:Dee Rune:null',
    ]);
    expect(await legacyFeatured(), ['Dee Rune']);
  });
}

Future<void> _setLegacyFeatured(Database db, List<String> names) {
  return db.update(
    DatabaseTables.songs,
    {'featured_artists': jsonEncode(names)},
    where: 'id = ?',
    whereArgs: ['song_1'],
  );
}

Future<void> _insertArtist(
  Database db, {
  required String id,
  required String name,
}) {
  final timestamp = DateTime.utc(2026, 10, 1).toIso8601String();

  return db.insert(DatabaseTables.artists, {
    'id': id,
    'name': name,
    'canonical_name': name.toLowerCase(),
    'is_blacklisted': 0,
    'created_at': timestamp,
    'updated_at': timestamp,
  });
}

Future<void> _insertAlbumStructure(Database db) async {
  final timestamp = DateTime.utc(2026, 10, 1).toIso8601String();

  await db.insert(DatabaseTables.albums, {
    'id': 'album_1',
    'artist_id': 'artist_ada',
    'title': 'Night Album',
    'canonical_title': 'night album',
    'created_at': timestamp,
    'updated_at': timestamp,
  });

  await db.insert(DatabaseTables.albumEditions, {
    'id': 'edition_1',
    'album_id': 'album_1',
    'title': 'Night Album',
    'type': 'standard',
    'is_primary': 1,
    'created_at': timestamp,
    'updated_at': timestamp,
  });

  await db.insert(DatabaseTables.songs, {
    'id': 'song_1',
    'artist_id': 'artist_ada',
    'album_id': 'album_1',
    'album_edition_id': 'edition_1',
    'title': 'Night Song',
    'canonical_title': 'night song',
    'track_number': 1,
    'disc_number': 1,
    'duration_seconds': 180,
    'is_single': 0,
    'is_blocked': 0,
    'featured_artists': '[]',
    'created_at': timestamp,
    'updated_at': timestamp,
  });
}

// Artist Removal Safety Guard: an artist that listening history, charts,
// Moments, project placement or an unconfirmed cloud write still refers to
// is never deleted, and nothing is changed. Real SQLite, real transaction.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/core/database/schema/sync_schema.dart';
import 'package:sonus_next/features/library/application/services/artist_profile_editing_service.dart';
import 'package:sonus_next/features/library/data/daos/artist_dao.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_artist_reference_repository.dart';
import 'package:sonus_next/features/library/domain/entities/artist.dart';
import 'package:sonus_next/features/library/domain/entities/entity_factory.dart';
import 'package:sonus_next/features/library/domain/repositories/artist_reference_repository.dart';
import 'package:sonus_next/features/library/presentation/models/artist_removal_message.dart';
import 'package:sonus_next/features/sync/application/services/sync_mutation_context.dart';
import 'package:sonus_next/features/sync/application/services/sync_mutation_runner.dart';
import 'package:sonus_next/features/sync/data/daos/local_sync_dao.dart';
import 'package:sonus_next/features/sync/data/repositories/sync_mutation_transaction_runner.dart';
import 'package:sonus_next/features/sync/domain/models/sync_data_contract.dart';

const _time = '2026-10-27T12:00:00.000Z';

void main() {
  sqfliteFfiInit();

  late AppDatabase appDatabase;
  late ArtistProfileEditingService service;

  setUp(() {
    appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    var nextOutboxId = 0;
    service = ArtistProfileEditingService(
      mutationRunner: SyncMutationTransactionRunner(
        appDatabase: appDatabase,
        generateId: () => 'outbox_${++nextOutboxId}',
        now: () => DateTime.utc(2026, 11, 4, 12),
      ),
    );
  });

  tearDown(() async => appDatabase.close());

  Future<Artist> createArtist([String name = 'Kept Artist']) async {
    final artist = EntityFactory.createArtist(
      name: name,
      now: DateTime.utc(2026, 9, 13),
    );
    await ArtistDao(await appDatabase.database).insert(artist);
    return artist;
  }

  Future<void> insert(String table, Map<String, Object?> row) async {
    await (await appDatabase.database).insert(table, row);
  }

  Future<int> count(String table) async {
    final rows = await (await appDatabase.database).rawQuery(
      'SELECT COUNT(*) AS n FROM $table',
    );
    return rows.single['n']! as int;
  }

  Map<String, Object?> session(String id, String artistId) => {
    'id': id,
    'song_id': 'song-gone',
    'artist_id': artistId,
    'album_id': 'album-gone',
    'album_edition_id': 'edition-gone',
    'song_title': 'Song',
    'artist_name': 'Kept Artist',
    'album_title': 'Album',
    'album_edition_title': 'Standard',
    'started_at': _time,
    'created_at': _time,
    'updated_at': _time,
  };

  Map<String, Object?> moment(
    String id, {
    String? entityArtistId,
    String? relatedArtistId,
  }) => {
    'id': id,
    'deduplication_key': 'key-$id',
    'chart_type': 'songs',
    'scope': 'finalized',
    'event_type': 'debut',
    'entity_id': 'song-gone',
    'entity_title': 'Song',
    'entity_artist_id': entityArtistId,
    'entity_artist_name': 'Someone',
    if (relatedArtistId != null) ...{
      'related_entity_id': 'song-other',
      'related_entity_title': 'Other Song',
      'related_entity_artist_id': relatedArtistId,
      'related_entity_artist_name': 'Kept Artist',
    },
    'week_start_utc': '2026-10-24T00:00:00.000Z',
    'week_end_utc': '2026-10-31T00:00:00.000Z',
    'occurred_at': _time,
    'created_at': _time,
  };

  /// Each reference, how to create it, and the table that must keep it.
  final cases =
      <
        (
          String,
          ArtistReference,
          String,
          Future<void> Function(String artistId),
        )
      >[
        (
          'a playback session (listening history)',
          ArtistReference.listeningHistory,
          DatabaseTables.playbackSessions,
          (id) => insert(DatabaseTables.playbackSessions, session('s1', id)),
        ),
        (
          'a qualified play (listening statistics)',
          ArtistReference.listeningHistory,
          DatabaseTables.qualifiedPlays,
          (id) async {
            // The play's session belongs to another artist, so only the
            // qualified play refers to this one.
            await insert(
              DatabaseTables.playbackSessions,
              session('s2', 'artist-other'),
            );
            await insert(DatabaseTables.qualifiedPlays, {
              'id': 'q1',
              'playback_session_id': 's2',
              'song_id': 'song-gone',
              'artist_id': id,
              'album_id': 'album-gone',
              'album_edition_id': 'edition-gone',
              'qualified_at': _time,
              'listened_duration_ms': 60000,
              'track_duration_ms': 180000,
              'created_at': _time,
            });
          },
        ),
        (
          'a chart entry',
          ArtistReference.charts,
          DatabaseTables.chartEntries,
          (id) async {
            await insert(DatabaseTables.chartSnapshots, {
              'id': 'snap-1',
              'chart_type': 'songs',
              'week_start_utc': '2026-10-24T00:00:00.000Z',
              'week_end_utc': '2026-10-31T00:00:00.000Z',
              'finalized_at': _time,
              'created_at': _time,
              'updated_at': _time,
            });
            await insert(DatabaseTables.chartEntries, {
              'id': 'entry-1',
              'chart_snapshot_id': 'snap-1',
              'entity_id': 'song-gone',
              'title': 'Song',
              'artist_id': id,
              'artist_name': 'Kept Artist',
              'rank': 1,
              'qualified_stream_count': 4,
              'peak_rank': 1,
              'peak_achieved_at': _time,
              'movement': 'newEntry',
              'last_qualified_at': _time,
              'created_at': _time,
              'updated_at': _time,
            });
          },
        ),
        (
          'a Moment about the artist',
          ArtistReference.moments,
          DatabaseTables.chartMomentEvents,
          (id) => insert(
            DatabaseTables.chartMomentEvents,
            moment('m1', entityArtistId: id),
          ),
        ),
        (
          'a Moment naming the artist as the related artist',
          ArtistReference.moments,
          DatabaseTables.chartMomentEvents,
          (id) => insert(
            DatabaseTables.chartMomentEvents,
            moment('m2', entityArtistId: 'artist-other', relatedArtistId: id),
          ),
        ),
        (
          'a Library project assignment',
          ArtistReference.projectAssignment,
          DatabaseTables.artistProjectAssignments,
          (id) => insert(DatabaseTables.artistProjectAssignments, {
            'artist_id': id,
            'mode': 'standalone',
            'created_at': _time,
            'updated_at': _time,
          }),
        ),
        (
          'an unconfirmed cloud artist write',
          ArtistReference.pendingCloudWrite,
          SyncSchema.artistWriteJournalTable,
          (id) => insert(SyncSchema.artistWriteJournalTable, {
            'user_id': 'user_1',
            'artist_id': id,
            'outbox_id': 'outbox-x',
            'mutation_revision': 1,
            'operation': 'create',
            'request_json': '{}',
            'created_at': _time,
          }),
        ),
        (
          'an unconfirmed cloud artist creation',
          ArtistReference.pendingCloudWrite,
          SyncSchema.artistDependencyJournalTable,
          (id) => insert(SyncSchema.artistDependencyJournalTable, {
            'user_id': 'user_1',
            'artist_id': id,
            'request_id': 'request-x',
            'request_json': '{}',
            'created_at': _time,
          }),
        ),
      ];

  group('an artist with history is kept, and nothing changes', () {
    for (final (what, reference, table, create) in cases) {
      test(what, () async {
        final artist = await createArtist();
        await create(artist.id);
        final rowsBefore = await count(table);
        final db = await appDatabase.database;

        await expectLater(
          service.removeArtist(userId: 'user_1', artistId: artist.id),
          throwsA(
            isA<ArtistStillReferencedException>().having(
              (error) => error.references,
              'references',
              {reference},
            ),
          ),
        );

        expect(await ArtistDao(db).findById(artist.id), isNotNull);
        expect(await count(table), rowsBefore, reason: 'history kept');
        expect(
          await LocalSyncDao(db).findPending('user_1'),
          isEmpty,
          reason: 'no cloud delete queued',
        );
      });
    }
  });

  test('every reference is reported together', () async {
    final artist = await createArtist();
    // A session, a chart entry and a Moment.
    for (final index in [0, 2, 3]) {
      await cases[index].$4(artist.id);
    }

    await expectLater(
      service.removeArtist(userId: 'user_1', artistId: artist.id),
      throwsA(
        isA<ArtistStillReferencedException>()
            .having((error) => error.references, 'references', {
              ArtistReference.listeningHistory,
              ArtistReference.charts,
              ArtistReference.moments,
            }),
      ),
    );
  });

  test('history of another artist does not block removal', () async {
    final artist = await createArtist('Unused Artist');
    final other = await createArtist('Listened Artist');
    for (final (_, _, _, create) in cases) {
      await create(other.id);
    }

    await service.removeArtist(userId: 'user_1', artistId: artist.id);

    final db = await appDatabase.database;
    expect(await ArtistDao(db).findById(artist.id), isNull);
    expect(await ArtistDao(db).findById(other.id), isNotNull);
  });

  test('an unreferenced artist still follows the existing safe deletion: '
      'removed, with its cloud delete queued', () async {
    final artist = await createArtist('Unused Artist');
    final db = await appDatabase.database;

    expect(
      await SqliteArtistReferenceRepository(db).findReferences(artist.id),
      isEmpty,
    );

    await service.removeArtist(userId: 'user_1', artistId: artist.id);

    expect(await ArtistDao(db).findById(artist.id), isNull);
    final pending = await LocalSyncDao(db).findPending('user_1');
    expect(pending, hasLength(1));
    expect(pending.single.entityType, CloudDataEntity.artist);
    expect(pending.single.entityId, artist.id);
  });

  test('without the reference check, removal refuses to run', () async {
    final artist = await createArtist('Unused Artist');
    final real = SyncMutationTransactionRunner(appDatabase: appDatabase);
    final withoutCheck = ArtistProfileEditingService(
      mutationRunner: _WithoutReferenceCheck(real),
    );

    await expectLater(
      withoutCheck.removeArtist(userId: 'user_1', artistId: artist.id),
      throwsStateError,
    );
    expect(
      await ArtistDao(await appDatabase.database).findById(artist.id),
      isNotNull,
    );
  });

  group('the explanation names what keeps the artist', () {
    test('history, charts and Moments', () {
      expect(
        artistRemovalBlockedMessage({
          ArtistReference.moments,
          ArtistReference.listeningHistory,
          ArtistReference.charts,
        }),
        'This artist was not removed. Sonus keeps it because it still has '
        'listening history, chart history and Moments.',
      );
    });

    test('a single reason', () {
      expect(
        artistRemovalBlockedMessage({ArtistReference.projectAssignment}),
        'This artist was not removed. Sonus keeps it because it still has '
        'a Library grouping.',
      );
    });

    test('every reference kind has wording', () {
      for (final reference in ArtistReference.values) {
        expect(
          artistRemovalBlockedMessage({reference}),
          startsWith('This artist was not removed.'),
        );
      }
    });
  });
}

/// The real transaction, minus the reference check.
class _WithoutReferenceCheck implements SyncMutationRunner {
  _WithoutReferenceCheck(this._inner);

  final SyncMutationRunner _inner;

  @override
  Future<T> run<T>(SyncMutationAction<T> action) {
    return _inner.run(
      (context) => action(
        SyncMutationContext(
          artistRepository: context.artistRepository,
          albumRepository: context.albumRepository,
          albumEditionRepository: context.albumEditionRepository,
          albumEditionTrackRepository: context.albumEditionTrackRepository,
          songRepository: context.songRepository,
          songArtistCreditRepository: context.songArtistCreditRepository,
          metadataFieldStateRepository: context.metadataFieldStateRepository,
          artworkAssetRepository: context.artworkAssetRepository,
          localSyncRepository: context.localSyncRepository,
        ),
      ),
    );
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/core/events/library_change_signal.dart';
import 'package:sonus_next/features/artwork/data/daos/artwork_asset_dao.dart';
import 'package:sonus_next/features/artwork/data/repositories/sqlite_artwork_asset_repository.dart';
import 'package:sonus_next/features/library/application/services/album_edition_management_service.dart';
import 'package:sonus_next/features/library/data/daos/album_dao.dart';
import 'package:sonus_next/features/library/data/daos/album_edition_dao.dart';
import 'package:sonus_next/features/library/data/daos/album_edition_track_dao.dart';
import 'package:sonus_next/features/library/data/daos/artist_dao.dart';
import 'package:sonus_next/features/library/data/daos/metadata_field_state_dao.dart';
import 'package:sonus_next/features/library/data/daos/song_artist_credit_dao.dart';
import 'package:sonus_next/features/library/data/daos/song_dao.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_album_edition_repository.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_album_edition_track_repository.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_album_repository.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_artist_repository.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_metadata_field_state_repository.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_song_artist_credit_repository.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_song_repository.dart';
import 'package:sonus_next/features/library/domain/entities/album.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition_track.dart';
import 'package:sonus_next/features/library/domain/entities/artist.dart';
import 'package:sonus_next/features/library/domain/entities/song.dart';
import 'package:sonus_next/features/library/domain/entities/song_artist_credit.dart';
import 'package:sonus_next/features/sync/application/services/cloud_conditional_write_result.dart';
import 'package:sonus_next/features/sync/application/services/cloud_sync_gateway.dart';
import 'package:sonus_next/features/sync/application/services/cloud_sync_reader.dart';
import 'package:sonus_next/features/sync/application/services/inbound_cloud_record_applier.dart';
import 'package:sonus_next/features/sync/application/services/outbound_sync_processor.dart';
import 'package:sonus_next/features/sync/data/daos/local_sync_dao.dart';
import 'package:sonus_next/features/sync/data/mappers/supabase_cloud_record_mapper.dart';
import 'package:sonus_next/features/sync/data/repositories/sqlite_local_sync_repository.dart';
import 'package:sonus_next/features/sync/data/repositories/sync_mutation_transaction_runner.dart';
import 'package:sonus_next/features/sync/domain/models/cloud_records.dart';
import 'package:sonus_next/features/sync/domain/models/sync_data_contract.dart';

import 'application/services/outbound_sync_processor_test.dart' as fx;

const _user = 'user_1';
final _t = DateTime.utc(2026, 10, 25, 12);

/// The cloud as rows on the wire: every write goes through the real
/// Supabase mapper and JSON, exactly as it would over HTTP.
class _WireCloud implements CloudSyncGateway {
  final Map<String, Map<String, dynamic>> rows = {};
  bool hasSongExtensions = true;

  static CloudDataEntity _entity(CloudOwnedRecord record) => switch (record) {
    CloudArtistRecord() => CloudDataEntity.artist,
    CloudAlbumRecord() => CloudDataEntity.album,
    CloudAlbumEditionRecord() => CloudDataEntity.albumEdition,
    CloudSongRecord() => CloudDataEntity.song,
    _ => CloudDataEntity.artworkAsset,
  };

  @override
  Future<void> upsert(CloudOwnedRecord record) async {
    final row = SupabaseCloudRecordMapper.toRow(record);
    if (!hasSongExtensions) {
      row.remove('edition_memberships');
      row.remove('artist_credits');
    }
    final key = '${_entity(record).name}:${record.id}';
    final revision = (rows[key]?['server_revision'] as int? ?? 0) + 1;
    rows[key] =
        jsonDecode(
              jsonEncode({
                ...row,
                'server_updated_at': _t.toIso8601String(),
                'server_revision': revision,
              }),
            )
            as Map<String, dynamic>;
  }

  List<CloudOwnedRecord> download(CloudDataEntity entity) => [
    for (final MapEntry(:key, :value) in rows.entries)
      if (key.startsWith('${entity.name}:'))
        SupabaseCloudRecordMapper.fromRow(
          entityType: entity,
          row: value,
        ).record,
  ];

  @override
  Future<CloudSyncItem?> fetchCurrent({
    required String userId,
    required CloudDataEntity entityType,
    required String entityId,
  }) async => null;

  @override
  Future<CloudConditionalWriteResult> insertIfAbsent(CloudOwnedRecord r) =>
      throw UnimplementedError();

  @override
  Future<CloudConditionalWriteResult> updateIfRevision(
    CloudOwnedRecord record, {
    required int expectedServerRevision,
  }) => throw UnimplementedError();

  @override
  Future<CloudConditionalWriteResult> markDeletedIfRevision({
    required String userId,
    required CloudDataEntity entityType,
    required String entityId,
    required DateTime deletedAt,
    required int expectedServerRevision,
  }) => throw UnimplementedError();

  @override
  Future<void> markDeleted({
    required String userId,
    required CloudDataEntity entityType,
    required String entityId,
    required DateTime deletedAt,
  }) => throw UnimplementedError();
}

void main() {
  sqfliteFfiInit();

  late Directory root;
  late AppDatabase deviceA;
  late AppDatabase deviceB;
  late _WireCloud cloud;

  // Separate files: two in-memory databases would be the same database.
  AppDatabase deviceDatabase(String name) => AppDatabase(
    databaseFactory: databaseFactoryFfi,
    databasePath: path.join(root.path, '$name.db'),
  );

  SyncMutationTransactionRunner runnerFor(AppDatabase database) {
    var next = 0;
    return SyncMutationTransactionRunner(
      appDatabase: database,
      generateId: () => 'outbox_${next++}',
      now: () => _t,
      changes: LibraryChangeSignal(),
    );
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('sonus_two_devices_');
    deviceA = deviceDatabase('device_a');
    deviceB = deviceDatabase('device_b');
    cloud = _WireCloud();
  });

  tearDown(() async {
    await deviceA.close();
    await deviceB.close();
    if (await root.exists()) await root.delete(recursive: true);
  });

  /// A Standard edition, a Deluxe that inherits its song, and a song with
  /// a primary and a featured credit, made through the real services.
  Future<String> seedLibrary(AppDatabase device) async {
    final runner = runnerFor(device);
    await runner.run((context) async {
      for (final (id, name) in [
        ('artist_1', 'Artist'),
        ('artist_2', 'Guest'),
      ]) {
        await context.artistRepository.create(
          Artist(
            id: id,
            name: name,
            canonicalName: name.toLowerCase(),
            createdAt: _t,
            updatedAt: _t,
          ),
        );
        await context.localSyncRepository.recordUpsert(
          userId: _user,
          entityType: CloudDataEntity.artist,
          entityId: id,
        );
      }
      await context.albumRepository.create(
        Album(
          id: 'album_1',
          artistId: 'artist_1',
          title: 'Album',
          canonicalTitle: 'album',
          createdAt: _t,
          updatedAt: _t,
        ),
      );
      await context.albumEditionRepository.create(
        AlbumEdition(
          id: 'edition_standard',
          albumId: 'album_1',
          title: 'Standard',
          type: AlbumEditionType.standard,
          isPrimary: true,
          createdAt: _t,
          updatedAt: _t,
        ),
      );
      await context.songRepository.create(
        Song(
          id: 'song_1',
          artistId: 'artist_1',
          albumId: 'album_1',
          albumEditionId: 'edition_standard',
          title: 'Song',
          canonicalTitle: 'song',
          trackNumber: 3,
          durationSeconds: 200,
          isSingle: false,
          createdAt: _t,
          updatedAt: _t,
        ),
      );
      await context.albumEditionTrackRepository.create(
        AlbumEditionTrack(
          albumEditionId: 'edition_standard',
          songId: 'song_1',
          discNumber: 1,
          trackNumber: 3,
          sortPosition: 2,
          createdAt: _t,
          updatedAt: _t,
        ),
      );
      for (final (index, (artist, role)) in [
        ('artist_1', SongArtistCreditRole.primary),
        ('artist_2', SongArtistCreditRole.featured),
      ].indexed) {
        await context.songArtistCreditRepository.create(
          SongArtistCredit(
            id: 'credit_$index',
            songId: 'song_1',
            artistId: artist,
            creditedName: artist == 'artist_1' ? 'Artist' : 'Guest',
            canonicalCreditedName: artist == 'artist_1' ? 'artist' : 'guest',
            role: role,
            position: index,
            createdAt: _t,
            updatedAt: _t,
          ),
        );
      }
    });

    final deluxe = await AlbumEditionManagementService(mutationRunner: runner)
        .createEdition(
          albumId: 'album_1',
          title: 'Deluxe',
          type: AlbumEditionType.deluxe,
          includeSongsFrom: 'edition_standard',
          userId: _user,
          now: _t,
        );
    return deluxe.id;
  }

  Future<void> uploadFromDeviceA() async {
    final db = await deviceA.database;
    final processor = OutboundSyncProcessor(
      localSyncRepository: SqliteLocalSyncRepository(
        dao: LocalSyncDao(db),
        generateId: () => 'unused',
        now: () => _t,
      ),
      artistRepository: SqliteArtistRepository(ArtistDao(db)),
      albumRepository: SqliteAlbumRepository(AlbumDao(db)),
      albumEditionRepository: SqliteAlbumEditionRepository(AlbumEditionDao(db)),
      songRepository: SqliteSongRepository(SongDao(db)),
      metadataFieldStateRepository: SqliteMetadataFieldStateRepository(
        MetadataFieldStateDao(db),
      ),
      artworkAssetRepository: SqliteArtworkAssetRepository(ArtworkAssetDao(db)),
      cloudArtworkStorage: fx.FakeCloudArtworkStorage(),
      cloudSyncGateway: cloud,
      albumEditionTrackRepository: SqliteAlbumEditionTrackRepository(
        AlbumEditionTrackDao(db),
      ),
      songArtistCreditRepository: SqliteSongArtistCreditRepository(
        SongArtistCreditDao(db),
      ),
    );
    await processor.pushPending(_user);
    expect(await LocalSyncDao(db).findPending(_user), isEmpty);
  }

  Future<void> downloadToDeviceB({
    List<CloudDataEntity> entities = const [
      CloudDataEntity.artist,
      CloudDataEntity.album,
      CloudDataEntity.albumEdition,
      CloudDataEntity.song,
    ],
  }) async {
    final runner = runnerFor(deviceB);
    const applier = InboundCloudRecordApplier();
    for (final entity in entities) {
      for (final record in cloud.download(entity)) {
        await runner.run(
          (context) => applier.apply(record: record, context: context),
        );
      }
    }
  }

  Future<List<Map<String, Object?>>> rows(
    AppDatabase database,
    String table,
    String orderBy,
  ) async => (await database.database).query(table, orderBy: orderBy);

  test('Deluxe membership and full credits survive upload and download '
      'to a new device', () async {
    final deluxeId = await seedLibrary(deviceA);

    // Inheriting the Standard song queued it for upload.
    final pending = await LocalSyncDao(
      await deviceA.database,
    ).findPending(_user);
    expect(
      pending.where((e) => e.entityType == CloudDataEntity.song),
      isNotEmpty,
    );

    await uploadFromDeviceA();

    final wire = cloud.rows['song:song_1']!;
    expect(wire['edition_memberships'], hasLength(2));
    expect(wire['artist_credits'], hasLength(2));

    await downloadToDeviceB();

    final membershipColumns = [
      'album_edition_id',
      'song_id',
      'disc_number',
      'track_number',
      'sort_position',
      'numbering_authority',
      'ordering_authority',
    ];
    List<Map<String, Object?>> trim(List<Map<String, Object?>> list) => [
      for (final row in list) {for (final c in membershipColumns) c: row[c]},
    ];

    final onA = trim(
      await rows(
        deviceA,
        DatabaseTables.albumEditionTracks,
        'album_edition_id',
      ),
    );
    final onB = trim(
      await rows(
        deviceB,
        DatabaseTables.albumEditionTracks,
        'album_edition_id',
      ),
    );
    expect(onB, onA);
    expect(onB.map((r) => r['album_edition_id']), contains(deluxeId));

    const creditColumns = [
      'id',
      'song_id',
      'artist_id',
      'credited_name',
      'canonical_credited_name',
      'role',
      'position',
    ];
    List<Map<String, Object?>> credits(List<Map<String, Object?>> list) => [
      for (final row in list) {for (final c in creditColumns) c: row[c]},
    ];
    expect(
      credits(
        await rows(deviceB, DatabaseTables.songArtistCredits, 'position'),
      ),
      credits(
        await rows(deviceA, DatabaseTables.songArtistCredits, 'position'),
      ),
    );
  });

  test(
    'a row without memberships or credits never removes local ones',
    () async {
      cloud.hasSongExtensions = false;
      await seedLibrary(deviceA);
      await uploadFromDeviceA();
      expect(
        cloud.rows['song:song_1']!.containsKey('edition_memberships'),
        isFalse,
      );

      // Device B already has the Deluxe listing and both credits.
      await seedLibrary(deviceB);
      final before = await rows(
        deviceB,
        DatabaseTables.albumEditionTracks,
        'album_edition_id',
      );
      final creditsBefore = await rows(
        deviceB,
        DatabaseTables.songArtistCredits,
        'position',
      );
      expect(before, hasLength(2));

      await downloadToDeviceB(entities: const [CloudDataEntity.song]);

      expect(
        await rows(
          deviceB,
          DatabaseTables.albumEditionTracks,
          'album_edition_id',
        ),
        hasLength(2),
      );
      expect(
        await rows(deviceB, DatabaseTables.songArtistCredits, 'position'),
        creditsBefore,
      );
    },
  );
}

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/import/application/services/import_duration_repair_service.dart';
import 'package:sonus_next/features/import/data/daos/media_file_binding_dao.dart';
import 'package:sonus_next/features/import/data/repositories/sqlite_media_file_binding_repository.dart';
import 'package:sonus_next/features/import/domain/entities/media_file_binding.dart';
import 'package:sonus_next/features/import/domain/models/audio_metadata.dart';
import 'package:sonus_next/features/import/domain/models/import_candidate.dart';
import 'package:sonus_next/features/import/domain/services/audio_metadata_reader.dart';
import 'package:sonus_next/features/library/data/daos/album_dao.dart';
import 'package:sonus_next/features/library/data/daos/album_edition_dao.dart';
import 'package:sonus_next/features/library/data/daos/artist_dao.dart';
import 'package:sonus_next/features/library/data/daos/song_dao.dart';
import 'package:sonus_next/features/library/domain/entities/entity_factory.dart';
import 'package:sonus_next/features/library/domain/entities/song.dart';
import 'package:sonus_next/features/sync/data/daos/local_sync_dao.dart';
import 'package:sonus_next/features/sync/data/repositories/sync_mutation_transaction_runner.dart';
import 'package:sonus_next/features/sync/domain/models/local_sync_models.dart';
import 'package:sonus_next/features/sync/domain/models/sync_data_contract.dart';

class CallbackAudioMetadataReader implements AudioMetadataReader {
  CallbackAudioMetadataReader(this.callback);

  final Future<AudioMetadata> Function(ImportCandidate candidate) callback;

  @override
  Future<AudioMetadata> read(ImportCandidate candidate) {
    return callback(candidate);
  }
}

void main() {
  sqfliteFfiInit();

  late AppDatabase appDatabase;
  late SqliteMediaFileBindingRepository bindingRepository;
  late SyncMutationTransactionRunner mutationRunner;

  final originalTime = DateTime.utc(2026, 9, 19, 12);
  final repairTime = DateTime.utc(2026, 9, 19, 13);

  setUp(() async {
    appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );

    final db = await appDatabase.database;

    bindingRepository = SqliteMediaFileBindingRepository(
      MediaFileBindingDao(db),
    );

    var nextOutboxId = 0;

    mutationRunner = SyncMutationTransactionRunner(
      appDatabase: appDatabase,
      generateId: () => 'outbox_${++nextOutboxId}',
      now: () => repairTime,
    );
  });

  tearDown(() async {
    await appDatabase.close();
  });

  AudioMetadata metadata({
    int durationSeconds = 200,
    String title = 'Physical File Title',
    String artistName = 'Physical File Artist',
    String albumTitle = 'Physical File Album',
  }) {
    return AudioMetadata(
      title: title,
      artistName: artistName,
      albumTitle: albumTitle,
      durationSeconds: durationSeconds,
      trackNumber: 99,
      discNumber: 9,
      isSingle: true,
      featuredArtists: const ['Physical Feature'],
    );
  }

  Future<Song> createSong({
    required String suffix,
    int durationSeconds = 0,
    String title = 'My Sonus Edit',
    int trackNumber = 7,
  }) async {
    final artist = EntityFactory.createArtist(
      name: 'Artist $suffix',
      now: originalTime,
    );

    final album = EntityFactory.createAlbum(
      artistId: artist.id,
      title: 'Album $suffix',
      now: originalTime,
    );

    final edition = EntityFactory.createAlbumEdition(
      albumId: album.id,
      title: 'Edition $suffix',
      isPrimary: true,
      now: originalTime,
    );

    final song = EntityFactory.createSong(
      artistId: artist.id,
      albumId: album.id,
      albumEditionId: edition.id,
      title: title,
      trackNumber: trackNumber,
      durationSeconds: durationSeconds,
      isSingle: false,
      featuredArtists: const ['Sonus Feature'],
      now: originalTime,
    );

    final db = await appDatabase.database;

    await ArtistDao(db).insert(artist);
    await AlbumDao(db).insert(album);
    await AlbumEditionDao(db).insert(edition);
    await SongDao(db).insert(song);

    return song;
  }

  Future<MediaFileBinding> createBinding({
    required Song song,
    required String suffix,
    bool isAvailable = true,
  }) async {
    final binding = MediaFileBinding(
      id: 'binding_$suffix',
      songId: song.id,
      filePath: 'content://music/$suffix.mp3',
      normalizedPath: 'content://music/$suffix.mp3',
      isAvailable: isAvailable,
      lastSeenAt: originalTime,
      createdAt: originalTime,
      updatedAt: originalTime,
    );

    await bindingRepository.create(binding);

    return binding;
  }

  ImportDurationRepairService buildService(AudioMetadataReader reader) {
    return ImportDurationRepairService(
      mediaFileBindingRepository: bindingRepository,
      metadataReader: reader,
      mutationRunner: mutationRunner,
    );
  }

  test('repairs only duration and preserves existing Sonus metadata', () async {
    final original = await createSong(suffix: 'one');
    await createBinding(song: original, suffix: 'one');

    final service = buildService(
      CallbackAudioMetadataReader((_) async => metadata(durationSeconds: 214)),
    );

    final summary = await service.repair(userId: null, now: repairTime);

    expect(summary.examined, 1);
    expect(summary.repaired, 1);
    expect(summary.skipped, 0);
    expect(summary.failed, 0);

    final db = await appDatabase.database;
    final stored = await SongDao(db).findById(original.id);

    expect(stored, isNotNull);
    expect(stored!.id, original.id);
    expect(stored.artistId, original.artistId);
    expect(stored.albumId, original.albumId);
    expect(stored.albumEditionId, original.albumEditionId);
    expect(stored.title, original.title);
    expect(stored.canonicalTitle, original.canonicalTitle);
    expect(stored.trackNumber, original.trackNumber);
    expect(stored.discNumber, original.discNumber);
    expect(stored.isSingle, original.isSingle);
    expect(stored.featuredArtists, original.featuredArtists);
    expect(stored.artworkId, original.artworkId);
    expect(stored.createdAt, original.createdAt);
    expect(stored.durationSeconds, 214);
    expect(stored.updatedAt, repairTime);
  });

  test('positive-duration songs are never read or changed', () async {
    final original = await createSong(suffix: 'positive', durationSeconds: 180);
    await createBinding(song: original, suffix: 'positive');

    var readCount = 0;

    final service = buildService(
      CallbackAudioMetadataReader((_) async {
        readCount++;
        return metadata(durationSeconds: 999);
      }),
    );

    final summary = await service.repair(userId: null, now: repairTime);

    expect(summary.examined, 0);
    expect(summary.repaired, 0);
    expect(summary.skipped, 0);
    expect(summary.failed, 0);
    expect(readCount, 0);

    final db = await appDatabase.database;
    final stored = await SongDao(db).findById(original.id);

    expect(stored, isNotNull);
    expect(stored!.durationSeconds, 180);
    expect(stored.updatedAt, originalTime);
  });

  test('unavailable binding is skipped without reading metadata', () async {
    final original = await createSong(suffix: 'unavailable');
    await createBinding(
      song: original,
      suffix: 'unavailable',
      isAvailable: false,
    );

    var readCount = 0;

    final service = buildService(
      CallbackAudioMetadataReader((_) async {
        readCount++;
        return metadata();
      }),
    );

    final summary = await service.repair(userId: null, now: repairTime);

    expect(summary.examined, 1);
    expect(summary.repaired, 0);
    expect(summary.skipped, 1);
    expect(summary.failed, 0);
    expect(readCount, 0);

    final db = await appDatabase.database;
    final stored = await SongDao(db).findById(original.id);

    expect(stored, isNotNull);
    expect(stored!.durationSeconds, 0);
    expect(stored.updatedAt, originalTime);
  });

  test('missing binding is skipped', () async {
    final original = await createSong(suffix: 'missing');

    final service = buildService(
      CallbackAudioMetadataReader(
        (_) async => throw StateError('Reader should not run'),
      ),
    );

    final summary = await service.repair(userId: null, now: repairTime);

    expect(summary.examined, 1);
    expect(summary.repaired, 0);
    expect(summary.skipped, 1);
    expect(summary.failed, 0);

    final db = await appDatabase.database;
    final stored = await SongDao(db).findById(original.id);

    expect(stored, isNotNull);
    expect(stored!.durationSeconds, 0);
  });

  test('zero duration returned by reader is skipped', () async {
    final original = await createSong(suffix: 'zero');
    await createBinding(song: original, suffix: 'zero');

    final service = buildService(
      CallbackAudioMetadataReader((_) async => metadata(durationSeconds: 0)),
    );

    final summary = await service.repair(userId: null, now: repairTime);

    expect(summary.examined, 1);
    expect(summary.repaired, 0);
    expect(summary.skipped, 1);
    expect(summary.failed, 0);

    final db = await appDatabase.database;
    final stored = await SongDao(db).findById(original.id);

    expect(stored, isNotNull);
    expect(stored!.durationSeconds, 0);
    expect(stored.updatedAt, originalTime);
  });

  test('reader failure does not stop later repairs', () async {
    final first = await createSong(suffix: 'failure');
    final second = await createSong(suffix: 'success');

    await createBinding(song: first, suffix: 'failure');
    await createBinding(song: second, suffix: 'success');

    final service = buildService(
      CallbackAudioMetadataReader((candidate) async {
        if (candidate.filePath.contains('failure')) {
          throw StateError('Unreadable file');
        }

        return metadata(durationSeconds: 321);
      }),
    );

    final summary = await service.repair(userId: null, now: repairTime);

    expect(summary.examined, 2);
    expect(summary.repaired, 1);
    expect(summary.skipped, 0);
    expect(summary.failed, 1);

    final db = await appDatabase.database;

    final failedSong = await SongDao(db).findById(first.id);
    final repairedSong = await SongDao(db).findById(second.id);

    expect(failedSong, isNotNull);
    expect(failedSong!.durationSeconds, 0);
    expect(failedSong.updatedAt, originalTime);

    expect(repairedSong, isNotNull);
    expect(repairedSong!.durationSeconds, 321);
    expect(repairedSong.updatedAt, repairTime);
  });

  test('signed-out repair does not create outbox entry', () async {
    final original = await createSong(suffix: 'signed_out');
    await createBinding(song: original, suffix: 'signed_out');

    final service = buildService(
      CallbackAudioMetadataReader((_) async => metadata(durationSeconds: 222)),
    );

    final summary = await service.repair(userId: null, now: repairTime);

    expect(summary.repaired, 1);

    final db = await appDatabase.database;

    expect(await LocalSyncDao(db).findPending(''), isEmpty);
  });

  test('signed-in repair records normal song upsert', () async {
    final original = await createSong(suffix: 'signed_in');
    await createBinding(song: original, suffix: 'signed_in');

    final service = buildService(
      CallbackAudioMetadataReader((_) async => metadata(durationSeconds: 222)),
    );

    final summary = await service.repair(userId: ' user_1 ', now: repairTime);

    expect(summary.repaired, 1);

    final db = await appDatabase.database;
    final pending = await LocalSyncDao(db).findPending('user_1');

    expect(pending, hasLength(1));
    expect(pending.single.entityType, CloudDataEntity.song);
    expect(pending.single.entityId, original.id);
    expect(pending.single.operation, SyncOutboxOperation.upsert);
  });
}

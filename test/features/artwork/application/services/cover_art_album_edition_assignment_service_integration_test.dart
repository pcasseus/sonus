import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/artwork/application/services/cover_art_album_edition_assignment_service.dart';
import 'package:sonus_next/features/artwork/data/daos/artwork_asset_dao.dart';
import 'package:sonus_next/features/artwork/domain/entities/artwork_asset_factory.dart';
import 'package:sonus_next/features/library/data/daos/album_dao.dart';
import 'package:sonus_next/features/library/data/daos/album_edition_dao.dart';
import 'package:sonus_next/features/library/data/daos/artist_dao.dart';
import 'package:sonus_next/features/library/data/daos/metadata_field_state_dao.dart';
import 'package:sonus_next/features/library/domain/entities/album.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/domain/entities/artist.dart';
import 'package:sonus_next/features/library/domain/metadata/metadata_field_state.dart';
import 'package:sonus_next/features/library/domain/metadata/metadata_fields.dart';
import 'package:sonus_next/features/library/domain/services/metadata_authority_policy.dart';
import 'package:sonus_next/features/sync/application/services/sync_mutation_runner.dart';
import 'package:sonus_next/features/sync/data/daos/local_sync_dao.dart';
import 'package:sonus_next/features/sync/data/repositories/sync_mutation_transaction_runner.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase database;
  late CoverArtAlbumEditionAssignmentService service;

  final originalTime = DateTime.utc(2026, 10, 9, 8);
  final appliedTime = DateTime.utc(2026, 10, 9, 9);

  const editionId = 'edition_caa_test';
  const reference = 'coverartarchive:release:test-release-id';
  const managedPath = r'C:\Sonus\artwork\cover_caa.png';

  setUp(() async {
    database = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );

    service = CoverArtAlbumEditionAssignmentService(
      mutationRunner: SyncMutationTransactionRunner(appDatabase: database),
    );

    final db = await database.database;

    await ArtistDao(db).insert(
      Artist(
        id: 'artist_caa_test',
        name: 'CAA Artist',
        canonicalName: 'caa artist',
        createdAt: originalTime,
        updatedAt: originalTime,
      ),
    );

    await AlbumDao(db).insert(
      Album(
        id: 'album_caa_test',
        artistId: 'artist_caa_test',
        title: 'CAA Album',
        canonicalTitle: 'caa album',
        createdAt: originalTime,
        updatedAt: originalTime,
      ),
    );

    await AlbumEditionDao(db).insert(
      AlbumEdition(
        id: editionId,
        albumId: 'album_caa_test',
        title: 'CAA Album',
        type: AlbumEditionType.standard,
        isPrimary: true,
        createdAt: originalTime,
        updatedAt: originalTime,
      ),
    );
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> setExistingArtwork(MetadataAuthority? authority) async {
    final db = await database.database;
    final edition = (await AlbumEditionDao(db).findById(editionId))!;

    final existingArtwork = ArtworkAssetFactory.create(
      filePath: r'C:\Sonus\artwork\existing.png',
      now: originalTime,
    ).copyWith(id: 'artwork_existing');

    await ArtworkAssetDao(db).insert(existingArtwork);

    await AlbumEditionDao(
      db,
    ).update(edition.copyWith(artworkId: 'artwork_existing'));

    if (authority != null) {
      await MetadataFieldStateDao(db).upsert(
        MetadataFieldState(
          entityType: MetadataEntityType.albumEdition,
          entityId: editionId,
          fieldName: MetadataFields.editionArtwork,
          authority: authority,
          source: MetadataProvenanceSource.legacy,
          updatedAt: originalTime,
        ),
      );
    }
  }

  test('assigns external CAA artwork to an empty album edition', () async {
    final result = await service.assignManagedArtwork(
      albumEditionId: editionId,
      managedFilePath: managedPath,
      sourceReference: reference,
      now: appliedTime,
    );

    final db = await database.database;
    final edition = await AlbumEditionDao(db).findById(editionId);
    final state = await MetadataFieldStateDao(db).find(
      entityType: MetadataEntityType.albumEdition,
      entityId: editionId,
      fieldName: MetadataFields.editionArtwork,
    );

    expect(result.applied, isTrue);
    expect(result.changed, isTrue);
    expect(result.artworkId, isNotNull);
    expect(edition!.artworkId, result.artworkId);
    expect(edition.updatedAt, appliedTime);

    final asset = await ArtworkAssetDao(db).findById(result.artworkId!);
    expect(asset, isNotNull);
    expect(asset!.filePath, managedPath);

    expect(state, isNotNull);
    expect(state!.authority, MetadataAuthority.external);
    expect(state.source, MetadataProvenanceSource.coverArtArchive);
    expect(state.sourceReference, reference);
  });

  test('protects manually selected album artwork', () async {
    await setExistingArtwork(MetadataAuthority.manual);

    final result = await service.assignManagedArtwork(
      albumEditionId: editionId,
      managedFilePath: managedPath,
      sourceReference: reference,
      now: appliedTime,
    );

    final db = await database.database;
    final edition = await AlbumEditionDao(db).findById(editionId);

    expect(result.decision, MetadataReplacementDecision.rejectLowerAuthority);
    expect(result.changed, isFalse);
    expect(edition!.artworkId, 'artwork_existing');
    expect(edition.updatedAt, originalTime);
    expect(await ArtworkAssetDao(db).findAll(), hasLength(1));
  });

  test('requires review for existing artwork with unknown authority', () async {
    await setExistingArtwork(null);

    final result = await service.assignManagedArtwork(
      albumEditionId: editionId,
      managedFilePath: managedPath,
      sourceReference: reference,
      now: appliedTime,
    );

    final db = await database.database;
    final edition = await AlbumEditionDao(db).findById(editionId);

    expect(
      result.decision,
      MetadataReplacementDecision.requireReviewUnknownAuthority,
    );
    expect(result.changed, isFalse);
    expect(edition!.artworkId, 'artwork_existing');
    expect(await ArtworkAssetDao(db).findAll(), hasLength(1));
  });

  test('allows existing imported artwork to be replaced', () async {
    await setExistingArtwork(MetadataAuthority.imported);

    final result = await service.assignManagedArtwork(
      albumEditionId: editionId,
      managedFilePath: managedPath,
      sourceReference: reference,
      now: appliedTime,
    );

    final db = await database.database;
    final edition = await AlbumEditionDao(db).findById(editionId);

    expect(result.applied, isTrue);
    expect(result.changed, isTrue);
    expect(edition!.artworkId, result.artworkId);
  });

  test('protects confirmed artwork', () async {
    await setExistingArtwork(MetadataAuthority.confirmed);

    final result = await service.assignManagedArtwork(
      albumEditionId: editionId,
      managedFilePath: managedPath,
      sourceReference: reference,
      now: appliedTime,
    );

    final db = await database.database;
    final edition = await AlbumEditionDao(db).findById(editionId);

    expect(result.decision, MetadataReplacementDecision.rejectLowerAuthority);
    expect(result.changed, isFalse);
    expect(edition!.artworkId, 'artwork_existing');
    expect(edition.updatedAt, originalTime);
    expect(await ArtworkAssetDao(db).findAll(), hasLength(1));
  });

  test('preserves intentional manual artwork clearing', () async {
    await setExistingArtwork(MetadataAuthority.manual);

    final db = await database.database;
    final edition = (await AlbumEditionDao(db).findById(editionId))!;

    await AlbumEditionDao(db).update(edition.copyWith(artworkId: null));

    final result = await service.assignManagedArtwork(
      albumEditionId: editionId,
      managedFilePath: managedPath,
      sourceReference: reference,
      now: appliedTime,
    );

    final stored = await AlbumEditionDao(db).findById(editionId);
    final state = await MetadataFieldStateDao(db).find(
      entityType: MetadataEntityType.albumEdition,
      entityId: editionId,
      fieldName: MetadataFields.editionArtwork,
    );

    expect(result.decision, MetadataReplacementDecision.rejectLowerAuthority);
    expect(result.changed, isFalse);
    expect(stored!.artworkId, isNull);
    expect(state!.authority, MetadataAuthority.manual);
    expect(await ArtworkAssetDao(db).findAll(), hasLength(1));
  });

  test('rolls back artwork, edition, and provenance on failure', () async {
    final failingService = CoverArtAlbumEditionAssignmentService(
      mutationRunner: _FailAfterActionRunner(
        SyncMutationTransactionRunner(appDatabase: database),
      ),
    );

    await expectLater(
      failingService.assignManagedArtwork(
        albumEditionId: editionId,
        managedFilePath: managedPath,
        sourceReference: reference,
        now: appliedTime,
      ),
      throwsA(isA<StateError>()),
    );

    final db = await database.database;
    final edition = await AlbumEditionDao(db).findById(editionId);
    final state = await MetadataFieldStateDao(db).find(
      entityType: MetadataEntityType.albumEdition,
      entityId: editionId,
      fieldName: MetadataFields.editionArtwork,
    );

    expect(edition, isNotNull);
    expect(edition!.artworkId, isNull);
    expect(edition.updatedAt, originalTime);
    expect(state, isNull);
    expect(await ArtworkAssetDao(db).findAll(), isEmpty);
  });

  test('records and coalesces CAA sync mutations', () async {
    const userId = 'sync_test_user';

    final first = await service.assignManagedArtwork(
      albumEditionId: editionId,
      managedFilePath: managedPath,
      sourceReference: reference,
      userId: userId,
      now: appliedTime,
    );

    expect(first.changed, isTrue);

    final db = await database.database;
    final outbox = LocalSyncDao(db);

    final firstPending = await outbox.findPending(userId);

    expect(firstPending, hasLength(2));
    expect(
      firstPending
          .map((entry) => '${entry.entityType.name}:${entry.entityId}')
          .toSet(),
      {'artworkAsset:${first.artworkId}', 'albumEdition:$editionId'},
    );

    final second = await service.assignManagedArtwork(
      albumEditionId: editionId,
      managedFilePath: managedPath,
      sourceReference: reference,
      userId: userId,
      now: appliedTime.add(const Duration(hours: 1)),
    );

    expect(second.changed, isFalse);
    expect(second.artworkId, first.artworkId);

    final secondPending = await outbox.findPending(userId);

    expect(secondPending, hasLength(2));
    expect(
      secondPending.map((entry) => entry.id).toSet(),
      firstPending.map((entry) => entry.id).toSet(),
    );
  });

  test('protected artwork does not enqueue CAA sync mutations', () async {
    const userId = 'protected_sync_user';

    await setExistingArtwork(MetadataAuthority.manual);

    final result = await service.assignManagedArtwork(
      albumEditionId: editionId,
      managedFilePath: managedPath,
      sourceReference: reference,
      userId: userId,
      now: appliedTime,
    );

    expect(result.decision, MetadataReplacementDecision.rejectLowerAuthority);

    final db = await database.database;
    expect(await LocalSyncDao(db).findPending(userId), isEmpty);
  });

  test('rollback removes CAA sync mutations', () async {
    const userId = 'rollback_sync_user';

    final failingService = CoverArtAlbumEditionAssignmentService(
      mutationRunner: _FailAfterActionRunner(
        SyncMutationTransactionRunner(appDatabase: database),
      ),
    );

    await expectLater(
      failingService.assignManagedArtwork(
        albumEditionId: editionId,
        managedFilePath: managedPath,
        sourceReference: reference,
        userId: userId,
        now: appliedTime,
      ),
      throwsA(isA<StateError>()),
    );

    final db = await database.database;

    expect(await LocalSyncDao(db).findPending(userId), isEmpty);
    expect(await ArtworkAssetDao(db).findAll(), isEmpty);
    expect((await AlbumEditionDao(db).findById(editionId))!.artworkId, isNull);
    expect(
      await MetadataFieldStateDao(db).find(
        entityType: MetadataEntityType.albumEdition,
        entityId: editionId,
        fieldName: MetadataFields.editionArtwork,
      ),
      isNull,
    );
  });

  test('repeating assignment is a no-op', () async {
    final first = await service.assignManagedArtwork(
      albumEditionId: editionId,
      managedFilePath: managedPath,
      sourceReference: reference,
      now: appliedTime,
    );

    final later = appliedTime.add(const Duration(hours: 1));

    final second = await service.assignManagedArtwork(
      albumEditionId: editionId,
      managedFilePath: managedPath,
      sourceReference: reference,
      now: later,
    );

    final db = await database.database;
    final edition = await AlbumEditionDao(db).findById(editionId);

    expect(second.applied, isTrue);
    expect(second.changed, isFalse);
    expect(second.artworkId, first.artworkId);
    expect(edition!.updatedAt, appliedTime);
    expect(await ArtworkAssetDao(db).findAll(), hasLength(1));
  });
}

class _FailAfterActionRunner implements SyncMutationRunner {
  const _FailAfterActionRunner(this.delegate);

  final SyncMutationRunner delegate;

  @override
  Future<T> run<T>(SyncMutationAction<T> action) {
    return delegate.run<T>((context) async {
      await action(context);
      throw StateError('Forced transaction rollback');
    });
  }
}

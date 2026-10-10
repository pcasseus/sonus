import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/artwork/application/models/cover_art_archive_image.dart';
import 'package:sonus_next/features/artwork/application/services/cover_art_album_edition_assignment_service.dart';
import 'package:sonus_next/features/artwork/application/services/cover_art_album_edition_import_service.dart';
import 'package:sonus_next/features/artwork/application/services/owned_artwork_managed_storage.dart';
import 'package:sonus_next/features/artwork/domain/entities/artwork_asset_factory.dart';
import 'package:sonus_next/features/artwork/data/daos/artwork_asset_dao.dart';
import 'package:sonus_next/features/library/domain/services/metadata_authority_policy.dart';
import 'package:sonus_next/features/artwork/data/services/cover_art_archive/cover_art_archive_binary_transport.dart';
import 'package:sonus_next/features/artwork/data/services/cover_art_archive/cover_art_cancellation.dart';
import 'package:sonus_next/features/artwork/data/services/cover_art_archive/cover_art_archive_downloader.dart';
import 'package:sonus_next/features/artwork/data/services/cover_art_archive/cover_art_image_validator.dart';
import 'package:sonus_next/features/artwork/data/services/cover_art_archive/cover_art_validated_download_service.dart';
import 'package:sonus_next/features/artwork/data/services/file_system_artwork_managed_storage.dart';
import 'package:sonus_next/features/library/data/daos/album_dao.dart';
import 'package:sonus_next/features/library/data/daos/album_edition_dao.dart';
import 'package:sonus_next/features/library/data/daos/artist_dao.dart';
import 'package:sonus_next/features/library/data/daos/metadata_field_state_dao.dart';
import 'package:sonus_next/features/library/domain/entities/album.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/domain/entities/artist.dart';
import 'package:sonus_next/features/library/domain/metadata/metadata_field_state.dart';
import 'package:sonus_next/features/library/domain/metadata/metadata_fields.dart';
import 'package:sonus_next/features/sync/data/repositories/sync_mutation_transaction_runner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory root;
  late AppDatabase database;
  late _FixtureTransport transport;
  late CoverArtAlbumEditionImportService service;

  const editionId = 'edition_caa_import';
  final timestamp = DateTime.utc(2026, 10, 9, 12);

  const candidate = CoverArtArchiveImage(
    entity: CoverArtArchiveEntity.release,
    entityId: 'test-release-id',
    imageUrl: 'https://coverartarchive.org/release/test-release-id/front',
    front: true,
    back: false,
  );

  setUp(() async {
    root = await Directory.systemTemp.createTemp('sonus_caa_import_');

    database = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );

    final db = await database.database;

    await ArtistDao(db).insert(
      Artist(
        id: 'artist_caa_import',
        name: 'CAA Import Artist',
        canonicalName: 'caa import artist',
        createdAt: timestamp,
        updatedAt: timestamp,
      ),
    );

    await AlbumDao(db).insert(
      Album(
        id: 'album_caa_import',
        artistId: 'artist_caa_import',
        title: 'CAA Import Album',
        canonicalTitle: 'caa import album',
        createdAt: timestamp,
        updatedAt: timestamp,
      ),
    );

    await AlbumEditionDao(db).insert(
      AlbumEdition(
        id: editionId,
        albumId: 'album_caa_import',
        title: 'CAA Import Album',
        type: AlbumEditionType.standard,
        isPrimary: true,
        createdAt: timestamp,
        updatedAt: timestamp,
      ),
    );

    transport = _FixtureTransport();

    service = CoverArtAlbumEditionImportService(
      downloadService: CoverArtValidatedDownloadService(
        downloader: CoverArtArchiveDownloader(
          transport: transport,
          userAgent: 'Sonus/1.0 (integration test)',
          temporaryDirectoryProvider: () async =>
              Directory(path.join(root.path, 'downloads'))
                ..createSync(recursive: true),
        ),
        validator: const CoverArtImageValidator(),
      ),
      managedStorage: FileSystemArtworkManagedStorage(
        applicationSupportDirectoryProvider: () async =>
            Directory(path.join(root.path, 'support')),
        uuid: const Uuid(),
      ),
      assignmentService: CoverArtAlbumEditionAssignmentService(
        mutationRunner: SyncMutationTransactionRunner(appDatabase: database),
      ),
    );
  });

  tearDown(() async {
    await database.close();

    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  test('manual artwork precheck skips download', () async {
    final db = await database.database;
    final manualPath = path.join(root.path, 'protected_cover.png');

    final existing = ArtworkAssetFactory.create(
      filePath: manualPath,
      now: timestamp,
    ).copyWith(id: 'protected_cover');

    await File(manualPath).writeAsBytes([11, 22, 33]);
    await ArtworkAssetDao(db).insert(existing);

    final edition = (await AlbumEditionDao(db).findById(editionId))!;
    await AlbumEditionDao(db).update(
      edition.copyWith(artworkId: existing.id),
    );

    await MetadataFieldStateDao(db).upsert(
      MetadataFieldState(
        entityType: MetadataEntityType.albumEdition,
        entityId: editionId,
        fieldName: MetadataFields.editionArtwork,
        authority: MetadataAuthority.manual,
        source: MetadataProvenanceSource.legacy,
        updatedAt: timestamp,
      ),
    );

    final result = await service.importImage(
      albumEditionId: editionId,
      image: candidate,
    );

    expect(
      result.decision,
      MetadataReplacementDecision.rejectLowerAuthority,
    );
    expect(result.applied, isFalse);
    expect(result.changed, isFalse);
    expect(result.artworkId, existing.id);
    expect(transport.requestCount, 0);

    final preserved = (await AlbumEditionDao(db).findById(editionId))!;
    expect(preserved.artworkId, existing.id);
    expect(await File(manualPath).readAsBytes(), [11, 22, 33]);

    expect(
      await Directory(path.join(root.path, 'downloads')).exists(),
      isFalse,
    );
    expect(
      await Directory(
        path.join(root.path, 'support', 'sonus', 'artwork'),
      ).exists(),
      isFalse,
    );

    expect(await ArtworkAssetDao(db).findAll(), hasLength(1));
    expect(await db.query('sync_outbox'), isEmpty);
  });

  test('manual-clear tombstone precheck skips download', () async {
    final db = await database.database;

    final editionBefore = (await AlbumEditionDao(db).findById(editionId))!;
    expect(editionBefore.artworkId, isNull);

    await MetadataFieldStateDao(db).upsert(
      MetadataFieldState(
        entityType: MetadataEntityType.albumEdition,
        entityId: editionId,
        fieldName: MetadataFields.editionArtwork,
        authority: MetadataAuthority.manual,
        source: MetadataProvenanceSource.legacy,
        updatedAt: timestamp,
      ),
    );

    final result = await service.importImage(
      albumEditionId: editionId,
      image: candidate,
    );

    expect(
      result.decision,
      MetadataReplacementDecision.rejectLowerAuthority,
    );
    expect(result.applied, isFalse);
    expect(result.changed, isFalse);
    expect(result.artworkId, isNull);
    expect(transport.requestCount, 0);

    final editionAfter = (await AlbumEditionDao(db).findById(editionId))!;
    expect(editionAfter.artworkId, isNull);

    final state = await MetadataFieldStateDao(db).find(
      entityType: MetadataEntityType.albumEdition,
      entityId: editionId,
      fieldName: MetadataFields.editionArtwork,
    );
    expect(state!.authority, MetadataAuthority.manual);

    expect(
      await Directory(path.join(root.path, 'downloads')).exists(),
      isFalse,
    );
    expect(
      await Directory(
        path.join(root.path, 'support', 'sonus', 'artwork'),
      ).exists(),
      isFalse,
    );

    expect(await ArtworkAssetDao(db).findAll(), isEmpty);
    expect(await db.query('sync_outbox'), isEmpty);
  });

  test('pre-cancelled import creates no artwork', () async {
    final token = CoverArtCancellationToken()..cancel();

    await expectLater(
      service.importImage(
        albumEditionId: editionId,
        image: candidate,
        cancellationToken: token,
      ),
      throwsA(isA<CoverArtCancelledException>()),
    );

    expect(transport.requestCount, 0);

    final edition = await AlbumEditionDao(
      await database.database,
    ).findById(editionId);

    expect(edition!.artworkId, isNull);

    expect(
      await Directory(
        path.join(root.path, 'support', 'sonus', 'artwork'),
      ).exists(),
      isFalse,
    );
  });

  test('invalid image is cleaned without assignment', () async {
    transport.bytes = const [137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 0];

    await expectLater(
      service.importImage(albumEditionId: editionId, image: candidate),
      throwsA(isA<CoverArtImageValidationException>()),
    );

    expect(transport.requestCount, 1);

    final edition = await AlbumEditionDao(
      await database.database,
    ).findById(editionId);

    expect(edition!.artworkId, isNull);

    final downloads = Directory(path.join(root.path, 'downloads'));

    expect(await downloads.list().toList(), isEmpty);

    expect(
      await Directory(
        path.join(root.path, 'support', 'sonus', 'artwork'),
      ).exists(),
      isFalse,
    );
  });

  test('manual artwork change during download rejects CAA cover', () async {
    transport.bytes = await _createValidPng();

    final db = await database.database;

    transport.beforeResponse = () async {
      final existing = ArtworkAssetFactory.create(
        filePath: path.join(root.path, 'existing_user_cover.png'),
        now: timestamp,
      ).copyWith(id: 'user_artwork');

      await File(existing.filePath).writeAsBytes([4, 5, 6]);
      await ArtworkAssetDao(db).insert(existing);

      final edition = (await AlbumEditionDao(db).findById(editionId))!;

      await AlbumEditionDao(
        db,
      ).update(edition.copyWith(artworkId: existing.id));

      await MetadataFieldStateDao(db).upsert(
        MetadataFieldState(
          entityType: MetadataEntityType.albumEdition,
          entityId: editionId,
          fieldName: MetadataFields.editionArtwork,
          authority: MetadataAuthority.manual,
          source: MetadataProvenanceSource.legacy,
          updatedAt: timestamp,
        ),
      );
    };

    final result = await service.importImage(
      albumEditionId: editionId,
      image: candidate,
    );

    expect(result.decision, MetadataReplacementDecision.rejectLowerAuthority);
    expect(result.changed, isFalse);
    expect(transport.requestCount, 1);

    final edition = (await AlbumEditionDao(db).findById(editionId))!;
    expect(edition.artworkId, 'user_artwork');

    expect(
      await File(path.join(root.path, 'existing_user_cover.png')).readAsBytes(),
      [4, 5, 6],
    );

    final managed = Directory(
      path.join(root.path, 'support', 'sonus', 'artwork'),
    );
    expect(await managed.list().toList(), isEmpty);

    final downloads = Directory(path.join(root.path, 'downloads'));
    expect(await downloads.list().toList(), isEmpty);
    expect(await ArtworkAssetDao(db).findAll(), hasLength(1));
  });

  test('database assignment failure cleans up imported files', () async {
    final png = await _createValidPng();
    transport.bytes = png;

    await expectLater(
      service.importImage(
        albumEditionId: 'edition_that_does_not_exist',
        image: candidate,
      ),
      throwsA(isA<StateError>()),
    );

    expect(transport.requestCount, 0);

    final managedDirectory = Directory(
      path.join(root.path, 'support', 'sonus', 'artwork'),
    );

    expect(await managedDirectory.exists(), isFalse);

    final downloads = Directory(path.join(root.path, 'downloads'));
    expect(await downloads.exists(), isFalse);

    final db = await database.database;
    final edition = await AlbumEditionDao(db).findById(editionId);

    expect(edition!.artworkId, isNull);

    final assets = await db.query('artwork_assets');
    expect(assets, isEmpty);

    final pending = await db.query('sync_outbox');
    expect(pending, isEmpty);
  });

  test('cancellation after managed copy discards artwork', () async {
    transport.bytes = await _createValidPng();
    final token = CoverArtCancellationToken();

    final cancellingService = CoverArtAlbumEditionImportService(
      downloadService: service.downloadService,
      managedStorage: _CancelAfterCopyStorage(
        delegate: service.managedStorage,
        token: token,
      ),
      assignmentService: service.assignmentService,
    );

    await expectLater(
      cancellingService.importImage(
        albumEditionId: editionId,
        image: candidate,
        cancellationToken: token,
      ),
      throwsA(isA<CoverArtCancelledException>()),
    );

    expect(token.isCancelled, isTrue);
    expect(transport.requestCount, 1);

    final db = await database.database;
    final edition = (await AlbumEditionDao(db).findById(editionId))!;

    expect(edition.artworkId, isNull);
    expect(await db.query('artwork_assets'), isEmpty);
    expect(await db.query('sync_outbox'), isEmpty);

    final managed = Directory(
      path.join(root.path, 'support', 'sonus', 'artwork'),
    );

    expect(await managed.exists(), isTrue);
    expect(await managed.list().toList(), isEmpty);

    final downloads = Directory(path.join(root.path, 'downloads'));
    expect(await downloads.list().toList(), isEmpty);
  });

  test('cleanup retries a failed discard after rejection', () async {
    transport.bytes = await _createValidPng();

    final db = await database.database;

    transport.beforeResponse = () async {
      final existing = ArtworkAssetFactory.create(
        filePath: path.join(root.path, 'manual_cover.png'),
        now: timestamp,
      ).copyWith(id: 'manual_cover');

      await File(existing.filePath).writeAsBytes([1, 2, 3]);
      await ArtworkAssetDao(db).insert(existing);

      final edition = (await AlbumEditionDao(db).findById(editionId))!;

      await AlbumEditionDao(
        db,
      ).update(edition.copyWith(artworkId: existing.id));

      await MetadataFieldStateDao(db).upsert(
        MetadataFieldState(
          entityType: MetadataEntityType.albumEdition,
          entityId: editionId,
          fieldName: MetadataFields.editionArtwork,
          authority: MetadataAuthority.manual,
          source: MetadataProvenanceSource.legacy,
          updatedAt: timestamp,
        ),
      );
    };

    final failingStorage = _FailOnceDiscardStorage(
      delegate: service.managedStorage,
    );

    final rejectingService = CoverArtAlbumEditionImportService(
      downloadService: service.downloadService,
      managedStorage: failingStorage,
      assignmentService: service.assignmentService,
    );

    await expectLater(
      rejectingService.importImage(albumEditionId: editionId, image: candidate),
      throwsA(isA<StateError>()),
    );

    expect(failingStorage.discardAttempts, 2);

    final managed = Directory(
      path.join(root.path, 'support', 'sonus', 'artwork'),
    );

    expect(await managed.list().toList(), isEmpty);

    final downloads = Directory(path.join(root.path, 'downloads'));
    expect(await downloads.list().toList(), isEmpty);

    final preserved = (await AlbumEditionDao(db).findById(editionId))!;
    expect(preserved.artworkId, 'manual_cover');
    expect(await File(path.join(root.path, 'manual_cover.png')).readAsBytes(), [
      1,
      2,
      3,
    ]);
  });

  test('successful CAA import retains only managed artwork', () async {
    final png = await _createValidPng();
    transport.bytes = png;

    final result = await service.importImage(
      albumEditionId: editionId,
      image: candidate,
      now: timestamp.add(const Duration(hours: 1)),
    );

    expect(result.applied, isTrue);
    expect(result.changed, isTrue);
    expect(transport.requestCount, 1);

    final db = await database.database;
    final edition = await AlbumEditionDao(db).findById(editionId);

    expect(edition!.artworkId, result.artworkId);

    final state = await MetadataFieldStateDao(db).find(
      entityType: MetadataEntityType.albumEdition,
      entityId: editionId,
      fieldName: MetadataFields.editionArtwork,
    );

    expect(state!.source, MetadataProvenanceSource.coverArtArchive);
    expect(state.sourceReference, candidate.sourceReference);

    final managedDirectory = Directory(
      path.join(root.path, 'support', 'sonus', 'artwork'),
    );

    final managedFiles = await managedDirectory
        .list()
        .where((entry) => entry is File)
        .toList();

    expect(managedFiles, hasLength(1));
    expect(await File(managedFiles.single.path).readAsBytes(), png);

    final downloads = Directory(path.join(root.path, 'downloads'));
    expect(await downloads.list().toList(), isEmpty);
  });
}

Future<List<int>> _createValidPng() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);

  canvas.drawRect(
    const ui.Rect.fromLTWH(0, 0, 2, 2),
    ui.Paint()..color = const ui.Color(0xFF0099FF),
  );

  final picture = recorder.endRecording();
  final image = await picture.toImage(2, 2);

  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);

    if (data == null) {
      throw StateError('Unable to create PNG test fixture.');
    }

    return data.buffer.asUint8List().toList();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

class _FixtureTransport implements CoverArtBinaryTransport {
  List<int> bytes = const [];
  int requestCount = 0;
  Future<void> Function()? beforeResponse;

  @override
  Future<CoverArtBinaryResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    CoverArtCancellationToken? cancellationToken,
  }) async {
    requestCount++;

    if (beforeResponse != null) {
      await beforeResponse!();
    }

    return CoverArtBinaryResponse(
      statusCode: HttpStatus.ok,
      bytes: Stream<List<int>>.value(bytes),
      contentLength: bytes.length,
      contentType: 'image/png',
    );
  }
}

class _CancelAfterCopyStorage implements OwnedArtworkManagedStorage {
  const _CancelAfterCopyStorage({required this.delegate, required this.token});

  final OwnedArtworkManagedStorage delegate;
  final CoverArtCancellationToken token;

  @override
  Future<OwnedArtworkImport> importOwnedArtwork(String sourceFilePath) async {
    final owned = await delegate.importOwnedArtwork(sourceFilePath);
    token.cancel();
    return owned;
  }
}

class _FailOnceDiscardStorage implements OwnedArtworkManagedStorage {
  _FailOnceDiscardStorage({required this.delegate});

  final OwnedArtworkManagedStorage delegate;
  int discardAttempts = 0;

  @override
  Future<OwnedArtworkImport> importOwnedArtwork(String sourceFilePath) async {
    final owned = await delegate.importOwnedArtwork(sourceFilePath);

    return _FailOnceOwnedImport(
      delegate: owned,
      onAttempt: () => discardAttempts++,
    );
  }
}

class _FailOnceOwnedImport implements OwnedArtworkImport {
  _FailOnceOwnedImport({required this.delegate, required this.onAttempt});

  final OwnedArtworkImport delegate;
  final void Function() onAttempt;
  int attempts = 0;

  @override
  String get filePath => delegate.filePath;

  @override
  Future<void> discard() async {
    attempts++;
    onAttempt();

    if (attempts == 1) {
      throw StateError('Simulated first cleanup failure');
    }

    await delegate.discard();
  }
}

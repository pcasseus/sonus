// SN-45 crop infrastructure over a disposable database, a temporary
// managed-artwork folder and Flutter's real image codecs.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/features/artwork/application/services/artwork_assignment_service.dart';
import 'package:sonus_next/features/artwork/application/services/artwork_crop_renderer.dart';
import 'package:sonus_next/features/artwork/application/services/artwork_crop_service.dart';
import 'package:sonus_next/features/artwork/data/daos/artwork_asset_dao.dart';
import 'package:sonus_next/features/artwork/data/repositories/sqlite_artwork_asset_repository.dart';
import 'package:sonus_next/features/artwork/data/repositories/sqlite_artwork_crop_repository.dart';
import 'package:sonus_next/features/artwork/data/services/file_system_artwork_managed_storage.dart';
import 'package:sonus_next/features/artwork/domain/entities/artwork_crop.dart';
import 'package:sonus_next/features/import/application/services/atomic_library_importer.dart';
import 'package:sonus_next/features/import/domain/models/audio_metadata.dart';
import 'package:sonus_next/features/import/domain/models/import_candidate.dart';
import 'package:sonus_next/features/library/data/daos/album_edition_dao.dart';
import 'package:sonus_next/features/library/data/daos/artist_dao.dart';
import 'package:sonus_next/features/library/data/daos/song_dao.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_album_edition_repository.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_artist_repository.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_song_repository.dart';
import 'package:sonus_next/features/sync/data/repositories/sync_mutation_transaction_runner.dart';

/// A [width] x [height] PNG: the left half red, the right half blue.
Future<Uint8List> twoColourPng(int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width / 2, height.toDouble()),
    ui.Paint()..color = const ui.Color(0xFFFF0000),
  );
  canvas.drawRect(
    ui.Rect.fromLTWH(width / 2, 0, width / 2, height.toDouble()),
    ui.Paint()..color = const ui.Color(0xFF0000FF),
  );
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

/// Size and the centre pixel's RGBA of an encoded image.
Future<(int, int, List<int>)> inspect(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final image = (await codec.getNextFrame()).image;
  final pixels = await image.toByteData();
  final offset = ((image.height ~/ 2) * image.width + image.width ~/ 2) * 4;
  final result = (
    image.width,
    image.height,
    [for (var i = 0; i < 4; i++) pixels!.getUint8(offset + i)],
  );
  image.dispose();
  codec.dispose();
  return result;
}

void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late AppDatabase appDatabase;
  late ArtworkCropService crops;
  late SqliteArtworkCropRepository cropRepository;
  late String editionId;
  late String artistId;
  late String photoPath;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('sonus_crop_');
    appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final now = DateTime.utc(2026, 10, 25);
    final result = await AtomicLibraryImporter(appDatabase: appDatabase).import(
      candidate: ImportCandidate(
        filePath: 'A/locket/x.mp3',
        normalizedPath: 'a/locket/x.mp3',
        discoveredAt: now,
      ),
      metadata: const AudioMetadata(
        title: 'X',
        artistName: 'Madison Beer',
        albumTitle: 'locket',
        durationSeconds: 100,
        trackNumber: 1,
        discNumber: 1,
        isSingle: false,
        featuredArtists: [],
      ),
      now: now,
    );
    final db = await appDatabase.database;
    final song = (await SongDao(db).findById(result.songId!))!;
    editionId = song.albumEditionId;
    artistId = song.artistId;

    final support = Directory(p.join(root.path, 'support'))..createSync();
    final temporary = Directory(p.join(root.path, 'tmp'))..createSync();
    final assets = SqliteArtworkAssetRepository(ArtworkAssetDao(db));
    cropRepository = SqliteArtworkCropRepository(db);
    crops = ArtworkCropService(
      assignment: ArtworkAssignmentService(
        artworkAssetRepository: assets,
        artistRepository: SqliteArtistRepository(ArtistDao(db)),
        albumEditionRepository: SqliteAlbumEditionRepository(
          AlbumEditionDao(db),
        ),
        songRepository: SqliteSongRepository(SongDao(db)),
        artworkManagedStorage: FileSystemArtworkManagedStorage(
          applicationSupportDirectoryProvider: () async => support,
        ),
        mutationRunner: SyncMutationTransactionRunner(appDatabase: appDatabase),
      ),
      crops: cropRepository,
      assets: assets,
      temporaryDirectory: () async => temporary,
    );

    photoPath = p.join(root.path, 'photo.png');
    await File(photoPath).writeAsBytes(await twoColourPng(400, 200));
  });

  tearDown(() async {
    await appDatabase.close();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Future<String?> editionArtworkId() async {
    final db = await appDatabase.database;
    return (await AlbumEditionDao(db).findById(editionId))!.artworkId;
  }

  Future<String> pathOfAsset(String id) async {
    final db = await appDatabase.database;
    return (await ArtworkAssetDao(db).findById(id))!.filePath;
  }

  test('the renderer crops the requested region at the target shape', () async {
    final rightHalf = CropRect(left: 0.5, top: 0, width: 0.5, height: 1);
    final png = await ArtworkCropRenderer.render(
      await File(photoPath).readAsBytes(),
      rightHalf,
      ArtworkCropTarget.albumEdition,
    );

    final (width, height, centre) = await inspect(png);
    // 200x200 of original pixels: never enlarged to the 1200 output size.
    expect((width, height), (200, 200));
    expect(centre.sublist(0, 3), [0, 0, 255]);
  });

  test('a cropped cover is assigned and the original kept', () async {
    final rect = CropRect(left: 0, top: 0, width: 0.5, height: 1);

    await crops.apply(
      target: ArtworkCropTarget.albumEdition,
      targetId: editionId,
      sourcePath: photoPath,
      rect: rect,
    );

    final assigned = (await editionArtworkId())!;
    final (width, height, centre) = await inspect(
      await File(await pathOfAsset(assigned)).readAsBytes(),
    );
    expect((width, height), (200, 200));
    expect(centre.sublist(0, 3), [255, 0, 0]);

    final crop = (await cropRepository.get(
      ArtworkCropTarget.albumEdition,
      editionId,
    ))!;
    expect(crop.outputArtworkId, assigned);
    expect(crop.rect, rect);
    // The original is an untouched managed copy, not the picked file.
    final original = await pathOfAsset(crop.sourceArtworkId);
    expect(original, isNot(photoPath));
    expect(
      await File(original).readAsBytes(),
      await File(photoPath).readAsBytes(),
    );
  });

  test('reposition reopens the original at the saved crop', () async {
    final rect = CropRect(left: 0.25, top: 0, width: 0.5, height: 1);
    await crops.apply(
      target: ArtworkCropTarget.albumEdition,
      targetId: editionId,
      sourcePath: photoPath,
      rect: rect,
    );

    final source = (await crops.repositionSource(
      target: ArtworkCropTarget.albumEdition,
      targetId: editionId,
      currentArtworkId: await editionArtworkId(),
      currentArtworkPath: null,
    ))!;

    expect(source.isRecropping, isTrue);
    expect(source.rect, rect);
    expect(
      await File(source.filePath).readAsBytes(),
      await File(photoPath).readAsBytes(),
    );
  });

  test('re-cropping reuses the original instead of copying it again', () async {
    await crops.apply(
      target: ArtworkCropTarget.albumEdition,
      targetId: editionId,
      sourcePath: photoPath,
      rect: CropRect(left: 0, top: 0, width: 0.5, height: 1),
    );
    final first = (await cropRepository.get(
      ArtworkCropTarget.albumEdition,
      editionId,
    ))!;
    final source = (await crops.repositionSource(
      target: ArtworkCropTarget.albumEdition,
      targetId: editionId,
      currentArtworkId: await editionArtworkId(),
      currentArtworkPath: null,
    ))!;

    await crops.apply(
      target: ArtworkCropTarget.albumEdition,
      targetId: editionId,
      sourcePath: source.filePath,
      rect: CropRect(left: 0.5, top: 0, width: 0.5, height: 1),
    );

    final second = (await cropRepository.get(
      ArtworkCropTarget.albumEdition,
      editionId,
    ))!;
    expect(second.sourceArtworkId, first.sourceArtworkId);
    expect(second.createdAt, first.createdAt);
  });

  test('reset puts the full original back and forgets the crop', () async {
    await crops.apply(
      target: ArtworkCropTarget.albumEdition,
      targetId: editionId,
      sourcePath: photoPath,
      rect: CropRect(left: 0, top: 0, width: 0.5, height: 1),
    );
    final crop = (await cropRepository.get(
      ArtworkCropTarget.albumEdition,
      editionId,
    ))!;

    final reset = await crops.reset(
      target: ArtworkCropTarget.albumEdition,
      targetId: editionId,
      currentArtworkId: await editionArtworkId(),
    );

    expect(reset, isTrue);
    expect(await editionArtworkId(), crop.sourceArtworkId);
    expect(
      await cropRepository.get(ArtworkCropTarget.albumEdition, editionId),
      isNull,
    );
  });

  test('a crop replaced elsewhere no longer applies', () async {
    await crops.apply(
      target: ArtworkCropTarget.albumEdition,
      targetId: editionId,
      sourcePath: photoPath,
      rect: CropRect(left: 0, top: 0, width: 0.5, height: 1),
    );

    expect(
      await crops.currentCrop(
        target: ArtworkCropTarget.albumEdition,
        targetId: editionId,
        currentArtworkId: 'some-newer-cover',
      ),
      isNull,
    );
    expect(
      await crops.reset(
        target: ArtworkCropTarget.albumEdition,
        targetId: editionId,
        currentArtworkId: 'some-newer-cover',
      ),
      isFalse,
    );
  });

  test('artist banner and portrait are cropped independently', () async {
    await crops.apply(
      target: ArtworkCropTarget.artistBanner,
      targetId: artistId,
      sourcePath: photoPath,
      rect: CropRect(left: 0, top: 0, width: 1, height: 0.75),
    );
    await crops.apply(
      target: ArtworkCropTarget.artistPortrait,
      targetId: artistId,
      sourcePath: photoPath,
      rect: CropRect(left: 0.5, top: 0, width: 0.5, height: 1),
    );

    final db = await appDatabase.database;
    final artist = (await ArtistDao(db).findById(artistId))!;
    expect(artist.headerArtworkId, isNotNull);
    expect(artist.topArtistsArtworkId, isNotNull);
    expect(artist.headerArtworkId, isNot(artist.topArtistsArtworkId));

    final (bannerWidth, bannerHeight, _) = await inspect(
      await File(await pathOfAsset(artist.headerArtworkId!)).readAsBytes(),
    );
    expect(bannerWidth / bannerHeight, closeTo(4 / 3, 0.02));
  });

  test(
    'a failed assignment keeps the old artwork and remembers no crop',
    () async {
      await expectLater(
        crops.apply(
          target: ArtworkCropTarget.albumEdition,
          targetId: 'missing-edition',
          sourcePath: photoPath,
          rect: CropRect.full,
        ),
        throwsStateError,
      );

      final db = await appDatabase.database;
      expect(await db.query(DatabaseTables.artworkCrops), isEmpty);
      expect(await editionArtworkId(), isNull);
      // No temporary crop file is left behind.
      expect(Directory(p.join(root.path, 'tmp')).listSync(), isEmpty);
    },
  );
}

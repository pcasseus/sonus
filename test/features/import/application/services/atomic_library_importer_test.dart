import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/import/application/services/atomic_library_importer.dart';
import 'package:sonus_next/features/import/data/daos/import_source_dao.dart';
import 'package:sonus_next/features/import/data/daos/media_file_binding_dao.dart';
import 'package:sonus_next/features/import/data/daos/song_import_review_dao.dart';
import 'package:sonus_next/features/import/domain/entities/import_source.dart';
import 'package:sonus_next/features/import/domain/entities/media_file_binding_factory.dart';
import 'package:sonus_next/features/import/domain/entities/song_import_review.dart';
import 'package:sonus_next/features/import/domain/models/audio_metadata.dart';
import 'package:sonus_next/features/import/domain/models/import_candidate.dart';
import 'package:sonus_next/features/import/domain/models/import_failure.dart';
import 'package:sonus_next/features/import/domain/models/import_result.dart';
import 'package:sonus_next/features/import/domain/models/resolved_metadata.dart';
import 'package:sonus_next/features/library/data/daos/album_dao.dart';
import 'package:sonus_next/features/library/data/daos/album_edition_dao.dart';
import 'package:sonus_next/features/library/data/daos/artist_dao.dart';
import 'package:sonus_next/features/library/data/daos/song_dao.dart';
import 'package:sonus_next/features/library/domain/entities/album.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/domain/entities/artist.dart';
import 'package:sonus_next/features/library/domain/entities/song.dart';
import 'package:sonus_next/features/sync/data/daos/local_sync_dao.dart';
import 'package:sonus_next/features/sync/domain/models/sync_data_contract.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase appDatabase;
  late AtomicLibraryImporter importer;

  final now = DateTime.utc(2026, 9, 10, 12);

  setUp(() {
    appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );

    importer = AtomicLibraryImporter(appDatabase: appDatabase);
  });

  tearDown(() async {
    await appDatabase.close();
  });

  ImportCandidate candidate({
    String filePath = r'C:\Music\Artist Name\Album Name\01 Song Name.mp3',
    String? sourceId,
    ImportCandidateStructure structure = ImportCandidateStructure.singleFile,
  }) {
    return ImportCandidate(
      filePath: filePath,
      normalizedPath: filePath.replaceAll('\\', '/').toLowerCase(),
      discoveredAt: now,
      sourceId: sourceId,
      structure: structure,
    );
  }

  AudioMetadata metadata({
    String artistName = 'Artist Name',
    String? albumArtistName,
    String albumTitle = 'Album Name',
    String title = 'Song Name',
    int durationSeconds = 200,
    int trackNumber = 1,
  }) {
    return AudioMetadata(
      title: title,
      artistName: artistName,
      albumTitle: albumTitle,
      albumArtistName: albumArtistName,
      durationSeconds: durationSeconds,
      trackNumber: trackNumber,
      discNumber: 1,
      isSingle: false,
      featuredArtists: const [],
    );
  }

  test('creates complete library graph and media binding atomically', () async {
    final result = await importer.import(
      candidate: candidate(),
      metadata: metadata(),
      now: now,
    );

    expect(result.status, ImportResultStatus.imported);
    expect(result.songId, isNotNull);

    final db = await appDatabase.database;

    final artists = await ArtistDao(db).findAll();

    expect(artists, hasLength(1));
    expect(artists.single.name, 'Artist Name');

    final albums = await AlbumDao(db).findByArtistId(artists.single.id);

    expect(albums, hasLength(1));
    expect(albums.single.title, 'Album Name');

    final editions = await AlbumEditionDao(db).findByAlbumId(albums.single.id);

    expect(editions, hasLength(1));
    expect(editions.single.isPrimary, isTrue);

    final songs = await SongDao(db).findByEditionId(editions.single.id);

    expect(songs, hasLength(1));
    expect(songs.single.id, result.songId);
    expect(songs.single.title, 'Song Name');

    final bindings = await MediaFileBindingDao(
      db,
    ).findBySongId(songs.single.id);

    expect(bindings, hasLength(1));
    expect(
      bindings.single.normalizedPath,
      'c:/music/artist name/album name/01 song name.mp3',
    );
  });

  test('clean embedded metadata does not create import review', () async {
    final result = await importer.import(
      candidate: candidate(),
      metadata: metadata(),
      metadataSource: MetadataSource.embedded,
      now: now,
    );

    expect(result.status, ImportResultStatus.imported);
    expect(result.songId, isNotNull);

    final db = await appDatabase.database;
    final reviewDao = SongImportReviewDao(db);

    expect(await reviewDao.findBySongId(result.songId!), isNull);
    expect(await reviewDao.countUnresolved(), 0);
  });

  test('mixed metadata creates fallback metadata review', () async {
    final result = await importer.import(
      candidate: candidate(),
      metadata: metadata(),
      metadataSource: MetadataSource.mixed,
      now: now,
    );

    expect(result.status, ImportResultStatus.imported);
    expect(result.songId, isNotNull);

    final db = await appDatabase.database;
    final review = await SongImportReviewDao(db).findBySongId(result.songId!);

    expect(review, isNotNull);
    expect(review!.metadataSource, MetadataSource.mixed);
    expect(review.reasons, [ImportReviewReason.fallbackMetadata]);
    expect(review.needsReview, isTrue);
    expect(review.resolvedAt, isNull);
  });
  test('clean loose album import creates structural review', () async {
    final result = await importer.import(
      candidate: candidate(
        filePath: r'C:\Music\Rags\01 Song Name.mp3',
        structure: ImportCandidateStructure.looseAlbum,
      ),
      metadata: metadata(),
      metadataSource: MetadataSource.embedded,
      now: now,
    );

    expect(result.status, ImportResultStatus.imported);
    expect(result.songId, isNotNull);

    final db = await appDatabase.database;
    final review = await SongImportReviewDao(db).findBySongId(result.songId!);

    expect(review, isNotNull);
    expect(review!.metadataSource, MetadataSource.embedded);
    expect(review.reasons, [ImportReviewReason.looseFolder]);
    expect(review.needsReview, isTrue);
    expect(review.resolvedAt, isNull);
  });
  test(
    'problematic metadata creates review with all derived reasons',
    () async {
      final result = await importer.import(
        candidate: candidate(),
        metadata: metadata(
          artistName: 'Unknown Artist',
          albumTitle: 'Unknown Album',
          trackNumber: 0,
          durationSeconds: 0,
        ),
        metadataSource: MetadataSource.fallback,
        now: now,
      );

      expect(result.status, ImportResultStatus.imported);
      expect(result.songId, isNotNull);

      final db = await appDatabase.database;
      final reviewDao = SongImportReviewDao(db);

      final review = await reviewDao.findBySongId(result.songId!);

      expect(review, isNotNull);
      expect(review!.metadataSource, MetadataSource.fallback);
      expect(review.resolvedAt, isNull);
      expect(review.needsReview, isTrue);
      expect(
        review.reasons,
        containsAll({
          ImportReviewReason.fallbackMetadata,
          ImportReviewReason.unknownArtist,
          ImportReviewReason.unknownAlbum,
          ImportReviewReason.missingTrackNumber,
          ImportReviewReason.missingDuration,
        }),
      );
      expect(review.reasons, hasLength(5));
      expect(await reviewDao.countUnresolved(), 1);
    },
  );
  test('new import persists remembered source id on media binding', () async {
    final db = await appDatabase.database;

    const sourceId = 'import_source_test';

    await ImportSourceDao(db).insert(
      ImportSource(
        id: sourceId,
        rootPath: r'C:\Music',
        normalizedRootPath: 'c:/music',
        createdAt: now,
        updatedAt: now,
      ),
    );

    final result = await importer.import(
      candidate: candidate(sourceId: sourceId),
      metadata: metadata(),
      now: now,
    );

    expect(result.status, ImportResultStatus.imported);
    expect(result.songId, isNotNull);

    final bindings = await MediaFileBindingDao(db).findBySongId(result.songId!);

    expect(bindings, hasLength(1));
    expect(bindings.single.sourceId, sourceId);

    final sourceBindings = await MediaFileBindingDao(
      db,
    ).findBySourceId(sourceId);

    expect(sourceBindings, hasLength(1));
    expect(sourceBindings.single.id, bindings.single.id);
  });
  test('reuses existing artist permanent identity', () async {
    final db = await appDatabase.database;

    final existingArtist = Artist(
      id: 'artist_permanent_existing',
      name: 'Artist Name',
      canonicalName: 'artist name',
      createdAt: now,
      updatedAt: now,
    );

    await ArtistDao(db).insert(existingArtist);

    final result = await importer.import(
      candidate: candidate(),
      metadata: metadata(),
      now: now,
    );

    expect(result.status, ImportResultStatus.imported);

    final artists = await ArtistDao(db).findAll();

    expect(artists, hasLength(1));
    expect(artists.single.id, 'artist_permanent_existing');

    final albums = await AlbumDao(db).findByArtistId(existingArtist.id);

    expect(albums, hasLength(1));
  });

  test('same normalized file path is skipped without duplication', () async {
    final first = await importer.import(
      candidate: candidate(),
      metadata: metadata(),
      now: now,
    );

    final second = await importer.import(
      candidate: candidate(
        filePath: r'C:\MUSIC\ARTIST NAME\ALBUM NAME\01 SONG NAME.MP3',
      ),
      metadata: metadata(),
      now: now,
    );

    expect(first.status, ImportResultStatus.imported);
    expect(second.status, ImportResultStatus.skipped);
    expect(second.songId, first.songId);

    final db = await appDatabase.database;

    final artists = await ArtistDao(db).findAll();

    expect(artists, hasLength(1));

    final albums = await AlbumDao(db).findByArtistId(artists.single.id);

    final editions = await AlbumEditionDao(db).findByAlbumId(albums.single.id);

    final songs = await SongDao(db).findByEditionId(editions.single.id);

    final bindings = await MediaFileBindingDao(
      db,
    ).findBySongId(songs.single.id);

    expect(albums, hasLength(1));
    expect(editions, hasLength(1));
    expect(songs, hasLength(1));
    expect(bindings, hasLength(1));
  });

  test('ambiguous artist match fails without creating partial graph', () async {
    final db = await appDatabase.database;

    await ArtistDao(db).insert(
      Artist(
        id: 'artist_ambiguous_1',
        name: 'Artist Name',
        canonicalName: 'artist name',
        createdAt: now,
        updatedAt: now,
      ),
    );

    await ArtistDao(db).insert(
      Artist(
        id: 'artist_ambiguous_2',
        name: 'ARTIST NAME',
        canonicalName: 'artist name',
        createdAt: now,
        updatedAt: now,
      ),
    );

    final result = await importer.import(
      candidate: candidate(),
      metadata: metadata(),
      now: now,
    );

    expect(result.status, ImportResultStatus.failed);

    final artists = await ArtistDao(db).findAll();

    expect(artists, hasLength(2));

    for (final artist in artists) {
      expect(await AlbumDao(db).findByArtistId(artist.id), isEmpty);
    }
  });

  test(
    'transaction rolls back all earlier writes when final write fails',
    () async {
      final failingImporter = AtomicLibraryImporter(
        appDatabase: appDatabase,
        beforeBindingWrite: () async {
          throw StateError('Forced binding failure');
        },
      );

      final result = await failingImporter.import(
        candidate: candidate(),
        metadata: metadata(
          artistName: 'Unknown Artist',
          albumTitle: 'Unknown Album',
          trackNumber: 0,
          durationSeconds: 0,
        ),
        metadataSource: MetadataSource.fallback,
        now: now,
      );

      expect(result.status, ImportResultStatus.failed);

      final db = await appDatabase.database;

      expect(await ArtistDao(db).findAll(), isEmpty);
      expect(await SongImportReviewDao(db).findUnresolved(), isEmpty);
      expect(await SongImportReviewDao(db).countUnresolved(), 0);
    },
  );
  test(
    'relinks an existing song when its old binding is unavailable',
    () async {
      final firstResult = await importer.import(
        candidate: candidate(),
        metadata: metadata(),
        now: now,
      );

      expect(firstResult.status, ImportResultStatus.imported);

      final originalSongId = firstResult.songId!;
      final db = await appDatabase.database;

      final bindings = await MediaFileBindingDao(
        db,
      ).findBySongId(originalSongId);

      expect(bindings, hasLength(1));

      final originalBinding = bindings.single;

      await MediaFileBindingDao(db).update(
        originalBinding.copyWith(
          isAvailable: false,
          updatedAt: now.add(const Duration(minutes: 1)),
        ),
      );

      final movedCandidate = candidate(
        filePath: r'C:\Moved Music\Artist Name\Album Name\01 Song Name.mp3',
      );

      final result = await importer.import(
        candidate: movedCandidate,
        metadata: metadata(),
        now: now.add(const Duration(minutes: 2)),
      );

      expect(result.status, ImportResultStatus.relinked);
      expect(result.songId, originalSongId);

      final updatedBindings = await MediaFileBindingDao(
        db,
      ).findBySongId(originalSongId);

      expect(updatedBindings, hasLength(1));

      final updatedBinding = updatedBindings.single;

      expect(updatedBinding.id, originalBinding.id);

      expect(updatedBinding.songId, originalSongId);

      expect(
        updatedBinding.normalizedPath,
        'c:/moved music/artist name/album name/01 song name.mp3',
      );

      expect(updatedBinding.isAvailable, isTrue);
    },
  );

  test('reactivates unavailable binding discovered at the same path', () async {
    final firstResult = await importer.import(
      candidate: candidate(),
      metadata: metadata(),
      now: now,
    );

    expect(firstResult.status, ImportResultStatus.imported);

    final songId = firstResult.songId!;
    final db = await appDatabase.database;

    final bindings = await MediaFileBindingDao(db).findBySongId(songId);

    expect(bindings, hasLength(1));

    final originalBinding = bindings.single;

    await MediaFileBindingDao(db).update(
      originalBinding.copyWith(
        isAvailable: false,
        updatedAt: now.add(const Duration(minutes: 1)),
      ),
    );

    final result = await importer.import(
      candidate: candidate(),
      metadata: metadata(),
      now: now.add(const Duration(minutes: 2)),
    );

    expect(result.status, ImportResultStatus.relinked);

    expect(result.songId, songId);

    final updatedBindings = await MediaFileBindingDao(db).findBySongId(songId);

    expect(updatedBindings, hasLength(1));

    expect(updatedBindings.single.id, originalBinding.id);

    expect(updatedBindings.single.isAvailable, isTrue);
  });

  test('does not replace an available binding with a duplicate copy', () async {
    final firstResult = await importer.import(
      candidate: candidate(),
      metadata: metadata(),
      now: now,
    );

    expect(firstResult.status, ImportResultStatus.imported);

    final originalSongId = firstResult.songId!;
    final db = await appDatabase.database;

    final originalBindings = await MediaFileBindingDao(
      db,
    ).findBySongId(originalSongId);

    expect(originalBindings, hasLength(1));

    final originalBinding = originalBindings.single;

    final duplicateCandidate = candidate(
      filePath: r'D:\Duplicate\Artist Name\Album Name\01 Song Name.mp3',
    );

    final result = await importer.import(
      candidate: duplicateCandidate,
      metadata: metadata(),
      now: now.add(const Duration(minutes: 1)),
    );

    expect(result.status, ImportResultStatus.skipped);

    expect(result.songId, originalSongId);

    final bindingsAfterDuplicate = await MediaFileBindingDao(
      db,
    ).findBySongId(originalSongId);

    expect(bindingsAfterDuplicate, hasLength(1));

    expect(bindingsAfterDuplicate.single.id, originalBinding.id);

    expect(
      bindingsAfterDuplicate.single.normalizedPath,
      originalBinding.normalizedPath,
    );
  });

  test('attaches a new binding to an existing unbound song', () async {
    final db = await appDatabase.database;

    final existingArtist = Artist(
      id: 'artist_existing_unbound',
      name: 'Artist Name',
      canonicalName: 'artist name',
      createdAt: now,
      updatedAt: now,
    );

    final existingAlbum = Album(
      id: 'album_existing_unbound',
      artistId: existingArtist.id,
      title: 'Album Name',
      canonicalTitle: 'album name',
      createdAt: now,
      updatedAt: now,
    );

    final existingEdition = AlbumEdition(
      id: 'edition_existing_unbound',
      albumId: existingAlbum.id,
      title: 'Album Name',
      type: AlbumEditionType.standard,
      isPrimary: true,
      createdAt: now,
      updatedAt: now,
    );

    final existingSong = Song(
      id: 'song_existing_unbound',
      artistId: existingArtist.id,
      albumId: existingAlbum.id,
      albumEditionId: existingEdition.id,
      title: 'Song Name',
      canonicalTitle: 'song name',
      trackNumber: 1,
      durationSeconds: 200,
      isSingle: false,
      featuredArtists: const [],
      createdAt: now,
      updatedAt: now,
    );

    await ArtistDao(db).insert(existingArtist);
    await AlbumDao(db).insert(existingAlbum);
    await AlbumEditionDao(db).insert(existingEdition);
    await SongDao(db).insert(existingSong);

    expect(
      await MediaFileBindingDao(db).findBySongId(existingSong.id),
      isEmpty,
    );

    final result = await importer.import(
      candidate: candidate(),
      metadata: metadata(),
      now: now,
    );

    expect(result.status, ImportResultStatus.relinked);

    expect(result.songId, existingSong.id);

    final songs = await SongDao(db).findByEditionId(existingEdition.id);

    expect(songs, hasLength(1));

    expect(songs.single.id, existingSong.id);

    final bindings = await MediaFileBindingDao(
      db,
    ).findBySongId(existingSong.id);

    expect(bindings, hasLength(1));

    expect(bindings.single.songId, existingSong.id);

    expect(bindings.single.isAvailable, isTrue);
  });

  test(
    'multiple unavailable bindings fail instead of guessing which to relink',
    () async {
      final db = await appDatabase.database;

      final existingArtist = Artist(
        id: 'artist_binding_ambiguity',
        name: 'Artist Name',
        canonicalName: 'artist name',
        createdAt: now,
        updatedAt: now,
      );

      final existingAlbum = Album(
        id: 'album_binding_ambiguity',
        artistId: existingArtist.id,
        title: 'Album Name',
        canonicalTitle: 'album name',
        createdAt: now,
        updatedAt: now,
      );

      final existingEdition = AlbumEdition(
        id: 'edition_binding_ambiguity',
        albumId: existingAlbum.id,
        title: 'Album Name',
        type: AlbumEditionType.standard,
        isPrimary: true,
        createdAt: now,
        updatedAt: now,
      );

      final existingSong = Song(
        id: 'song_binding_ambiguity',
        artistId: existingArtist.id,
        albumId: existingAlbum.id,
        albumEditionId: existingEdition.id,
        title: 'Song Name',
        canonicalTitle: 'song name',
        trackNumber: 1,
        durationSeconds: 200,
        isSingle: false,
        featuredArtists: const [],
        createdAt: now,
        updatedAt: now,
      );

      await ArtistDao(db).insert(existingArtist);
      await AlbumDao(db).insert(existingAlbum);
      await AlbumEditionDao(db).insert(existingEdition);
      await SongDao(db).insert(existingSong);

      final firstBinding = MediaFileBindingFactory.create(
        songId: existingSong.id,
        filePath: r'C:\Old Music\Artist Name\Album Name\01 Song Name.mp3',
        isAvailable: false,
        now: now,
      );

      final secondBinding = MediaFileBindingFactory.create(
        songId: existingSong.id,
        filePath: r'D:\Older Music\Artist Name\Album Name\01 Song Name.mp3',
        isAvailable: false,
        now: now,
      );

      await MediaFileBindingDao(db).insert(firstBinding);
      await MediaFileBindingDao(db).insert(secondBinding);

      final result = await importer.import(
        candidate: candidate(
          filePath: r'E:\New Music\Artist Name\Album Name\01 Song Name.mp3',
        ),
        metadata: metadata(),
        now: now.add(const Duration(minutes: 1)),
      );

      expect(result.status, ImportResultStatus.failed);

      expect(result.songId, existingSong.id);

      expect(result.failure?.type, ImportFailureType.ambiguousFileBinding);

      final bindings = await MediaFileBindingDao(
        db,
      ).findBySongId(existingSong.id);

      expect(bindings, hasLength(2));

      expect(bindings.every((binding) => !binding.isAvailable), isTrue);
    },
  );

  test(
    'different track artists share one album through album artist metadata',
    () async {
      final first = await importer.import(
        candidate: candidate(filePath: r'C:\Music\Rags\01 Track One.mp3'),
        metadata: metadata(
          artistName: 'Track Artist One',
          albumArtistName: 'Original Cast',
          albumTitle: 'Rags',
          title: 'Track One',
          trackNumber: 1,
        ),
        now: now,
      );

      final second = await importer.import(
        candidate: candidate(filePath: r'C:\Music\Rags\02 Track Two.mp3'),
        metadata: metadata(
          artistName: 'Track Artist Two',
          albumArtistName: 'Original Cast',
          albumTitle: 'Rags',
          title: 'Track Two',
          trackNumber: 2,
        ),
        now: now.add(const Duration(seconds: 1)),
      );

      expect(first.status, ImportResultStatus.imported);
      expect(second.status, ImportResultStatus.imported);

      final db = await appDatabase.database;
      final artists = await ArtistDao(db).findAll();

      expect(artists, hasLength(3));

      final albumArtist = artists.singleWhere(
        (artist) => artist.name == 'Original Cast',
      );
      final firstTrackArtist = artists.singleWhere(
        (artist) => artist.name == 'Track Artist One',
      );
      final secondTrackArtist = artists.singleWhere(
        (artist) => artist.name == 'Track Artist Two',
      );

      final albums = await AlbumDao(db).findByArtistId(albumArtist.id);

      expect(albums, hasLength(1));
      expect(albums.single.title, 'Rags');

      expect(await AlbumDao(db).findByArtistId(firstTrackArtist.id), isEmpty);
      expect(await AlbumDao(db).findByArtistId(secondTrackArtist.id), isEmpty);

      final editions = await AlbumEditionDao(
        db,
      ).findByAlbumId(albums.single.id);

      expect(editions, hasLength(1));

      final songs = await SongDao(db).findByEditionId(editions.single.id);

      expect(songs, hasLength(2));

      final firstSong = songs.singleWhere((song) => song.title == 'Track One');
      final secondSong = songs.singleWhere((song) => song.title == 'Track Two');

      expect(firstSong.artistId, firstTrackArtist.id);
      expect(secondSong.artistId, secondTrackArtist.id);

      expect(firstSong.albumId, albums.single.id);
      expect(secondSong.albumId, albums.single.id);

      expect(firstSong.albumEditionId, editions.single.id);
      expect(secondSong.albumEditionId, editions.single.id);
    },
  );
  test('signed-in import records newly created cloud entities', () async {
    final signedInImporter = AtomicLibraryImporter(
      appDatabase: appDatabase,
      userId: 'user_1',
    );

    final result = await signedInImporter.import(
      candidate: candidate(),
      metadata: metadata(),
      now: now,
    );

    expect(result.status, ImportResultStatus.imported);

    final db = await appDatabase.database;
    final pending = await LocalSyncDao(db).findPending('user_1');

    expect(pending, hasLength(4));
    expect(pending.map((entry) => entry.entityType).toSet(), {
      CloudDataEntity.artist,
      CloudDataEntity.album,
      CloudDataEntity.albumEdition,
      CloudDataEntity.song,
    });
  });

  test(
    'signed-in import queues only newly created entities when hierarchy exists',
    () async {
      final db = await appDatabase.database;

      final existingArtist = Artist(
        id: 'artist_existing_sync',
        name: 'Artist Name',
        canonicalName: 'artist name',
        createdAt: now,
        updatedAt: now,
      );

      final existingAlbum = Album(
        id: 'album_existing_sync',
        artistId: existingArtist.id,
        title: 'Album Name',
        canonicalTitle: 'album name',
        createdAt: now,
        updatedAt: now,
      );

      final existingEdition = AlbumEdition(
        id: 'edition_existing_sync',
        albumId: existingAlbum.id,
        title: 'Album Name',
        type: AlbumEditionType.standard,
        isPrimary: true,
        createdAt: now,
        updatedAt: now,
      );

      await ArtistDao(db).insert(existingArtist);
      await AlbumDao(db).insert(existingAlbum);
      await AlbumEditionDao(db).insert(existingEdition);

      final signedInImporter = AtomicLibraryImporter(
        appDatabase: appDatabase,
        userId: 'user_1',
      );

      final result = await signedInImporter.import(
        candidate: candidate(
          filePath: r'C:\Music\Artist Name\Album Name\02 Second Song.mp3',
        ),
        metadata: metadata(title: 'Second Song'),
        now: now,
      );

      expect(result.status, ImportResultStatus.imported);
      expect(result.songId, isNotNull);

      final pending = await LocalSyncDao(db).findPending('user_1');

      expect(pending, hasLength(1));
      expect(pending.single.entityType, CloudDataEntity.song);
      expect(pending.single.entityId, result.songId);

      expect(
        pending.any((entry) => entry.entityType == CloudDataEntity.artist),
        isFalse,
      );
      expect(
        pending.any((entry) => entry.entityType == CloudDataEntity.album),
        isFalse,
      );
      expect(
        pending.any(
          (entry) => entry.entityType == CloudDataEntity.albumEdition,
        ),
        isFalse,
      );
    },
  );
  test('local-only import does not create sync outbox entries', () async {
    final result = await importer.import(
      candidate: candidate(),
      metadata: metadata(),
      now: now,
    );

    expect(result.status, ImportResultStatus.imported);

    final db = await appDatabase.database;

    expect(await LocalSyncDao(db).findPending('user_1'), isEmpty);
  });
}

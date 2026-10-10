import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
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
import 'package:sonus_next/features/library/data/daos/album_edition_track_dao.dart';
import 'package:sonus_next/features/library/data/daos/artist_dao.dart';
import 'package:sonus_next/features/library/data/daos/metadata_field_state_dao.dart';
import 'package:sonus_next/features/library/domain/metadata/metadata_field_state.dart';
import 'package:sonus_next/features/library/domain/metadata/metadata_fields.dart';
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
    String? metadataFallbackPath,
    String? sourceId,
    ImportCandidateStructure structure = ImportCandidateStructure.singleFile,
  }) {
    return ImportCandidate(
      filePath: filePath,
      normalizedPath: filePath.replaceAll('\\', '/').toLowerCase(),
      discoveredAt: now,
      metadataFallbackPath: metadataFallbackPath,
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

  test('fresh import creates edition membership', () async {
    final result = await importer.import(
      candidate: candidate(),
      metadata: metadata(trackNumber: 7),
      now: now,
    );

    expect(result.status, ImportResultStatus.imported);
    expect(result.songId, isNotNull);

    final db = await appDatabase.database;
    final songs = await SongDao(db).findAll();
    final editions = await AlbumEditionDao(db).findAll();

    expect(songs, hasLength(1));
    expect(editions, hasLength(1));

    final memberships = await AlbumEditionTrackDao(
      db,
    ).findByEditionId(editions.single.id);

    expect(memberships, hasLength(1));

    final membership = memberships.single;

    expect(membership.songId, result.songId);
    expect(membership.albumEditionId, editions.single.id);
    expect(membership.discNumber, songs.single.discNumber);
    expect(membership.trackNumber, 7);
    expect(membership.sortPosition, 0);
    expect(membership.createdAt, now);
    expect(membership.updatedAt, now);
  });

  test('fresh imports append edition membership sort positions', () async {
    final first = await importer.import(
      candidate: candidate(
        filePath: r'C:\Music\Artist Name\Album Name\01 First Song.mp3',
      ),
      metadata: metadata(title: 'First Song', trackNumber: 1),
      now: now,
    );

    final second = await importer.import(
      candidate: candidate(
        filePath: r'C:\Music\Artist Name\Album Name\02 Second Song.mp3',
      ),
      metadata: metadata(title: 'Second Song', trackNumber: 2),
      now: now.add(const Duration(seconds: 1)),
    );

    expect(first.status, ImportResultStatus.imported);
    expect(second.status, ImportResultStatus.imported);

    final db = await appDatabase.database;
    final editions = await AlbumEditionDao(db).findAll();

    expect(editions, hasLength(1));

    final memberships = await AlbumEditionTrackDao(
      db,
    ).findByEditionId(editions.single.id);

    expect(memberships, hasLength(2));
    expect(memberships.map((membership) => membership.songId), [
      first.songId,
      second.songId,
    ]);
    expect(memberships.map((membership) => membership.sortPosition), [0, 1]);
    expect(memberships.map((membership) => membership.trackNumber), [1, 2]);
  });
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

      final membershipRows = await db.query(DatabaseTables.albumEditionTracks);
      expect(membershipRows, isEmpty);
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
    'matching artist folder preserves punctuation-bearing artist name',
    () async {
      final result = await importer.import(
        candidate: candidate(
          filePath:
              r'C:\Music\Earth, Wind & Fire\Greatest Hits\01 September.mp3',
          metadataFallbackPath:
              r'Earth, Wind & Fire\Greatest Hits\01 September.mp3',
          structure: ImportCandidateStructure.artistAlbum,
        ),
        metadata: metadata(
          artistName: 'Earth, Wind & Fire',
          albumTitle: 'Greatest Hits',
          title: 'September',
        ),
        now: now,
      );

      expect(result.status, ImportResultStatus.imported);
      expect(result.songId, isNotNull);

      final db = await appDatabase.database;
      final artists = await ArtistDao(db).findAll();

      expect(artists, hasLength(1));
      expect(artists.single.name, 'Earth, Wind & Fire');

      final albums = await AlbumDao(db).findByArtistId(artists.single.id);
      expect(albums, hasLength(1));

      final editions = await AlbumEditionDao(
        db,
      ).findByAlbumId(albums.single.id);
      expect(editions, hasLength(1));

      final songs = await SongDao(db).findByEditionId(editions.single.id);

      expect(songs, hasLength(1));
      expect(songs.single.artistId, artists.single.id);
      expect(songs.single.featuredArtists, isEmpty);
    },
  );

  test('artist folder parses explicit feature marker conservatively', () async {
    final result = await importer.import(
      candidate: candidate(
        filePath: r'C:\Music\Megan Thee Stallion\Megan\01 Explicit Feature.mp3',
        metadataFallbackPath:
            r'Megan Thee Stallion\Megan\01 Explicit Feature.mp3',
        structure: ImportCandidateStructure.artistAlbum,
      ),
      metadata: metadata(
        artistName: 'Megan Thee Stallion feat. Cardi B',
        albumTitle: 'Megan',
        title: 'Explicit Feature',
      ),
      now: now,
    );

    expect(result.status, ImportResultStatus.imported);
    expect(result.songId, isNotNull);

    final db = await appDatabase.database;
    final artists = await ArtistDao(db).findAll();

    expect(artists, hasLength(1));
    expect(artists.single.name, 'Megan Thee Stallion');

    final albums = await AlbumDao(db).findByArtistId(artists.single.id);
    expect(albums, hasLength(1));

    final editions = await AlbumEditionDao(db).findByAlbumId(albums.single.id);
    expect(editions, hasLength(1));

    final songs = await SongDao(db).findByEditionId(editions.single.id);

    expect(songs, hasLength(1));
    expect(songs.single.artistId, artists.single.id);
    expect(songs.single.featuredArtists, ['Cardi B']);
  });

  test(
    'artist-folder ambiguous separator credit avoids composite identity and creates review',
    () async {
      final result = await importer.import(
        candidate: candidate(
          filePath: r'C:\Music\Megan Thee Stallion\Megan\01 Collaboration.mp3',
          metadataFallbackPath:
              r'Megan Thee Stallion\Megan\01 Collaboration.mp3',
          structure: ImportCandidateStructure.artistAlbum,
        ),
        metadata: metadata(
          artistName: 'Megan Thee Stallion & Cardi B',
          albumTitle: 'Megan',
          title: 'Collaboration',
        ),
        now: now,
      );

      expect(result.status, ImportResultStatus.imported);
      expect(result.songId, isNotNull);

      final db = await appDatabase.database;
      final artists = await ArtistDao(db).findAll();

      expect(artists, hasLength(1));
      expect(artists.single.name, 'Megan Thee Stallion');

      final albums = await AlbumDao(db).findByArtistId(artists.single.id);

      expect(albums, hasLength(1));
      expect(albums.single.title, 'Megan');

      final editions = await AlbumEditionDao(
        db,
      ).findByAlbumId(albums.single.id);

      expect(editions, hasLength(1));

      final songs = await SongDao(db).findByEditionId(editions.single.id);

      expect(songs, hasLength(1));
      expect(songs.single.artistId, artists.single.id);
      expect(songs.single.featuredArtists, isEmpty);

      final review = await SongImportReviewDao(db).findBySongId(result.songId!);

      expect(review, isNotNull);
      expect(
        review!.reasons,
        contains(ImportReviewReason.ambiguousArtistCredit),
      );
      expect(review.payload?.rawArtistCredit, 'Megan Thee Stallion & Cardi B');
    },
  );

  test(
    'artist-folder album keeps folder owner when track has different performer',
    () async {
      final result = await importer.import(
        candidate: candidate(
          filePath: r'C:\Music\Cheetah Girls\Cheetah Girls\01 Solo Track.mp3',
          metadataFallbackPath:
              r'Cheetah Girls\Cheetah Girls\01 Solo Track.mp3',
          structure: ImportCandidateStructure.artistAlbum,
        ),
        metadata: metadata(
          artistName: 'Adrienne Bailon',
          albumTitle: 'Cheetah Girls',
          title: 'Solo Track',
        ),
        now: now,
      );

      expect(result.status, ImportResultStatus.imported);
      expect(result.songId, isNotNull);

      final db = await appDatabase.database;
      final artists = await ArtistDao(db).findAll();

      expect(artists, hasLength(2));

      final albumArtist = artists.singleWhere(
        (artist) => artist.name == 'Cheetah Girls',
      );
      final trackArtist = artists.singleWhere(
        (artist) => artist.name == 'Adrienne Bailon',
      );

      final albums = await AlbumDao(db).findByArtistId(albumArtist.id);

      expect(albums, hasLength(1));
      expect(albums.single.title, 'Cheetah Girls');
      expect(await AlbumDao(db).findByArtistId(trackArtist.id), isEmpty);

      final editions = await AlbumEditionDao(
        db,
      ).findByAlbumId(albums.single.id);

      expect(editions, hasLength(1));

      final songs = await SongDao(db).findByEditionId(editions.single.id);

      expect(songs, hasLength(1));
      expect(songs.single.artistId, trackArtist.id);
      expect(songs.single.featuredArtists, isEmpty);
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
  test('import strips live suffix into structured version metadata', () async {
    final result = await importer.import(
      candidate: candidate(),
      metadata: metadata(title: 'Song Name (Live)'),
      now: now,
    );

    expect(result.status, ImportResultStatus.imported);

    final db = await appDatabase.database;
    final songs = await SongDao(db).findAll();

    expect(songs, hasLength(1));

    final song = songs.single;

    expect(song.title, 'Song Name');
    expect(song.canonicalTitle, 'song name');
    expect(song.versionLabel, 'Live');
    expect(song.versionCharacteristics, const [SongVersionCharacteristic.live]);
  });

  test('import strips remix suffix into structured version metadata', () async {
    final result = await importer.import(
      candidate: candidate(
        filePath: r'C:\Music\Artist Name\Album Name\02 Song Name Remix.mp3',
      ),
      metadata: metadata(title: 'Song Name [Remix]', trackNumber: 2),
      now: now,
    );

    expect(result.status, ImportResultStatus.imported);

    final db = await appDatabase.database;
    final songs = await SongDao(db).findAll();

    final song = songs.single;

    expect(song.title, 'Song Name');
    expect(song.versionLabel, 'Remix');
    expect(song.versionCharacteristics, const [
      SongVersionCharacteristic.remix,
    ]);
  });

  test('import preserves unrecognized terminal qualifier', () async {
    final result = await importer.import(
      candidate: candidate(),
      metadata: metadata(title: 'Song Name (From The Motion Picture)'),
      now: now,
    );

    expect(result.status, ImportResultStatus.imported);

    final db = await appDatabase.database;
    final songs = await SongDao(db).findAll();

    expect(songs, hasLength(1));

    final song = songs.single;

    expect(song.title, 'Song Name (From The Motion Picture)');
    expect(song.versionLabel, isNull);
    expect(song.versionCharacteristics, isEmpty);
  });

  test('standard and live imports remain separate song identities', () async {
    final standard = await importer.import(
      candidate: candidate(
        filePath: r'C:\Music\Artist Name\Album Name\01 Song Name.mp3',
      ),
      metadata: metadata(title: 'Song Name', trackNumber: 1),
      now: now,
    );

    final live = await importer.import(
      candidate: candidate(
        filePath: r'C:\Music\Artist Name\Album Name\02 Song Name Live.mp3',
      ),
      metadata: metadata(title: 'Song Name (Live)', trackNumber: 2),
      now: now.add(const Duration(seconds: 1)),
    );

    expect(standard.status, ImportResultStatus.imported);
    expect(live.status, ImportResultStatus.imported);
    expect(live.songId, isNot(standard.songId));

    final db = await appDatabase.database;
    final songs = await SongDao(db).findAll();

    expect(songs, hasLength(2));

    final standardSong = songs.singleWhere(
      (song) => song.versionCharacteristics.isEmpty,
    );

    final liveSong = songs.singleWhere(
      (song) =>
          song.versionCharacteristics.contains(SongVersionCharacteristic.live),
    );

    expect(standardSong.title, 'Song Name');
    expect(liveSong.title, 'Song Name');
    expect(standardSong.canonicalTitle, liveSong.canonicalTitle);
    expect(liveSong.versionLabel, 'Live');
  });
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

  test('embedded import records imported embedded-tag provenance', () async {
    final result = await importer.import(
      candidate: candidate(),
      metadata: metadata(),
      metadataOrigins: const ImportMetadataOrigins.all(
        ImportMetadataFieldSource.embedded,
      ),
      now: now,
    );

    expect(result.status, ImportResultStatus.imported);

    final db = await appDatabase.database;

    final artists = await ArtistDao(db).findAll();
    final albums = await AlbumDao(db).findAll();
    final editions = await AlbumEditionDao(db).findAll();
    final songs = await SongDao(db).findAll();

    expect(artists, hasLength(1));
    expect(albums, hasLength(1));
    expect(editions, hasLength(1));
    expect(songs, hasLength(1));

    final artistStates = await MetadataFieldStateDao(db).findByEntity(
      entityType: MetadataEntityType.artist,
      entityId: artists.single.id,
    );

    expect(artistStates, hasLength(1));
    expect(artistStates.single.fieldName, MetadataFields.artistName);
    expect(artistStates.single.authority, MetadataAuthority.imported);
    expect(artistStates.single.source, MetadataProvenanceSource.embeddedTag);

    final albumStates = await MetadataFieldStateDao(db).findByEntity(
      entityType: MetadataEntityType.album,
      entityId: albums.single.id,
    );

    expect(albumStates.map((state) => state.fieldName).toSet(), {
      MetadataFields.albumArtist,
      MetadataFields.albumTitle,
    });

    final editionStates = await MetadataFieldStateDao(db).findByEntity(
      entityType: MetadataEntityType.albumEdition,
      entityId: editions.single.id,
    );

    expect(editionStates.map((state) => state.fieldName).toSet(), {
      MetadataFields.editionTitle,
    });

    final songStates = await MetadataFieldStateDao(db).findByEntity(
      entityType: MetadataEntityType.song,
      entityId: songs.single.id,
    );

    expect(songStates.map((state) => state.fieldName).toSet(), {
      MetadataFields.songArtist,
      MetadataFields.songArtistCredits,
      MetadataFields.songAlbum,
      MetadataFields.songAlbumEdition,
      MetadataFields.songTitle,
      MetadataFields.songTrackNumber,
      MetadataFields.songDiscNumber,
      MetadataFields.songIsSingle,
    });

    expect(
      [...albumStates, ...editionStates, ...songStates].every(
        (state) =>
            state.authority == MetadataAuthority.imported &&
            state.source == MetadataProvenanceSource.embeddedTag &&
            state.updatedAt == now,
      ),
      isTrue,
    );
  });

  test('fallback import records inferred filename provenance', () async {
    final result = await importer.import(
      candidate: candidate(),
      metadata: metadata(),
      metadataSource: MetadataSource.fallback,
      metadataOrigins: const ImportMetadataOrigins.all(
        ImportMetadataFieldSource.fallback,
      ),
      now: now,
    );

    expect(result.status, ImportResultStatus.imported);

    final db = await appDatabase.database;

    final artists = await ArtistDao(db).findAll();
    final albums = await AlbumDao(db).findAll();
    final editions = await AlbumEditionDao(db).findAll();
    final songs = await SongDao(db).findAll();

    final states = <MetadataFieldState>[
      ...await MetadataFieldStateDao(db).findByEntity(
        entityType: MetadataEntityType.artist,
        entityId: artists.single.id,
      ),
      ...await MetadataFieldStateDao(db).findByEntity(
        entityType: MetadataEntityType.album,
        entityId: albums.single.id,
      ),
      ...await MetadataFieldStateDao(db).findByEntity(
        entityType: MetadataEntityType.albumEdition,
        entityId: editions.single.id,
      ),
      ...await MetadataFieldStateDao(db).findByEntity(
        entityType: MetadataEntityType.song,
        entityId: songs.single.id,
      ),
    ];

    expect(states, isNotEmpty);

    expect(
      states.every(
        (state) =>
            state.authority == MetadataAuthority.inferred &&
            state.source == MetadataProvenanceSource.filename &&
            state.updatedAt == now,
      ),
      isTrue,
    );
  });

  test('mixed import preserves per-field provenance', () async {
    final result = await importer.import(
      candidate: candidate(),
      metadata: metadata(),
      metadataSource: MetadataSource.mixed,
      metadataOrigins: const ImportMetadataOrigins(
        title: ImportMetadataFieldSource.fallback,
        artistName: ImportMetadataFieldSource.embedded,
        albumTitle: ImportMetadataFieldSource.embedded,
        albumArtistName: ImportMetadataFieldSource.embedded,
        trackNumber: ImportMetadataFieldSource.fallback,
        discNumber: ImportMetadataFieldSource.embedded,
        isSingle: ImportMetadataFieldSource.embedded,
        featuredArtists: ImportMetadataFieldSource.embedded,
        releaseDate: ImportMetadataFieldSource.fallback,
        genre: ImportMetadataFieldSource.embedded,
      ),
      now: now,
    );

    expect(result.status, ImportResultStatus.imported);

    final db = await appDatabase.database;
    final song = (await SongDao(db).findAll()).single;

    final states = await MetadataFieldStateDao(
      db,
    ).findByEntity(entityType: MetadataEntityType.song, entityId: song.id);

    final byField = {for (final state in states) state.fieldName: state};

    expect(
      byField[MetadataFields.songTitle]!.authority,
      MetadataAuthority.inferred,
    );
    expect(
      byField[MetadataFields.songTitle]!.source,
      MetadataProvenanceSource.filename,
    );

    expect(
      byField[MetadataFields.songTrackNumber]!.authority,
      MetadataAuthority.inferred,
    );
    expect(
      byField[MetadataFields.songTrackNumber]!.source,
      MetadataProvenanceSource.filename,
    );

    for (final fieldName in [
      MetadataFields.songArtist,
      MetadataFields.songArtistCredits,
      MetadataFields.songAlbum,
      MetadataFields.songAlbumEdition,
      MetadataFields.songDiscNumber,
      MetadataFields.songIsSingle,
    ]) {
      expect(
        byField[fieldName]!.authority,
        MetadataAuthority.imported,
        reason: fieldName,
      );
      expect(
        byField[fieldName]!.source,
        MetadataProvenanceSource.embeddedTag,
        reason: fieldName,
      );
    }
  });

  test(
    'folder-normalized artist identity records filename provenance',
    () async {
      final result = await importer.import(
        candidate: candidate(
          filePath:
              r'C:\Music\Megan Thee Stallion\Megan\01 Explicit Feature.mp3',
          metadataFallbackPath:
              r'Megan Thee Stallion\Megan\01 Explicit Feature.mp3',
          structure: ImportCandidateStructure.artistAlbum,
        ),
        metadata: metadata(
          artistName: 'Megan Thee Stallion feat. Cardi B',
          albumTitle: 'Megan',
          title: 'Explicit Feature',
        ),
        metadataOrigins: const ImportMetadataOrigins.all(
          ImportMetadataFieldSource.embedded,
        ),
        now: now,
      );

      expect(result.status, ImportResultStatus.imported);

      final db = await appDatabase.database;
      final songs = await SongDao(db).findAll();

      expect(songs, hasLength(1));

      final song = songs.single;
      final primaryArtist = await ArtistDao(db).findById(song.artistId);

      expect(primaryArtist, isNotNull);
      expect(primaryArtist!.name, 'Megan Thee Stallion');

      final artistStates = await MetadataFieldStateDao(db).findByEntity(
        entityType: MetadataEntityType.artist,
        entityId: primaryArtist.id,
      );

      expect(artistStates, hasLength(1));
      expect(artistStates.single.fieldName, MetadataFields.artistName);
      expect(artistStates.single.authority, MetadataAuthority.inferred);
      expect(artistStates.single.source, MetadataProvenanceSource.filename);

      final songStates = await MetadataFieldStateDao(
        db,
      ).findByEntity(entityType: MetadataEntityType.song, entityId: song.id);

      final byField = {for (final state in songStates) state.fieldName: state};

      expect(
        byField[MetadataFields.songArtist]!.authority,
        MetadataAuthority.inferred,
      );
      expect(
        byField[MetadataFields.songArtist]!.source,
        MetadataProvenanceSource.filename,
      );

      expect(byField.containsKey(MetadataFields.songArtistCredits), isFalse);
    },
  );

  test('reused artist does not receive import provenance', () async {
    final db = await appDatabase.database;

    final existingArtist = Artist(
      id: 'artist_existing_provenance',
      name: 'Artist Name',
      canonicalName: 'artist name',
      createdAt: now,
      updatedAt: now,
    );

    await ArtistDao(db).insert(existingArtist);

    final result = await importer.import(
      candidate: candidate(),
      metadata: metadata(),
      metadataOrigins: const ImportMetadataOrigins.all(
        ImportMetadataFieldSource.embedded,
      ),
      now: now,
    );

    expect(result.status, ImportResultStatus.imported);

    expect(
      await MetadataFieldStateDao(db).findByEntity(
        entityType: MetadataEntityType.artist,
        entityId: existingArtist.id,
      ),
      isEmpty,
    );
  });

  test('relink does not create metadata provenance', () async {
    final first = await importer.import(
      candidate: candidate(),
      metadata: metadata(),
      now: now,
    );

    expect(first.status, ImportResultStatus.imported);

    final db = await appDatabase.database;
    final songId = first.songId!;

    expect(await db.query(DatabaseTables.metadataFieldStates), isEmpty);

    final bindings = await MediaFileBindingDao(db).findBySongId(songId);
    expect(bindings, hasLength(1));

    await MediaFileBindingDao(db).update(
      bindings.single.copyWith(
        isAvailable: false,
        updatedAt: now.add(const Duration(minutes: 1)),
      ),
    );

    final relinked = await importer.import(
      candidate: candidate(),
      metadata: metadata(),
      metadataOrigins: const ImportMetadataOrigins.all(
        ImportMetadataFieldSource.embedded,
      ),
      now: now.add(const Duration(minutes: 2)),
    );

    expect(relinked.status, ImportResultStatus.relinked);
    expect(relinked.songId, songId);

    expect(await db.query(DatabaseTables.metadataFieldStates), isEmpty);
  });
}

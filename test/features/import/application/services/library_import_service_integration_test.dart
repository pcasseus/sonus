import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/import/application/services/atomic_library_importer.dart';
import 'package:sonus_next/features/import/application/services/library_import_service.dart';
import 'package:sonus_next/features/import/application/services/lyrics_ingestion_service.dart';
import 'package:sonus_next/features/import/application/services/metadata_resolver.dart';
import 'package:sonus_next/features/import/data/daos/media_file_binding_dao.dart';
import 'package:sonus_next/features/import/data/daos/song_import_review_dao.dart';
import 'package:sonus_next/features/import/data/repositories/sqlite_media_file_binding_repository.dart';
import 'package:sonus_next/features/import/domain/entities/song_import_review.dart';
import 'package:sonus_next/features/import/domain/models/audio_metadata.dart';
import 'package:sonus_next/features/import/domain/models/import_candidate.dart';
import 'package:sonus_next/features/import/domain/models/import_failure.dart';
import 'package:sonus_next/features/import/domain/models/import_result.dart';
import 'package:sonus_next/features/import/domain/models/resolved_metadata.dart';
import 'package:sonus_next/features/import/domain/services/audio_metadata_reader.dart';
import 'package:sonus_next/features/import/domain/services/lyrics_source_reader.dart';
import 'package:sonus_next/features/library/data/daos/album_dao.dart';
import 'package:sonus_next/features/library/data/daos/album_edition_dao.dart';
import 'package:sonus_next/features/library/data/daos/artist_dao.dart';
import 'package:sonus_next/features/library/data/daos/song_dao.dart';
import 'package:sonus_next/features/player/domain/models/track_lyrics.dart';
import 'package:sonus_next/features/player/domain/repositories/track_lyrics_repository.dart';

class CallbackAudioMetadataReader implements AudioMetadataReader {
  CallbackAudioMetadataReader(this.callback);

  final Future<AudioMetadata> Function(ImportCandidate candidate) callback;

  @override
  Future<AudioMetadata> read(ImportCandidate candidate) {
    return callback(candidate);
  }
}

class CallbackLyricsSourceReader implements LyricsSourceReader {
  CallbackLyricsSourceReader(this.callback);

  final Future<String?> Function(ImportCandidate candidate) callback;

  @override
  Future<String?> read(ImportCandidate candidate) {
    return callback(candidate);
  }
}

class RecordingTrackLyricsRepository implements TrackLyricsRepository {
  int saveCalls = 0;
  String? savedSongId;
  String? savedPlainText;
  String? savedSyncedText;

  @override
  Future<void> deleteBySongId(String songId) async {}

  @override
  Future<TrackLyrics?> getBySongId(String songId) async => null;

  @override
  Future<void> save({
    required String songId,
    String? plainText,
    String? syncedText,
  }) async {
    saveCalls += 1;
    savedSongId = songId;
    savedPlainText = plainText;
    savedSyncedText = syncedText;
  }
}

void main() {
  sqfliteFfiInit();

  late AppDatabase appDatabase;

  final now = DateTime.utc(2026, 9, 10, 12);

  setUp(() {
    appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
  });

  tearDown(() async {
    await appDatabase.close();
  });

  ImportCandidate candidate({
    String filePath = r'C:\Music\Artist Name\Album Name\01 Song Name.mp3',
  }) {
    return ImportCandidate(
      filePath: filePath,
      normalizedPath: filePath.replaceAll('\\', '/').toLowerCase(),
      discoveredAt: now,
    );
  }

  AudioMetadata metadata({
    String title = 'Song Name',
    String artistName = 'Artist Name',
    String albumTitle = 'Album Name',
  }) {
    return AudioMetadata(
      title: title,
      artistName: artistName,
      albumTitle: albumTitle,
      durationSeconds: 200,
      trackNumber: 1,
      discNumber: 1,
      isSingle: false,
      featuredArtists: const [],
    );
  }

  Future<LibraryImportService> buildService({
    required AudioMetadataReader primaryReader,
    required AudioMetadataReader fallbackReader,
    LyricsIngestionService? lyricsIngestionService,
  }) async {
    final db = await appDatabase.database;

    return LibraryImportService(
      metadataResolver: MetadataResolver(
        primaryReader: primaryReader,
        fallbackReader: fallbackReader,
      ),
      atomicImporter: AtomicLibraryImporter(appDatabase: appDatabase),
      mediaFileBindingRepository: SqliteMediaFileBindingRepository(
        MediaFileBindingDao(db),
      ),
      lyricsIngestionService: lyricsIngestionService,
    );
  }

  test('imports candidate through the complete import pipeline', () async {
    final service = await buildService(
      primaryReader: CallbackAudioMetadataReader((_) async => metadata()),
      fallbackReader: CallbackAudioMetadataReader(
        (_) async => throw StateError('Fallback should not run'),
      ),
    );

    final result = await service.importCandidate(candidate(), now: now);

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

    final songs = await SongDao(db).findByEditionId(editions.single.id);

    expect(songs, hasLength(1));
    expect(songs.single.id, result.songId);

    final bindings = await MediaFileBindingDao(
      db,
    ).findBySongId(songs.single.id);

    expect(bindings, hasLength(1));
    expect(bindings.single.isAvailable, isTrue);

    expect(await SongImportReviewDao(db).findBySongId(songs.single.id), isNull);
  });

  test('uses fallback metadata when primary metadata reader fails', () async {
    final service = await buildService(
      primaryReader: CallbackAudioMetadataReader(
        (_) async => throw StateError('Primary metadata failure'),
      ),
      fallbackReader: CallbackAudioMetadataReader(
        (_) async => metadata(
          title: 'Fallback Song',
          artistName: 'Fallback Artist',
          albumTitle: 'Fallback Album',
        ),
      ),
    );

    final result = await service.importCandidate(candidate(), now: now);

    expect(result.status, ImportResultStatus.imported);

    final db = await appDatabase.database;

    final artists = await ArtistDao(db).findAll();

    expect(artists, hasLength(1));
    expect(artists.single.name, 'Fallback Artist');

    final albums = await AlbumDao(db).findByArtistId(artists.single.id);

    expect(albums, hasLength(1));
    expect(albums.single.title, 'Fallback Album');

    final editions = await AlbumEditionDao(db).findByAlbumId(albums.single.id);

    final songs = await SongDao(db).findByEditionId(editions.single.id);

    expect(songs, hasLength(1));
    expect(songs.single.title, 'Fallback Song');
    final review = await SongImportReviewDao(db).findBySongId(songs.single.id);

    expect(review, isNotNull);
    expect(review!.metadataSource, MetadataSource.fallback);
    expect(review.reasons, contains(ImportReviewReason.fallbackMetadata));
  });

  test('metadata failure leaves the database untouched', () async {
    final service = await buildService(
      primaryReader: CallbackAudioMetadataReader(
        (_) async => throw StateError('Primary failed'),
      ),
      fallbackReader: CallbackAudioMetadataReader(
        (_) async => throw StateError('Fallback failed'),
      ),
    );

    final result = await service.importCandidate(candidate(), now: now);

    expect(result.status, ImportResultStatus.failed);
    expect(result.failure?.type, ImportFailureType.metadataUnreadable);

    final db = await appDatabase.database;

    expect(await ArtistDao(db).findAll(), isEmpty);
  });

  test(
    'duplicate candidate is skipped through the complete pipeline',
    () async {
      final service = await buildService(
        primaryReader: CallbackAudioMetadataReader((_) async => metadata()),
        fallbackReader: CallbackAudioMetadataReader(
          (_) async => throw StateError('Fallback should not run'),
        ),
      );

      final first = await service.importCandidate(candidate(), now: now);

      final second = await service.importCandidate(
        candidate(
          filePath: r'C:\MUSIC\ARTIST NAME\ALBUM NAME\01 SONG NAME.MP3',
        ),
        now: now.add(const Duration(minutes: 1)),
      );

      expect(first.status, ImportResultStatus.imported);
      expect(second.status, ImportResultStatus.skipped);
      expect(second.songId, first.songId);

      final db = await appDatabase.database;

      final artists = await ArtistDao(db).findAll();

      expect(artists, hasLength(1));

      final albums = await AlbumDao(db).findByArtistId(artists.single.id);

      final editions = await AlbumEditionDao(
        db,
      ).findByAlbumId(albums.single.id);

      final songs = await SongDao(db).findByEditionId(editions.single.id);

      final bindings = await MediaFileBindingDao(
        db,
      ).findBySongId(songs.single.id);

      expect(albums, hasLength(1));
      expect(editions, hasLength(1));
      expect(songs, hasLength(1));
      expect(bindings, hasLength(1));
    },
  );

  test(
    'known file rescan ingests newly discovered LRC without rereading metadata',
    () async {
      var initialPrimaryReadCount = 0;

      final initialService = await buildService(
        primaryReader: CallbackAudioMetadataReader((_) async {
          initialPrimaryReadCount += 1;
          return metadata();
        }),
        fallbackReader: CallbackAudioMetadataReader(
          (_) async => throw StateError('Fallback should not run'),
        ),
      );

      final originalCandidate = candidate();
      final first = await initialService.importCandidate(
        originalCandidate,
        now: now,
      );

      expect(first.status, ImportResultStatus.imported);
      expect(first.songId, isNotNull);
      expect(initialPrimaryReadCount, 1);

      final lyricsRepository = RecordingTrackLyricsRepository();
      var lyricsReadCount = 0;
      ImportCandidate? lyricsCandidate;

      final rescanService = await buildService(
        primaryReader: CallbackAudioMetadataReader(
          (_) async => throw StateError('Primary metadata should not rerun'),
        ),
        fallbackReader: CallbackAudioMetadataReader(
          (_) async => throw StateError('Fallback metadata should not rerun'),
        ),
        lyricsIngestionService: LyricsIngestionService(
          sourceReader: CallbackLyricsSourceReader((candidate) async {
            lyricsReadCount += 1;
            lyricsCandidate = candidate;
            return '[00:01.00]First line';
          }),
          trackLyricsRepository: lyricsRepository,
        ),
      );

      final rescanAt = now.add(const Duration(minutes: 5));
      final lyricsPath = r'C:\Music\Artist Name\Album Name\01 Song Name.lrc';

      final second = await rescanService.importCandidate(
        originalCandidate.copyWith(
          discoveredAt: rescanAt,
          lyricsPath: lyricsPath,
        ),
        now: rescanAt,
      );

      expect(second.status, ImportResultStatus.skipped);
      expect(second.songId, first.songId);
      expect(initialPrimaryReadCount, 1);

      expect(lyricsReadCount, 1);
      expect(lyricsCandidate, isNotNull);
      expect(lyricsCandidate!.lyricsPath, lyricsPath);

      expect(lyricsRepository.saveCalls, 1);
      expect(lyricsRepository.savedSongId, first.songId);
      expect(lyricsRepository.savedPlainText, isNull);
      expect(lyricsRepository.savedSyncedText, '[00:01.00]First line');
    },
  );
  test(
    'known file rescan preserves edited metadata and import review state',
    () async {
      var primaryReadCount = 0;
      var fallbackReadCount = 0;

      final service = await buildService(
        primaryReader: CallbackAudioMetadataReader((_) async {
          primaryReadCount += 1;
          throw StateError('Force fallback metadata');
        }),
        fallbackReader: CallbackAudioMetadataReader((_) async {
          fallbackReadCount += 1;
          return metadata();
        }),
      );

      final originalCandidate = candidate();

      final first = await service.importCandidate(originalCandidate, now: now);

      expect(first.status, ImportResultStatus.imported);
      expect(first.songId, isNotNull);
      expect(primaryReadCount, 1);
      expect(fallbackReadCount, 1);

      final db = await appDatabase.database;
      final songDao = SongDao(db);
      final reviewDao = SongImportReviewDao(db);

      final importedSong = await songDao.findById(first.songId!);

      expect(importedSong, isNotNull);
      expect(importedSong!.title, 'Song Name');

      final originalReview = await reviewDao.findBySongId(first.songId!);

      expect(originalReview, isNotNull);
      expect(originalReview!.metadataSource, MetadataSource.fallback);
      expect(
        originalReview.reasons,
        contains(ImportReviewReason.fallbackMetadata),
      );
      expect(originalReview.resolvedAt, isNull);
      expect(originalReview.needsReview, isTrue);

      final editedAt = now.add(const Duration(seconds: 30));

      await songDao.update(
        importedSong.copyWith(
          title: 'My Sonus Edit',
          canonicalTitle: 'my sonus edit',
          isBlocked: true,
          updatedAt: editedAt,
        ),
      );

      final resolvedAt = now.add(const Duration(minutes: 1));
      final reviewUpdatedAt = now.add(const Duration(minutes: 2));

      await reviewDao.update(
        originalReview.copyWith(
          resolvedAt: resolvedAt,
          updatedAt: reviewUpdatedAt,
        ),
      );

      final reviewBeforeRescan = await reviewDao.findBySongId(first.songId!);

      expect(reviewBeforeRescan, isNotNull);
      expect(reviewBeforeRescan!.resolvedAt, resolvedAt);
      expect(reviewBeforeRescan.needsReview, isFalse);

      final bindingsBefore = await MediaFileBindingDao(
        db,
      ).findBySongId(first.songId!);

      expect(bindingsBefore, hasLength(1));

      final originalBinding = bindingsBefore.single;
      final rescanAt = now.add(const Duration(minutes: 5));

      final rescannedCandidate = originalCandidate.copyWith(
        discoveredAt: rescanAt,
      );

      final second = await service.importCandidate(
        rescannedCandidate,
        now: rescanAt,
      );

      expect(second.status, ImportResultStatus.skipped);
      expect(second.songId, first.songId);

      expect(primaryReadCount, 1);
      expect(fallbackReadCount, 1);

      final songAfterRescan = await songDao.findById(first.songId!);

      expect(songAfterRescan, isNotNull);
      expect(songAfterRescan!.title, 'My Sonus Edit');
      expect(songAfterRescan.canonicalTitle, 'my sonus edit');
      expect(songAfterRescan.isBlocked, isTrue);
      expect(songAfterRescan.updatedAt, editedAt);

      final reviewAfterRescan = await reviewDao.findBySongId(first.songId!);

      expect(reviewAfterRescan, isNotNull);
      expect(
        reviewAfterRescan!.metadataSource,
        reviewBeforeRescan.metadataSource,
      );
      expect(reviewAfterRescan.reasons, reviewBeforeRescan.reasons);
      expect(reviewAfterRescan.resolvedAt, reviewBeforeRescan.resolvedAt);
      expect(reviewAfterRescan.createdAt, reviewBeforeRescan.createdAt);
      expect(reviewAfterRescan.updatedAt, reviewBeforeRescan.updatedAt);
      expect(reviewAfterRescan.needsReview, isFalse);

      final bindingsAfter = await MediaFileBindingDao(
        db,
      ).findBySongId(first.songId!);

      expect(bindingsAfter, hasLength(1));
      expect(bindingsAfter.single.id, originalBinding.id);
      expect(bindingsAfter.single.songId, first.songId);
      expect(bindingsAfter.single.isAvailable, isTrue);
      expect(bindingsAfter.single.lastSeenAt, rescanAt);
      expect(bindingsAfter.single.sourceId, isNull);
    },
  );
  test('moved file relinks without changing permanent song identity', () async {
    final service = await buildService(
      primaryReader: CallbackAudioMetadataReader((_) async => metadata()),
      fallbackReader: CallbackAudioMetadataReader(
        (_) async => throw StateError('Fallback should not run'),
      ),
    );

    final first = await service.importCandidate(candidate(), now: now);

    expect(first.status, ImportResultStatus.imported);

    final songId = first.songId!;
    final db = await appDatabase.database;

    final originalBindings = await MediaFileBindingDao(db).findBySongId(songId);

    expect(originalBindings, hasLength(1));

    final originalBinding = originalBindings.single;

    await MediaFileBindingDao(db).update(
      originalBinding.copyWith(
        isAvailable: false,
        updatedAt: now.add(const Duration(minutes: 1)),
      ),
    );

    final moved = await service.importCandidate(
      candidate(
        filePath:
            r'D:\Reorganized Music\Artist Name\Album Name\01 Song Name.mp3',
      ),
      now: now.add(const Duration(minutes: 2)),
    );

    expect(moved.status, ImportResultStatus.relinked);
    expect(moved.songId, songId);

    final updatedBindings = await MediaFileBindingDao(db).findBySongId(songId);

    expect(updatedBindings, hasLength(1));
    expect(updatedBindings.single.id, originalBinding.id);
    expect(updatedBindings.single.songId, songId);
    expect(updatedBindings.single.isAvailable, isTrue);
    expect(
      updatedBindings.single.normalizedPath,
      'd:/reorganized music/artist name/album name/01 song name.mp3',
    );
  });
}

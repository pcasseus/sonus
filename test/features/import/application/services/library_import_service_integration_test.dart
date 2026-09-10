import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/import/application/services/atomic_library_importer.dart';
import 'package:sonus_next/features/import/application/services/library_import_service.dart';
import 'package:sonus_next/features/import/application/services/metadata_resolver.dart';
import 'package:sonus_next/features/import/data/daos/media_file_binding_dao.dart';
import 'package:sonus_next/features/import/domain/models/audio_metadata.dart';
import 'package:sonus_next/features/import/domain/models/import_candidate.dart';
import 'package:sonus_next/features/import/domain/models/import_failure.dart';
import 'package:sonus_next/features/import/domain/models/import_result.dart';
import 'package:sonus_next/features/import/domain/services/audio_metadata_reader.dart';
import 'package:sonus_next/features/library/data/daos/album_dao.dart';
import 'package:sonus_next/features/library/data/daos/album_edition_dao.dart';
import 'package:sonus_next/features/library/data/daos/artist_dao.dart';
import 'package:sonus_next/features/library/data/daos/song_dao.dart';

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

  LibraryImportService buildService({
    required AudioMetadataReader primaryReader,
    required AudioMetadataReader fallbackReader,
  }) {
    return LibraryImportService(
      metadataResolver: MetadataResolver(
        primaryReader: primaryReader,
        fallbackReader: fallbackReader,
      ),
      atomicImporter: AtomicLibraryImporter(appDatabase: appDatabase),
    );
  }

  test('imports candidate through the complete import pipeline', () async {
    final service = buildService(
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
  });

  test('uses fallback metadata when primary metadata reader fails', () async {
    final service = buildService(
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
  });

  test('metadata failure leaves the database untouched', () async {
    final service = buildService(
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
      final service = buildService(
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

  test('moved file relinks without changing permanent song identity', () async {
    final service = buildService(
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

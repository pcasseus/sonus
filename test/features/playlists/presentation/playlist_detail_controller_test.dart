import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/features/import/data/daos/media_file_binding_dao.dart';
import 'package:sonus_next/features/import/domain/entities/media_file_binding.dart';
import 'package:sonus_next/features/library/data/daos/library_query_dao.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_library_query_repository.dart';
import 'package:sonus_next/features/playlists/application/services/playlist_service.dart';
import 'package:sonus_next/features/playlists/data/daos/playlist_dao.dart';
import 'package:sonus_next/features/playlists/data/repositories/sqlite_playlist_repository.dart';
import 'package:sonus_next/features/playlists/presentation/controllers/playlist_detail_controller.dart';
import 'package:sonus_next/features/sync/data/repositories/sync_mutation_transaction_runner.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase appDatabase;
  late SqlitePlaylistRepository playlistRepository;
  late PlaylistService service;

  final now = DateTime.utc(2026, 9, 30, 12);

  setUp(() async {
    appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );

    final db = await appDatabase.database;

    playlistRepository = SqlitePlaylistRepository(PlaylistDao(db));

    service = PlaylistService(
      repository: playlistRepository,
      library: SqliteLibraryQueryRepository(LibraryQueryDao(db)),
      mutationRunner: SyncMutationTransactionRunner(appDatabase: appDatabase),
      generatePlaylistId: () => 'playlist_test',
      generatePlaylistItemId: () {
        throw StateError('Use explicit item generators per test.');
      },
      now: () => now,
    );
  });

  tearDown(() async {
    await appDatabase.close();
  });

  test(
    'reorderVisible reorders visible songs while preserving hidden membership slot',
    () async {
      await _seedSongs(
        appDatabase,
        now: now,
        songIds: const ['song_1', 'song_2', 'song_3'],
        availableSongIds: const {'song_1', 'song_3'},
      );

      var itemCounter = 0;

      service = PlaylistService(
        repository: playlistRepository,
        library: SqliteLibraryQueryRepository(
          LibraryQueryDao(await appDatabase.database),
        ),
        mutationRunner: SyncMutationTransactionRunner(appDatabase: appDatabase),
        generatePlaylistId: () => 'playlist_test',
        generatePlaylistItemId: () => 'item_${++itemCounter}',
        now: () => now,
      );

      final playlist = await service.createPlaylist(name: 'Ghost Reorder');

      await service.addSong(playlistId: playlist.id, songId: 'song_1');
      await service.addSong(playlistId: playlist.id, songId: 'song_2');
      await service.addSong(playlistId: playlist.id, songId: 'song_3');

      final controller = PlaylistDetailController(
        service: service,
        playlistId: playlist.id,
      );

      await controller.load();

      expect(controller.tracks, hasLength(3));

      expect(
        controller.tracks
            .where((entry) => controller.isTrackVisible(entry.track))
            .map((entry) => entry.track.songId),
        ['song_1', 'song_3'],
      );

      expect(controller.isTrackVisible(controller.tracks[1].track), isFalse);

      final changed = await controller.reorderVisible(oldIndex: 1, newIndex: 0);

      expect(changed, isTrue);

      final persisted = await playlistRepository.getItems(playlist.id);

      expect(persisted.map((item) => item.songId), [
        'song_3',
        'song_2',
        'song_1',
      ]);

      expect(persisted.map((item) => item.position), [0, 1, 2]);

      expect(controller.tracks.map((entry) => entry.track.songId), [
        'song_3',
        'song_2',
        'song_1',
      ]);

      expect(
        controller.tracks
            .where((entry) => controller.isTrackVisible(entry.track))
            .map((entry) => entry.track.songId),
        ['song_3', 'song_1'],
      );

      controller.dispose();
    },
  );
}

Future<void> _seedSongs(
  AppDatabase appDatabase, {
  required DateTime now,
  required List<String> songIds,
  required Set<String> availableSongIds,
}) async {
  final db = await appDatabase.database;
  final timestamp = now.toIso8601String();

  await db.insert(DatabaseTables.artists, {
    'id': 'artist_playlist_controller',
    'name': 'Playlist Artist',
    'canonical_name': 'playlist artist',
    'created_at': timestamp,
    'updated_at': timestamp,
  });

  await db.insert(DatabaseTables.albums, {
    'id': 'album_playlist_controller',
    'artist_id': 'artist_playlist_controller',
    'title': 'Playlist Album',
    'canonical_title': 'playlist album',
    'created_at': timestamp,
    'updated_at': timestamp,
  });

  await db.insert(DatabaseTables.albumEditions, {
    'id': 'edition_playlist_controller',
    'album_id': 'album_playlist_controller',
    'title': 'Playlist Album',
    'type': 'standard',
    'is_primary': 1,
    'created_at': timestamp,
    'updated_at': timestamp,
  });

  final bindingDao = MediaFileBindingDao(db);

  for (var index = 0; index < songIds.length; index++) {
    final songId = songIds[index];

    await db.insert(DatabaseTables.songs, {
      'id': songId,
      'artist_id': 'artist_playlist_controller',
      'album_id': 'album_playlist_controller',
      'album_edition_id': 'edition_playlist_controller',
      'title': 'Song ${index + 1}',
      'canonical_title': 'song ${index + 1}',
      'track_number': index + 1,
      'disc_number': 1,
      'duration_seconds': 180,
      'is_single': 0,
      'is_blocked': 0,
      'featured_artists': '[]',
      'created_at': timestamp,
      'updated_at': timestamp,
    });

    if (availableSongIds.contains(songId)) {
      await bindingDao.insert(
        MediaFileBinding(
          id: 'media_$songId',
          songId: songId,
          filePath: 'C:\\Music\\$songId.mp3',
          normalizedPath: 'c:/music/$songId.mp3',
          isAvailable: true,
          lastSeenAt: now,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
  }
}

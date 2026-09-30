import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/features/library/data/daos/library_query_dao.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_library_query_repository.dart';
import 'package:sonus_next/features/playlists/application/services/playlist_service.dart';
import 'package:sonus_next/features/playlists/data/daos/playlist_dao.dart';
import 'package:sonus_next/features/playlists/data/repositories/sqlite_playlist_repository.dart';
import 'package:sonus_next/features/sync/data/repositories/sync_mutation_transaction_runner.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase appDatabase;
  late PlaylistService service;
  late SqlitePlaylistRepository playlistRepository;

  final now = DateTime.utc(2026, 9, 29, 12);

  var playlistIdCounter = 0;
  var playlistItemIdCounter = 0;

  setUp(() async {
    playlistIdCounter = 0;
    playlistItemIdCounter = 0;

    appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );

    final db = await appDatabase.database;

    playlistRepository = SqlitePlaylistRepository(PlaylistDao(db));

    final libraryRepository = SqliteLibraryQueryRepository(LibraryQueryDao(db));

    service = PlaylistService(
      repository: playlistRepository,
      library: libraryRepository,
      mutationRunner: SyncMutationTransactionRunner(appDatabase: appDatabase),
      generatePlaylistId: () {
        playlistIdCounter++;
        return 'playlist_generated_$playlistIdCounter';
      },
      generatePlaylistItemId: () {
        playlistItemIdCounter++;
        return 'playlist_item_generated_$playlistItemIdCounter';
      },
      now: () => now,
    );
  });

  tearDown(() async {
    await appDatabase.close();
  });

  Future<void> seedSongs(
    List<String> songIds, {
    Set<String> blockedSongIds = const {},
  }) async {
    final db = await appDatabase.database;
    final timestamp = now.toIso8601String();

    await db.insert(DatabaseTables.artists, {
      'id': 'artist_playlist_service',
      'name': 'Playlist Service Artist',
      'canonical_name': 'playlist service artist',
      'created_at': timestamp,
      'updated_at': timestamp,
    });

    await db.insert(DatabaseTables.albums, {
      'id': 'album_playlist_service',
      'artist_id': 'artist_playlist_service',
      'title': 'Playlist Service Album',
      'canonical_title': 'playlist service album',
      'created_at': timestamp,
      'updated_at': timestamp,
    });

    await db.insert(DatabaseTables.albumEditions, {
      'id': 'edition_playlist_service',
      'album_id': 'album_playlist_service',
      'title': 'Playlist Service Album',
      'type': 'standard',
      'is_primary': 1,
      'created_at': timestamp,
      'updated_at': timestamp,
    });

    for (var index = 0; index < songIds.length; index++) {
      final songId = songIds[index];

      await db.insert(DatabaseTables.songs, {
        'id': songId,
        'artist_id': 'artist_playlist_service',
        'album_id': 'album_playlist_service',
        'album_edition_id': 'edition_playlist_service',
        'title': 'Song ${index + 1}',
        'canonical_title': 'song ${index + 1}',
        'track_number': index + 1,
        'disc_number': 1,
        'duration_seconds': 180,
        'is_single': 0,
        'is_blocked': blockedSongIds.contains(songId) ? 1 : 0,
        'featured_artists': '[]',
        'created_at': timestamp,
        'updated_at': timestamp,
      });
    }
  }

  Future<void> seedMediaBinding(String songId, {bool available = true}) async {
    final db = await appDatabase.database;
    final timestamp = now.toIso8601String();
    final normalizedSongId = songId.toLowerCase();

    await db.insert(DatabaseTables.mediaFileBindings, {
      'id': 'binding_$songId',
      'song_id': songId,
      'file_path': 'C:/Music/$songId.mp3',
      'normalized_path': 'c:/music/$normalizedSongId.mp3',
      'is_available': available ? 1 : 0,
      'created_at': timestamp,
      'updated_at': timestamp,
    });
  }

  test(
    'creates, renames, and deletes playlist without account identity',
    () async {
      final playlist = await service.createPlaylist(name: '  Favorites  ');

      expect(playlist.id, 'playlist_generated_1');
      expect(playlist.name, 'Favorites');
      expect(playlist.createdAt, now);
      expect(playlist.updatedAt, now);

      final renamed = await service.renamePlaylist(
        playlistId: playlist.id,
        name: 'Road Trip',
        now: now.add(const Duration(hours: 1)),
      );

      expect(renamed.id, playlist.id);
      expect(renamed.name, 'Road Trip');
      expect(renamed.updatedAt, now.add(const Duration(hours: 1)));

      await service.deletePlaylist(playlist.id);

      expect(await playlistRepository.getById(playlist.id), isNull);
    },
  );

  test('rejects blank playlist names', () async {
    expect(() => service.createPlaylist(name: '   '), throwsArgumentError);
  });

  test(
    'adds song idempotently and hydrates current library metadata',
    () async {
      await seedSongs(['song_1'], blockedSongIds: {'song_1'});

      final playlist = await service.createPlaylist(name: 'Blocked Songs');

      final first = await service.addSong(
        playlistId: playlist.id,
        songId: 'song_1',
      );

      final second = await service.addSong(
        playlistId: playlist.id,
        songId: 'song_1',
      );

      expect(second.id, first.id);

      final items = await playlistRepository.getItems(playlist.id);

      expect(items, hasLength(1));
      expect(items.single.songId, 'song_1');
      expect(items.single.position, 0);

      final detail = await service.getPlaylist(playlist.id);

      expect(detail.trackCount, 1);
      expect(detail.tracks.single.item.id, first.id);
      expect(detail.tracks.single.track.songId, 'song_1');
      expect(detail.tracks.single.track.title, 'Song 1');
      expect(detail.tracks.single.track.isBlocked, isTrue);
      expect(detail.tracks.single.track.isAvailable, isFalse);
    },
  );

  test('playlist detail reflects later library metadata changes', () async {
    await seedSongs(['song_1']);

    final playlist = await service.createPlaylist(name: 'Current Metadata');

    await service.addSong(playlistId: playlist.id, songId: 'song_1');

    final db = await appDatabase.database;

    await db.update(
      DatabaseTables.songs,
      {
        'title': 'Renamed Song',
        'canonical_title': 'renamed song',
        'updated_at': now.add(const Duration(hours: 2)).toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: ['song_1'],
    );

    final detail = await service.getPlaylist(playlist.id);

    expect(detail.tracks.single.track.title, 'Renamed Song');
  });

  test('appends songs using stable manual positions', () async {
    await seedSongs(['song_1', 'song_2', 'song_3']);

    final playlist = await service.createPlaylist(name: 'Ordered');

    final first = await service.addSong(
      playlistId: playlist.id,
      songId: 'song_1',
    );

    final second = await service.addSong(
      playlistId: playlist.id,
      songId: 'song_2',
    );

    final third = await service.addSong(
      playlistId: playlist.id,
      songId: 'song_3',
    );

    expect(first.position, 0);
    expect(second.position, 1);
    expect(third.position, 2);
  });

  test('removing middle song compacts remaining positions', () async {
    await seedSongs(['song_1', 'song_2', 'song_3']);

    final playlist = await service.createPlaylist(name: 'Compact');

    await service.addSong(playlistId: playlist.id, songId: 'song_1');

    await service.addSong(playlistId: playlist.id, songId: 'song_2');

    await service.addSong(playlistId: playlist.id, songId: 'song_3');

    final removed = await service.removeSong(
      playlistId: playlist.id,
      songId: 'song_2',
      now: now.add(const Duration(hours: 1)),
    );

    expect(removed, isTrue);

    final items = await playlistRepository.getItems(playlist.id);

    expect(items.map((item) => item.songId), ['song_1', 'song_3']);

    expect(items.map((item) => item.position), [0, 1]);
  });

  test('removing absent song is an idempotent no-op', () async {
    await seedSongs(['song_1']);

    final playlist = await service.createPlaylist(name: 'No Op');

    final removed = await service.removeSong(
      playlistId: playlist.id,
      songId: 'song_1',
    );

    expect(removed, isFalse);
  });

  test('reorders complete playlist membership', () async {
    await seedSongs(['song_1', 'song_2', 'song_3']);

    final playlist = await service.createPlaylist(name: 'Reorder');

    final first = await service.addSong(
      playlistId: playlist.id,
      songId: 'song_1',
    );

    final second = await service.addSong(
      playlistId: playlist.id,
      songId: 'song_2',
    );

    final third = await service.addSong(
      playlistId: playlist.id,
      songId: 'song_3',
    );

    final reordered = await service.reorderItems(
      playlistId: playlist.id,
      orderedItemIds: [third.id, first.id, second.id],
      now: now.add(const Duration(hours: 1)),
    );

    expect(reordered.map((item) => item.songId), [
      'song_3',
      'song_1',
      'song_2',
    ]);

    expect(reordered.map((item) => item.position), [0, 1, 2]);

    final persisted = await playlistRepository.getItems(playlist.id);

    expect(persisted.map((item) => item.songId), [
      'song_3',
      'song_1',
      'song_2',
    ]);
  });

  test('rejects incomplete or duplicate reorder requests', () async {
    await seedSongs(['song_1', 'song_2']);

    final playlist = await service.createPlaylist(name: 'Validation');

    final first = await service.addSong(
      playlistId: playlist.id,
      songId: 'song_1',
    );

    final second = await service.addSong(
      playlistId: playlist.id,
      songId: 'song_2',
    );

    await expectLater(
      service.reorderItems(playlistId: playlist.id, orderedItemIds: [first.id]),
      throwsArgumentError,
    );

    expect(
      () => service.reorderItems(
        playlistId: playlist.id,
        orderedItemIds: [first.id, first.id],
      ),
      throwsArgumentError,
    );

    expect(second.id, isNot(first.id));
  });

  test(
    'playlist summaries count current visible tracks without mutating membership',
    () async {
      await seedSongs(
        ['song_1', 'song_2', 'song_3'],
        blockedSongIds: {'song_3'},
      );

      await seedMediaBinding('song_1');
      await seedMediaBinding('song_2', available: false);
      await seedMediaBinding('song_3');

      final empty = await service.createPlaylist(name: 'Empty');
      final populated = await service.createPlaylist(name: 'Populated');

      await service.addSong(playlistId: populated.id, songId: 'song_1');

      await service.addSong(playlistId: populated.id, songId: 'song_2');

      await service.addSong(playlistId: populated.id, songId: 'song_3');

      final summaries = await service.getPlaylists();

      final byId = {
        for (final summary in summaries) summary.playlist.id: summary,
      };

      expect(byId[empty.id]?.trackCount, 0);

      // song_1 is available, song_2 is unavailable, and song_3 is
      // blocked but still available/currently visible.
      expect(byId[populated.id]?.trackCount, 2);

      // Availability only affects presentation count. Membership survives.
      final items = await playlistRepository.getItems(populated.id);

      expect(items, hasLength(3));
      expect(items.map((item) => item.songId), ['song_1', 'song_2', 'song_3']);
    },
  );

  test('rejects adding nonexistent song', () async {
    final playlist = await service.createPlaylist(name: 'Missing Song');

    await expectLater(
      service.addSong(playlistId: playlist.id, songId: 'song_missing'),
      throwsStateError,
    );

    expect(await playlistRepository.getItems(playlist.id), isEmpty);
  });
}

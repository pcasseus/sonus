import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/features/playlists/data/daos/playlist_dao.dart';
import 'package:sonus_next/features/playlists/data/repositories/sqlite_playlist_repository.dart';
import 'package:sonus_next/features/playlists/domain/entities/playlist.dart';
import 'package:sonus_next/features/playlists/domain/entities/playlist_item.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase appDatabase;

  final now = DateTime.utc(2026, 9, 29, 12);

  setUp(() {
    appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
  });

  tearDown(() async {
    await appDatabase.close();
  });

  Future<void> createSong(Database db) async {
    final timestamp = now.toIso8601String();

    await db.insert(DatabaseTables.artists, {
      'id': 'artist_playlist_repo',
      'name': 'Repository Artist',
      'canonical_name': 'repository artist',
      'created_at': timestamp,
      'updated_at': timestamp,
    });

    await db.insert(DatabaseTables.albums, {
      'id': 'album_playlist_repo',
      'artist_id': 'artist_playlist_repo',
      'title': 'Repository Album',
      'canonical_title': 'repository album',
      'created_at': timestamp,
      'updated_at': timestamp,
    });

    await db.insert(DatabaseTables.albumEditions, {
      'id': 'edition_playlist_repo',
      'album_id': 'album_playlist_repo',
      'title': 'Repository Album',
      'type': 'standard',
      'is_primary': 1,
      'created_at': timestamp,
      'updated_at': timestamp,
    });

    await db.insert(DatabaseTables.songs, {
      'id': 'song_playlist_repo',
      'artist_id': 'artist_playlist_repo',
      'album_id': 'album_playlist_repo',
      'album_edition_id': 'edition_playlist_repo',
      'title': 'Repository Song',
      'canonical_title': 'repository song',
      'track_number': 1,
      'disc_number': 1,
      'duration_seconds': 210,
      'is_single': 0,
      'featured_artists': '[]',
      'created_at': timestamp,
      'updated_at': timestamp,
    });
  }

  test('repository persists playlist and ordered membership', () async {
    final db = await appDatabase.database;
    final repository = SqlitePlaylistRepository(PlaylistDao(db));

    await createSong(db);

    final playlist = Playlist(
      id: 'playlist_repo',
      name: 'Repository Playlist',
      createdAt: now,
      updatedAt: now,
    );

    final item = PlaylistItem(
      id: 'playlist_item_repo',
      playlistId: playlist.id,
      songId: 'song_playlist_repo',
      position: 0,
      createdAt: now,
      updatedAt: now,
    );

    await repository.create(playlist);
    await repository.addItem(item);

    expect(await repository.getById(playlist.id), playlist);
    expect(await repository.getItems(playlist.id), [item]);
    expect(await repository.getItemById(item.id), item);
  });

  test('repository saves playlist and item while preserving ids', () async {
    final db = await appDatabase.database;
    final repository = SqlitePlaylistRepository(PlaylistDao(db));

    await createSong(db);

    final playlist = Playlist(
      id: 'playlist_repo_save',
      name: 'Old Name',
      createdAt: now,
      updatedAt: now,
    );

    final item = PlaylistItem(
      id: 'playlist_item_repo_save',
      playlistId: playlist.id,
      songId: 'song_playlist_repo',
      position: 0,
      createdAt: now,
      updatedAt: now,
    );

    await repository.create(playlist);
    await repository.addItem(item);

    final renamed = playlist.copyWith(
      name: 'New Name',
      updatedAt: now.add(const Duration(hours: 1)),
    );

    final moved = item.copyWith(
      position: 5,
      updatedAt: now.add(const Duration(hours: 1)),
    );

    await repository.save(renamed);
    await repository.saveItem(moved);

    final restoredPlaylist = await repository.getById(playlist.id);
    final restoredItem = await repository.getItemById(item.id);

    expect(restoredPlaylist?.id, playlist.id);
    expect(restoredPlaylist?.name, 'New Name');

    expect(restoredItem?.id, item.id);
    expect(restoredItem?.position, 5);
  });

  test('repository removes playlist item and playlist', () async {
    final db = await appDatabase.database;
    final repository = SqlitePlaylistRepository(PlaylistDao(db));

    await createSong(db);

    final playlist = Playlist(
      id: 'playlist_repo_delete',
      name: 'Delete Me',
      createdAt: now,
      updatedAt: now,
    );

    final item = PlaylistItem(
      id: 'playlist_item_repo_delete',
      playlistId: playlist.id,
      songId: 'song_playlist_repo',
      position: 0,
      createdAt: now,
      updatedAt: now,
    );

    await repository.create(playlist);
    await repository.addItem(item);

    await repository.removeItem(item.id);

    expect(await repository.getItemById(item.id), isNull);

    await repository.delete(playlist.id);

    expect(await repository.getById(playlist.id), isNull);
  });
}

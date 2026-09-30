import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/features/playlists/data/daos/playlist_dao.dart';
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

  Future<void> createLibrarySongs(Database db, List<String> songIds) async {
    final timestamp = now.toIso8601String();

    await db.insert(DatabaseTables.artists, {
      'id': 'artist_playlist_dao',
      'name': 'Playlist Artist',
      'canonical_name': 'playlist artist',
      'created_at': timestamp,
      'updated_at': timestamp,
    });

    await db.insert(DatabaseTables.albums, {
      'id': 'album_playlist_dao',
      'artist_id': 'artist_playlist_dao',
      'title': 'Playlist Album',
      'canonical_title': 'playlist album',
      'created_at': timestamp,
      'updated_at': timestamp,
    });

    await db.insert(DatabaseTables.albumEditions, {
      'id': 'edition_playlist_dao',
      'album_id': 'album_playlist_dao',
      'title': 'Playlist Album',
      'type': 'standard',
      'is_primary': 1,
      'created_at': timestamp,
      'updated_at': timestamp,
    });

    for (var index = 0; index < songIds.length; index++) {
      await db.insert(DatabaseTables.songs, {
        'id': songIds[index],
        'artist_id': 'artist_playlist_dao',
        'album_id': 'album_playlist_dao',
        'album_edition_id': 'edition_playlist_dao',
        'title': 'Song ${index + 1}',
        'canonical_title': 'song ${index + 1}',
        'track_number': index + 1,
        'disc_number': 1,
        'duration_seconds': 180,
        'is_single': 0,
        'featured_artists': '[]',
        'created_at': timestamp,
        'updated_at': timestamp,
      });
    }
  }

  test('persists, updates, and loads playlist', () async {
    final db = await appDatabase.database;
    final dao = PlaylistDao(db);

    final playlist = Playlist(
      id: 'playlist_dao',
      name: 'Original Playlist',
      createdAt: now,
      updatedAt: now,
    );

    await dao.insertPlaylist(playlist);

    expect(await dao.findPlaylistById(playlist.id), playlist);

    final renamed = playlist.copyWith(
      name: 'Renamed Playlist',
      updatedAt: now.add(const Duration(hours: 1)),
    );

    await dao.updatePlaylist(renamed);

    final restored = await dao.findPlaylistById(playlist.id);

    expect(restored?.id, playlist.id);
    expect(restored?.name, 'Renamed Playlist');
    expect(restored?.updatedAt, now.add(const Duration(hours: 1)));
  });

  test('loads playlists in deterministic name order', () async {
    final db = await appDatabase.database;
    final dao = PlaylistDao(db);

    await dao.insertPlaylist(
      Playlist(id: 'playlist_z', name: 'Zulu', createdAt: now, updatedAt: now),
    );

    await dao.insertPlaylist(
      Playlist(id: 'playlist_a', name: 'alpha', createdAt: now, updatedAt: now),
    );

    final playlists = await dao.findPlaylists();

    expect(playlists.map((playlist) => playlist.id), [
      'playlist_a',
      'playlist_z',
    ]);
  });

  test('persists playlist items in manual position order', () async {
    final db = await appDatabase.database;
    final dao = PlaylistDao(db);

    await createLibrarySongs(db, ['song_a', 'song_b']);

    await dao.insertPlaylist(
      Playlist(
        id: 'playlist_items',
        name: 'Items',
        createdAt: now,
        updatedAt: now,
      ),
    );

    final laterItem = PlaylistItem(
      id: 'playlist_item_b',
      playlistId: 'playlist_items',
      songId: 'song_b',
      position: 1,
      createdAt: now,
      updatedAt: now,
    );

    final firstItem = PlaylistItem(
      id: 'playlist_item_a',
      playlistId: 'playlist_items',
      songId: 'song_a',
      position: 0,
      createdAt: now,
      updatedAt: now,
    );

    await dao.insertItem(laterItem);
    await dao.insertItem(firstItem);

    final items = await dao.findItemsByPlaylistId('playlist_items');

    expect(items, [firstItem, laterItem]);
    expect(items.map((item) => item.position), [0, 1]);
  });

  test('updates playlist item position without changing identity', () async {
    final db = await appDatabase.database;
    final dao = PlaylistDao(db);

    await createLibrarySongs(db, ['song_reorder']);

    await dao.insertPlaylist(
      Playlist(
        id: 'playlist_reorder',
        name: 'Reorder',
        createdAt: now,
        updatedAt: now,
      ),
    );

    final item = PlaylistItem(
      id: 'playlist_item_reorder',
      playlistId: 'playlist_reorder',
      songId: 'song_reorder',
      position: 0,
      createdAt: now,
      updatedAt: now,
    );

    await dao.insertItem(item);

    final moved = item.copyWith(
      position: 7,
      updatedAt: now.add(const Duration(minutes: 5)),
    );

    await dao.updateItem(moved);

    final restored = await dao.findItemById(item.id);

    expect(restored?.id, item.id);
    expect(restored?.playlistId, item.playlistId);
    expect(restored?.songId, item.songId);
    expect(restored?.position, 7);
  });

  test('deletes playlist item by permanent item id', () async {
    final db = await appDatabase.database;
    final dao = PlaylistDao(db);

    await createLibrarySongs(db, ['song_remove']);

    await dao.insertPlaylist(
      Playlist(
        id: 'playlist_remove',
        name: 'Remove',
        createdAt: now,
        updatedAt: now,
      ),
    );

    final item = PlaylistItem(
      id: 'playlist_item_remove',
      playlistId: 'playlist_remove',
      songId: 'song_remove',
      position: 0,
      createdAt: now,
      updatedAt: now,
    );

    await dao.insertItem(item);
    await dao.deleteItem(item.id);

    expect(await dao.findItemById(item.id), isNull);
    expect(await dao.findItemsByPlaylistId('playlist_remove'), isEmpty);
  });

  test('throws when updating missing playlist or playlist item', () async {
    final db = await appDatabase.database;
    final dao = PlaylistDao(db);

    await expectLater(
      dao.updatePlaylist(
        Playlist(
          id: 'playlist_missing',
          name: 'Missing',
          createdAt: now,
          updatedAt: now,
        ),
      ),
      throwsA(isA<StateError>()),
    );

    await expectLater(
      dao.updateItem(
        PlaylistItem(
          id: 'playlist_item_missing',
          playlistId: 'playlist_missing',
          songId: 'song_missing',
          position: 0,
          createdAt: now,
          updatedAt: now,
        ),
      ),
      throwsA(isA<StateError>()),
    );
  });
}

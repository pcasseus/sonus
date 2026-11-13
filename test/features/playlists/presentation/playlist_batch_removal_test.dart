// App Update 1.2 patches, Checkpoint 4 (BUG-03): removing several selected
// songs from a playlist at once; the songs stay in the library.
// Disposable databases and fictional fixtures only.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/features/import/data/daos/media_file_binding_dao.dart';
import 'package:sonus_next/features/import/domain/entities/media_file_binding.dart';
import 'package:sonus_next/features/library/application/repositories/library_query_repository.dart';
import 'package:sonus_next/features/library/data/daos/library_query_dao.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_library_query_repository.dart';
import 'package:sonus_next/features/playlists/application/services/playlist_service.dart';
import 'package:sonus_next/features/playlists/data/daos/playlist_dao.dart';
import 'package:sonus_next/features/playlists/data/repositories/sqlite_playlist_repository.dart';
import 'package:sonus_next/features/playlists/presentation/pages/playlist_detail_page.dart';
import 'package:sonus_next/features/sync/data/repositories/sync_mutation_transaction_runner.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase appDatabase;
  late PlaylistService service;
  late Database db;
  final now = DateTime.utc(2026, 11, 8, 12);

  setUp(() async {
    appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfiNoIsolate,
      databasePath: inMemoryDatabasePath,
    );
    db = await appDatabase.database;
    var item = 0;
    service = PlaylistService(
      repository: SqlitePlaylistRepository(PlaylistDao(db)),
      library: SqliteLibraryQueryRepository(LibraryQueryDao(db)),
      mutationRunner: SyncMutationTransactionRunner(appDatabase: appDatabase),
      generatePlaylistId: () => 'playlist_mix',
      generatePlaylistItemId: () => 'item_${++item}',
      now: () => now,
    );
    final stamp = now.toIso8601String();
    await db.insert(DatabaseTables.artists, {
      'id': 'artist_nova',
      'name': 'Nova',
      'canonical_name': 'nova',
      'created_at': stamp,
      'updated_at': stamp,
    });
    await db.insert(DatabaseTables.albums, {
      'id': 'album_nova',
      'artist_id': 'artist_nova',
      'title': 'First Light',
      'canonical_title': 'first light',
      'created_at': stamp,
      'updated_at': stamp,
    });
    await db.insert(DatabaseTables.albumEditions, {
      'id': 'edition_nova',
      'album_id': 'album_nova',
      'title': 'First Light',
      'type': 'standard',
      'is_primary': 1,
      'created_at': stamp,
      'updated_at': stamp,
    });
    for (var index = 0; index < 4; index++) {
      await db.insert(DatabaseTables.songs, {
        'id': 'song_$index',
        'artist_id': 'artist_nova',
        'album_id': 'album_nova',
        'album_edition_id': 'edition_nova',
        'title': 'Song $index',
        'canonical_title': 'song $index',
        'track_number': index + 1,
        'disc_number': 1,
        'duration_seconds': 180,
        'is_single': 0,
        'is_blocked': 0,
        'featured_artists': '[]',
        'created_at': stamp,
        'updated_at': stamp,
      });
      await MediaFileBindingDao(db).insert(
        MediaFileBinding(
          id: 'media_song_$index',
          songId: 'song_$index',
          filePath: '/music/song_$index.mp3',
          normalizedPath: '/music/song_$index.mp3',
          isAvailable: true,
          lastSeenAt: now,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
  });

  tearDown(() => appDatabase.close());

  Future<List<(Object?, Object?)>> items(String playlistId) async => [
    for (final row in await db.query(
      DatabaseTables.playlistItems,
      where: 'playlist_id = ?',
      whereArgs: [playlistId],
      orderBy: 'position',
    ))
      (row['song_id'], row['position']),
  ];

  Future<String> playlistWithFour() async {
    final playlist = await service.createPlaylist(name: 'Mix');
    await service.addSongs(
      playlistId: playlist.id,
      songIds: ['song_0', 'song_1', 'song_2', 'song_3'],
    );
    return playlist.id;
  }

  test('removeSongs removes them in one change, keeps the order of the rest '
      'and renumbers them; the songs stay in the library', () async {
    final id = await playlistWithFour();

    final removed = await service.removeSongs(
      playlistId: id,
      songIds: ['song_2', 'song_0', 'not_in_playlist'],
    );

    expect(removed, 2);
    expect(await items(id), [('song_1', 0), ('song_3', 1)]);
    expect(
      (await db.query(DatabaseTables.songs)).length,
      4,
      reason: 'only the playlist changed',
    );
    expect(await service.removeSongs(playlistId: id, songIds: ['song_0']), 0);
  });

  testWidgets('select songs, Remove from playlist, confirm: they leave the '
      'playlist only; cancelling changes nothing', (tester) async {
    final id = (await tester.runAsync(playlistWithFour))!;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<PlaylistService?>.value(value: service),
          Provider<LibraryQueryRepository?>.value(
            value: SqliteLibraryQueryRepository(LibraryQueryDao(db)),
          ),
        ],
        child: MaterialApp(
          home: PlaylistDetailPage(playlistId: id, initialName: 'Mix'),
        ),
      ),
    );
    Future<void> settle(Finder finder) async {
      for (var i = 0; i < 60 && finder.evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
    }

    final first = find.byKey(const ValueKey<String>('playlist-track-item_1'));
    await settle(first);
    await tester.longPress(first);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('playlist-track-item_3')),
    );
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('track-selection-delete-library')),
      findsNothing,
      reason: 'a playlist only removes from itself',
    );

    final remove = find.byKey(
      const ValueKey<String>('track-selection-remove-playlist'),
    );
    await tester.tap(remove);
    await tester.pumpAndSettle();
    expect(find.text('Remove 2 songs from Mix?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect((await tester.runAsync(() => items(id)))!.length, 4);

    await tester.tap(remove);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('playlist-remove-selected-confirm')),
    );
    await settle(find.text('Removed 2 songs from Mix.'));

    expect(await tester.runAsync(() => items(id)), [
      ('song_1', 0),
      ('song_3', 1),
    ]);
    expect(find.text('2 selected'), findsNothing, reason: 'selection ends');
    expect(
      (await tester.runAsync(() => db.query(DatabaseTables.songs)))!.length,
      4,
    );
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/features/import/data/daos/media_file_binding_dao.dart';
import 'package:sonus_next/features/import/domain/entities/media_file_binding.dart';
import 'package:sonus_next/features/library/data/daos/library_query_dao.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_library_query_repository.dart';
import 'package:sonus_next/features/player/application/controllers/playback_coordinator.dart';
import 'package:sonus_next/features/player/domain/models/playback_state.dart';
import 'package:sonus_next/features/player/domain/services/playback_engine.dart';
import 'package:sonus_next/features/player/presentation/controllers/playback_state_controller.dart';
import 'package:sonus_next/features/playlists/application/services/playlist_service.dart';
import 'package:sonus_next/features/playlists/data/daos/playlist_dao.dart';
import 'package:sonus_next/features/playlists/data/repositories/sqlite_playlist_repository.dart';
import 'package:sonus_next/features/playlists/presentation/pages/playlist_detail_page.dart';
import 'package:sonus_next/features/sync/data/repositories/sync_mutation_transaction_runner.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase appDatabase;
  late SqlitePlaylistRepository playlistRepository;
  late PlaylistService service;
  late _NoOpPlaybackEngine playbackEngine;
  late PlaybackCoordinator playbackCoordinator;
  late PlaybackStateController playbackStateController;

  final now = DateTime.utc(2026, 9, 30, 12);

  setUp(() async {
    appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfiNoIsolate,
      databasePath: inMemoryDatabasePath,
    );

    final db = await appDatabase.database;

    playlistRepository = SqlitePlaylistRepository(PlaylistDao(db));

    var itemCounter = 0;

    service = PlaylistService(
      repository: playlistRepository,
      library: SqliteLibraryQueryRepository(LibraryQueryDao(db)),
      mutationRunner: SyncMutationTransactionRunner(appDatabase: appDatabase),
      generatePlaylistId: () => 'playlist_test',
      generatePlaylistItemId: () => 'item_${++itemCounter}',
      now: () => now,
    );

    playbackEngine = _NoOpPlaybackEngine();

    playbackCoordinator = PlaybackCoordinator(engine: playbackEngine);

    playbackStateController = PlaybackStateController(
      coordinator: playbackCoordinator,
    );
  });

  tearDown(() async {
    playbackStateController.dispose();
    await playbackEngine.dispose();
    await appDatabase.close();
  });

  testWidgets('ghosts unavailable playlist rows while preserving membership', (
    tester,
  ) async {
    await _seedSongs(
      appDatabase,
      now: now,
      songIds: const ['song_available', 'song_unavailable'],
      availableSongIds: const {'song_available'},
    );

    final playlist = await service.createPlaylist(name: 'Ghost Playlist');

    final availableItem = await service.addSong(
      playlistId: playlist.id,
      songId: 'song_available',
    );

    final unavailableItem = await service.addSong(
      playlistId: playlist.id,
      songId: 'song_unavailable',
    );

    expect(await playlistRepository.getItems(playlist.id), hasLength(2));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<PlaylistService?>.value(value: service),
          Provider<PlaybackCoordinator>.value(value: playbackCoordinator),
          ChangeNotifierProvider<PlaybackStateController>.value(
            value: playbackStateController,
          ),
        ],
        child: MaterialApp(
          home: PlaylistDetailPage(
            playlistId: playlist.id,
            initialName: playlist.name,
          ),
        ),
      ),
    );

    await tester.pump();

    for (var attempt = 0; attempt < 40; attempt++) {
      await tester.pump(const Duration(milliseconds: 50));

      if (find
          .byKey(ValueKey<String>('playlist-track-${availableItem.id}'))
          .evaluate()
          .isNotEmpty) {
        break;
      }
    }

    expect(
      find.byKey(ValueKey<String>('playlist-track-${availableItem.id}')),
      findsOneWidget,
    );

    expect(
      find.byKey(ValueKey<String>('playlist-track-${unavailableItem.id}')),
      findsNothing,
    );

    expect(find.text('Song 1'), findsOneWidget);
    expect(find.text('Song 2'), findsNothing);

    expect(find.text('1 song'), findsOneWidget);
    expect(find.text('2 songs'), findsNothing);

    final persisted = await playlistRepository.getItems(playlist.id);

    expect(persisted, hasLength(2));
    expect(persisted.map((item) => item.songId), [
      'song_available',
      'song_unavailable',
    ]);
  });
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
    'id': 'artist_playlist_page',
    'name': 'Playlist Artist',
    'canonical_name': 'playlist artist',
    'created_at': timestamp,
    'updated_at': timestamp,
  });

  await db.insert(DatabaseTables.albums, {
    'id': 'album_playlist_page',
    'artist_id': 'artist_playlist_page',
    'title': 'Playlist Album',
    'canonical_title': 'playlist album',
    'created_at': timestamp,
    'updated_at': timestamp,
  });

  await db.insert(DatabaseTables.albumEditions, {
    'id': 'edition_playlist_page',
    'album_id': 'album_playlist_page',
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
      'artist_id': 'artist_playlist_page',
      'album_id': 'album_playlist_page',
      'album_edition_id': 'edition_playlist_page',
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

class _NoOpPlaybackEngine implements PlaybackEngine {
  @override
  Stream<PlaybackState> get states => const Stream.empty();

  @override
  PlaybackState get currentState => const PlaybackState();

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) {
    return super.noSuchMethod(invocation);
  }
}

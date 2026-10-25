import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/core/design/sonus_theme_id.dart';
import 'package:sonus_next/core/design/sonus_tokens.dart';
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
import 'package:sonus_next/features/playlists/presentation/pages/playlists_page.dart';
import 'package:sonus_next/features/sync/data/repositories/sync_mutation_transaction_runner.dart';

// SN-48K2: Playlists and Playlist Detail presentation. Fictional data in an
// in-memory database.
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
    var playlistCounter = 0;
    var itemCounter = 0;
    service = PlaylistService(
      repository: playlistRepository,
      library: SqliteLibraryQueryRepository(LibraryQueryDao(db)),
      mutationRunner: SyncMutationTransactionRunner(appDatabase: appDatabase),
      generatePlaylistId: () => 'playlist_${++playlistCounter}',
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

  Future<void> pump(
    WidgetTester tester,
    Widget home, {
    SonusAppearanceSpec spec = const SonusAppearanceSpec(),
    Size size = const Size(411, 900),
    double textScale = 1,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<PlaylistService?>.value(value: service),
          Provider<PlaybackCoordinator>.value(value: playbackCoordinator),
          Provider<PlaybackCoordinator?>.value(value: playbackCoordinator),
          ChangeNotifierProvider<PlaybackStateController>.value(
            value: playbackStateController,
          ),
        ],
        child: MaterialApp(
          theme: SonusThemeFactory.build(spec),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: home,
        ),
      ),
    );
    // Database work completes outside fake time.
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<String> playlistWithSongs(List<String> songIds) async {
    await _seedSongs(appDatabase, now: now, songIds: songIds);
    final playlist = await service.createPlaylist(
      name: 'A Remarkably Long Fixture Playlist Name For Wrapping',
    );
    for (final songId in songIds) {
      await service.addSong(playlistId: playlist.id, songId: songId);
    }
    return playlist.id;
  }

  group('Playlists', () {
    for (final id in SonusThemeId.values) {
      testWidgets('${id.label} fits 320dp at 2x text', (tester) async {
        await tester.runAsync(() => playlistWithSongs(['song_a', 'song_b']));
        await pump(
          tester,
          const Scaffold(body: PlaylistsPage()),
          spec: SonusAppearanceSpec(themeId: id),
          size: const Size(320, 900),
          textScale: 2,
        );

        expect(tester.takeException(), isNull);
        expect(
          find.byKey(const ValueKey<String>('playlists-create-button')),
          findsOneWidget,
        );
        expect(find.text('2 songs'), findsOneWidget);
      });
    }

    testWidgets('empty library shows the empty state', (tester) async {
      await pump(tester, const Scaffold(body: PlaylistsPage()));

      expect(find.text('No playlists yet'), findsOneWidget);
    });

    testWidgets('delete asks first, with a destructive confirm button', (
      tester,
    ) async {
      final id = await tester.runAsync(() => playlistWithSongs(['song_a']));
      await pump(tester, const Scaffold(body: PlaylistsPage()));

      await tester.tap(find.byKey(ValueKey<String>('playlist-menu-$id')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Delete playlist?'), findsOneWidget);
      expect(find.textContaining('will not be deleted'), findsOneWidget);
      final confirm = tester.widget<FilledButton>(
        find.byKey(const ValueKey<String>('playlist-delete-confirm-button')),
      );
      final scheme = Theme.of(
        tester.element(find.text('Delete playlist?')),
      ).colorScheme;
      expect(confirm.style!.backgroundColor!.resolve({}), scheme.error);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });
  });

  group('Playlist Detail', () {
    Widget detail(String id) =>
        PlaylistDetailPage(playlistId: id, initialName: 'Fixture');

    for (final id in SonusThemeId.values) {
      testWidgets('${id.label} fits 320dp at 2x text', (tester) async {
        final playlistId = await tester.runAsync(
          () => playlistWithSongs(['song_a', 'song_b']),
        );
        await pump(
          tester,
          detail(playlistId!),
          spec: SonusAppearanceSpec(themeId: id),
          size: const Size(320, 1600),
          textScale: 2,
        );

        expect(tester.takeException(), isNull);
        expect(find.text('Song 1'), findsOneWidget);
      });
    }

    for (final level in SonusDecorationIntensity.values) {
      testWidgets('Decoration ${level.label} renders cleanly', (tester) async {
        final playlistId = await tester.runAsync(
          () => playlistWithSongs(['song_a']),
        );
        await pump(
          tester,
          detail(playlistId!),
          spec: SonusAppearanceSpec(decoration: level),
        );

        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('Move down reorders without dragging and is persisted', (
      tester,
    ) async {
      final playlistId = await tester.runAsync(
        () => playlistWithSongs(['song_a', 'song_b', 'song_c']),
      );
      await pump(tester, detail(playlistId!));

      final items = await tester.runAsync(
        () => playlistRepository.getItems(playlistId),
      );
      final first = items!.first.id;

      await tester.tap(
        find.descendant(
          of: find.byKey(ValueKey<String>(first)),
          matching: find.byTooltip('Song options'),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<PopupMenuItem<Object?>>(
              find.byKey(ValueKey<String>('playlist-move-up-$first')),
            )
            .enabled,
        isFalse,
      );
      await tester.tap(find.text('Move down'));
      await tester.pump();
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }

      final reordered = await tester.runAsync(
        () => playlistRepository.getItems(playlistId),
      );
      expect(reordered!.map((item) => item.songId), [
        'song_b',
        'song_a',
        'song_c',
      ]);
    });

    testWidgets('the drag handle is a 48dp target', (tester) async {
      final playlistId = await tester.runAsync(
        () => playlistWithSongs(['song_a']),
      );
      await pump(tester, detail(playlistId!));

      final handle = tester.getSize(
        find
            .ancestor(
              of: find.byIcon(Icons.drag_handle_rounded),
              matching: find.byType(SizedBox),
            )
            .first,
      );
      expect(handle.width, greaterThanOrEqualTo(48));
      expect(handle.height, greaterThanOrEqualTo(48));
    });
  });
}

Future<void> _seedSongs(
  AppDatabase appDatabase, {
  required DateTime now,
  required List<String> songIds,
}) async {
  final db = await appDatabase.database;
  final timestamp = now.toIso8601String();

  await db.insert(DatabaseTables.artists, {
    'id': 'artist_playlist_design',
    'name': 'Playlist Fixture Artist',
    'canonical_name': 'playlist fixture artist',
    'created_at': timestamp,
    'updated_at': timestamp,
  }, conflictAlgorithm: ConflictAlgorithm.ignore);
  await db.insert(DatabaseTables.albums, {
    'id': 'album_playlist_design',
    'artist_id': 'artist_playlist_design',
    'title': 'Playlist Fixture Album',
    'canonical_title': 'playlist fixture album',
    'created_at': timestamp,
    'updated_at': timestamp,
  }, conflictAlgorithm: ConflictAlgorithm.ignore);
  await db.insert(DatabaseTables.albumEditions, {
    'id': 'edition_playlist_design',
    'album_id': 'album_playlist_design',
    'title': 'Playlist Fixture Album',
    'type': 'standard',
    'is_primary': 1,
    'created_at': timestamp,
    'updated_at': timestamp,
  }, conflictAlgorithm: ConflictAlgorithm.ignore);

  final bindingDao = MediaFileBindingDao(db);

  for (var index = 0; index < songIds.length; index++) {
    final songId = songIds[index];
    await db.insert(DatabaseTables.songs, {
      'id': songId,
      'artist_id': 'artist_playlist_design',
      'album_id': 'album_playlist_design',
      'album_edition_id': 'edition_playlist_design',
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

class _NoOpPlaybackEngine implements PlaybackEngine {
  @override
  Stream<PlaybackState> get states => const Stream.empty();

  @override
  PlaybackState get currentState => const PlaybackState();

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

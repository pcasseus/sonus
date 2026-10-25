// SN-45: the Android Auto catalog over a real (disposable, in-memory)
// Sonus database: edition order, playlist order and recently played.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/features/import/application/services/atomic_library_importer.dart';
import 'package:sonus_next/features/import/domain/models/audio_metadata.dart';
import 'package:sonus_next/features/import/domain/models/import_candidate.dart';
import 'package:sonus_next/features/import/domain/models/resolved_metadata.dart';
import 'package:sonus_next/features/library/data/daos/library_query_dao.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_library_query_repository.dart';
import 'package:sonus_next/features/player/application/services/media_session/media_browse_catalog.dart';
import 'package:sonus_next/features/player/application/services/media_session/media_browse_library.dart';
import 'package:sonus_next/features/player/data/services/recently_played_song_query.dart';
import 'package:sonus_next/features/playlists/application/services/playlist_service.dart';
import 'package:sonus_next/features/playlists/data/daos/playlist_dao.dart';
import 'package:sonus_next/features/playlists/data/repositories/sqlite_playlist_repository.dart';
import 'package:sonus_next/features/sync/data/repositories/sync_mutation_transaction_runner.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase appDatabase;
  late MediaBrowseCatalog catalog;
  late PlaylistService playlists;
  final now = DateTime.utc(2026, 10, 25, 12);
  final songIds = <String, String>{};

  setUp(() async {
    songIds.clear();
    appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );

    // Discovered out of order on purpose.
    final importer = AtomicLibraryImporter(appDatabase: appDatabase);
    for (final (title, track) in [('Third', 3), ('First', 1), ('Second', 2)]) {
      final path = 'Madison Beer/locket/$title.mp3';
      final result = await importer.import(
        candidate: ImportCandidate(
          filePath: path,
          normalizedPath: path.toLowerCase(),
          discoveredAt: now,
        ),
        metadata: AudioMetadata(
          title: title,
          artistName: 'Madison Beer',
          albumTitle: 'locket',
          durationSeconds: 180,
          trackNumber: track,
          discNumber: 1,
          isSingle: false,
          featuredArtists: const [],
        ),
        metadataSource: MetadataSource.embedded,
        now: now,
      );
      songIds[title] = result.songId!;
    }

    final db = await appDatabase.database;
    final library = SqliteLibraryQueryRepository(LibraryQueryDao(db));
    var ids = 0;
    playlists = PlaylistService(
      repository: SqlitePlaylistRepository(PlaylistDao(db)),
      library: library,
      mutationRunner: SyncMutationTransactionRunner(appDatabase: appDatabase),
      generatePlaylistId: () => 'playlist_${++ids}',
      generatePlaylistItemId: () => 'item_${++ids}',
      now: () => now,
    );
    catalog = MediaBrowseCatalog(
      library: RepositoryMediaBrowseLibrary(
        library: library,
        playlists: playlists,
        recentlyPlayedSongIds: RecentlyPlayedSongQuery(db).songIds,
      ),
    );
  });

  tearDown(() => appDatabase.close());

  Future<void> listen(String title, DateTime at, {String? id}) async {
    final db = await appDatabase.database;
    final song = (await db.query(
      DatabaseTables.songs,
      where: 'id = ?',
      whereArgs: [songIds[title]],
    )).single;
    await db.insert(DatabaseTables.playbackSessions, {
      'id': id ?? 'session-$title-${at.millisecondsSinceEpoch}',
      'song_id': song['id'],
      'artist_id': song['artist_id'],
      'album_id': song['album_id'],
      'album_edition_id': song['album_edition_id'],
      'song_title': title,
      'artist_name': 'Madison Beer',
      'album_title': 'locket',
      'album_edition_title': 'Standard',
      'started_at': at.toIso8601String(),
      'listened_duration_ms': 1000,
      'track_duration_ms': 180000,
      'final_position_ms': 1000,
      'created_at': at.toIso8601String(),
      'updated_at': at.toIso8601String(),
    });
  }

  test('an album plays in its edition track order', () async {
    final albums = await catalog.children('sonus:albums');
    final album = albums.single;
    expect(album.title, 'locket');

    final songs = await catalog.children(album.id);
    expect(songs.map((s) => s.title), ['First', 'Second', 'Third']);

    final queue = await catalog.queueFor(songs[2].id);
    expect(queue!.startIndex, 2);
    expect(queue.tracks.map((t) => t.title), ['First', 'Second', 'Third']);
  });

  test('the artist lists the album and the songs', () async {
    final artist = (await catalog.children('sonus:artists')).single;
    expect(artist.title, 'Madison Beer');

    final children = await catalog.children(artist.id);
    expect(children.first.title, 'locket');
    expect(children.skip(1).map((s) => s.title).toSet(), {
      'First',
      'Second',
      'Third',
    });
  });

  test('a playlist keeps its saved order', () async {
    final playlist = await playlists.createPlaylist(name: 'Drive');
    for (final title in ['Third', 'First', 'Second']) {
      await playlists.addSong(playlistId: playlist.id, songId: songIds[title]!);
    }

    final listed = await catalog.children('sonus:playlists');
    expect(listed.single.title, 'Drive');

    final songs = await catalog.children(listed.single.id);
    expect(songs.map((s) => s.title), ['Third', 'First', 'Second']);
  });

  test('recently played lists each song once, newest first', () async {
    await listen('First', DateTime.utc(2026, 10, 20));
    await listen('Second', DateTime.utc(2026, 10, 21));
    await listen('First', DateTime.utc(2026, 10, 22));

    final recent = await catalog.children('sonus:recent');

    expect(recent.map((s) => s.title), ['First', 'Second']);
  });

  test('with no history, recently played is empty', () async {
    expect(await catalog.children('sonus:recent'), isEmpty);
    expect(await catalog.children('recent'), isEmpty);
  });

  test('browsing never writes to the library', () async {
    final db = await appDatabase.database;
    Future<List<int>> counts() async => [
      for (final table in [
        DatabaseTables.songs,
        DatabaseTables.playbackSessions,
        DatabaseTables.syncOutbox,
        DatabaseTables.playlists,
      ])
        (await db.rawQuery('SELECT COUNT(*) AS n FROM $table')).single['n']!
            as int,
    ];

    final before = await counts();
    for (final id in [
      'root',
      'sonus:recent',
      'sonus:artists',
      'sonus:albums',
      'sonus:library',
      'sonus:songs',
      'sonus:added',
      'sonus:playlists',
    ]) {
      await catalog.children(id);
    }
    await catalog.search('first');

    expect(await counts(), before);
  });
}

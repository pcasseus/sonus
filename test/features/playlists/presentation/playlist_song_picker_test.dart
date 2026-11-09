// App Update 1.2 patches, Checkpoint 4 (BUG-07): a dedicated screen to
// search the library and add several songs to a playlist at once.
// Disposable databases and fictional fixtures only.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/application/repositories/library_query_repository.dart';
import 'package:sonus_next/features/library/data/daos/library_query_dao.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_library_query_repository.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/playlists/application/models/playlist_add_result.dart';
import 'package:sonus_next/features/playlists/application/services/playlist_service.dart';
import 'package:sonus_next/features/playlists/data/daos/playlist_dao.dart';
import 'package:sonus_next/features/playlists/data/repositories/sqlite_playlist_repository.dart';
import 'package:sonus_next/features/playlists/presentation/controllers/playlist_song_picker_controller.dart';
import 'package:sonus_next/features/playlists/presentation/pages/playlist_detail_page.dart';
import 'package:sonus_next/features/sync/data/repositories/sync_mutation_transaction_runner.dart';
import 'package:sonus_next/features/sync/data/services/sqlite_cloud_archive_store.dart';
import 'package:sonus_next/features/sync/domain/models/cloud_archive_record.dart';

LibraryTrack _track(
  String id, {
  String? title,
  String artist = 'Nova',
  String album = 'First Light',
  List<String> featured = const [],
  bool blocked = false,
}) => LibraryTrack(
  songId: id,
  title: title ?? 'Song $id',
  artistId: 'artist-$artist',
  artistName: artist,
  albumId: 'album-$album',
  albumTitle: album,
  albumEditionId: 'edition-$album',
  albumEditionTitle: 'Standard',
  albumEditionType: AlbumEditionType.values.first,
  trackNumber: 1,
  durationSeconds: 180,
  isSingle: false,
  featuredArtists: featured,
  dateAdded: DateTime(2026, 1, 1),
  filePath: '/music/$id.mp3',
  isAvailable: true,
  isSongBlocked: blocked,
);

void main() {
  group('PlaylistSongPickerController', () {
    late List<List<String>> added;

    PlaylistSongPickerController picker({
      List<LibraryTrack>? tracks,
      Set<String> inPlaylist = const {},
      bool failAdd = false,
    }) {
      added = [];
      return PlaylistSongPickerController(
        loadTracks: () async =>
            tracks ??
            [
              _track('a', title: 'Afterglow'),
              _track('b', title: 'Blue Hour', artist: 'Lumen'),
              _track('c', title: 'Cinder', album: 'Second Wind'),
              _track('d', title: 'Drift', featured: const ['Echo Vale']),
              _track('x', title: 'Hidden', blocked: true),
            ],
        songIdsInPlaylist: inPlaylist,
        add: (ids) async {
          if (failAdd) throw StateError('offline');
          added.add(ids);
          return PlaylistAddResult(
            playlistName: 'Mix',
            added: ids.length,
            alreadyPresent: 0,
            failed: 0,
          );
        },
      );
    }

    List<String> ids(PlaylistSongPickerController c) => [
      for (final t in c.visibleTracks) t.songId,
    ];

    test('lists the library, leaving out blocked songs and repeats', () async {
      final c = picker(
        tracks: [_track('a'), _track('a'), _track('x', blocked: true)],
      );
      await c.load();
      expect(ids(c), ['a']);
    });

    test('search matches title, artist, featured artist and release, with '
        'every word', () async {
      final c = picker();
      await c.load();
      c.search('lumen');
      expect(ids(c), ['b']);
      c.search('echo');
      expect(ids(c), ['d']);
      c.search('second wind');
      expect(ids(c), ['c']);
      c.search('AFTER');
      expect(ids(c), ['a']);
      c.search('blue nova');
      expect(ids(c), isEmpty, reason: 'every word must match');
      c.search('');
      expect(ids(c), ['a', 'b', 'c', 'd']);
    });

    test('songs in the playlist are marked and cannot be chosen', () async {
      final c = picker(inPlaylist: {'b'});
      await c.load();
      expect(c.isInPlaylist('b'), isTrue);
      c.toggle('b');
      expect(c.selectedCount, 0);
    });

    test('the choice survives searching and is added in the order chosen, '
        'in one call', () async {
      final c = picker();
      await c.load();
      c.search('drift');
      c.toggle('d');
      c.search('');
      c.toggle('a');
      c.toggle('c');
      c.toggle('c');
      c.toggle('b');
      expect(c.selectedCount, 3);
      expect([for (final t in c.selectedTracks) t.songId], ['d', 'a', 'b']);

      final result = await c.addSelected();
      expect(result!.added, 3);
      expect(added, [
        ['d', 'a', 'b'],
      ]);
    });

    test(
      'nothing chosen adds nothing; a failed add keeps the choice',
      () async {
        final c = picker(failAdd: true);
        await c.load();
        expect(await c.addSelected(), isNull);

        c.toggle('a');
        expect(await c.addSelected(), isNull);
        expect(c.hasError, isTrue);
        expect(c.selectedCount, 1, reason: 'kept to try again');
        expect(c.isAdding, isFalse);
      },
    );
  });

  group('from a playlist', () {
    sqfliteFfiInit();

    late AppDatabase appDatabase;
    late PlaylistService service;
    final now = DateTime.utc(2026, 11, 8, 12);

    setUp(() async {
      appDatabase = AppDatabase(
        databaseFactory: databaseFactoryFfiNoIsolate,
        databasePath: inMemoryDatabasePath,
      );
      final db = await appDatabase.database;
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
      for (final (index, title) in [
        'Afterglow',
        'Blue Hour',
        'Cinder',
        'Drift',
      ].indexed) {
        await db.insert(DatabaseTables.songs, {
          'id': 'song_$index',
          'artist_id': 'artist_nova',
          'album_id': 'album_nova',
          'album_edition_id': 'edition_nova',
          'title': title,
          'canonical_title': title.toLowerCase(),
          'track_number': index + 1,
          'disc_number': 1,
          'duration_seconds': 180,
          'is_single': 0,
          'is_blocked': 0,
          'featured_artists': '[]',
          'created_at': stamp,
          'updated_at': stamp,
        });
      }
    });

    tearDown(() => appDatabase.close());

    Future<void> pumpUntil(WidgetTester tester, Finder finder) async {
      for (var i = 0; i < 60 && finder.evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    testWidgets('songs are searched, chosen and added at the end in the order '
        'chosen, with their song ids, and the change is recorded for sync', (
      tester,
    ) async {
      final playlist = await tester.runAsync(
        () => service.createPlaylist(name: 'Mix'),
      );
      await tester.runAsync(
        () => service.addSong(playlistId: playlist!.id, songId: 'song_1'),
      );
      final db = await appDatabase.database;

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<PlaylistService?>.value(value: service),
            Provider<LibraryQueryRepository?>.value(
              value: SqliteLibraryQueryRepository(LibraryQueryDao(db)),
            ),
          ],
          child: MaterialApp(
            home: PlaylistDetailPage(
              playlistId: playlist!.id,
              initialName: 'Mix',
            ),
          ),
        ),
      );
      final addSongs = find.byKey(const ValueKey<String>('playlist-add-songs'));
      await pumpUntil(tester, addSongs);
      await tester.tap(addSongs);
      final firstRow = find.byKey(
        const ValueKey<String>('song-picker-row-song_0'),
      );
      await pumpUntil(tester, firstRow);
      await tester.pumpAndSettle();

      // Blue Hour is already in the playlist: marked, not selectable.
      expect(
        find.byKey(const ValueKey<String>('song-picker-in-playlist-song_1')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const ValueKey<String>('song-picker-row-song_1')),
            )
            .onChanged,
        isNull,
      );
      final add = find.byKey(const ValueKey<String>('song-picker-add'));
      expect(tester.widget<FilledButton>(add).onPressed, isNull);

      await tester.enterText(
        find.byKey(const ValueKey<String>('song-picker-search')),
        'drift',
      );
      await tester.pumpAndSettle();
      expect(firstRow, findsNothing);
      await tester.tap(
        find.byKey(const ValueKey<String>('song-picker-row-song_3')),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('song-picker-search-clear')),
      );
      await tester.pumpAndSettle();
      await tester.tap(firstRow);
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);

      await tester.tap(add);
      await pumpUntil(tester, find.text('Added 2 songs to Mix.'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('playlist-song-picker')),
        findsNothing,
      );
      final items = (await tester.runAsync(
        () => db.query(
          DatabaseTables.playlistItems,
          where: 'playlist_id = ?',
          whereArgs: [playlist.id],
          orderBy: 'position',
        ),
      ))!;
      expect(
        [for (final i in items) (i['song_id'], i['position'])],
        [('song_1', 0), ('song_3', 1), ('song_0', 2)],
      );
      // Playlists sync through the cloud archive, which reads them as
      // stored: the record it would upload carries the songs in order.
      final archived =
          (await tester.runAsync(
            () => SqliteCloudArchiveStore(appDatabase: appDatabase).collect(),
          ))!.singleWhere(
            (r) => r.kind == CloudArchiveKind.playlist && r.key == playlist.id,
          );
      expect(
        [
          for (final item in archived.payload['items']! as List)
            (item as Map)['song_id'],
        ],
        ['song_1', 'song_3', 'song_0'],
      );
    });

    testWidgets('an empty playlist offers Add songs', (tester) async {
      final playlist = await tester.runAsync(
        () => service.createPlaylist(name: 'Empty'),
      );
      final db = await appDatabase.database;
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<PlaylistService?>.value(value: service),
            Provider<LibraryQueryRepository?>.value(
              value: SqliteLibraryQueryRepository(LibraryQueryDao(db)),
            ),
          ],
          child: MaterialApp(
            home: PlaylistDetailPage(
              playlistId: playlist!.id,
              initialName: 'Empty',
            ),
          ),
        ),
      );
      final emptyAdd = find.byKey(
        const ValueKey<String>('playlist-empty-add-songs'),
      );
      await pumpUntil(tester, emptyAdd);
      await tester.tap(emptyAdd);
      await pumpUntil(
        tester,
        find.byKey(const ValueKey<String>('song-picker-row-song_0')),
      );
      expect(find.text('0 selected'), findsOneWidget);
      unawaited(tester.binding.handlePopRoute());
      await tester.pumpAndSettle();
    });
  });
}

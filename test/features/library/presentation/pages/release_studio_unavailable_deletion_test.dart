// App Update 1.2 (Purpose repair): a song whose file is unavailable is
// listed only in Release Studio, so it can be deleted permanently from
// there, through the same sheet and service as everywhere else. Real
// disposable database, real query repository, controller and deletion
// service; fictional fixtures only.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/features/library/data/daos/library_query_dao.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_library_query_repository.dart';
import 'package:sonus_next/features/library/presentation/controllers/album_profile_controller.dart';
import 'package:sonus_next/features/library/presentation/pages/release_studio_page.dart';

const _stamp = '2026-11-01T12:00:00.000Z';

void main() {
  sqfliteFfiInit();

  late Directory dir;
  late AppDatabase database;
  late Database db;

  Future<void> insertSong(
    String id,
    String title, {
    required int track,
    required bool available,
    String album = 'album',
    String edition = 'edition',
  }) async {
    await db.insert(DatabaseTables.songs, {
      'id': id,
      'artist_id': 'nova',
      'album_id': album,
      'album_edition_id': edition,
      'title': title,
      'canonical_title': title.toLowerCase(),
      'track_number': track,
      'disc_number': 1,
      'duration_seconds': 200,
      'created_at': _stamp,
      'updated_at': _stamp,
    });
    await db.insert(DatabaseTables.albumEditionTracks, {
      'album_edition_id': edition,
      'song_id': id,
      'disc_number': 1,
      'track_number': track,
      'sort_position': track - 1,
      'created_at': _stamp,
      'updated_at': _stamp,
    });
    await db.insert(DatabaseTables.mediaFileBindings, {
      'id': 'media_$id',
      'song_id': id,
      'file_path': '/music/$id.mp3',
      'normalized_path': '/music/$id.mp3',
      'is_available': available ? 1 : 0,
      'created_at': _stamp,
      'updated_at': _stamp,
    });
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('sonus_studio_delete_');
    database = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: p.join(dir.path, 'studio.db'),
    );
    db = await database.database;
    await db.insert(DatabaseTables.artists, {
      'id': 'nova',
      'name': 'Nova',
      'canonical_name': 'nova',
      'created_at': _stamp,
      'updated_at': _stamp,
    });
    for (final (album, title) in [
      ('album', 'First Light'),
      ('other', 'Dusk'),
    ]) {
      await db.insert(DatabaseTables.albums, {
        'id': album,
        'artist_id': 'nova',
        'title': title,
        'canonical_title': title.toLowerCase(),
        'created_at': _stamp,
        'updated_at': _stamp,
      });
    }
    for (final (edition, album, title) in [
      ('edition', 'album', 'First Light'),
      ('other_edition', 'other', 'Dusk'),
    ]) {
      await db.insert(DatabaseTables.albumEditions, {
        'id': edition,
        'album_id': album,
        'title': title,
        'type': 'standard',
        'is_primary': 1,
        'created_at': _stamp,
        'updated_at': _stamp,
      });
    }
    await insertSong('here', 'Here', track: 1, available: true);
    await insertSong('gone', 'Gone Song', track: 2, available: false);
    await insertSong('after', 'After', track: 3, available: true);
    await insertSong(
      'elsewhere',
      'Elsewhere',
      track: 1,
      available: true,
      album: 'other',
      edition: 'other_edition',
    );
    // History on a song that stays.
    await db.insert(DatabaseTables.playbackSessions, {
      'id': 'session_here',
      'song_id': 'here',
      'artist_id': 'nova',
      'album_id': 'album',
      'album_edition_id': 'edition',
      'song_title': 'Here',
      'artist_name': 'Nova',
      'album_title': 'First Light',
      'album_edition_title': 'First Light',
      'started_at': _stamp,
      'ended_at': _stamp,
      'listened_duration_ms': 200000,
      'track_duration_ms': 200000,
      'created_at': _stamp,
      'updated_at': _stamp,
    });
    await db.insert(DatabaseTables.qualifiedPlays, {
      'id': 'play_here',
      'playback_session_id': 'session_here',
      'song_id': 'here',
      'artist_id': 'nova',
      'album_id': 'album',
      'album_edition_id': 'edition',
      'qualified_at': _stamp,
      'listened_duration_ms': 200000,
      'track_duration_ms': 200000,
      'created_at': _stamp,
    });
  });

  tearDown(() async {
    await database.close();
    await dir.delete(recursive: true);
  });

  Finder key(String value) => find.byKey(ValueKey<String>(value));

  /// Lets the real database work run between frames: [rounds] frames, or
  /// until [until] holds (about 10 s at most, which only stops a broken
  /// test; a busy machine never fails it).
  Future<void> settle(
    WidgetTester tester, {
    int rounds = 30,
    bool Function()? until,
  }) async {
    final limit = until == null ? rounds : 1000;
    for (var i = 0; i < limit && !(until?.call() ?? false); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
  }

  Future<int> count(String table, [String where = '1']) async =>
      (await db.rawQuery(
            'SELECT COUNT(*) AS n FROM $table WHERE $where',
          )).single['n']!
          as int;

  Future<Map<String, Object?>> snapshotOf(String songId) async => {
    'song': (await db.query(
      DatabaseTables.songs,
      where: 'id = ?',
      whereArgs: [songId],
    )).single,
    'binding': (await db.query(
      DatabaseTables.mediaFileBindings,
      where: 'song_id = ?',
      whereArgs: [songId],
    )).single,
  };

  /// Release Studio on the tracklist, as Album Profile's "Review in Edit
  /// Release" opens it.
  Future<AlbumProfileController> openStudio(WidgetTester tester) async {
    final controller = AlbumProfileController(
      repository: SqliteLibraryQueryRepository(LibraryQueryDao(db)),
      albumId: 'album',
    );
    addTearDown(controller.dispose);
    // The Galaxy S26 Ultra's logical size.
    tester.view.devicePixelRatio = 2.8125;
    tester.view.physicalSize = const Size(384, 832) * 2.8125;
    addTearDown(tester.view.reset);
    await tester.runAsync(controller.load);
    await tester.pumpWidget(
      Provider<AppDatabase>.value(
        value: database,
        child: MaterialApp(
          home: ReleaseStudioPage(
            controller: controller,
            userId: null,
            initialSection: ReleaseStudioSection.tracklist,
          ),
        ),
      ),
    );
    await settle(tester, rounds: 5);
    return controller;
  }

  Future<void> tapDelete(WidgetTester tester, String songId) async {
    final button = key('album-studio-delete-$songId');
    await tester.ensureVisible(button);
    await tester.pump();
    await tester.tap(button);
    await settle(
      tester,
      until: () =>
          // The preview has loaded (or could not be).
          find.text('What will be deleted').evaluate().isNotEmpty ||
          key('permanent-deletion-load-error').evaluate().isNotEmpty,
    );
    // The sheet slides in once its preview has loaded.
    await tester.pumpAndSettle();
  }

  Future<void> confirm(WidgetTester tester, String name) async {
    await tester.ensureVisible(key('permanent-deletion-continue'));
    await tester.pump();
    await tester.tap(key('permanent-deletion-continue'));
    await tester.pumpAndSettle();
    await tester.enterText(key('permanent-deletion-confirm-field'), name);
    await tester.pump();
    await tester.tap(key('permanent-deletion-confirm-delete'));
    // Until the outcome shows: the confirmation, or why nothing was deleted.
    await settle(
      tester,
      until: () =>
          key('album-studio-delete-done').evaluate().isNotEmpty ||
          find.textContaining('Nothing was deleted').evaluate().isNotEmpty ||
          find.textContaining('Your library changed').evaluate().isNotEmpty,
    );
    await settle(tester, rounds: 5);
  }

  testWidgets('only an unavailable song offers Delete song permanently, '
      'and placement editing stays', (tester) async {
    await openStudio(tester);

    expect(key('album-studio-delete-gone'), findsOneWidget);
    expect(
      tester.widget<IconButton>(key('album-studio-delete-gone')).tooltip,
      'Delete song permanently…',
    );
    expect(key('album-studio-delete-here'), findsNothing);
    expect(key('album-studio-delete-after'), findsNothing);
    for (final id in ['here', 'gone', 'after']) {
      expect(key('album-studio-edit-placement-$id'), findsOneWidget);
    }
  });

  testWidgets('cancelling deletes nothing', (tester) async {
    await openStudio(tester);
    await tapDelete(tester, 'gone');
    expect(key('permanent-deletion-continue'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await settle(tester, rounds: 5);

    expect(await tester.runAsync(() => count(DatabaseTables.songs)), 4);
    expect(key('album-studio-delete-gone'), findsOneWidget);
  });

  testWidgets('confirmed, the song is deleted through the permanent '
      'deletion; the others keep their IDs, history and files, and the '
      'tracklist refreshes', (tester) async {
    final before = await tester.runAsync(
      () async => {
        for (final id in ['here', 'after', 'elsewhere'])
          id: await snapshotOf(id),
      },
    );
    await openStudio(tester);

    await tapDelete(tester, 'gone');
    await confirm(tester, 'Gone Song');

    expect(key('album-studio-delete-done'), findsOneWidget);
    expect(find.text('Gone Song was permanently deleted.'), findsOneWidget);
    expect(key('album-studio-track-gone'), findsNothing);
    expect(key('album-studio-track-here'), findsOneWidget);
    expect(key('album-studio-track-after'), findsOneWidget);

    await tester.runAsync(() async {
      expect(await count(DatabaseTables.songs, "id = 'gone'"), 0);
      // The existing service's ledger: the song and its old file path.
      expect(
        await count(
          DatabaseTables.libraryDeletionLedger,
          "entity_type = 'song' AND entity_id = 'gone' "
          "AND reason = 'userDeletion'",
        ),
        1,
      );
      expect(
        await count(
          DatabaseTables.libraryDeletionLedger,
          "entity_type = 'mediaFile' AND entity_id = '/music/gone.mp3'",
        ),
        1,
      );
      expect(
        await count(
          DatabaseTables.libraryDeletionLedger,
          "entity_type = 'mediaFile'",
        ),
        1,
        reason: 'no available file is ledgered',
      );
      expect(await count(DatabaseTables.libraryDeletionJournal), 1);
      for (final id in ['here', 'after', 'elsewhere']) {
        expect(await snapshotOf(id), before![id], reason: id);
      }
      expect(await count(DatabaseTables.qualifiedPlays, "song_id = 'here'"), 1);
      expect(await count(DatabaseTables.playbackSessions), 1);
    });
  });

  testWidgets('blocked by the cloud: the reason is shown and nothing is '
      'deleted', (tester) async {
    // Linked to an account whose cloud cannot keep the deletion (no
    // readiness probe: unknown means no).
    await tester.runAsync(
      () => db.insert(DatabaseTables.localAccountBinding, {
        'id': 1,
        'user_id': 'user-1',
        'bound_at': _stamp,
        'updated_at': _stamp,
      }),
    );
    await openStudio(tester);
    await tapDelete(tester, 'gone');

    expect(key('permanent-deletion-cloud-unavailable'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(key('permanent-deletion-continue')).onPressed,
      isNull,
    );
    expect(await tester.runAsync(() => count(DatabaseTables.songs)), 4);
    expect(
      await tester.runAsync(() => count(DatabaseTables.libraryDeletionLedger)),
      0,
    );
  });

  testWidgets('a file that came back before confirming keeps the song, and '
      'says why', (tester) async {
    await openStudio(tester);
    await tapDelete(tester, 'gone');
    // A rescan found the file while the sheet was open.
    await tester.runAsync(
      () => db.update(DatabaseTables.mediaFileBindings, {
        'is_available': 1,
      }, where: "song_id = 'gone'"),
    );
    await confirm(tester, 'Gone Song');

    expect(
      find.textContaining('Its music file is available again'),
      findsOneWidget,
    );
    expect(find.textContaining('Nothing was deleted.'), findsWidgets);
    expect(await tester.runAsync(() => count(DatabaseTables.songs)), 4);
    expect(
      await tester.runAsync(() => count(DatabaseTables.libraryDeletionLedger)),
      0,
    );
  });

  testWidgets('a song that changed after the preview is not deleted', (
    tester,
  ) async {
    await openStudio(tester);
    await tapDelete(tester, 'gone');
    // It gained a stream after the preview was shown.
    await tester.runAsync(() async {
      await db.insert(DatabaseTables.playbackSessions, {
        'id': 'session_gone',
        'song_id': 'gone',
        'artist_id': 'nova',
        'album_id': 'album',
        'album_edition_id': 'edition',
        'song_title': 'Gone Song',
        'artist_name': 'Nova',
        'album_title': 'First Light',
        'album_edition_title': 'First Light',
        'started_at': _stamp,
        'ended_at': _stamp,
        'listened_duration_ms': 200000,
        'track_duration_ms': 200000,
        'created_at': _stamp,
        'updated_at': _stamp,
      });
      await db.insert(DatabaseTables.qualifiedPlays, {
        'id': 'play_gone',
        'playback_session_id': 'session_gone',
        'song_id': 'gone',
        'artist_id': 'nova',
        'album_id': 'album',
        'album_edition_id': 'edition',
        'qualified_at': _stamp,
        'listened_duration_ms': 200000,
        'track_duration_ms': 200000,
        'created_at': _stamp,
      });
    });
    await confirm(tester, 'Gone Song');

    expect(
      find.textContaining('Your library changed since this preview'),
      findsOneWidget,
    );
    expect(await tester.runAsync(() => count(DatabaseTables.songs)), 4);
    expect(
      await tester.runAsync(() => count(DatabaseTables.libraryDeletionLedger)),
      0,
    );
  });
}

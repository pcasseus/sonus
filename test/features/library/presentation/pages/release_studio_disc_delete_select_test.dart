// App Update 1.2, PATCH-02: Delete Disc in Release Studio. Real disposable database, query
// repository, ordering service and controller; fictional songs.
//
// Standard: Disc 1 "Main" a b, Disc 2 c d, Disc 3 e f. Deluxe also lists
// c and d, so they may leave Standard; e and f may not.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/features/library/application/services/album_edition_track_ordering_service.dart';
import 'package:sonus_next/features/library/data/daos/library_query_dao.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_album_edition_disc_label_repository.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_library_query_repository.dart';
import 'package:sonus_next/features/library/presentation/controllers/album_profile_controller.dart';
import 'package:sonus_next/features/library/presentation/pages/release_studio_page.dart';
import 'package:sonus_next/features/sync/data/repositories/sync_mutation_transaction_runner.dart';

const _stamp = '2026-11-01T12:00:00.000Z';

void main() {
  sqfliteFfiInit();

  late Directory dir;
  late AppDatabase database;
  late Database db;

  Future<void> list(String edition, String song, int disc, int n, int at) =>
      db.insert(DatabaseTables.albumEditionTracks, {
        'album_edition_id': edition,
        'song_id': song,
        'disc_number': disc,
        'track_number': n,
        'sort_position': at,
        'created_at': _stamp,
        'updated_at': _stamp,
      });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('sonus_disc_delete_');
    database = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: p.join(dir.path, 'discs.db'),
    );
    db = await database.database;
    await db.insert(DatabaseTables.artists, {
      'id': 'nova',
      'name': 'Nova',
      'canonical_name': 'nova',
      'created_at': _stamp,
      'updated_at': _stamp,
    });
    await db.insert(DatabaseTables.albums, {
      'id': 'album',
      'artist_id': 'nova',
      'title': 'First Light',
      'canonical_title': 'first light',
      'created_at': _stamp,
      'updated_at': _stamp,
    });
    for (final (id, title, primary) in [
      ('standard', 'First Light', 1),
      ('deluxe', 'First Light (Deluxe)', 0),
    ]) {
      await db.insert(DatabaseTables.albumEditions, {
        'id': id,
        'album_id': 'album',
        'title': title,
        'type': primary == 1 ? 'standard' : 'deluxe',
        'is_primary': primary,
        'created_at': _stamp,
        'updated_at': _stamp,
      });
    }
    const layout = [
      ('a', 1, 1),
      ('b', 1, 2),
      ('c', 2, 1),
      ('d', 2, 2),
      ('e', 3, 1),
      ('f', 3, 2),
    ];
    for (final (index, (id, disc, number)) in layout.indexed) {
      await db.insert(DatabaseTables.songs, {
        'id': id,
        'artist_id': 'nova',
        'album_id': 'album',
        'album_edition_id': 'standard',
        'title': 'Song ${id.toUpperCase()}',
        'canonical_title': 'song $id',
        'track_number': number,
        'disc_number': disc,
        'duration_seconds': 200,
        'created_at': _stamp,
        'updated_at': _stamp,
      });
      await list('standard', id, disc, number, index);
      await db.insert(DatabaseTables.mediaFileBindings, {
        'id': 'media_$id',
        'song_id': id,
        'file_path': '/music/$id.mp3',
        'normalized_path': '/music/$id.mp3',
        'is_available': 1,
        'created_at': _stamp,
        'updated_at': _stamp,
      });
    }
    await list('deluxe', 'c', 1, 1, 0);
    await list('deluxe', 'd', 1, 2, 1);
    await db.insert(DatabaseTables.albumEditionDiscLabels, {
      'album_edition_id': 'standard',
      'disc_number': 1,
      'label': 'Main',
      'created_at': _stamp,
      'updated_at': _stamp,
    });
  });

  tearDown(() async {
    await database.close();
    await dir.delete(recursive: true);
  });

  Finder key(String value) => find.byKey(ValueKey<String>(value));

  Future<void> settle(WidgetTester tester, {bool Function()? until}) async {
    for (var i = 0; i < (until == null ? 20 : 1000); i++) {
      if (until?.call() ?? false) break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
  }

  /// (song, disc, number) of [edition] in its order, as stored.
  Future<List<(String, int, int)>> stored(
    WidgetTester tester, [
    String edition = 'standard',
  ]) async => [
    for (final r in (await tester.runAsync(
      () => db.query(
        DatabaseTables.albumEditionTracks,
        where: 'album_edition_id = ?',
        whereArgs: [edition],
        orderBy: 'sort_position',
      ),
    ))!)
      (
        r['song_id']! as String,
        r['disc_number']! as int,
        r['track_number']! as int,
      ),
  ];

  const original = [
    ('a', 1, 1),
    ('b', 1, 2),
    ('c', 2, 1),
    ('d', 2, 2),
    ('e', 3, 1),
    ('f', 3, 2),
  ];

  Future<void> openStudio(WidgetTester tester, {double textScale = 1}) async {
    final query = SqliteLibraryQueryRepository(LibraryQueryDao(db));
    final controller = AlbumProfileController(
      repository: query,
      albumId: 'album',
      albumEditionTrackOrderingService: AlbumEditionTrackOrderingService(
        mutationRunner: SyncMutationTransactionRunner(appDatabase: database),
      ),
      discLabelRepository: SqliteAlbumEditionDiscLabelRepository(db),
    );
    addTearDown(controller.dispose);
    tester.view.devicePixelRatio = 2.8125;
    tester.view.physicalSize = const Size(384, 832) * 2.8125;
    addTearDown(tester.view.reset);
    await tester.runAsync(controller.load);
    await tester.pumpWidget(
      Provider<AppDatabase>.value(
        value: database,
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: ReleaseStudioPage(
            controller: controller,
            userId: null,
            library: query,
            initialSection: ReleaseStudioSection.tracklist,
          ),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> saved(WidgetTester tester) => settle(
    tester,
    until: () => key('album-studio-reorder-progress').evaluate().isEmpty,
  );

  Future<void> reveal(WidgetTester tester, Finder finder) async {
    await tester.dragUntilVisible(
      finder,
      find.byType(Scrollable).first,
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pump();
    await settle(tester);
  }

  Future<void> startDelete(WidgetTester tester, int disc) async {
    await reveal(tester, key('album-studio-delete-disc-$disc'));
    await tapAndSettle(tester, key('album-studio-delete-disc-$disc'));
  }

  Future<void> confirmPreview(WidgetTester tester) async {
    expect(key('album-studio-disc-preview'), findsOneWidget);
    await tapAndSettle(tester, key('album-studio-disc-preview-confirm'));
    await saved(tester);
    await settle(tester);
  }

  group('Delete Disc (PATCH-02)', () {
    testWidgets('every disc heading offers Delete Disc', (tester) async {
      await openStudio(tester);
      for (final disc in [1, 2, 3]) {
        await reveal(tester, key('album-studio-delete-disc-$disc'));
        expect(
          find.byTooltip('Delete Disc $disc'),
          findsOneWidget,
          reason: 'disc $disc',
        );
      }
    });

    testWidgets('moving the songs: the preview shows the result, then Disc 3 '
        'becomes Disc 2', (tester) async {
      await openStudio(tester);
      await startDelete(tester, 2);
      expect(key('album-studio-delete-disc-dialog'), findsOneWidget);

      await tapAndSettle(tester, key('album-studio-delete-disc-move'));
      await tapAndSettle(tester, key('album-studio-move-to-disc-1'));

      final preview = key('album-studio-disc-preview');
      expect(
        find.descendant(of: preview, matching: find.text('Disc 1 — Main')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: preview, matching: find.text('4. Song D')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: preview, matching: find.text('Disc 2')),
        findsOneWidget,
      );
      await confirmPreview(tester);

      expect(await stored(tester), [
        ('a', 1, 1),
        ('b', 1, 2),
        ('c', 1, 3),
        ('d', 1, 4),
        ('e', 2, 1),
        ('f', 2, 2),
      ]);
      expect(
        find.text('Disc 2 deleted. Its songs moved to Disc 1.'),
        findsOneWidget,
      );
    });

    testWidgets('removing the songs from this edition keeps them in the '
        'library and on Deluxe', (tester) async {
      await openStudio(tester);
      await startDelete(tester, 2);
      await tapAndSettle(tester, key('album-studio-delete-disc-remove'));

      final preview = key('album-studio-disc-preview');
      expect(
        find.descendant(of: preview, matching: find.text('Song C')),
        findsOneWidget,
      );
      await confirmPreview(tester);

      expect(await stored(tester), [
        ('a', 1, 1),
        ('b', 1, 2),
        ('e', 2, 1),
        ('f', 2, 2),
      ]);
      expect(await stored(tester, 'deluxe'), [('c', 1, 1), ('d', 1, 2)]);
      final songs = await tester.runAsync(
        () => db.query(DatabaseTables.songs, columns: ['id'], orderBy: 'id'),
      );
      expect([for (final r in songs!) r['id']], ['a', 'b', 'c', 'd', 'e', 'f']);
      expect(
        await tester.runAsync(() => db.query(DatabaseTables.mediaFileBindings)),
        hasLength(6),
      );
    });

    testWidgets('songs on no other edition can only be moved, and Cancel '
        'changes nothing', (tester) async {
      await openStudio(tester);
      await startDelete(tester, 3);

      final remove = tester.widget<SimpleDialogOption>(
        find.ancestor(
          of: find.text('Remove the songs from this edition'),
          matching: find.byType(SimpleDialogOption),
        ),
      );
      expect(remove.onPressed, isNull);
      expect(key('album-studio-delete-disc-remove-blocked'), findsOneWidget);

      await tapAndSettle(tester, key('album-studio-delete-disc-cancel'));
      expect(key('album-studio-delete-disc-dialog'), findsNothing);
      expect(await stored(tester), original);
    });

    testWidgets('Cancel on the preview changes nothing', (tester) async {
      await openStudio(tester);
      await startDelete(tester, 2);
      await tapAndSettle(tester, key('album-studio-delete-disc-remove'));
      await tapAndSettle(tester, key('album-studio-disc-preview-cancel'));

      expect(await stored(tester), original);
      expect(
        await tester.runAsync(() => db.query(DatabaseTables.syncOutbox)),
        isEmpty,
      );
    });

    testWidgets('an empty disc just added goes after a confirmation, with '
        'nothing saved', (tester) async {
      await openStudio(tester);
      await reveal(tester, key('album-studio-add-disc'));
      await tapAndSettle(tester, key('album-studio-add-disc'));
      await reveal(tester, key('album-studio-disc-4'));

      await startDelete(tester, 4);
      expect(key('album-studio-delete-disc-dialog'), findsNothing);
      await confirmPreview(tester);

      expect(key('album-studio-disc-4'), findsNothing);
      expect(await stored(tester), original);
      expect(
        await tester.runAsync(() => db.query(DatabaseTables.syncOutbox)),
        isEmpty,
      );
    });
  });
}

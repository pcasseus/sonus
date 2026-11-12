// App Update 1.2, REF-13 / REF-13c: arranging the tracklist in Release
// Studio. Dragging and the Move menu change order and discs, numbering is
// automatic on each disc, discs can be named. Real disposable database,
// query repository, ordering service and controller; fictional songs.
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

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('sonus_discs_');
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
    await db.insert(DatabaseTables.albumEditions, {
      'id': 'edition',
      'album_id': 'album',
      'title': 'First Light',
      'type': 'standard',
      'is_primary': 1,
      'created_at': _stamp,
      'updated_at': _stamp,
    });
    for (final (index, id) in ['a', 'b', 'c', 'd'].indexed) {
      await db.insert(DatabaseTables.songs, {
        'id': id,
        'artist_id': 'nova',
        'album_id': 'album',
        'album_edition_id': 'edition',
        'title': 'Song ${id.toUpperCase()}',
        'canonical_title': 'song $id',
        'track_number': index + 1,
        'disc_number': 1,
        'duration_seconds': 200,
        'created_at': _stamp,
        'updated_at': _stamp,
      });
      await db.insert(DatabaseTables.albumEditionTracks, {
        'album_edition_id': 'edition',
        'song_id': id,
        'disc_number': 1,
        'track_number': index + 1,
        'sort_position': index,
        'created_at': _stamp,
        'updated_at': _stamp,
      });
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

  /// (song, disc, number) in the edition's order, as stored.
  Future<List<(String, int, int)>> stored() async => [
    for (final r in await db.query(
      DatabaseTables.albumEditionTracks,
      where: 'album_edition_id = ?',
      whereArgs: ['edition'],
      orderBy: 'sort_position',
    ))
      (
        r['song_id']! as String,
        r['disc_number']! as int,
        r['track_number']! as int,
      ),
  ];

  late AlbumProfileController controller;

  Future<void> openStudio(WidgetTester tester) async {
    final service = AlbumEditionTrackOrderingService(
      mutationRunner: SyncMutationTransactionRunner(appDatabase: database),
    );
    controller = AlbumProfileController(
      repository: SqliteLibraryQueryRepository(LibraryQueryDao(db)),
      albumId: 'album',
      albumEditionTrackOrderingService: service,
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
          home: ReleaseStudioPage(
            controller: controller,
            userId: null,
            initialSection: ReleaseStudioSection.tracklist,
          ),
        ),
      ),
    );
    await settle(tester);
  }

  /// Waits for an arrangement to be saved and shown.
  Future<void> saved(WidgetTester tester) => settle(
    tester,
    until: () => key('album-studio-reorder-progress').evaluate().isEmpty,
  );

  /// Scrolls Release Studio until [finder] is built and on screen: rows
  /// below the fold are only built when they are scrolled to.
  Future<void> reveal(WidgetTester tester, Finder finder) async {
    await tester.dragUntilVisible(
      finder,
      find.byType(Scrollable).first,
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
  }

  SliverReorderableList list(WidgetTester tester) =>
      tester.widget<SliverReorderableList>(key('album-studio-track-list'));

  Future<void> chooseMove(
    WidgetTester tester,
    String songId,
    String label,
  ) async {
    final menu = key('album-studio-move-$songId');
    await reveal(tester, menu);
    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pump();
    await settle(tester);
    await saved(tester);
  }

  testWidgets('one disc stays implicit; there is no Auto-renumber switch', (
    tester,
  ) async {
    await openStudio(tester);

    expect(key('album-studio-auto-renumber'), findsNothing);
    expect(key('album-studio-order-help'), findsOneWidget);
    expect(key('album-studio-disc-1'), findsNothing);
    expect(key('album-studio-move-a'), findsOneWidget);
  });

  testWidgets('dragging reorders, and the disc is numbered 1, 2, 3, 4', (
    tester,
  ) async {
    await openStudio(tester);

    list(tester).onReorderItem!(0, 2); // a goes after c
    await tester.pump();
    await settle(tester);
    await saved(tester);

    expect(await tester.runAsync(stored), [
      ('b', 1, 1),
      ('c', 1, 2),
      ('a', 1, 3),
      ('d', 1, 4),
    ]);
  });

  testWidgets('Add disc, then Move to Disc 2: the song changes disc and '
      'both discs are numbered from 1', (tester) async {
    await openStudio(tester);
    await tester.tap(key('album-studio-add-disc'));
    await tester.pump();
    expect(list(tester).itemCount, 6, reason: 'two headings and 4 songs');
    await reveal(tester, key('album-studio-disc-2'));
    expect(key('album-studio-disc-2'), findsOneWidget);

    await chooseMove(tester, 'c', 'Move to Disc 2');

    expect(await tester.runAsync(stored), [
      ('a', 1, 1),
      ('b', 1, 2),
      ('d', 1, 3),
      ('c', 2, 1),
    ]);
    // The song's own copy follows on its home edition.
    final c = (await tester.runAsync(
      () => db.query(DatabaseTables.songs, where: "id = 'c'"),
    ))!.single;
    expect((c['disc_number'], c['track_number']), (2, 1));
  });

  testWidgets('dragging a song below the Disc 2 heading moves it there', (
    tester,
  ) async {
    await openStudio(tester);
    await tester.tap(key('album-studio-add-disc'));
    await tester.pump();
    // [Disc 1, a, b, c, d, Disc 2]: drop "a" (1) at the end (5).
    list(tester).onReorderItem!(1, 5);
    await tester.pump();
    await settle(tester);
    await saved(tester);

    expect(await tester.runAsync(stored), [
      ('b', 1, 1),
      ('c', 1, 2),
      ('d', 1, 3),
      ('a', 2, 1),
    ]);
  });

  testWidgets('Move up and Move down, for keyboard and screen readers', (
    tester,
  ) async {
    await openStudio(tester);

    await chooseMove(tester, 'c', 'Move up');
    expect(
      [for (final r in (await tester.runAsync(stored))!) r.$1],
      ['a', 'c', 'b', 'd'],
    );
    await chooseMove(tester, 'a', 'Move down');
    expect(
      [for (final r in (await tester.runAsync(stored))!) r.$1],
      ['c', 'a', 'b', 'd'],
    );
  });

  testWidgets('a disc is named, keeps its name through moves, and is '
      'cleared by saving it empty', (tester) async {
    await openStudio(tester);
    await chooseMove(tester, 'd', 'Move to a new disc (2)');

    await reveal(tester, key('album-studio-disc-name-2'));
    await tester.tap(key('album-studio-disc-name-2'));
    await tester.pumpAndSettle();
    await tester.enterText(key('album-studio-disc-name-field'), 'Bonus Tracks');
    await tester.tap(key('album-studio-disc-name-save'));
    await tester.pump();
    await settle(tester);

    await reveal(tester, key('album-studio-disc-title-2'));
    expect(
      tester.widget<Text>(key('album-studio-disc-title-2')).data,
      'Disc 2 — Bonus Tracks',
    );

    await chooseMove(tester, 'c', 'Move to Disc 2');
    expect(controller.discLabels, {2: 'Bonus Tracks'});
    await reveal(tester, key('album-studio-disc-title-2'));
    expect(
      tester.widget<Text>(key('album-studio-disc-title-2')).data,
      'Disc 2 — Bonus Tracks',
    );

    await reveal(tester, key('album-studio-disc-name-2'));
    await tester.tap(key('album-studio-disc-name-2'));
    await tester.pumpAndSettle();
    await tester.enterText(key('album-studio-disc-name-field'), '');
    await tester.tap(key('album-studio-disc-name-save'));
    await tester.pump();
    await settle(tester);
    expect(controller.discLabels, isEmpty);
    await reveal(tester, key('album-studio-disc-title-2'));
    expect(
      tester.widget<Text>(key('album-studio-disc-title-2')).data,
      'Disc 2',
    );
  });

  testWidgets('the name survives reopening (a fresh controller reads it '
      'back)', (tester) async {
    await openStudio(tester);
    await chooseMove(tester, 'd', 'Move to a new disc (2)');
    await tester.runAsync(
      () => controller.setSelectedEditionDiscLabel(disc: 2, label: 'Live'),
    );

    await openStudio(tester);
    expect(controller.discLabels, {2: 'Live'});
    await reveal(tester, key('album-studio-disc-title-2'));
    expect(
      tester.widget<Text>(key('album-studio-disc-title-2')).data,
      'Disc 2 — Live',
    );
  });
}

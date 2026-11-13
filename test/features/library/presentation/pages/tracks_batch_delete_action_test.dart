// App Update 1.2 patches, Checkpoint 4 (BUG-03): Tracks' selection offers
// "Delete from library" when the app's database is there, and never
// "Remove from playlist". Fictional fixtures only.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sonus_next/core/database/app_database.dart';

import 'tracks_page_test.dart' as base;

void main() {
  sqfliteFfiInit();

  const delete = ValueKey<String>('track-selection-delete-library');
  const removeFromPlaylist = ValueKey<String>(
    'track-selection-remove-playlist',
  );

  Future<void> select(WidgetTester tester, {AppDatabase? database}) async {
    final page = base.buildSubject(
      repository: base.FakeLibraryQueryRepository(
        tracks: [base.createTrack(songId: 'amber', title: 'Amber')],
      ),
    );
    await tester.pumpWidget(
      database == null
          ? page
          : Provider<AppDatabase>.value(value: database, child: page),
    );
    await tester.pumpAndSettle();
    await tester.longPress(find.byKey(const ValueKey<String>('track-amber')));
    await tester.pump();
    expect(find.text('1 selected'), findsOneWidget);
  }

  testWidgets('with the app database: Delete from library, styled as '
      'destructive', (tester) async {
    final database = AppDatabase(
      databaseFactory: databaseFactoryFfiNoIsolate,
      databasePath: inMemoryDatabasePath,
    );
    addTearDown(database.close);
    await select(tester, database: database);

    expect(find.byKey(delete), findsOneWidget);
    expect(find.text('Delete from library'), findsOneWidget);
    expect(find.byKey(removeFromPlaylist), findsNothing);
  });

  testWidgets('without it, the selection keeps only its other actions', (
    tester,
  ) async {
    await select(tester);

    expect(find.byKey(delete), findsNothing);
    expect(find.byKey(removeFromPlaylist), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('track-selection-queue')),
      findsOneWidget,
    );
  });
}

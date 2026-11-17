// App Update 1.3 (user decision 2026-11-16): published new-release debut
// stories, one per song, written once and read back exactly.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/features/charts/data/repositories/sqlite_new_release_publication_repository.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_scope.dart';
import 'package:sonus_next/features/charts/domain/moments/new_release_eligibility.dart';
import 'package:sonus_next/features/charts/domain/moments/new_release_publication.dart';
import 'package:sonus_next/features/library/domain/entities/library_organization.dart';
import 'package:sonus_next/features/library/domain/entities/release_date.dart';

NewReleasePublication publication({
  String songId = 'song-dead',
  String headline =
      'Madison Beer debuts new single "Dead" on the Weekly '
      'Sonus Hot 100 at #12.',
  NewReleaseDebutKind kind = NewReleaseDebutKind.single,
  ReleaseDate? releaseDate,
}) {
  final albumTrack = kind == NewReleaseDebutKind.albumTrack;
  return NewReleasePublication(
    songId: songId,
    storyId: 'moment:$songId',
    eventId: 'event-$songId',
    eventKey: 'finalized|debut|$songId',
    kind: kind,
    scope: ChartMomentScope.finalized,
    rank: 12,
    chartName: 'the Weekly Sonus Hot 100',
    weekStartUtc: DateTime.utc(2026, 11, 15),
    debutedAtUtc: DateTime.utc(2026, 11, 22),
    songTitle: 'Dead',
    artistName: 'Madison Beer',
    featuredArtists: const ['Kehlani', 'SZA'],
    albumId: albumTrack ? 'album-1' : null,
    albumTitle: albumTrack ? 'Locket' : null,
    albumFormat: albumTrack ? ReleaseFormat.ep : null,
    releaseDate: releaseDate ?? ReleaseDate.of(2026, 11, 7)!,
    headline: headline,
    publishedAtUtc: DateTime.utc(2026, 11, 22, 9),
  );
}

void main() {
  sqfliteFfiInit();

  late AppDatabase database;
  late SqliteNewReleasePublicationRepository store;

  setUp(() {
    database = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    store = SqliteNewReleasePublicationRepository(database);
  });
  tearDown(() => database.close());

  test('round trips every fact, at each date precision and both '
      'kinds', () async {
    final records = [
      publication(),
      publication(
        songId: 'song-month',
        kind: NewReleaseDebutKind.albumTrack,
        releaseDate: ReleaseDate.of(2026, 11),
      ),
      publication(songId: 'song-year', releaseDate: ReleaseDate.of(2027)),
    ];
    final stored = await store.publish(
      records,
      restoreGeneration: store.restoreGeneration,
    );
    expect(stored, {for (final r in records) r.songId: r});
    expect(await store.readAll(), stored);
  });

  test('a song keeps its first record: a second is ignored', () async {
    final first = publication();
    await store.publish([first], restoreGeneration: store.restoreGeneration);
    final second = publication(headline: 'Another headline.');
    final stored = await store.publish([
      second,
    ], restoreGeneration: store.restoreGeneration);
    expect(stored[first.songId], first);
    expect(await store.readAll(), {first.songId: first});
  });

  test('racing writers leave one record per song', () async {
    final writes = [
      for (var i = 0; i < 5; i++)
        store.publish([
          publication(headline: 'Headline $i.'),
        ], restoreGeneration: store.restoreGeneration),
    ];
    final results = await Future.wait(writes);
    final stored = await store.readAll();
    expect(stored, hasLength(1));
    for (final result in results) {
      expect(result, stored);
    }
  });

  test('a restore since the facts were read: nothing is written', () async {
    final stale = store.restoreGeneration;
    await database.mutationCoordinator.runExclusiveRestore(() async {});
    final stored = await store.publish([
      publication(),
    ], restoreGeneration: stale);
    expect(stored, isEmpty);
    expect(await store.readAll(), isEmpty);
  });

  test('an unreadable row still claims its song and tells nothing', () async {
    final db = await database.database;
    final row = SqliteNewReleasePublicationRepository.toRow(publication());
    // A kind this build does not know (a later build's).
    await db.insert(DatabaseTables.newReleaseDebutPublications, row);
    await db.execute('PRAGMA ignore_check_constraints = ON');
    await db.update(DatabaseTables.newReleaseDebutPublications, {
      'kind': 'futureKind',
    });
    await db.execute('PRAGMA ignore_check_constraints = OFF');

    final read = await store.readAll();
    expect(read.keys, ['song-dead']);
    expect(read['song-dead']!.eventKey, isEmpty);
    // It is not replaced.
    await store.publish([
      publication(),
    ], restoreGeneration: store.restoreGeneration);
    final raw = await db.query(DatabaseTables.newReleaseDebutPublications);
    expect(raw.single['kind'], 'futureKind');
  });

  test('checks refuse impossible rows', () async {
    final db = await database.database;
    final good = SqliteNewReleasePublicationRepository.toRow(publication());
    final bad = <String, Map<String, Object?>>{
      'rank 0': {'chart_rank': 0},
      'rank 201': {'chart_rank': 201},
      'live scope': {'chart_scope': 'live'},
      'unknown kind': {'kind': 'remix'},
      'single with album title': {'album_title': 'Locket'},
      'album track without album': {'kind': 'albumTrack'},
      'single release format': {
        'kind': 'albumTrack',
        'album_title': 'Locket',
        'album_format': 'single',
      },
      'date shape': {'release_date': '2026-11'},
      'precision': {'release_date_precision': 'week'},
      'correction without revision': {
        'corrected_at': '2026-12-01T00:00:00.000Z',
      },
      'revision without correction': {'revision': 2},
      'revision 0': {'revision': 0},
    };
    for (final MapEntry(key: name, value: change) in bad.entries) {
      await expectLater(
        db.insert(DatabaseTables.newReleaseDebutPublications, {
          ...good,
          ...change,
        }),
        throwsA(isA<DatabaseException>()),
        reason: name,
      );
    }
    // A correction (a future, separately controlled process) is storable.
    await db.insert(DatabaseTables.newReleaseDebutPublications, {
      ...good,
      'revision': 2,
      'corrected_at': '2026-12-01T00:00:00.000Z',
    });
    expect((await store.readAll())['song-dead']!.revision, 2);
  });
}

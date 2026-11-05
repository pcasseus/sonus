// A1 safe artist retirement: active, kept for history (retired), waiting
// for sync, removable. Derived from real SQLite references; reading never
// changes a row, and a retired artist used again is active at once.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/library/application/models/library_artist.dart';
import 'package:sonus_next/features/library/application/models/library_health_report.dart';
import 'package:sonus_next/features/library/application/services/album_edition_management_service.dart';
import 'package:sonus_next/features/library/application/services/artist_retirement_service.dart';
import 'package:sonus_next/features/library/application/services/library_integrity_service.dart';
import 'package:sonus_next/features/library/data/daos/library_integrity_dao.dart';
import 'package:sonus_next/features/library/data/daos/library_query_dao.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_artist_reference_repository.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_library_query_repository.dart';
import 'package:sonus_next/features/library/domain/repositories/artist_reference_repository.dart';
import 'package:sonus_next/features/library/presentation/controllers/artist_profile_controller.dart';
import 'package:sonus_next/features/library/presentation/widgets/track_studio_launcher.dart';
import 'package:sonus_next/features/sync/data/repositories/sync_mutation_transaction_runner.dart';

import '../../../../support/artist_reference_fixtures.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase appDatabase;
  late Database db;
  late ArtistReferenceFixtures fixtures;
  late ArtistRetirementService service;

  setUp(() async {
    appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    db = await appDatabase.database;
    fixtures = ArtistReferenceFixtures(db);
    service = ArtistRetirementService(
      () async => SqliteArtistReferenceRepository(db),
    );
  });

  tearDown(() async => appDatabase.close());

  Future<ArtistReferenceSummary> summaryOf(String artistId) async {
    return (await service.classifyAll()).singleWhere(
      (summary) => summary.artistId == artistId,
    );
  }

  Future<ArtistLibraryState> stateOf(String artistId) async =>
      (await summaryOf(artistId)).state;

  group('classification', () {
    final cases =
        <(String, ArtistLibraryState, Future<void> Function(String id))>[
          ('a song', ArtistLibraryState.active, (id) => fixtures.song(id)),
          (
            'an album only',
            ArtistLibraryState.active,
            (id) => fixtures.album(id),
          ),
          (
            'a credit only',
            ArtistLibraryState.active,
            (id) async {
              await fixtures.artist('owner');
              await fixtures.credit(await fixtures.song('owner'), id);
            },
          ),
          (
            'a Library grouping only',
            ArtistLibraryState.active,
            (id) => fixtures.assignment(id),
          ),
          (
            'a playback session only',
            ArtistLibraryState.retired,
            (id) => fixtures.session(id),
          ),
          (
            'a qualified play only',
            ArtistLibraryState.retired,
            (id) => fixtures.play(id),
          ),
          (
            'a chart entry only',
            ArtistLibraryState.retired,
            (id) => fixtures.chartEntry(id),
          ),
          (
            'a Moment about it only',
            ArtistLibraryState.retired,
            (id) => fixtures.moment(entityArtistId: id),
          ),
          (
            'a Moment naming it as related artist only',
            ArtistLibraryState.retired,
            (id) => fixtures.moment(
              entityArtistId: 'someone-else',
              relatedArtistId: id,
            ),
          ),
          (
            'only an unconfirmed cloud write',
            ArtistLibraryState.waitingForSync,
            (id) => fixtures.pendingWrite(id),
          ),
          (
            'history and an unconfirmed cloud write',
            ArtistLibraryState.retired,
            (id) async {
              await fixtures.play(id);
              await fixtures.pendingWrite(id);
            },
          ),
          ('nothing', ArtistLibraryState.removable, (_) async {}),
        ];

    for (final (what, expected, create) in cases) {
      test('an artist with $what is ${expected.name}', () async {
        await fixtures.artist('a1');
        await create('a1');

        final summary = await summaryOf('a1');
        expect(summary.state, expected);

        // The same answer the removal guard gets inside its transaction.
        final guard = await SqliteArtistReferenceRepository(
          db,
        ).findReferences('a1');
        expect(summary.references, guard);

        expect(
          (await service.retiredArtistIds()).contains('a1'),
          expected == ArtistLibraryState.retired,
        );
      });
    }

    test('only a removable artist is offered for removal: pending writes '
        'and history both keep it', () async {
      await fixtures.artist('pending');
      await fixtures.pendingWrite('pending');
      await fixtures.artist('history');
      await fixtures.chartEntry('history');
      await fixtures.artist('free');

      final removable = [
        for (final summary in await service.classifyAll())
          if (summary.state == ArtistLibraryState.removable) summary.artistId,
      ];
      expect(removable, ['free']);
    });
  });

  test('counts plays, chart weeks, Moments, songs, albums and credits, '
      'for every artist at once', () async {
    await fixtures.artist('a1', 'Counted');
    final albumId = await fixtures.album('a1');
    await fixtures.song('a1', albumId: albumId);
    await fixtures.song('a1', albumId: albumId);
    await fixtures.artist('owner');
    await fixtures.credit(await fixtures.song('owner'), 'a1');
    await fixtures.play('a1');
    await fixtures.play('a1');
    await fixtures.session('a1');
    // Two charts in one week, one in the next: two chart weeks.
    await fixtures.chartEntry('a1');
    await fixtures.chartEntry('a1', chartType: 'albums');
    await fixtures.chartEntry('a1', week: '2026-10-31T00:00:00.000Z');
    // A Moment naming the artist twice is one Moment.
    await fixtures.moment(entityArtistId: 'a1', relatedArtistId: 'a1');
    await fixtures.moment(entityArtistId: 'a1');

    final summary = await summaryOf('a1');
    expect(summary.name, 'Counted');
    expect(summary.songs, 2);
    expect(summary.albums, 1);
    expect(summary.credits, 1);
    expect(summary.qualifiedPlays, 2);
    expect(summary.listeningSessions, 3);
    expect(summary.chartEntries, 3);
    expect(summary.chartWeeks, 2);
    expect(summary.moments, 2);
    expect(summary.pendingCloudWrites, 0);
    expect(summary.state, ArtistLibraryState.active);
  });

  test('classifying changes no row: history, charts and Moments are '
      'untouched', () async {
    await fixtures.artist('kept');
    await fixtures.play('kept');
    await fixtures.chartEntry('kept');
    await fixtures.moment(entityArtistId: 'kept');
    await fixtures.pendingWrite('kept');
    await fixtures.artist('free');
    final before = await fixtures.referenceRowCounts();

    await service.classifyAll();
    await service.retiredArtistIds();

    expect(await fixtures.referenceRowCounts(), before);
  });

  test('a retired artist used again is active at once (derived)', () async {
    await fixtures.artist('back');
    await fixtures.play('back');
    expect(await stateOf('back'), ArtistLibraryState.retired);

    // An edit credits the artist on a song again.
    await fixtures.artist('owner');
    await fixtures.credit(await fixtures.song('owner'), 'back');

    expect(await stateOf('back'), ArtistLibraryState.active);
    expect(await service.retiredArtistIds(), isNot(contains('back')));

    final summary = await summaryOf('back');
    expect(summary.qualifiedPlays, 1, reason: 'history still counted');
  });

  test('an import of a new song by a retired artist makes it active', () async {
    await fixtures.artist('back');
    await fixtures.moment(entityArtistId: 'back');
    expect(await stateOf('back'), ArtistLibraryState.retired);

    await fixtures.song('back');

    expect(await stateOf('back'), ArtistLibraryState.active);
  });

  group('pickers and Search', () {
    LibraryArtist libraryArtist(String id) => LibraryArtist(
      artistId: id,
      name: 'Artist $id',
      albumCount: 0,
      songCount: 0,
      dateAdded: DateTime.utc(2026, 10, 1),
    );

    Future<void> seedThree() async {
      await fixtures.artist('active', 'Nova Active');
      await fixtures.song('active');
      await fixtures.artist('retired', 'Nova Retired');
      await fixtures.play('retired');
      await fixtures.artist('fresh', 'Nova Fresh');
    }

    test('withoutRetired drops retired artists only', () async {
      await seedThree();

      final kept = await service.withoutRetired([
        libraryArtist('active'),
        libraryArtist('retired'),
        libraryArtist('fresh'),
      ]);

      expect(kept.map((a) => a.artistId), ['active', 'fresh']);
    });

    testWidgets('Track Studio offers active artists but not retired ones', (
      tester,
    ) async {
      await tester.runAsync(seedThree);
      final repository = SqliteLibraryQueryRepository(LibraryQueryDao(db));
      late BuildContext captured;
      await tester.pumpWidget(
        Provider<ArtistRetirementService?>.value(
          value: service,
          child: Builder(
            builder: (context) {
              captured = context;
              return const SizedBox();
            },
          ),
        ),
      );

      final artists = await tester.runAsync(
        () => trackStudioArtists(captured, repository),
      );

      expect(
        artists!.map((a) => a.artistId),
        containsAll(<String>['active', 'fresh']),
      );
      expect(artists.map((a) => a.artistId), isNot(contains('retired')));

      // The full list used by Charts, Pulse and Moments is unchanged.
      final all = await tester.runAsync(repository.getArtists);
      expect(all!.map((a) => a.artistId), contains('retired'));
    });

    testWidgets('without the service, Track Studio offers every artist', (
      tester,
    ) async {
      await tester.runAsync(seedThree);
      final repository = SqliteLibraryQueryRepository(LibraryQueryDao(db));
      late BuildContext captured;
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            captured = context;
            return const SizedBox();
          },
        ),
      );

      final artists = await tester.runAsync(
        () => trackStudioArtists(captured, repository),
      );

      expect(artists!.map((a) => a.artistId), contains('retired'));
    });

    test('Search lists active artists, not retired ones', () async {
      await seedThree();

      final results = await LibraryQueryDao(db).search('nova');

      expect(
        results.artists.map((a) => a.artistId),
        containsAll(<String>['active', 'fresh']),
      );
      expect(
        results.artists.map((a) => a.artistId),
        isNot(contains('retired')),
      );
    });
  });

  test('Verify Library reports retired and removable artists, read-only, '
      'with no correction', () async {
    await fixtures.artist('active');
    await fixtures.song('active');
    await fixtures.artist('retired');
    await fixtures.chartEntry('retired');
    await fixtures.artist('free');
    await fixtures.artist('pending');
    await fixtures.pendingWrite('pending');
    final before = await fixtures.referenceRowCounts();

    final report = await LibraryIntegrityService(
      dao: LibraryIntegrityDao(db),
      editions: AlbumEditionManagementService(
        mutationRunner: SyncMutationTransactionRunner(appDatabase: appDatabase),
      ),
      fileExists: (_) async => true,
      artists: service,
    ).verify();

    final retired = report.findings.singleWhere(
      (f) => f.check == HealthCheck.retiredArtists,
    );
    expect(retired.severity, HealthSeverity.verified);
    expect(retired.entityIds, ['retired']);
    expect(retired.summary, startsWith('1 artist kept for history'));
    expect(retired.corrections, isEmpty);

    final removable = report.findings.singleWhere(
      (f) => f.check == HealthCheck.removableArtists,
    );
    expect(removable.severity, HealthSeverity.warning);
    expect(removable.entityIds, ['free']);
    expect(removable.corrections, isEmpty);

    expect(await fixtures.referenceRowCounts(), before);
  });

  test('a retired artist with no songs opens its profile without an '
      'error', () async {
    await fixtures.artist('retired');
    await fixtures.play('retired');
    await fixtures.chartEntry('retired');

    final controller = ArtistProfileController(
      repository: SqliteLibraryQueryRepository(LibraryQueryDao(db)),
      artistId: 'retired',
    );
    addTearDown(controller.dispose);
    await controller.load();

    expect(controller.hasError, isFalse);
    expect(controller.isLoading, isFalse);
    expect(controller.tracks, isEmpty);
  });
}

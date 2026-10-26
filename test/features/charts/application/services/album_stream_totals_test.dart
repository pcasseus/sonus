// SN-45 album stream rule (database level): a song's qualified plays count
// toward the album it belongs to, whoever performs it. A soundtrack is an
// album like any other, and artist identity (who is standalone, who is a
// contributor) never decides which plays an album receives.
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/features/analytics/application/models/analytics_period.dart';
import 'package:sonus_next/features/analytics/application/services/analytics_entity_ranking_service.dart';
import 'package:sonus_next/features/analytics/domain/entities/qualified_play.dart';
import 'package:sonus_next/features/analytics/domain/repositories/qualified_play_repository.dart';
import 'package:sonus_next/features/charts/application/services/all_time_chart_service.dart';
import 'package:sonus_next/features/charts/application/services/chart_snapshot_builder_service.dart';
import 'package:sonus_next/features/charts/data/repositories/sqlite_chart_repository.dart';
import 'package:sonus_next/features/charts/domain/models/chart_type.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/application/services/album_edition_management_service.dart';
import 'package:sonus_next/features/library/application/services/library_organization_service.dart';
import 'package:sonus_next/features/library/data/daos/library_query_dao.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_library_organization_repository.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_library_query_repository.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/sync/data/repositories/sync_mutation_transaction_runner.dart';

import '../../../library/support/fixture_library.dart';

class _Plays implements QualifiedPlayRepository {
  _Plays(this.plays);

  final List<QualifiedPlay> plays;

  @override
  Future<List<QualifiedPlay>> getAll({
    DateTime? qualifiedAtOrAfter,
    DateTime? qualifiedBefore,
  }) async => [
    for (final play in plays)
      if ((qualifiedAtOrAfter == null ||
              !play.qualifiedAt.isBefore(qualifiedAtOrAfter)) &&
          (qualifiedBefore == null ||
              play.qualifiedAt.isBefore(qualifiedBefore)))
        play,
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Descendants: a soundtrack performed by a soundtrack-only contributor
/// (Mitchell Hope) and an independent artist with her own album (Dove
/// Cameron).
const List<FixtureTrack> _tracks = [
  FixtureTrack(
    'Descendants/Descendants/1 Evil Like Me.mp3',
    title: 'Evil Like Me',
    artist: 'Dove Cameron',
    album: 'Descendants',
    albumArtist: 'Descendants Cast',
    track: 1,
  ),
  FixtureTrack(
    'Descendants/Descendants/2 Did I Mention.mp3',
    title: 'Did I Mention',
    artist: 'Mitchell Hope',
    album: 'Descendants',
    albumArtist: 'Descendants Cast',
    track: 2,
  ),
  FixtureTrack(
    'Dove Cameron/Bloodshot/1 Bloodshot.mp3',
    title: 'Bloodshot',
    artist: 'Dove Cameron',
    album: 'Bloodshot',
    albumArtist: 'Dove Cameron',
    track: 1,
  ),
];

void main() {
  late AppDatabase database;
  late SqliteLibraryQueryRepository library;
  late LibraryOrganizationService organization;

  setUp(() async {
    database = fixtureDatabase();
    library = SqliteLibraryQueryRepository(
      LibraryQueryDao(await database.database),
    );
    organization = LibraryOrganizationService(
      library: library,
      collaborators: library,
      organization: SqliteLibraryOrganizationRepository(database),
    );
    await importFixtureTracks(database, _tracks);
  });

  tearDown(() => database.close());

  var sequence = 0;
  QualifiedPlay play(LibraryTrack track, {String? editionId}) {
    sequence++;
    return QualifiedPlay(
      id: 'play-$sequence',
      playbackSessionId: 'session-$sequence',
      songId: track.songId,
      artistId: track.artistId,
      albumId: track.albumId,
      albumEditionId: editionId ?? track.albumEditionId,
      qualifiedAt: DateTime.utc(2026, 10, 20, 12, sequence),
      listenedDuration: const Duration(seconds: 120),
      trackDuration: const Duration(seconds: 200),
      createdAt: DateTime.utc(2026, 10, 20),
    );
  }

  Future<LibraryTrack> track(String title) async =>
      (await library.getTracks()).firstWhere((t) => t.title == title);

  /// Album totals from every place that ranks releases: Insights rankings,
  /// the all-time Albums & EPs chart and a weekly release chart.
  Future<List<Map<String, int>>> albumTotals(List<QualifiedPlay> plays) async {
    final source = _Plays(plays);
    final rankings =
        await AnalyticsEntityRankingService(
          qualifiedPlays: source,
          artistAttribution: OrganizationArtistAttribution(organization),
        ).load(
          period: AnalyticsPeriod.lifetime,
          referenceLocal: DateTime(2026, 10, 26),
        );
    final allTime = await AllTimeChartService(
      qualifiedPlays: source,
      library: library,
    ).load(chartType: ChartType.albums, referenceLocal: DateTime(2026, 10, 26));
    final weekly =
        await ChartSnapshotBuilderService(
          qualifiedPlays: source,
          library: library,
          charts: SqliteChartRepository(database),
        ).build(
          chartType: ChartType.albums,
          weekStartUtc: DateTime.utc(2026, 10, 19),
          weekEndUtc: DateTime.utc(2026, 10, 26),
        );
    return [
      {for (final r in rankings.albums) r.entityId: r.qualifiedStreamCount},
      {
        for (final e in allTime.entries)
          e.entity.entityId: e.qualifiedStreamCount,
      },
      {
        for (final e in weekly.entries)
          e.entity.entityId: e.qualifiedStreamCount,
      },
    ];
  }

  test(
    'Descendants receives all six streams, whoever performs the songs',
    () async {
      final evil = await track('Evil Like Me');
      final mention = await track('Did I Mention');
      final descendants = await fixtureAlbumId(database, 'Descendants');

      final plays = [
        for (var i = 0; i < 3; i++) play(evil),
        for (var i = 0; i < 3; i++) play(mention),
      ];

      for (final totals in await albumTotals(plays)) {
        expect(totals, {descendants: 6});
      }

      // Artist level is a different question with its own answer: Dove
      // Cameron owns a release, so her plays count for her; Mitchell Hope is
      // a contributor, so his count for the soundtrack's owner. Each play
      // still counts exactly once.
      final org = await organization.load();
      expect(
        org.isShownInLibrary(await fixtureArtistId(database, 'Dove Cameron')),
        isTrue,
      );
      expect(
        org.isShownInLibrary(await fixtureArtistId(database, 'Mitchell Hope')),
        isFalse,
      );
      final artists =
          (await AnalyticsEntityRankingService(
                qualifiedPlays: _Plays(plays),
                artistAttribution: OrganizationArtistAttribution(organization),
              ).load(
                period: AnalyticsPeriod.lifetime,
                referenceLocal: DateTime(2026, 10, 26),
              ))
              .artists;
      expect(
        {for (final r in artists) r.entityId: r.qualifiedStreamCount},
        {
          await fixtureArtistId(database, 'Dove Cameron'): 3,
          await fixtureArtistId(database, 'Descendants'): 3,
        },
      );
    },
  );

  test('a song shared by Standard and Deluxe adds one play per play to the '
      'parent album', () async {
    final descendants = await fixtureAlbumId(database, 'Descendants');
    final db = await database.database;
    final standard =
        (await db.query(
              DatabaseTables.albumEditions,
              where: 'album_id = ?',
              whereArgs: [descendants],
            )).single['id']!
            as String;
    final deluxe =
        await AlbumEditionManagementService(
          mutationRunner: SyncMutationTransactionRunner(appDatabase: database),
        ).createEdition(
          albumId: descendants,
          title: 'Descendants (Deluxe)',
          type: AlbumEditionType.deluxe,
          includeSongsFrom: standard,
        );

    final evil = await track('Evil Like Me');
    final mention = await track('Did I Mention');
    final plays = [
      play(evil, editionId: standard),
      play(evil, editionId: deluxe.id),
      play(evil, editionId: deluxe.id),
      play(mention, editionId: standard),
      play(mention, editionId: deluxe.id),
      play(mention, editionId: standard),
    ];

    for (final totals in await albumTotals(plays)) {
      expect(totals, {descendants: 6});
    }
  });
}

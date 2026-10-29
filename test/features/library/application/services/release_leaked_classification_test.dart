// SN-50 A-Q2C/A-Q2D/B-Q13: Leaked is a release-wide fact the user sets.
// It is independent of the songs' own leak flags in both directions, sits
// beside the kind, the format and Live, and changes no chart.
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/features/analytics/domain/entities/qualified_play.dart';
import 'package:sonus_next/features/analytics/domain/repositories/qualified_play_repository.dart';
import 'package:sonus_next/features/charts/application/services/all_time_chart_service.dart';
import 'package:sonus_next/features/charts/application/services/library_release_chart_eligibility.dart';
import 'package:sonus_next/features/charts/domain/models/chart_type.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/application/services/library_organization_service.dart';
import 'package:sonus_next/features/library/data/daos/library_query_dao.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_library_organization_repository.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_library_query_repository.dart';
import 'package:sonus_next/features/library/domain/entities/library_organization.dart';

import '../../support/fixture_library.dart';

final _today = DateTime(2026, 10, 27, 10);

class _Plays implements QualifiedPlayRepository {
  final List<QualifiedPlay> all = [];

  void add(LibraryTrack track, DateTime at) => all.add(
    QualifiedPlay(
      id: 'play-${all.length + 1}',
      playbackSessionId: 'session-${all.length + 1}',
      songId: track.songId,
      artistId: track.artistId,
      albumId: track.albumId,
      albumEditionId: track.albumEditionId,
      qualifiedAt: at.toUtc(),
      listenedDuration: const Duration(seconds: 120),
      trackDuration: const Duration(seconds: 200),
      createdAt: at.toUtc(),
    ),
  );

  @override
  Future<List<QualifiedPlay>> getAll({
    DateTime? qualifiedAtOrAfter,
    DateTime? qualifiedBefore,
  }) async => all;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late AppDatabase database;
  late SqliteLibraryQueryRepository library;
  late LibraryOrganizationService organization;
  late String satellites;
  late String harbor;

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
    await importFixtureTracks(database, [
      for (final i in [1, 2])
        FixtureTrack(
          'Nova Reyes/Paper Satellites/$i Orbit $i.mp3',
          title: 'Orbit $i',
          artist: 'Nova Reyes',
          album: 'Paper Satellites',
          albumArtist: 'Nova Reyes',
          track: i,
        ),
      const FixtureTrack(
        'Nova Reyes/Glass Harbor/1 Tidewater.mp3',
        title: 'Tidewater',
        artist: 'Nova Reyes',
        album: 'Glass Harbor',
        albumArtist: 'Nova Reyes',
        track: 1,
      ),
    ]);
    satellites = await fixtureAlbumId(database, 'Paper Satellites');
    harbor = await fixtureAlbumId(database, 'Glass Harbor');
  });

  tearDown(() => database.close());

  Future<void> flagSongsOf(String albumId) async {
    await (await database.database).update(
      DatabaseTables.songs,
      {'is_leak': 1},
      where: 'album_id = ?',
      whereArgs: [albumId],
    );
  }

  Future<List<Object?>> songLeakFlags() async => [
    for (final row in await (await database.database).query(
      DatabaseTables.songs,
      columns: ['is_leak'],
      orderBy: 'id',
    ))
      row['is_leak'],
  ];

  test('A-Q2D: songs flagged as leaks never mark their release', () async {
    await flagSongsOf(satellites);

    final org = await organization.load();
    expect(org.isLeaked(satellites), isFalse);
    expect(org.leaked, isEmpty);
  });

  test('marking the release leaves every song flag as it was', () async {
    final before = await songLeakFlags();

    await organization.setReleaseLeaked(satellites);

    expect((await organization.load()).isLeaked(satellites), isTrue);
    expect((await organization.load()).isLeaked(harbor), isFalse);
    expect(await songLeakFlags(), before);
  });

  test('Leaked sits beside the kind, the format and Live; each clears '
      'alone', () async {
    await organization.classifyRelease(
      albumId: satellites,
      kind: ReleaseKind.compilation,
    );
    await organization.setReleaseFormat(
      albumId: satellites,
      format: ReleaseFormat.ep,
    );
    await organization.setReleaseLive(albumId: satellites, live: true);
    await organization.setReleaseLeaked(satellites);

    var org = await organization.load();
    expect(org.isLeaked(satellites), isTrue);
    expect(org.isLive(satellites), isTrue);
    expect(org.formatOf(satellites), ReleaseFormat.ep);
    expect(org.classifications[satellites]!.kind, ReleaseKind.compilation);

    await organization.clearReleaseClassification(satellites);
    await organization.clearReleaseFormat(satellites);
    await organization.clearReleaseLive(satellites);
    org = await organization.load();
    expect(org.isLeaked(satellites), isTrue, reason: 'a Leaked-only row');

    await organization.setReleaseLive(albumId: satellites, live: false);
    await organization.clearReleaseLeaked(satellites);
    org = await organization.load();
    expect(org.isLeaked(satellites), isFalse);
    expect(org.lives[satellites]!.isLive, isFalse);

    await organization.clearReleaseLive(satellites);
    expect(
      await (await database.database).query(
        DatabaseTables.albumReleaseClassifications,
      ),
      isEmpty,
      reason: 'the row goes once no fact is left',
    );
  });

  test('B-Q13: a leaked release charts exactly as before', () async {
    for (final id in [satellites, harbor]) {
      await organization.setReleaseFormat(
        albumId: id,
        format: ReleaseFormat.album,
      );
    }
    final plays = _Plays();
    final tracks = {for (final t in await library.getTracks()) t.title: t};
    var minute = 0;
    for (final title in ['Orbit 1', 'Orbit 2', 'Tidewater']) {
      plays.add(tracks[title]!, _today.subtract(Duration(minutes: ++minute)));
    }
    final charts = AllTimeChartService(
      qualifiedPlays: plays,
      library: library,
      releaseEligibility: LibraryReleaseChartEligibility(organization),
    );

    Future<List<(String, int, int)>> chart(ChartType type) async => [
      for (final e in (await charts.load(
        chartType: type,
        referenceLocal: _today,
      )).entries)
        (e.entity.title, e.rank, e.qualifiedStreamCount),
    ];

    final albumsBefore = await chart(ChartType.albums);
    final songsBefore = await chart(ChartType.songs);

    await organization.setReleaseLeaked(satellites);

    expect(await chart(ChartType.albums), albumsBefore);
    expect(await chart(ChartType.songs), songsBefore);
    expect(albumsBefore.first, ('Paper Satellites', 1, 2));
  });
}

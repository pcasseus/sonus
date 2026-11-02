// SN-45 Scenario E (database level): a release marked Single charts only
// through its song. It takes no place on the release chart and earns no
// release Moment; its plays, song chart history and stored Moments are
// kept, and making it an Album again restores its release standing. A
// short release whose format nobody stated is never guessed: it waits for
// review, off the release chart.
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/analytics/domain/entities/qualified_play.dart';
import 'package:sonus_next/features/analytics/domain/repositories/qualified_play_repository.dart';
import 'package:sonus_next/features/charts/application/services/all_time_chart_service.dart';
import 'package:sonus_next/features/charts/application/services/all_time_moment_service.dart';
import 'package:sonus_next/features/charts/application/services/library_release_chart_eligibility.dart';
import 'package:sonus_next/features/charts/data/repositories/sqlite_chart_moment_repository.dart';
import 'package:sonus_next/features/charts/domain/models/chart_type.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/application/services/library_organization_service.dart';
import 'package:sonus_next/features/library/data/daos/library_query_dao.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_library_organization_repository.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_library_query_repository.dart';
import 'package:sonus_next/features/library/domain/entities/library_organization.dart';

import '../../../library/support/fixture_library.dart';

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
  }) async => [
    for (final play in all)
      if ((qualifiedAtOrAfter == null ||
              !play.qualifiedAt.isBefore(qualifiedAtOrAfter)) &&
          (qualifiedBefore == null ||
              play.qualifiedAt.isBefore(qualifiedBefore)))
        play,
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late AppDatabase database;
  late SqliteLibraryQueryRepository library;
  late LibraryOrganizationService organization;
  late _Plays plays;

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
      const FixtureTrack(
        'Madison Beer/15 Minutes/15 Minutes.mp3',
        title: '15 Minutes',
        artist: 'Madison Beer',
        album: '15 Minutes',
        albumArtist: 'Madison Beer',
        track: 1,
      ),
      for (final i in [1, 2])
        FixtureTrack(
          'Madison Beer/Life Support/$i Track $i.mp3',
          title: 'Life Support $i',
          artist: 'Madison Beer',
          album: 'Life Support',
          albumArtist: 'Madison Beer',
          track: i,
        ),
      const FixtureTrack(
        'Tate McRae/Think Later/1 Greedy.mp3',
        title: 'Greedy',
        artist: 'Tate McRae',
        album: 'Think Later',
        albumArtist: 'Tate McRae',
        track: 1,
      ),
    ]);

    // The two albums are short fixtures; MusicBrainz states their format,
    // so they chart as albums.
    for (final title in ['Life Support', 'Think Later']) {
      await organization.suggestReleaseFormat(
        albumId: await fixtureAlbumId(database, title),
        format: ReleaseFormat.album,
      );
    }

    plays = _Plays();
    final tracks = {for (final t in await library.getTracks()) t.title: t};
    var minute = 0;
    DateTime next() => _today.subtract(Duration(hours: 5, minutes: -minute++));
    for (var i = 0; i < 5; i++) {
      plays.add(tracks['15 Minutes']!, next());
    }
    plays.add(tracks['Life Support 1']!, next());
    plays.add(tracks['Life Support 2']!, next());
    plays.add(tracks['Greedy']!, next());
  });

  tearDown(() => database.close());

  AllTimeChartService charts() => AllTimeChartService(
    qualifiedPlays: plays,
    library: library,
    releaseEligibility: LibraryReleaseChartEligibility(organization),
  );

  AllTimeMomentService moments() => AllTimeMomentService(
    qualifiedPlays: plays,
    library: library,
    moments: SqliteChartMomentRepository(database),
    activationUtc: DateTime.utc(2026, 1, 1),
    now: () => _today,
    releaseEligibility: LibraryReleaseChartEligibility(organization),
  );

  Future<String> singleId() => fixtureAlbumId(database, '15 Minutes');

  test(
    'a Single never appears on the release chart; its song charts',
    () async {
      await organization.setReleaseFormat(
        albumId: await singleId(),
        format: ReleaseFormat.single,
      );

      final albums = await charts().load(
        chartType: ChartType.albums,
        referenceLocal: _today,
      );
      expect(
        [for (final e in albums.entries) (e.entity.title, e.rank)],
        [('Life Support', 1), ('Think Later', 2)],
      );

      final songs = await charts().load(
        chartType: ChartType.songs,
        referenceLocal: _today,
      );
      expect(songs.entries.first.entity.title, '15 Minutes');
      expect(songs.entries.first.rank, 1);
      expect(songs.entries.first.qualifiedStreamCount, 5);
    },
  );

  test('a Single earns song Moments but never a release Moment', () async {
    await organization.setReleaseFormat(
      albumId: await singleId(),
      format: ReleaseFormat.single,
    );

    final events = await moments().record(referenceLocal: _today);

    expect(
      events.where(
        (e) =>
            e.chartType == ChartType.albums && e.entity.title == '15 Minutes',
      ),
      isEmpty,
    );
    expect(
      events.where(
        (e) => e.chartType == ChartType.songs && e.entity.title == '15 Minutes',
      ),
      isNotEmpty,
    );
  });

  test('reclassifying keeps every stream and every stored Moment', () async {
    final before = await moments().record(referenceLocal: _today);
    final stored = await SqliteChartMomentRepository(database).getRecent();
    expect(stored, hasLength(before.length));

    await organization.setReleaseFormat(
      albumId: await singleId(),
      format: ReleaseFormat.single,
    );
    await moments().record(referenceLocal: _today);
    final afterSingle = await SqliteChartMomentRepository(database).getRecent();
    expect(
      {for (final e in afterSingle) e.id},
      containsAll({for (final e in stored) e.id}),
      reason: 'history is never deleted when the format changes',
    );

    await organization.setReleaseFormat(
      albumId: await singleId(),
      format: ReleaseFormat.album,
    );
    final albums = await charts().load(
      chartType: ChartType.albums,
      referenceLocal: _today,
    );
    expect(albums.entries.first.entity.title, '15 Minutes');
    expect(albums.entries.first.qualifiedStreamCount, 5);
    expect(plays.all, hasLength(8));
  });

  test('an unstated one-song release is not guessed: it waits for review, '
      'off the release chart, while its song charts', () async {
    final org = await organization.load();
    expect(org.formatOf(await singleId()), isNull);
    expect(org.needsFormatReview(await singleId()), isTrue);
    expect(
      org.formats,
      isNot(contains(await singleId())),
      reason: 'nothing is stored as a guess',
    );
    expect(
      [for (final a in await organization.releasesNeedingFormat()) a.title],
      ['15 Minutes'],
    );

    final albums = await charts().load(
      chartType: ChartType.albums,
      referenceLocal: _today,
    );
    expect(
      albums.entries.map((e) => e.entity.title),
      isNot(contains('15 Minutes')),
    );
    final songs = await charts().load(
      chartType: ChartType.songs,
      referenceLocal: _today,
    );
    expect(songs.entries.first.entity.title, '15 Minutes');

    final events = await moments().record(referenceLocal: _today);
    expect(
      events.where(
        (e) =>
            e.chartType == ChartType.albums && e.entity.title == '15 Minutes',
      ),
      isEmpty,
      reason: 'no album Moment merely because the format is unknown',
    );

    // Choosing EP (or Album) puts it on the release chart with every play.
    await organization.setReleaseFormat(
      albumId: await singleId(),
      format: ReleaseFormat.ep,
    );
    expect(await organization.releasesNeedingFormat(), isEmpty);
    final after = await charts().load(
      chartType: ChartType.albums,
      referenceLocal: _today,
    );
    expect(after.entries.first.entity.title, '15 Minutes');
    expect(after.entries.first.qualifiedStreamCount, 5);
  });

  test(
    'an unstated release of four or more songs counts as an Album',
    () async {
      await importFixtureTracks(database, [
        for (final i in [1, 2, 3, 4])
          FixtureTrack(
            'Tate McRae/So Close To What/$i Song $i.mp3',
            title: 'So Close $i',
            artist: 'Tate McRae',
            album: 'So Close To What',
            albumArtist: 'Tate McRae',
            track: i,
          ),
      ], batchId: 'later');
      final id = await fixtureAlbumId(database, 'So Close To What');
      final org = await organization.load();
      expect(org.formatOf(id), ReleaseFormat.album);
      expect(org.needsFormatReview(id), isFalse);
    },
  );

  group('SN-49 Live', () {
    test(
      'a live release charts once, as its format, with no extra streams',
      () async {
        final lifeSupport = await fixtureAlbumId(database, 'Life Support');
        await organization.setReleaseLive(albumId: lifeSupport, live: true);
        await organization.setReleaseFormat(
          albumId: await singleId(),
          format: ReleaseFormat.single,
        );
        await organization.setReleaseLive(
          albumId: await singleId(),
          live: true,
        );

        final albums = await charts().load(
          chartType: ChartType.albums,
          referenceLocal: _today,
        );
        expect(
          [
            for (final e in albums.entries)
              (e.entity.title, e.rank, e.qualifiedStreamCount),
          ],
          [('Life Support', 1, 2), ('Think Later', 2, 1)],
          reason: 'a live album charts once; a live Single never as a release',
        );

        final songs = await charts().load(
          chartType: ChartType.songs,
          referenceLocal: _today,
        );
        expect(songs.entries.first.entity.title, '15 Minutes');
        expect(songs.entries.first.qualifiedStreamCount, 5);
        expect(
          songs.entries.map((e) => e.entity.title).toList(),
          hasLength(songs.entries.map((e) => e.entity.entityId).toSet().length),
        );
        expect(plays.all, hasLength(8));
      },
    );

    test(
      'Live sits beside the kind and the format; each clears alone',
      () async {
        final id = await fixtureAlbumId(database, 'Life Support');
        await organization.classifyRelease(
          albumId: id,
          kind: ReleaseKind.soundtrack,
        );
        await organization.setReleaseLive(albumId: id, live: true);

        var org = await organization.load();
        expect(org.isLive(id), isTrue);
        expect(org.classifications[id]!.kind, ReleaseKind.soundtrack);
        expect(org.formatOf(id), ReleaseFormat.album);

        await organization.clearReleaseClassification(id);
        await organization.clearReleaseFormat(id);
        org = await organization.load();
        expect(org.isLive(id), isTrue);
        expect(org.classifications[id], isNull);

        await organization.clearReleaseLive(id);
        org = await organization.load();
        expect(org.isLive(id), isFalse);
        expect(org.lives[id], isNull);
      },
    );

    test("the user's answer outlasts a MusicBrainz suggestion", () async {
      final id = await fixtureAlbumId(database, 'Think Later');

      expect(await organization.suggestReleaseLive(albumId: id), isTrue);
      expect((await organization.load()).isLive(id), isTrue);

      await organization.setReleaseLive(albumId: id, live: false);
      expect(await organization.suggestReleaseLive(albumId: id), isFalse);
      final org = await organization.load();
      expect(org.isLive(id), isFalse);
      expect(org.lives[id]!.authority, ReleaseClassificationAuthority.manual);
    });
  });
}

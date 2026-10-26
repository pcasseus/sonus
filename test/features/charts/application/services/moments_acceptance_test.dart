// SN-45 Moments acceptance (database level): fictional libraries go
// through the real import pipeline; plays go through the real all-time
// Moment service; stories come from the real editorial desk.
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/analytics/domain/entities/qualified_play.dart';
import 'package:sonus_next/features/analytics/domain/repositories/qualified_play_repository.dart';
import 'package:sonus_next/features/charts/application/services/all_time_moment_service.dart';
import 'package:sonus_next/features/charts/application/services/chart_moment_feed_aggregator.dart';
import 'package:sonus_next/features/charts/application/services/library_release_chart_eligibility.dart';
import 'package:sonus_next/features/charts/data/repositories/sqlite_chart_moment_repository.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event_type.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_editorial_desk.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_facts.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_family.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_visuals.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/application/services/library_organization_service.dart';
import 'package:sonus_next/features/library/data/daos/library_query_dao.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_library_organization_repository.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_library_query_repository.dart';
import 'package:sonus_next/features/library/domain/entities/library_organization.dart';

import '../../../library/support/fixture_library.dart';

final _now = DateTime(2026, 10, 27, 20);

class _Plays implements QualifiedPlayRepository {
  final List<QualifiedPlay> all = [];
  var _minute = 0;

  void add(LibraryTrack track) {
    final at = DateTime(2026, 10, 26, 8).add(Duration(minutes: _minute++));
    all.add(
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
  }

  @override
  Future<List<QualifiedPlay>> getAll({
    DateTime? qualifiedAtOrAfter,
    DateTime? qualifiedBefore,
  }) async => all;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Lookups over the fixture library, with made-up artwork paths so the
/// image choices are visible.
class _Lookups implements MomentLookups {
  _Lookups(this.tracks, this.artists, this.formats);

  final Map<String, LibraryTrack> tracks;
  final Map<String, String> artists;
  final Map<String, ReleaseFormat?> formats;

  @override
  String? artistName(String artistId) => artists[artistId];

  @override
  ReleaseFormat? formatOf(String albumId) =>
      formats.containsKey(albumId) ? formats[albumId] : ReleaseFormat.album;

  @override
  ReleaseFormat? songReleaseFormat(String songId) {
    final album = tracks[songId]?.albumId;
    return album == null ? null : formatOf(album);
  }

  @override
  List<String> featuredOf(String songId) =>
      tracks[songId]?.featuredArtists ?? const [];

  @override
  String? artistIdNamed(String name) {
    for (final MapEntry(key: id, value: artist) in artists.entries) {
      if (artist == name) return id;
    }
    return null;
  }

  @override
  String? songCover(String songId) {
    final album = tracks[songId]?.albumId;
    return album == null ? null : '/covers/$album.jpg';
  }

  @override
  String? releaseCover(String albumId) => '/covers/$albumId.jpg';

  @override
  String? artistPortrait(String artistId) => '/portraits/$artistId.jpg';
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
    plays = _Plays();
  });

  tearDown(() => database.close());

  AllTimeMomentService moments() => AllTimeMomentService(
    qualifiedPlays: plays,
    library: library,
    moments: SqliteChartMomentRepository(database),
    activationUtc: DateTime.utc(2026, 1, 1),
    now: () => _now,
    releaseEligibility: LibraryReleaseChartEligibility(organization),
    artistAttribution: OrganizationArtistAttribution(organization),
  );

  Future<List<MomentStory>> stories() async {
    final tracks = {for (final t in await library.getTracks()) t.songId: t};
    final artists = {
      for (final a in await library.getArtists()) a.artistId: a.name,
    };
    final events = await SqliteChartMomentRepository(database).getRecent();
    return MomentEditorialDesk(
      lookups: _Lookups(
        tracks,
        artists,
        await organization.releaseFormatsForDisplay(),
      ),
      // Every story in these scenarios is wanted.
      minorStoriesPerDay: 1000,
    ).compose(const ChartMomentFeedAggregator().aggregate(events));
  }

  Future<Map<String, LibraryTrack>> tracksByTitle() async => {
    for (final t in await library.getTracks()) t.title: t,
  };

  test(
    'Scenario G: #106 on Bubbling Under, then a breakthrough to #94',
    () async {
      await importFixtureTracks(database, [
        for (var i = 1; i <= 105; i++)
          FixtureTrack(
            'Catalog/Deep Cuts/$i Song $i.mp3',
            title: 'Deep $i',
            artist: 'Catalog',
            album: 'Deep Cuts',
            albumArtist: 'Catalog',
            track: i,
          ),
        const FixtureTrack(
          'Flo Milli/Fine Ho, Stay/1 Never Lose Me.mp3',
          title: 'Never Lose Me',
          artist: 'Flo Milli',
          album: 'Fine Ho, Stay',
          albumArtist: 'Flo Milli',
          track: 1,
        ),
      ]);
      final tracks = await tracksByTitle();
      for (var i = 1; i <= 105; i++) {
        final times = i <= 93 ? 3 : 2;
        for (var n = 0; n < times; n++) {
          plays.add(tracks['Deep $i']!);
        }
      }

      plays.add(tracks['Never Lose Me']!);
      await moments().record(referenceLocal: _now);
      var published = await stories();
      final debut = published.firstWhere(
        (s) => s.facts.title == 'Never Lose Me',
      );
      expect(debut.family, MomentFamily.songBubblingUnderDebut);
      expect(debut.rank, 106);
      expect(debut.headline, contains('#106'));
      expect(debut.headline, contains('Sonus Bubbling Under'));
      expect(debut.tag, 'BUBBLING UNDER #106');

      plays
        ..add(tracks['Never Lose Me']!)
        ..add(tracks['Never Lose Me']!);
      await moments().record(referenceLocal: _now);
      published = await stories();
      final mine = [
        for (final s in published)
          if (s.facts.title == 'Never Lose Me') s,
      ];
      final breakthrough = mine.firstWhere((s) => s.rank == 94);
      expect(breakthrough.family, isNot(MomentFamily.songDebut));
      expect(
        breakthrough.family,
        anyOf(
          MomentFamily.songHot100Breakthrough,
          MomentFamily.artistFirstHot100,
        ),
      );
      expect(breakthrough.tag, 'HOT 100 #94');
      expect(breakthrough.headline, contains('Sonus Hot 100'));
      expect(breakthrough.facts.streams, 3, reason: 'one continuous history');
      expect(
        [for (final s in mine) s.family].where(
          (f) =>
              f == MomentFamily.songDebut ||
              f == MomentFamily.songDebutTop10 ||
              f == MomentFamily.songBubblingUnderDebut,
        ),
        hasLength(1),
        reason: 'entering the Hot 100 is not a second debut',
      );
    },
  );

  test('Scenario H: one artist genuinely overtakes another', () async {
    await importFixtureTracks(database, [
      const FixtureTrack(
        'ILLIT/Super Real Me/1 Magnetic.mp3',
        title: 'Magnetic',
        artist: 'ILLIT',
        album: 'Super Real Me',
        albumArtist: 'ILLIT',
        track: 1,
      ),
      const FixtureTrack(
        'Flo Milli/Fine Ho, Stay/1 Never Lose Me.mp3',
        title: 'Never Lose Me',
        artist: 'Flo Milli',
        album: 'Fine Ho, Stay',
        albumArtist: 'Flo Milli',
        track: 1,
      ),
    ]);
    final tracks = await tracksByTitle();
    for (var i = 0; i < 3; i++) {
      plays.add(tracks['Magnetic']!);
    }
    for (var i = 0; i < 4; i++) {
      plays.add(tracks['Never Lose Me']!);
    }

    await moments().record(referenceLocal: _now);
    final events = await SqliteChartMomentRepository(database).getRecent();
    final overtakes = events
        .where(
          (e) => e.eventType == ChartMomentEventType.artistBecomesTopArtist,
        )
        .toList();
    expect(overtakes, hasLength(1), reason: 'one verified overtake');
    expect(overtakes.single.entity.title, 'Flo Milli');
    expect(overtakes.single.relatedEntity?.title, 'ILLIT');

    final story = (await stories()).firstWhere(
      (s) => s.item.events.any(
        (e) => e.eventType == ChartMomentEventType.artistBecomesTopArtist,
      ),
    );
    // The play that made Flo Milli the top artist also took the song to
    // #1: one story, with the overtake told in it.
    final text = '${story.headline} ${story.body ?? ''}';
    expect(text, contains('Flo Milli'));
    expect(text, contains('ILLIT'));
    expect(text, contains('#1'));
  });

  test('Scenario H: an overtake on its own shows both artists', () async {
    await importFixtureTracks(database, [
      for (final (artist, song) in [
        ('ILLIT', 'Magnetic'),
        ('ILLIT', 'Lucky Girl Syndrome'),
        ('Flo Milli', 'Never Lose Me'),
        ('Flo Milli', 'Conceited'),
      ])
        FixtureTrack(
          '$artist/Album/$song.mp3',
          title: song,
          artist: artist,
          album: '$artist Album',
          albumArtist: artist,
        ),
    ]);
    final t = await tracksByTitle();
    // ILLIT leads with two songs; Flo Milli passes ILLIT with a song that
    // is not #1, so the overtake is the story.
    for (final title in ['Magnetic', 'Magnetic', 'Magnetic']) {
      plays.add(t[title]!);
    }
    for (final title in ['Lucky Girl Syndrome', 'Lucky Girl Syndrome']) {
      plays.add(t[title]!);
    }
    for (final title in [
      'Never Lose Me',
      'Never Lose Me',
      'Conceited',
      'Conceited',
      'Never Lose Me',
      'Conceited',
    ]) {
      plays.add(t[title]!);
    }

    await moments().record(referenceLocal: _now);
    final story = (await stories()).firstWhere(
      (s) => s.family == MomentFamily.artistTopArtist,
    );
    final ids = {
      for (final a in await library.getArtists()) a.name: a.artistId,
    };
    expect(story.visual.layout, MomentVisualLayout.artistAndArtist);
    expect(story.visual.left.entityId, ids['Flo Milli']);
    expect(story.visual.right!.entityId, ids['ILLIT']);
    expect(story.headline, contains('#1'));
    expect(
      story.headline.indexOf('Flo Milli'),
      lessThan(story.headline.indexOf('ILLIT')),
    );
  });

  test('Scenario I: one album displaces another at #1; a Single never '
      'charts as a release', () async {
    await importFixtureTracks(database, [
      for (final (artist, album, song) in [
        ('Tate McRae', 'Think Later', 'Greedy'),
        ('Tate McRae', 'Think Later', 'Exes'),
        ('Madison Beer', 'Life Support', 'Selfish'),
        ('Madison Beer', 'Life Support', 'Baby'),
        ('Madison Beer', '15 Minutes', '15 Minutes'),
      ])
        FixtureTrack(
          '$artist/$album/$song.mp3',
          title: song,
          artist: artist,
          album: album,
          albumArtist: artist,
        ),
    ]);
    await organization.setReleaseFormat(
      albumId: await fixtureAlbumId(database, '15 Minutes'),
      format: ReleaseFormat.single,
    );
    // The two-song fixtures stand in for full albums.
    for (final album in ['Think Later', 'Life Support']) {
      await organization.setReleaseFormat(
        albumId: await fixtureAlbumId(database, album),
        format: ReleaseFormat.album,
      );
    }
    final t = await tracksByTitle();
    for (final title in ['Greedy', 'Exes', 'Greedy']) {
      plays.add(t[title]!);
    }
    // The Single is played the most, and still never charts as a release.
    for (var i = 0; i < 6; i++) {
      plays.add(t['15 Minutes']!);
    }
    for (final title in ['Selfish', 'Baby', 'Selfish', 'Baby']) {
      plays.add(t[title]!);
    }

    await moments().record(referenceLocal: _now);
    final published = await stories();
    final releaseStories = [
      for (final s in published)
        if (s.family.isRelease) s,
    ];
    expect(
      releaseStories.where((s) => s.facts.title == '15 Minutes'),
      isEmpty,
      reason: 'a Single never charts as a release',
    );

    final takeover = releaseStories.firstWhere(
      (s) => s.facts.title == 'Life Support' && s.facts.rank == 1,
    );
    expect(takeover.facts.rivalTitle, 'Think Later');
    expect(takeover.headline, contains('#1'));
    expect(takeover.headline, contains('Think Later'));
    expect(takeover.visual.layout, MomentVisualLayout.releaseAndRelease);
    expect(
      takeover.visual.left.entityId,
      await fixtureAlbumId(database, 'Life Support'),
    );
    expect(
      takeover.visual.right!.entityId,
      await fixtureAlbumId(database, 'Think Later'),
    );
  });

  test('Scenario J: a story reads the same after a restart, once', () async {
    await importFixtureTracks(database, [
      const FixtureTrack(
        'ILLIT/Super Real Me/1 Magnetic.mp3',
        title: 'Magnetic',
        artist: 'ILLIT',
        album: 'Super Real Me',
        albumArtist: 'ILLIT',
        track: 1,
      ),
    ]);
    final t = await tracksByTitle();
    plays
      ..add(t['Magnetic']!)
      ..add(t['Magnetic']!);

    await moments().record(referenceLocal: _now);
    final first = await stories();
    final eventsBefore = await SqliteChartMomentRepository(
      database,
    ).getRecent();

    // A restart: new services, the same database.
    await moments().record(referenceLocal: _now);
    await moments().record(referenceLocal: _now);
    final again = await stories();
    final eventsAfter = await SqliteChartMomentRepository(database).getRecent();

    expect(eventsAfter.length, eventsBefore.length, reason: 'no duplicates');
    expect(
      [
        for (final s in again)
          (
            s.id,
            s.publisher,
            s.headline,
            s.body,
            s.occurredAt,
            s.visual.layout,
            s.visual.left.entityId,
            s.visual.right?.entityId,
          ),
      ],
      [
        for (final s in first)
          (
            s.id,
            s.publisher,
            s.headline,
            s.body,
            s.occurredAt,
            s.visual.layout,
            s.visual.left.entityId,
            s.visual.right?.entityId,
          ),
      ],
    );
  });
}

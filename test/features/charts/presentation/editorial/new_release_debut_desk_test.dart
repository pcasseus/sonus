// App Update 1.3 new-release debuts through the real editorial desk (user
// decisions 2026-11-16): one special story per song across the Weekly and
// Career charts, the first qualifying debut by chronology (same instant:
// Weekly), only a debut story re-worded in place, prospective only, and
// nothing changes while approval is off.
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/charts/application/models/chart_moment_feed_item.dart';
import 'package:sonus_next/features/charts/application/services/chart_moment_feed_aggregator.dart';
import 'package:sonus_next/features/charts/domain/models/chart_entity_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_rules.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_scope.dart';
import 'package:sonus_next/features/charts/domain/moments/new_release_eligibility.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_editorial_desk.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_family.dart';
import 'package:sonus_next/features/charts/presentation/editorial/new_release_debut_desk.dart';
import 'package:sonus_next/features/charts/presentation/editorial/new_release_debut_headlines.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/domain/entities/library_organization.dart';
import 'package:sonus_next/features/library/domain/entities/release_date.dart';

import 'moment_editorial_test.dart' show FakeLookups;

/// The write-once start; the week starting here is the first one told.
final start = DateTime.utc(2026, 11, 15);
final week1 = start;
final week2 = start.add(const Duration(days: 7));

const dead = ChartEntitySnapshot(
  entityId: 'song-dead',
  title: 'Dead',
  artistId: 'madison-beer',
  artistName: 'Madison Beer',
);

const eternity = ChartEntitySnapshot(
  entityId: 'song-eternity',
  title: 'For All Eternity',
  artistId: 'tate-mcrae',
  artistName: 'Tate McRae',
);

ChartMomentEvent weekly(
  ChartEntitySnapshot song, {
  required DateTime weekStart,
  required int rank,
  ChartMomentEventType type = ChartMomentEventType.debut,
  int? previousPeak,
}) {
  final key = 'finalized|${type.name}|${song.entityId}|$weekStart';
  final end = weekStart.add(const Duration(days: 7));
  return ChartMomentEvent(
    id: key,
    deduplicationKey: key,
    chartType: ChartType.songs,
    scope: ChartMomentScope.finalized,
    eventType: type,
    entity: song,
    weekStartUtc: weekStart,
    weekEndUtc: end,
    // Finalized when the app next ran, after the week closed.
    occurredAt: end.add(const Duration(hours: 9)),
    createdAt: end.add(const Duration(hours: 9)),
    currentRank: rank,
    previousPeakRank: previousPeak,
  );
}

ChartMomentEvent career(
  ChartEntitySnapshot song, {
  required DateTime at,
  required int rank,
  ChartMomentEventType type = ChartMomentEventType.debut,
  int? previousPeak,
}) {
  final key = 'allTime|${type.name}|${song.entityId}|$at';
  final weekStart = at.isBefore(week1)
      ? week1.subtract(const Duration(days: 7))
      : at.isBefore(week2)
      ? week1
      : week2;
  return ChartMomentEvent(
    id: key,
    deduplicationKey: key,
    sourceId: 'play-$at',
    chartType: ChartType.songs,
    scope: ChartMomentScope.allTime,
    eventType: type,
    entity: song,
    weekStartUtc: weekStart,
    weekEndUtc: weekStart.add(const Duration(days: 7)),
    occurredAt: at,
    createdAt: at,
    currentRank: rank,
    previousPeakRank: previousPeak,
  );
}

NewReleaseAlbumFacts albumFacts({
  String title = 'Anatomy of a Popstar',
  ReleaseFormat format = ReleaseFormat.album,
  String date = '2026-11-07',
  ReleaseKind? kind,
  bool? live,
}) => NewReleaseAlbumFacts(
  albumId: 'album-$title',
  title: title,
  format: format,
  kind: kind,
  live: live,
  editions: [
    NewReleaseEditionFacts(
      type: AlbumEditionType.standard,
      releaseDate: ReleaseDate.tryParse(date),
    ),
  ],
);

class Facts implements NewReleaseLookups {
  Facts(this.bySong);

  final Map<String, NewReleaseSongFacts> bySong;

  @override
  NewReleaseSongFacts? newReleaseFactsOf(String songId) => bySong[songId];
}

final newSingle = Facts({
  dead.entityId: NewReleaseSongFacts(
    songId: dead.entityId,
    isSingle: true,
    singleReleaseDate: ReleaseDate.of(2026, 11, 7),
  ),
});

NewReleaseSongFacts albumTrack(NewReleaseAlbumFacts album) =>
    NewReleaseSongFacts(
      songId: eternity.entityId,
      isSingle: false,
      album: album,
    );

/// Every recorded debut is told (SN-50 device polish), as on the device.
final rules = ChartMomentRules(
  devicePolishFromUtc: DateTime.utc(2026, 10, 1),
  newReleaseDebutsFromUtc: start,
);

List<MomentStory> compose(
  List<ChartMomentEvent> events, {
  NewReleaseLookups? facts,
  List<ChartMomentEvent> storedDebuts = const [],
  bool approved = true,
  bool attach = true,
  ChartMomentRules? withRules,
  FakeLookups? lookups,
}) {
  final effective = withRules ?? rules;
  return MomentEditorialDesk(
    lookups: lookups ?? FakeLookups(),
    rules: effective,
    newReleases: attach
        ? NewReleaseDebutDesk(
            start: NewReleaseDebutStart(effective.newReleaseDebutsFromUtc),
            lookups: facts ?? newSingle,
            storedDebuts: storedDebuts,
            generationApproved: approved,
            headlinesApproved: approved,
          )
        : null,
  ).compose(_items(events));
}

List<ChartMomentFeedItem> _items(List<ChartMomentEvent> events) =>
    const ChartMomentFeedAggregator().aggregate(events);

MomentStory storyOf(List<MomentStory> stories, ChartMomentEvent event) =>
    stories.singleWhere(
      (story) => story.item.events.any(
        (e) => e.deduplicationKey == event.deduplicationKey,
      ),
    );

bool isNewRelease(MomentStory story) =>
    story.variantId.startsWith('new-release-');

void main() {
  group('one new-release story per song across Weekly and Career', () {
    test('career debut first: the career story is the new single, the '
        'weekly debut keeps its ordinary headline', () {
      final careerDebut = career(
        dead,
        at: week1.add(const Duration(days: 2)),
        rank: 45,
      );
      final weeklyDebut = weekly(dead, weekStart: week1, rank: 12);
      final stories = compose([weeklyDebut, careerDebut]);

      final careerStory = storyOf(stories, careerDebut);
      expect(
        careerStory.headline,
        'Madison Beer debuts new single "Dead" on the Career Sonus Hot 100 '
        'at #45.',
      );
      expect(careerStory.variantId, 'new-release-single');
      expect(careerStory.family, MomentFamily.songDebut);

      final weeklyStory = storyOf(stories, weeklyDebut);
      expect(isNewRelease(weeklyStory), isFalse);
      expect(weeklyStory.family, MomentFamily.songDebut);
      expect(weeklyStory.headline, isNot(contains('new single')));
    });

    test('weekly debut first: the weekly story is the new single, the later '
        'career debut stays ordinary', () {
      final weeklyDebut = weekly(dead, weekStart: week1, rank: 12);
      final careerDebut = career(
        dead,
        at: week2.add(const Duration(days: 2)),
        rank: 80,
      );
      final stories = compose([careerDebut, weeklyDebut]);

      expect(
        storyOf(stories, weeklyDebut).headline,
        'Madison Beer debuts new single "Dead" on the Weekly Sonus Hot 100 '
        'at #12.',
      );
      expect(isNewRelease(storyOf(stories, careerDebut)), isFalse);
    });

    test('the same effective time prefers the Weekly chart', () {
      final weeklyDebut = weekly(dead, weekStart: week1, rank: 12);
      // A career debut at the instant the weekly chart week closed.
      final careerDebut = career(dead, at: week2, rank: 45);
      final stories = compose([careerDebut, weeklyDebut]);

      expect(isNewRelease(storyOf(stories, weeklyDebut)), isTrue);
      expect(isNewRelease(storyOf(stories, careerDebut)), isFalse);
      expect(
        NewReleaseEligibility.compareChronology(weeklyDebut, careerDebut),
        lessThan(0),
      );
    });

    test('a weekly week is dated by its close, not by when it was '
        'finalized', () {
      // Finalized nine hours after the week closed; the career debut came
      // in between and is later than the weekly debut.
      final weeklyDebut = weekly(dead, weekStart: week1, rank: 12);
      final careerDebut = career(
        dead,
        at: week2.add(const Duration(hours: 1)),
        rank: 45,
      );
      final stories = compose([careerDebut, weeklyDebut]);

      expect(isNewRelease(storyOf(stories, weeklyDebut)), isTrue);
      expect(isNewRelease(storyOf(stories, careerDebut)), isFalse);
    });

    test('the choice survives paging: a stored earlier career debut outside '
        'the loaded page keeps the weekly debut ordinary', () {
      final careerDebut = career(
        dead,
        at: week1.add(const Duration(days: 2)),
        rank: 45,
      );
      final weeklyDebut = weekly(dead, weekStart: week1, rank: 12);

      final pageOnly = compose([weeklyDebut], storedDebuts: [careerDebut]);
      expect(isNewRelease(storyOf(pageOnly, weeklyDebut)), isFalse);

      final full = compose(
        [weeklyDebut, careerDebut],
        storedDebuts: [careerDebut],
      );
      expect(isNewRelease(storyOf(full, careerDebut)), isTrue);
      expect(
        storyOf(full, weeklyDebut).headline,
        storyOf(pageOnly, weeklyDebut).headline,
      );
    });

    test('composing again (a restart) gives the same stories', () {
      final events = [
        weekly(dead, weekStart: week1, rank: 12),
        career(dead, at: week1.add(const Duration(days: 2)), rank: 45),
      ];
      final once = compose(events);
      final again = compose(events.reversed.toList());
      expect(
        [for (final s in again) (s.id, s.headline)],
        [for (final s in once) (s.id, s.headline)],
      );
    });
  });

  group('never a release announcement for anything but the first debut', () {
    test('a re-entry is never announced, on either chart', () {
      final events = [
        weekly(
          dead,
          weekStart: week2,
          rank: 20,
          type: ChartMomentEventType.reentry,
          previousPeak: 30,
        ),
        career(
          dead,
          at: week2.add(const Duration(days: 1)),
          rank: 90,
          type: ChartMomentEventType.reentry,
          previousPeak: 120,
        ),
      ];
      final stories = compose(events);
      expect(stories, isNotEmpty);
      expect(stories.where(isNewRelease), isEmpty);
    });

    test('after the new-release debut, the re-entry and the other chart\'s '
        'debut are ordinary', () {
      final first = weekly(dead, weekStart: week1, rank: 12);
      final reentry = weekly(
        dead,
        weekStart: week2.add(const Duration(days: 7)),
        rank: 25,
        type: ChartMomentEventType.reentry,
        previousPeak: 12,
      );
      final careerDebut = career(
        dead,
        at: week2.add(const Duration(days: 3)),
        rank: 70,
      );
      final stories = compose([first, reentry, careerDebut]);

      expect(stories.where(isNewRelease).map((s) => s.id), [
        storyOf(stories, first).id,
      ]);
    });
  });

  group('prospective only', () {
    test('debuts before the start get nothing, on either chart', () {
      final oldWeekly = weekly(
        dead,
        weekStart: week1.subtract(const Duration(days: 7)),
        rank: 12,
      );
      final oldCareer = career(
        dead,
        at: start.subtract(const Duration(seconds: 1)),
        rank: 45,
      );
      final stories = compose([oldWeekly, oldCareer]);
      expect(stories, hasLength(2));
      expect(stories.where(isNewRelease), isEmpty);
    });

    test('a career debut at the start instant is told', () {
      final debut = career(dead, at: start, rank: 45);
      expect(isNewRelease(storyOf(compose([debut]), debut)), isTrue);
    });

    test('no recorded start: nothing is told', () {
      final debut = weekly(dead, weekStart: week1, rank: 12);
      final stories = compose([
        debut,
      ], withRules: ChartMomentRules(devicePolishFromUtc: DateTime.utc(2026)));
      expect(stories.where(isNewRelease), isEmpty);
    });
  });

  group('release facts and exact headlines', () {
    test('single: weekly and career, Hot 100 and Bubbling Under', () {
      final cases = {
        weekly(dead, weekStart: week1, rank: 12):
            'Madison Beer debuts new single "Dead" on the Weekly Sonus Hot '
            '100 at #12.',
        weekly(dead, weekStart: week1, rank: 140):
            'Madison Beer debuts new single "Dead" on the Weekly Sonus '
            'Bubbling Under at #140.',
        career(dead, at: week1.add(const Duration(days: 1)), rank: 45):
            'Madison Beer debuts new single "Dead" on the Career Sonus Hot '
            '100 at #45.',
        career(dead, at: week1.add(const Duration(days: 1)), rank: 160):
            'Madison Beer debuts new single "Dead" on the Career Sonus '
            'Bubbling Under at #160.',
      };
      for (final MapEntry(key: debut, value: headline) in cases.entries) {
        expect(storyOf(compose([debut]), debut).headline, headline);
      }
    });

    test('album and EP tracks say "from the new album" / "from the new '
        'EP"', () {
      final weeklyDebut = weekly(eternity, weekStart: week1, rank: 12);
      final careerDebut = career(
        eternity,
        at: week1.add(const Duration(days: 1)),
        rank: 150,
      );
      final album = Facts({eternity.entityId: albumTrack(albumFacts())});
      final ep = Facts({
        eternity.entityId: albumTrack(albumFacts(format: ReleaseFormat.ep)),
      });

      expect(
        storyOf(compose([weeklyDebut], facts: album), weeklyDebut).headline,
        '"For All Eternity" by Tate McRae debuts at #12 on the Weekly Sonus '
        'Hot 100 from the new album Anatomy of a Popstar.',
      );
      expect(
        storyOf(compose([careerDebut], facts: album), careerDebut).headline,
        '"For All Eternity" by Tate McRae debuts at #150 on the Career Sonus '
        'Bubbling Under from the new album Anatomy of a Popstar.',
      );
      expect(
        storyOf(compose([weeklyDebut], facts: ep), weeklyDebut).headline,
        '"For All Eternity" by Tate McRae debuts at #12 on the Weekly Sonus '
        'Hot 100 from the new EP Anatomy of a Popstar.',
      );
      expect(
        storyOf(compose([careerDebut], facts: ep), careerDebut).headline,
        '"For All Eternity" by Tate McRae debuts at #150 on the Career Sonus '
        'Bubbling Under from the new EP Anatomy of a Popstar.',
      );
    });

    test('featured artists are credited in the headline, once', () {
      final debut = weekly(dead, weekStart: week1, rank: 12);
      final story = storyOf(
        compose(
          [debut],
          lookups: FakeLookups(
            featured: {
              dead.entityId: ['Kehlani'],
            },
          ),
        ),
        debut,
      );
      expect(
        story.headline,
        'Madison Beer debuts new single "Dead" featuring Kehlani on the '
        'Weekly Sonus Hot 100 at #12.',
      );
      expect(story.body ?? '', isNot(contains('Featuring Kehlani')));
    });

    test('a single uses its own date, never the album\'s', () {
      final debut = weekly(dead, weekStart: week1, rank: 12);
      NewReleaseLookups singleDated(
        String date, {
        String album = '2026-11-07',
      }) => Facts({
        dead.entityId: NewReleaseSongFacts(
          songId: dead.entityId,
          isSingle: true,
          singleReleaseDate: ReleaseDate.tryParse(date),
          album: albumFacts(date: album),
        ),
      });

      // An old single on a new album: not a new single.
      expect(
        isNewRelease(
          storyOf(compose([debut], facts: singleDated('2026-09-01')), debut),
        ),
        isFalse,
      );
      // A new single from an old album: a new single.
      expect(
        storyOf(
          compose([debut], facts: singleDated('2026-11-07', album: '2025')),
          debut,
        ).headline,
        'Madison Beer debuts new single "Dead" on the Weekly Sonus Hot 100 '
        'at #12.',
      );
      // Released on the cutoff day: not new.
      expect(
        isNewRelease(
          storyOf(compose([debut], facts: singleDated('2026-10-01')), debut),
        ),
        isFalse,
      );
    });

    test('soundtrack and live album tracks are excluded', () {
      final debut = weekly(eternity, weekStart: week1, rank: 12);
      for (final album in [
        albumFacts(kind: ReleaseKind.soundtrack),
        albumFacts(live: true),
      ]) {
        final stories = compose([
          debut,
        ], facts: Facts({eternity.entityId: albumTrack(album)}));
        expect(isNewRelease(storyOf(stories, debut)), isFalse);
      }
    });

    test('a release dated on or before 2026-10-01 is not new', () {
      final debut = weekly(eternity, weekStart: week1, rank: 12);
      final stories = compose(
        [debut],
        facts: Facts({
          eternity.entityId: albumTrack(albumFacts(date: '2026-10-01')),
        }),
      );
      expect(isNewRelease(storyOf(stories, debut)), isFalse);
    });
  });

  group('switched off', () {
    test('the build keeps both approvals off', () {
      expect(NewReleaseDebutActivation.generationApproved, isFalse);
      expect(NewReleaseDebutHeadlines.approved, isFalse);
      final desk = NewReleaseDebutDesk(
        start: NewReleaseDebutStart(start),
        lookups: newSingle,
      );
      expect(desk.active, isFalse);
    });

    test('with approval off the composed feed is exactly as without the '
        'hook', () {
      final events = [
        weekly(dead, weekStart: week1, rank: 12),
        career(dead, at: week1.add(const Duration(days: 2)), rank: 45),
        weekly(eternity, weekStart: week1, rank: 140),
      ];
      final off = compose(events, approved: false);
      final without = compose(events, attach: false);
      final defaults = MomentEditorialDesk(
        lookups: FakeLookups(),
        rules: rules,
        newReleases: NewReleaseDebutDesk(
          start: NewReleaseDebutStart(start),
          lookups: newSingle,
        ),
      ).compose(_items(events));

      List<(String, String, String, String?)> view(List<MomentStory> s) => [
        for (final story in s)
          (story.id, story.variantId, story.headline, story.body),
      ];
      expect(view(off), view(without));
      expect(view(defaults), view(without));
      expect(off.where(isNewRelease), isEmpty);
    });
  });
}

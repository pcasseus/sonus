// SN-45 Sonus Moments editorial engine: the headline library, the desk's
// choices (stable, varied, truthful, not spam) and the image matrix.
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/charts/application/models/chart_moment_feed_item.dart';
import 'package:sonus_next/features/charts/application/services/chart_moment_feed_aggregator.dart';
import 'package:sonus_next/features/charts/domain/models/chart_entity_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_scope.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_editorial_desk.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_facts.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_family.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_headlines.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_publisher.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_visuals.dart';
import 'package:sonus_next/features/library/domain/entities/library_organization.dart';

/// Library lookups for fictional entities.
class FakeLookups implements MomentLookups {
  FakeLookups({
    this.artists = const {},
    this.formats = const {},
    this.songFormats = const {},
    this.featured = const {},
    this.covers = const {},
    this.portraits = const {},
  });

  final Map<String, String> artists;
  final Map<String, ReleaseFormat?> formats;

  /// The format of each song's release; Album when missing.
  final Map<String, ReleaseFormat?> songFormats;
  final Map<String, List<String>> featured;
  final Map<String, String> covers;
  final Map<String, String> portraits;

  @override
  String? artistName(String artistId) => artists[artistId];

  @override
  ReleaseFormat? formatOf(String albumId) =>
      formats.containsKey(albumId) ? formats[albumId] : ReleaseFormat.album;

  @override
  ReleaseFormat? songReleaseFormat(String songId) =>
      songFormats.containsKey(songId)
      ? songFormats[songId]
      : ReleaseFormat.album;

  @override
  List<String> featuredOf(String songId) => featured[songId] ?? const [];

  @override
  String? artistIdNamed(String name) {
    for (final MapEntry(key: id, value: artist) in artists.entries) {
      if (artist == name) return id;
    }
    return null;
  }

  @override
  String? songCover(String songId) => covers[songId];

  @override
  String? releaseCover(String albumId) => covers[albumId];

  @override
  String? artistPortrait(String artistId) => portraits[artistId];
}

ChartEntitySnapshot song(String id, {String artist = 'artist-a'}) =>
    ChartEntitySnapshot(
      entityId: id,
      title: 'Song $id',
      artistId: artist,
      artistName: 'Name $artist',
      albumTitle: 'Album of $id',
    );

ChartEntitySnapshot release(String id, {String artist = 'artist-a'}) =>
    ChartEntitySnapshot(
      entityId: id,
      title: 'Release $id',
      artistId: artist,
      artistName: 'Name $artist',
    );

ChartEntitySnapshot artistEntity(String id) => ChartEntitySnapshot(
  entityId: id,
  title: 'Name $id',
  artistId: id,
  artistName: 'Name $id',
);

final _week = DateTime.utc(2026, 10, 25);

ChartMomentEvent event(
  ChartMomentEventType type, {
  required ChartEntitySnapshot entity,
  ChartType chartType = ChartType.songs,
  ChartMomentScope scope = ChartMomentScope.allTime,
  String source = 'play-1',
  DateTime? at,
  int? rank,
  int? previousRank,
  int? previousPeak,
  int? threshold,
  int? streams,
  int? milestone,
  ChartEntitySnapshot? related,
}) {
  final key = '${scope.name}|${type.name}|${entity.entityId}|$source';
  return ChartMomentEvent(
    id: key,
    deduplicationKey: key,
    sourceId: source,
    chartType: chartType,
    scope: scope,
    eventType: type,
    entity: entity,
    relatedEntity: related,
    weekStartUtc: _week,
    weekEndUtc: _week.add(const Duration(days: 7)),
    occurredAt: at ?? DateTime.utc(2026, 10, 26, 12),
    createdAt: DateTime.utc(2026, 10, 26, 12),
    currentRank: rank,
    previousRank: previousRank,
    previousPeakRank: previousPeak,
    threshold: threshold,
    qualifiedStreamCount: streams,
    milestoneValue: milestone,
  );
}

List<ChartMomentFeedItem> items(List<ChartMomentEvent> events) =>
    const ChartMomentFeedAggregator().aggregate(events);

/// Every fact a family can use, so every headline renders.
MomentFacts fullFacts(MomentFamily family) {
  final release = family.isRelease;
  final numberOne =
      family.isNumberOne || family == MomentFamily.artistTopArtist;
  final rank = switch (family) {
    _ when numberOne => 1,
    MomentFamily.songBubblingUnderDebut => 106,
    MomentFamily.songHot100Breakthrough => 94,
    _ => 7,
  };
  return MomentFacts(
    chartType: release ? ChartType.albums : ChartType.songs,
    weekly: false,
    title:
        family == MomentFamily.artistTopArtist ||
            family == MomentFamily.artistStreamMilestone
        ? 'Flo Milli'
        : 'Never Lose Me',
    artist: 'Flo Milli',
    ownerName: 'Fine Ho, Stay Cast',
    album: 'Fine Ho, Stay',
    format: release ? ReleaseFormat.ep : null,
    rank: rank,
    previousRank: switch (family) {
      MomentFamily.songHot100Breakthrough => 106,
      _ => rank + 23,
    },
    previousPeak: rank + 2,
    streams: 57,
    milestone: 100,
    ordinal: 3,
    threshold: family == MomentFamily.artistSimultaneous ? 10 : 10,
    weeks: 5,
    rivalTitle: family == MomentFamily.artistTopArtist ? 'ILLIT' : 'Magnetic',
    rivalArtist: family == MomentFamily.artistTopArtist ? null : 'ILLIT',
    featured: 'Kehlani',
    consecutive: true,
    count: 3,
  );
}

void main() {
  group('the headline library', () {
    test('every family has twelve distinct headlines, six per publisher', () {
      final ids = <String>{};
      for (final family in MomentFamily.values) {
        final variants = MomentHeadlines.of(family);
        expect(variants.length, greaterThanOrEqualTo(12), reason: '$family');
        for (final publisher in MomentPublisher.values) {
          expect(
            variants.where((v) => v.publisher == publisher).length,
            greaterThanOrEqualTo(6),
            reason: '$family ${publisher.label}',
          );
        }
        for (final variant in variants) {
          expect(
            ids.add(variant.id),
            isTrue,
            reason: 'duplicate ${variant.id}',
          );
        }
        final facts = fullFacts(family);
        final texts = {for (final v in variants) v.build(facts)};
        expect(texts.length, variants.length, reason: '$family repeats itself');
      }
    });

    test('no headline uses banned or vague wording, and #1 says #1', () {
      const banned = [
        'lifetime',
        'summit',
        'all-time leader',
        'another chart cycle',
        'steady movement',
        'null',
        'points',
      ];
      for (final family in MomentFamily.values) {
        final facts = fullFacts(family);
        for (final variant in MomentHeadlines.of(family)) {
          final text = variant.build(facts);
          for (final word in banned) {
            expect(
              text.toLowerCase(),
              isNot(contains(word)),
              reason: '${variant.id}: $text',
            );
          }
          expect(text, isNot(contains('  ')), reason: variant.id);
          expect(text, matches(RegExp(r'[.!]$')), reason: variant.id);
          if (family.isNumberOne || family == MomentFamily.artistTopArtist) {
            expect(text, contains('#1'), reason: '${variant.id}: $text');
          }
        }
      }
    });

    test('Bubbling Under keeps its real position: #106, never #6', () {
      final facts = fullFacts(MomentFamily.songBubblingUnderDebut);
      for (final variant in MomentHeadlines.of(
        MomentFamily.songBubblingUnderDebut,
      )) {
        final text = variant.build(facts);
        expect(text, contains('#106'), reason: text);
        expect(text, contains('Sonus Bubbling Under'), reason: text);
        expect(text, isNot(contains('#6 ')));
      }
    });

    test('singular and plural streams', () {
      expect(MomentFacts.streamCount(1), '1 stream');
      expect(MomentFacts.streamCount(2), '2 streams');
      expect(MomentFacts.streamCount(25000), '25,000 streams');
      expect(MomentFacts.ordinalWord(3), 'third');
      expect(MomentFacts.ordinalWord(21), '21st');
      expect(MomentFacts.ordinalWord(12), '12th');
    });
  });

  group('the desk', () {
    final lookups = FakeLookups(
      artists: {'artist-a': 'Name artist-a', 'artist-b': 'Name artist-b'},
    );
    MomentEditorialDesk desk({int minor = 3}) =>
        MomentEditorialDesk(lookups: lookups, minorStoriesPerDay: minor);

    test('a headline that needs a fact is never chosen without it', () {
      // No previous rank, no rival, no streams: only plain headlines fit.
      final stories = desk().compose(
        items([
          event(
            ChartMomentEventType.firstNumberOne,
            entity: song('s1'),
            rank: 1,
            threshold: 1,
          ),
        ]),
      );
      final story = stories.single;
      final variant = MomentHeadlines.of(
        story.family,
      ).firstWhere((v) => v.id == story.variantId);
      expect(variant.requires, isNot(contains(MomentFact.rival)));
      expect(variant.requires, isNot(contains(MomentFact.previousRank)));
      expect(variant.requires, isNot(contains(MomentFact.streams)));
      expect(story.headline, contains('#1'));
    });

    test('the same feed composes to the same stories, every time', () {
      final feed = items([
        for (var i = 0; i < 6; i++)
          event(
            ChartMomentEventType.debut,
            entity: song('s$i'),
            source: 'play-$i',
            rank: 5 + i,
            streams: 1,
            at: DateTime.utc(2026, 10, 26, 10, i),
          ),
      ]);
      final first = desk().compose(feed);
      final again = desk().compose(feed);
      expect(
        [for (final s in again) (s.id, s.publisher, s.headline, s.body)],
        [for (final s in first) (s.id, s.publisher, s.headline, s.body)],
      );
    });

    test('a newer story never rewrites the ones before it', () {
      final older = [
        for (var i = 0; i < 4; i++)
          event(
            ChartMomentEventType.newPeak,
            entity: song('s$i'),
            source: 'play-$i',
            rank: 9,
            previousRank: 12,
            previousPeak: 12,
            threshold: 10,
            streams: 9,
            at: DateTime.utc(2026, 10, 26, 10, i),
          ),
      ];
      final before = {
        for (final s in desk().compose(items(older))) s.id: s.headline,
      };
      final after = {
        for (final s in desk().compose(
          items([
            ...older,
            event(
              ChartMomentEventType.newPeak,
              entity: song('s9'),
              source: 'play-9',
              rank: 4,
              previousRank: 8,
              previousPeak: 8,
              threshold: 5,
              streams: 30,
              at: DateTime.utc(2026, 10, 26, 11),
            ),
          ]),
        ))
          s.id: s.headline,
      };
      for (final MapEntry(key: id, value: headline) in before.entries) {
        expect(after[id], headline, reason: id);
      }
    });

    test('adjacent stories never share a headline when another fits', () {
      final feed = items([
        for (var i = 0; i < 24; i++)
          event(
            ChartMomentEventType.newPeak,
            entity: song('s$i'),
            source: 'play-$i',
            rank: 9,
            previousRank: 12,
            previousPeak: 12,
            threshold: 10,
            streams: 9,
            at: DateTime.utc(2026, 10, 26, 8, i),
          ),
      ]);
      final stories = desk().compose(feed);
      for (var i = 1; i < stories.length; i++) {
        expect(
          stories[i].variantId,
          isNot(stories[i - 1].variantId),
          reason: 'stories ${i - 1} and $i',
        );
      }
      expect(
        {for (final s in stories) s.publisher},
        MomentPublisher.values.toSet(),
        reason: 'both publishers write',
      );
    });

    test('minor stories are capped per day, keeping the first ones', () {
      final feed = items([
        for (var i = 0; i < 6; i++)
          event(
            ChartMomentEventType.debut,
            entity: song('s$i'),
            source: 'play-$i',
            rank: 150 + i,
            streams: 1,
            at: DateTime.utc(2026, 10, 26, 10, i),
          ),
      ]);
      final stories = desk(minor: 3).compose(feed);
      expect(stories, hasLength(3));
      expect(
        {for (final s in stories) s.item.entity.entityId},
        {'s0', 's1', 's2'},
      );
      expect(stories.first.headline, contains('Sonus Bubbling Under'));
    });

    test('one play\'s facts make one story: the career fact leads', () {
      final stories = desk().compose(
        items([
          event(
            ChartMomentEventType.firstNumberOne,
            entity: song('s1', artist: 'artist-b'),
            rank: 1,
            previousRank: 4,
            threshold: 1,
            streams: 20,
            related: song('s0'),
          ),
          event(
            ChartMomentEventType.artistFirstNumberOneSong,
            entity: song('s1', artist: 'artist-b'),
            rank: 1,
            threshold: 1,
            milestone: 1,
          ),
          event(
            ChartMomentEventType.artistBecomesTopArtist,
            entity: artistEntity('artist-b'),
            threshold: 1,
            streams: 40,
            related: artistEntity('artist-a'),
          ),
        ]),
      );
      final story = stories.single;
      expect(story.family, MomentFamily.artistFirstNumberOne);
      expect(story.headline, contains('#1'));
      expect(
        story.headline,
        contains('"Song s0"'),
        reason: 'names who it passed',
      );
      expect(
        story.body,
        contains('The same stream makes Name artist-b your #1 artist'),
      );
    });

    test('supporting text never repeats itself or the headline', () {
      final stories = desk().compose(
        items([
          for (var i = 0; i < 12; i++)
            event(
              ChartMomentEventType.newPeak,
              entity: song('s$i'),
              source: 'play-$i',
              rank: 2,
              previousRank: 3,
              previousPeak: 3,
              threshold: 2,
              streams: 6,
              at: DateTime.utc(2026, 10, 26, 9, i),
            ),
        ]),
      );
      for (final story in stories) {
        final body = story.body ?? '';
        expect(
          RegExp('The song').allMatches(body).length,
          lessThanOrEqualTo(1),
          reason: body,
        );
        if (story.headline.contains('#3')) {
          expect(body, isNot(contains('#3')), reason: story.headline);
        }
      }
    });

    test('weekly movement is not news; the week\'s biggest gainer is', () {
      final weekly = [
        event(
          ChartMomentEventType.rankRise,
          entity: song('small'),
          scope: ChartMomentScope.finalized,
          source: 'week',
          rank: 40,
          previousRank: 45,
        ),
        event(
          ChartMomentEventType.rankRise,
          entity: song('big'),
          scope: ChartMomentScope.finalized,
          source: 'week',
          rank: 12,
          previousRank: 60,
        ),
        event(
          ChartMomentEventType.rankFall,
          entity: song('down'),
          scope: ChartMomentScope.finalized,
          source: 'week',
          rank: 50,
          previousRank: 20,
        ),
      ];
      final stories = desk().compose(items(weekly));
      expect(stories.single.item.entity.entityId, 'big');
      expect(stories.single.family, MomentFamily.songBiggestGainer);
      expect(stories.single.headline, contains('#12'));
    });

    test('a release story names its format', () {
      final stories =
          MomentEditorialDesk(
            lookups: FakeLookups(
              artists: {'artist-a': 'Name artist-a'},
              formats: {'r1': ReleaseFormat.ep},
            ),
          ).compose(
            items([
              for (var i = 0; i < 12; i++)
                event(
                  ChartMomentEventType.debut,
                  entity: release('r1'),
                  chartType: ChartType.albums,
                  source: 'p$i',
                  rank: 4,
                  streams: 3,
                ),
            ]),
          );
      expect(stories.first.facts.releaseWord, 'EP');
      expect(stories.first.headline, isNot(contains(' album ')));
    });

    test('a song story names its release correctly: Single, EP, Album, or '
        'Release while unconfirmed', () {
      MomentFacts factsFor(ReleaseFormat? format) => MomentFacts.of(
        items([
          event(
            ChartMomentEventType.debut,
            entity: song('s1'),
            rank: 4,
            streams: 3,
          ),
        ]).single,
        FakeLookups(songFormats: {'s1': format}),
      );

      expect(factsFor(ReleaseFormat.single).releaseLabel, 'Single');
      expect(factsFor(ReleaseFormat.ep).releaseLabel, 'EP');
      expect(factsFor(ReleaseFormat.album).releaseLabel, 'Album');
      expect(factsFor(null).releaseLabel, 'Release');

      // "From <album>" is only said of a song on an EP or album.
      expect(
        factsFor(ReleaseFormat.single).available,
        isNot(contains(MomentFact.album)),
      );
      expect(
        factsFor(ReleaseFormat.album).available,
        contains(MomentFact.album),
      );
    });

    test('a release whose format is unconfirmed is a "release", never an '
        '"album"', () {
      final facts = MomentFacts.of(
        items([
          event(
            ChartMomentEventType.debut,
            entity: release('r1'),
            chartType: ChartType.albums,
            rank: 4,
            streams: 3,
          ),
        ]).single,
        FakeLookups(formats: {'r1': null}),
      );
      expect(facts.releaseWord, 'release');
      expect(facts.releaseLabel, 'Release');
    });
  });

  group('supporting text and grammar', () {
    MomentEditorialDesk desk() => MomentEditorialDesk(
      lookups: FakeLookups(artists: {'artist-a': 'Name artist-a'}),
      minorStoriesPerDay: 1000,
    );

    test('a rank before this stream that was also the best is said once', () {
      final stories = desk().compose(
        items([
          for (var i = 0; i < 12; i++)
            event(
              ChartMomentEventType.newPeak,
              entity: song('s$i'),
              source: 'play-$i',
              rank: 3,
              previousRank: 4,
              previousPeak: 4,
              threshold: 3,
              streams: 2,
              at: DateTime.utc(2026, 10, 26, 9, i),
            ),
        ]),
      );
      for (final story in stories) {
        final body = story.body ?? '';
        expect(
          RegExp('#4').allMatches('${story.headline} $body').length,
          lessThanOrEqualTo(1),
          reason: '${story.headline} | $body',
        );
      }
    });

    test('a first stream is never the whole supporting paragraph', () {
      final stories = desk().compose(
        items([
          for (var i = 0; i < 12; i++)
            event(
              ChartMomentEventType.debut,
              entity: song('s$i'),
              source: 'play-$i',
              rank: 20 + i,
              streams: 1,
              at: DateTime.utc(2026, 10, 26, 9, i),
            ),
        ]),
      );
      for (final story in stories) {
        expect(story.body ?? '', isNot(contains('1 stream')));
      }
    });

    test('ordinals take the right article', () {
      expect(MomentFacts.withArticle('second'), 'a second');
      expect(MomentFacts.withArticle('eighth'), 'an eighth');
      expect(MomentFacts.withArticle('eleventh'), 'an eleventh');
      expect(MomentFacts.withArticle('11th'), 'an 11th');
      expect(MomentFacts.withArticle('18th'), 'an 18th');
      expect(MomentFacts.withArticle('80th'), 'an 80th');
      expect(MomentFacts.withArticle('12th'), 'a 12th');
      expect(MomentFacts.withArticle('100th'), 'a 100th');
      for (final family in MomentFamily.values) {
        for (final variant in MomentHeadlines.of(family)) {
          final text = variant.build(fullFacts(family));
          expect(
            text,
            isNot(matches(RegExp(r'a (eighth|eleventh|8|11th|18th)'))),
          );
        }
      }
    });
  });

  group('pictures match the headline', () {
    final lookups = FakeLookups(
      artists: {
        'artist-a': 'Name artist-a',
        'artist-b': 'Name artist-b',
        'guest': 'Guest Star',
      },
      featured: {
        'duet': ['Guest Star'],
        'posse': ['Guest Star', 'Someone Else'],
      },
      covers: {
        's1': '/covers/s1.jpg',
        's0': '/covers/s0.jpg',
        'duet': '/covers/duet.jpg',
        'posse': '/covers/posse.jpg',
        'r1': '/covers/r1.jpg',
        'r0': '/covers/r0.jpg',
      },
      portraits: {
        'artist-a': '/portraits/a.jpg',
        'artist-b': '/portraits/b.jpg',
        'guest': '/portraits/guest.jpg',
      },
    );
    MomentStory compose(List<ChartMomentEvent> events) =>
        MomentEditorialDesk(lookups: lookups).compose(items(events)).single;

    void expectImage(
      MomentImage? image,
      MomentImageKind kind,
      String entityId,
      String? path,
    ) {
      expect(image, isNotNull);
      expect(image!.kind, kind);
      expect(image.entityId, entityId);
      expect(image.path, path);
    }

    test('song story: song cover, then its artist', () {
      final story = compose([
        event(ChartMomentEventType.debut, entity: song('s1'), rank: 30),
      ]);
      expect(story.visual.layout, MomentVisualLayout.songAndArtist);
      expectImage(
        story.visual.left,
        MomentImageKind.cover,
        's1',
        '/covers/s1.jpg',
      );
      expectImage(
        story.visual.right,
        MomentImageKind.portrait,
        'artist-a',
        '/portraits/a.jpg',
      );
    });

    test('release story: release cover, then its owner', () {
      final story = compose([
        event(
          ChartMomentEventType.debut,
          entity: release('r1'),
          chartType: ChartType.albums,
          rank: 5,
        ),
      ]);
      expect(story.visual.layout, MomentVisualLayout.releaseAndOwner);
      expectImage(
        story.visual.left,
        MomentImageKind.cover,
        'r1',
        '/covers/r1.jpg',
      );
      expectImage(
        story.visual.right,
        MomentImageKind.portrait,
        'artist-a',
        '/portraits/a.jpg',
      );
    });

    test('artist passes artist: both portraits, in headline order', () {
      final story = compose([
        event(
          ChartMomentEventType.artistBecomesTopArtist,
          entity: artistEntity('artist-b'),
          threshold: 1,
          related: artistEntity('artist-a'),
        ),
      ]);
      expect(story.visual.layout, MomentVisualLayout.artistAndArtist);
      expectImage(
        story.visual.left,
        MomentImageKind.portrait,
        'artist-b',
        '/portraits/b.jpg',
      );
      expectImage(
        story.visual.right,
        MomentImageKind.portrait,
        'artist-a',
        '/portraits/a.jpg',
      );
      expect(
        story.headline.indexOf('Name artist-b'),
        lessThan(story.headline.indexOf('Name artist-a')),
      );
    });

    test('song passes song: both covers', () {
      final story = compose([
        event(
          ChartMomentEventType.firstNumberOne,
          entity: song('s1', artist: 'artist-b'),
          rank: 1,
          previousRank: 2,
          threshold: 1,
          related: song('s0'),
        ),
      ]);
      expect(story.visual.layout, MomentVisualLayout.songAndSong);
      expectImage(
        story.visual.left,
        MomentImageKind.cover,
        's1',
        '/covers/s1.jpg',
      );
      expectImage(
        story.visual.right,
        MomentImageKind.cover,
        's0',
        '/covers/s0.jpg',
      );
    });

    test('release passes release: both covers', () {
      final story = compose([
        event(
          ChartMomentEventType.firstNumberOne,
          entity: release('r1', artist: 'artist-b'),
          chartType: ChartType.albums,
          rank: 1,
          previousRank: 2,
          threshold: 1,
          related: release('r0'),
        ),
      ]);
      expect(story.visual.layout, MomentVisualLayout.releaseAndRelease);
      expectImage(
        story.visual.left,
        MomentImageKind.cover,
        'r1',
        '/covers/r1.jpg',
      );
      expectImage(
        story.visual.right,
        MomentImageKind.cover,
        'r0',
        '/covers/r0.jpg',
      );
    });

    test('a two-artist song: both portraits when the headline names both', () {
      final item = items([
        event(ChartMomentEventType.debut, entity: song('duet'), rank: 8),
      ]).single;
      final facts = MomentFacts.of(item, lookups);
      HeadlineVariant variant(String id) => MomentHeadlines.of(
        MomentFamily.songDebutTop10,
      ).firstWhere((v) => v.id == id);

      // "Song" by artist featuring guest debuts at #8 …
      final both = MomentVisuals.select(
        item: item,
        family: MomentFamily.songDebutTop10,
        facts: facts,
        variant: variant('song-debut-10-d1'),
        lookups: lookups,
      );
      expect(variant('song-debut-10-d1').build(facts), contains('Guest Star'));
      expect(both.layout, MomentVisualLayout.collaboration);
      expectImage(
        both.left,
        MomentImageKind.portrait,
        'artist-a',
        '/portraits/a.jpg',
      );
      expectImage(
        both.right,
        MomentImageKind.portrait,
        'guest',
        '/portraits/guest.jpg',
      );

      // A headline naming only the lead artist shows the song and them.
      final lead = MomentVisuals.select(
        item: item,
        family: MomentFamily.songDebutTop10,
        facts: facts,
        variant: variant('song-debut-10-p2'),
        lookups: lookups,
      );
      expect(
        variant('song-debut-10-p2').build(facts),
        isNot(contains('Guest')),
      );
      expect(lead.layout, MomentVisualLayout.songAndArtist);
    });

    test('three or more artists: the cover alone', () {
      final story = compose([
        event(ChartMomentEventType.debut, entity: song('posse'), rank: 8),
      ]);
      expect(story.visual.layout, MomentVisualLayout.singleCover);
      expectImage(
        story.visual.left,
        MomentImageKind.cover,
        'posse',
        '/covers/posse.jpg',
      );
      expect(story.visual.right, isNull);
    });

    test('artist milestone: one portrait; release milestone: one cover', () {
      final artist = compose([
        event(
          ChartMomentEventType.artistStreamMilestone,
          entity: artistEntity('artist-a'),
          milestone: 100,
          streams: 100,
        ),
      ]);
      expect(artist.visual.layout, MomentVisualLayout.singlePortrait);
      expectImage(
        artist.visual.left,
        MomentImageKind.portrait,
        'artist-a',
        '/portraits/a.jpg',
      );

      final album = compose([
        event(
          ChartMomentEventType.lifetimeStreamMilestone,
          entity: release('r1'),
          chartType: ChartType.albums,
          milestone: 100,
          streams: 100,
        ),
      ]);
      expect(album.visual.layout, MomentVisualLayout.singleCover);
      expectImage(
        album.visual.left,
        MomentImageKind.cover,
        'r1',
        '/covers/r1.jpg',
      );
    });

    test('missing artwork stays missing: never a stand-in picture', () {
      final story = compose([
        event(
          ChartMomentEventType.debut,
          entity: song('unknown', artist: 'nobody'),
          rank: 30,
        ),
      ]);
      expect(story.visual.left.entityId, 'unknown');
      expect(story.visual.left.hasImage, isFalse);
      expect(story.visual.right!.entityId, 'nobody');
      expect(story.visual.right!.hasImage, isFalse);
    });
  });
}

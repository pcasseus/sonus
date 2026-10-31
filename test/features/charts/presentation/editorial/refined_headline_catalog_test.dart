// SN-50 Batch 0: refined headline changes never reach stories told under the
// earlier rules, and unapproved changes have no effect anywhere (contract
// §5). Legacy rendering itself is pinned by legacy_rendering_golden_test.
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/charts/application/services/chart_moment_feed_aggregator.dart';
import 'package:sonus_next/features/charts/domain/models/chart_entity_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_rules.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_scope.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_editorial_desk.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_facts.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_family.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_headlines.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_publisher.dart';
import 'package:sonus_next/features/charts/presentation/editorial/refined_headline_catalog.dart';
import 'package:sonus_next/features/library/domain/entities/library_organization.dart';

class _Lookups implements MomentLookups {
  const _Lookups();

  @override
  String? artistName(String artistId) => 'Artist $artistId';
  @override
  ReleaseFormat? formatOf(String albumId) => ReleaseFormat.album;
  @override
  ReleaseFormat? songReleaseFormat(String songId) => ReleaseFormat.album;
  @override
  List<String> featuredOf(String songId) => const [];
  @override
  String? artistIdNamed(String name) => null;
  @override
  String? songCover(String songId) => null;
  @override
  String? releaseCover(String albumId) => null;
  @override
  String? currentSongCover(String songId) => null;
  @override
  String? currentReleaseCover(String albumId) => null;
  @override
  String? artistPortrait(String artistId) => null;
}

MomentFacts _facts({bool refined = true, String? featured}) => MomentFacts(
  chartType: ChartType.songs,
  weekly: true,
  refined: refined,
  title: 'Paper Moon',
  artist: 'Mira Vale',
  rank: 40,
  featured: featured,
);

List<String> _ids(List<HeadlineVariant> variants) => [
  for (final v in variants) v.id,
];

/// A debut at #40 on career standings, which both rule sets tell as a
/// songDebut story.
List<ChartMomentEvent> _debut(String source) {
  final song = ChartEntitySnapshot(
    entityId: 'song-$source',
    title: 'Song $source',
    artistId: 'mira',
    artistName: 'Artist mira',
  );
  final key = 'allTime|debut|song-$source|$source';
  return [
    ChartMomentEvent(
      id: key,
      deduplicationKey: key,
      sourceId: source,
      chartType: ChartType.songs,
      scope: ChartMomentScope.allTime,
      eventType: ChartMomentEventType.debut,
      entity: song,
      weekStartUtc: DateTime.utc(2026, 10, 19),
      weekEndUtc: DateTime.utc(2026, 10, 26),
      occurredAt: DateTime.utc(2026, 10, 26, 12),
      createdAt: DateTime.utc(2026, 10, 26, 12),
      currentRank: 40,
    ),
  ];
}

/// Every songDebut line reworded, so any refined story shows the change.
RefinedHeadlineCatalog _rewordDebuts({required bool approved}) =>
    RefinedHeadlineCatalog(
      overrides: [
        for (final v in MomentHeadlines.legacyOf(MomentFamily.songDebut))
          RefinedOverride(v.id, (f) => 'REFINED ${v.id}.', approved: approved),
      ],
    );

void main() {
  final activated = ChartMomentRules(activatedAtUtc: DateTime.utc(2026, 1, 1));

  group('SN-50 Batch 0: refined catalog isolation', () {
    test('MomentHeadlines.of is the frozen legacy catalog', () {
      for (final family in MomentHeadlines.families) {
        expect(
          identical(
            MomentHeadlines.of(family),
            MomentHeadlines.legacyOf(family),
          ),
          isTrue,
          reason: family.name,
        );
      }
    });

    test('unapproved overrides, exclusions and additions change nothing', () {
      final first = MomentHeadlines.legacyOf(MomentFamily.songDebut).first;
      final catalog = RefinedHeadlineCatalog(
        overrides: [RefinedOverride(first.id, (f) => 'X.', approved: false)],
        exclusions: [RefinedExclusion(first.id, approved: false)],
        additions: [
          RefinedAddition(
            MomentFamily.songDebut,
            HeadlineVariant(
              'song-debut-new',
              MomentPublisher.sonusDaily,
              (f) => 'Y.',
            ),
            approved: false,
          ),
        ],
      );
      for (final family in MomentHeadlines.families) {
        final refined = catalog.of(family, _facts());
        final legacy = MomentHeadlines.legacyOf(family);
        expect(_ids(refined), _ids(legacy), reason: family.name);
        for (var i = 0; i < legacy.length; i++) {
          expect(identical(refined[i], legacy[i]), isTrue);
        }
      }
    });

    test('an approved override keeps the id and place and changes only the '
        'refined text', () {
      final legacy = MomentHeadlines.legacyOf(MomentFamily.songDebut);
      final target = legacy[2];
      final catalog = RefinedHeadlineCatalog(
        overrides: [RefinedOverride(target.id, (f) => 'New.', approved: true)],
      );

      final refined = catalog.of(MomentFamily.songDebut, _facts());

      expect(_ids(refined), _ids(legacy));
      expect(refined[2].build(_facts()), 'New.');
      expect(refined[2].publisher, target.publisher);
      expect(refined[2].requires, target.requires);
      expect(target.build(_facts(refined: false)), isNot('New.'));
    });

    test('an approved exclusion applies only when its condition holds', () {
      final legacy = MomentHeadlines.legacyOf(MomentFamily.songDebut);
      final catalog = RefinedHeadlineCatalog(
        exclusions: [
          RefinedExclusion(
            legacy.first.id,
            when: (f) => f.featured != null,
            approved: true,
          ),
        ],
      );

      expect(_ids(catalog.of(MomentFamily.songDebut, _facts())), _ids(legacy));
      expect(
        _ids(catalog.of(MomentFamily.songDebut, _facts(featured: 'Guest'))),
        _ids(legacy).skip(1).toList(),
      );
    });

    test('an approved addition follows the family\'s catalog lines', () {
      final added = HeadlineVariant(
        'song-debut-added',
        MomentPublisher.pulsePop,
        (f) => 'Added.',
      );
      final catalog = RefinedHeadlineCatalog(
        additions: [
          RefinedAddition(MomentFamily.songDebut, added, approved: true),
        ],
      );

      expect(_ids(catalog.of(MomentFamily.songDebut, _facts())), [
        ..._ids(MomentHeadlines.legacyOf(MomentFamily.songDebut)),
        'song-debut-added',
      ]);
      expect(
        catalog.of(MomentFamily.songReentry, _facts()),
        MomentHeadlines.legacyOf(MomentFamily.songReentry),
      );
    });

    test('the desk uses refined changes only for stories under the refined '
        'rules', () {
      final feed = const ChartMomentFeedAggregator().aggregate([
        for (final source in ['a', 'b', 'c', 'd']) ..._debut(source),
      ]);

      MomentEditorialDesk desk(ChartMomentRules rules, bool approved) =>
          MomentEditorialDesk(
            lookups: const _Lookups(),
            rules: rules,
            refinedCatalog: _rewordDebuts(approved: approved),
          );
      final plain = MomentEditorialDesk(
        lookups: const _Lookups(),
        rules: ChartMomentRules.legacy,
      );

      final refined = desk(activated, true).compose(feed);
      expect(refined, isNotEmpty);
      for (final story in refined) {
        expect(story.headline, startsWith('REFINED '));
      }

      String headlines(List<MomentStory> stories) => [
        for (final s in stories) '${s.id}:${s.variantId}:${s.headline}',
      ].join('\n');
      expect(
        headlines(desk(ChartMomentRules.legacy, true).compose(feed)),
        headlines(plain.compose(feed)),
      );
      final before = ChartMomentRules(activatedAtUtc: DateTime.utc(2027, 1, 1));
      expect(
        headlines(desk(before, true).compose(feed)),
        headlines(plain.compose(feed)),
      );
      for (final story in desk(activated, false).compose(feed)) {
        expect(story.headline, isNot(startsWith('REFINED ')));
      }
    });

    test('every standard change names a real line, and additions have new '
        'ids', () {
      final catalog = RefinedHeadlineCatalog.standard;
      final legacyIds = {
        for (final family in MomentHeadlines.families)
          ..._ids(MomentHeadlines.legacyOf(family)),
      };
      for (final override in catalog.overrides) {
        expect(legacyIds, contains(override.id));
      }
      for (final exclusion in catalog.exclusions) {
        expect(legacyIds, contains(exclusion.id));
      }
      final added = [for (final a in catalog.additions) a.variant.id];
      expect(added.toSet().length, added.length);
      expect(added.toSet().intersection(legacyIds), isEmpty);
    });
  });
}

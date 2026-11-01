// SN-50 R-V (Progress BLOCKED #28): a refined story keeps the headline
// catalog version it was first told with. Version 1 starts at the
// activation instant; each later version at the first run of a build that
// carries it (write-once, per install). Missing or unreadable metadata
// never re-tells a story with other words.
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/charts/application/services/chart_moment_feed_aggregator.dart';
import 'package:sonus_next/features/charts/application/services/moment_rules_activation.dart';
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
import 'package:sonus_next/features/charts/presentation/editorial/refined_headline_catalog.dart';
import 'package:sonus_next/features/library/domain/entities/library_organization.dart';

final _activated = DateTime.utc(2026, 10, 1);
final _v2Start = DateTime.utc(2026, 10, 20);

ChartMomentRules _withV2() => ChartMomentRules(
  activatedAtUtc: _activated,
  catalogStarts: [RefinedCatalogStart(2, _v2Start)],
);

class _Store implements MomentRulesActivationStore {
  _Store({this.activation, Map<int, String>? starts}) : starts = starts ?? {};

  String? activation;
  final Map<int, String> starts;
  bool dropCatalogWrites = false;
  int reads = 0;
  int writes = 0;

  @override
  Future<String?> read() async {
    reads++;
    return activation;
  }

  @override
  Future<void> write(String activatedAtUtc) async {
    writes++;
    activation = activatedAtUtc;
  }

  @override
  Future<String?> readCatalogStart(int version) async {
    reads++;
    return starts[version];
  }

  @override
  Future<void> writeCatalogStart(int version, String fromUtc) async {
    writes++;
    if (!dropCatalogWrites) starts[version] = fromUtc;
  }
}

class _Lookups implements MomentLookups {
  const _Lookups();

  @override
  String? artistName(String artistId) => 'Mira Vale';
  @override
  ReleaseFormat? formatOf(String albumId) => ReleaseFormat.album;
  @override
  ReleaseFormat? songReleaseFormat(String songId) => ReleaseFormat.album;
  @override
  List<String> guestsOf(String songId) => const [];

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

/// A career debut at #40 at [at]: a songDebut story under both rule sets.
ChartMomentEvent _debut(String id, DateTime at) => ChartMomentEvent(
  id: 'allTime|debut|$id',
  deduplicationKey: 'allTime|debut|$id',
  sourceId: id,
  chartType: ChartType.songs,
  scope: ChartMomentScope.allTime,
  eventType: ChartMomentEventType.debut,
  entity: ChartEntitySnapshot(
    entityId: id,
    title: 'Song $id',
    artistId: 'mira',
    artistName: 'Mira Vale',
  ),
  weekStartUtc: DateTime.utc(at.year, at.month, at.day),
  weekEndUtc: DateTime.utc(at.year, at.month, at.day + 7),
  occurredAt: at,
  createdAt: at,
  currentRank: 40,
);

/// A hypothetical version 2 that rewords every songDebut line.
final _v2 = RefinedHeadlineCatalog(
  overrides: [
    for (final v in MomentHeadlines.legacyOf(MomentFamily.songDebut))
      RefinedOverride(v.id, (f) => 'V2 ${v.id}.', approved: true),
  ],
);

String _key(MomentStory s) => '${s.id}|${s.variantId}|${s.headline}|${s.body}';

void main() {
  group('SN-50 R-V: catalog version boundaries', () {
    test('career stories take the version that had started by the play', () {
      final rules = _withV2();
      int? at(DateTime time) => rules.catalogVersionFor(
        scope: ChartMomentScope.allTime,
        occurredAt: time,
        weekStartUtc: DateTime.utc(2026, 9, 28),
      );
      expect(at(_activated.subtract(const Duration(seconds: 1))), isNull);
      expect(at(_activated), 1);
      expect(at(_v2Start.subtract(const Duration(seconds: 1))), 1);
      expect(at(_v2Start), 2);
      expect(at(DateTime.utc(2027)), 2);
    });

    test('weekly stories take the version that had started by the week\'s '
        'start, however late they are finalized', () {
      final rules = _withV2();
      int? week(DateTime start) => rules.catalogVersionFor(
        scope: ChartMomentScope.finalized,
        occurredAt: DateTime.utc(2027),
        weekStartUtc: start,
      );
      expect(week(DateTime.utc(2026, 9, 28)), isNull);
      expect(week(DateTime.utc(2026, 10, 5)), 1);
      expect(week(DateTime.utc(2026, 10, 19)), 1);
      expect(week(DateTime.utc(2026, 10, 26)), 2);
    });

    test('without an activation there is no refined version at all', () {
      expect(
        const ChartMomentRules().catalogVersionFor(
          scope: ChartMomentScope.allTime,
          occurredAt: DateTime.utc(2027),
          weekStartUtc: DateTime.utc(2027),
        ),
        isNull,
      );
    });

    test('this build carries exactly versions 1 to the current one', () {
      expect(ChartMomentRules.currentCatalogVersion, 1);
      expect(RefinedHeadlineCatalog.versions.keys.toSet(), {
        for (var v = 1; v <= ChartMomentRules.currentCatalogVersion; v++) v,
      });
      expect(
        identical(
          RefinedHeadlineCatalog.forVersion(1),
          RefinedHeadlineCatalog.standard,
        ),
        isTrue,
      );
    });
  });

  group('SN-50 R-V: recording catalog starts', () {
    test('a stored marker and starts with the flag off read nothing and keep '
        'the earlier rules', () async {
      final store = _Store(
        activation: '2026-10-01T00:00:00.000Z',
        starts: {2: '2026-10-20T00:00:00.000Z'},
      );
      final rules = await MomentRulesActivation(
        store: store,
        approved: false,
        catalogVersion: 2,
      ).rules();
      expect(rules.activatedAtUtc, isNull);
      expect(store.reads + store.writes, 0);
    });

    test('a version 1 build records no catalog start', () async {
      final store = _Store(activation: '2026-10-01T00:00:00.000Z');
      final rules = await MomentRulesActivation(
        store: store,
        approved: true,
      ).rules();
      expect(rules.activatedAtUtc, _activated);
      expect(rules.catalogStarts, isEmpty);
      expect(store.writes, 0);
      expect(store.starts, isEmpty);
    });

    test('a version 2 build starts version 2 at its first run, never '
        'earlier, and a restart keeps it', () async {
      final store = _Store(activation: '2026-10-01T00:00:00.000Z');
      final first = await MomentRulesActivation(
        store: store,
        approved: true,
        catalogVersion: 2,
        now: () => DateTime.utc(2026, 10, 20, 9),
      ).rules();
      expect(first.catalogStarts.single.version, 2);
      expect(first.catalogStarts.single.fromUtc, DateTime.utc(2026, 10, 20, 9));

      final restarted = await MomentRulesActivation(
        store: store,
        approved: true,
        catalogVersion: 2,
        now: () => DateTime.utc(2026, 12, 1),
      ).rules();
      expect(restarted.activatedAtUtc, _activated);
      expect(
        restarted.catalogStarts.single.fromUtc,
        DateTime.utc(2026, 10, 20, 9),
      );
      final story = (
        scope: ChartMomentScope.allTime,
        occurredAt: DateTime.utc(2026, 10, 10),
        weekStartUtc: DateTime.utc(2026, 10, 5),
      );
      expect(
        restarted.catalogVersionFor(
          scope: story.scope,
          occurredAt: story.occurredAt,
          weekStartUtc: story.weekStartUtc,
        ),
        first.catalogVersionFor(
          scope: story.scope,
          occurredAt: story.occurredAt,
          weekStartUtc: story.weekStartUtc,
        ),
      );
    });

    test('a fresh install on a version 2 build starts both at the same '
        'instant', () async {
      final store = _Store();
      final rules = await MomentRulesActivation(
        store: store,
        approved: true,
        catalogVersion: 2,
        now: () => DateTime.utc(2026, 11, 3),
      ).rules();
      expect(rules.activatedAtUtc, DateTime.utc(2026, 11, 3));
      expect(rules.catalogStarts.single.fromUtc, DateTime.utc(2026, 11, 3));
    });

    test('an unreadable or unsaved start, or a start from a newer build, '
        'keeps the earlier rules', () async {
      Future<ChartMomentRules> resolve(_Store store, int version) =>
          MomentRulesActivation(
            store: store,
            approved: true,
            catalogVersion: version,
            now: () => DateTime.utc(2026, 11, 3),
          ).rules();
      const activation = '2026-10-01T00:00:00.000Z';

      final corrupt = await resolve(
        _Store(activation: activation, starts: {2: 'not a date'}),
        2,
      );
      expect(corrupt.activatedAtUtc, isNull);

      final dropped = _Store(activation: activation)..dropCatalogWrites = true;
      expect((await resolve(dropped, 2)).activatedAtUtc, isNull);

      final newer = await resolve(
        _Store(activation: activation, starts: {2: '2026-10-20T00:00:00.000Z'}),
        1,
      );
      expect(newer.activatedAtUtc, isNull);
    });
  });

  group('SN-50 R-V: composing with more than one catalog version', () {
    final feed = const ChartMomentFeedAggregator().aggregate([
      for (var i = 0; i < 12; i++) ...[
        _debut('before-$i', DateTime.utc(2026, 10, 10, 8, i)),
        _debut('after-$i', DateTime.utc(2026, 10, 25, 8, i)),
        _debut('legacy-$i', DateTime.utc(2026, 9, 20, 8, i)),
      ],
    ]);

    List<MomentStory> compose(
      ChartMomentRules rules, {
      Map<int, RefinedHeadlineCatalog>? catalogs,
    }) => MomentEditorialDesk(
      lookups: const _Lookups(),
      rules: rules,
      refinedCatalogs: catalogs,
    ).compose(feed);

    test('stories first told with v1 stay byte-identical when v2 exists', () {
      final v1Only = {
        for (final s in compose(ChartMomentRules(activatedAtUtc: _activated)))
          if (s.id.contains('before-') || s.id.contains('legacy-'))
            s.id: _key(s),
      };
      final both = compose(
        _withV2(),
        catalogs: {1: RefinedHeadlineCatalog.standard, 2: _v2},
      );

      expect(v1Only, hasLength(24));
      for (final story in both) {
        if (story.id.contains('after-')) {
          expect(story.headline, startsWith('V2 '));
        } else {
          expect(_key(story), v1Only[story.id], reason: story.id);
          expect(story.headline, isNot(startsWith('V2 ')));
        }
      }
    });

    test('a story whose catalog this build lacks is held, never re-told', () {
      final stories = compose(
        _withV2(),
        catalogs: {1: RefinedHeadlineCatalog.standard},
      );
      expect(stories.where((s) => s.id.contains('after-')), isEmpty);
      expect(stories.where((s) => s.id.contains('before-')), hasLength(12));
      expect(stories.where((s) => s.id.contains('legacy-')), hasLength(12));
    });

    test('the facts carry the version each story is told with', () {
      for (final story in compose(
        _withV2(),
        catalogs: {1: RefinedHeadlineCatalog.standard, 2: _v2},
      )) {
        final expected = story.id.contains('legacy-')
            ? null
            : story.id.contains('after-')
            ? 2
            : 1;
        expect(story.facts.catalogVersion, expected, reason: story.id);
        expect(story.facts.refined, expected != null);
      }
    });
  });
}

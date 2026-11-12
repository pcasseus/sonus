// App Update 1.2, REF-19: two primary artists jointly holding every place
// from #1 to #N (N at least 4, two songs each) on a finalized weekly Sonus
// Hot 100. Never a collaboration, never an ordinary Top 2 split.
import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/charts/domain/entities/chart_entry.dart';
import 'package:sonus_next/features/charts/domain/entities/chart_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_entity_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_movement.dart';
import 'package:sonus_next/features/charts/domain/models/chart_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_artist_dominance.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_artist_joint_control.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_scope.dart';

void main() {
  const detector = ChartMomentArtistJointControlDetector();
  final createdAt = DateTime.utc(2026, 11, 16, 1);
  final weekStart = DateTime.utc(2026, 11, 8);

  ChartEntry entry(String songId, String artistId, int rank) => ChartEntry(
    entity: ChartEntitySnapshot(
      entityId: songId,
      title: 'Song $songId',
      artistId: artistId,
      artistName: 'Name $artistId',
    ),
    rank: rank,
    qualifiedStreamCount: 300 - rank,
    lastQualifiedAt: weekStart,
    peakRank: rank,
    peakAchievedAt: weekStart,
    weeksOnChart: 1,
    movement: ChartMovement.newEntry,
  );

  /// [top] lists the artist at #1, #2 ...; every later place has an artist
  /// of its own.
  ChartSnapshot week(
    List<String> top, {
    int weeksBefore = 0,
    ChartType chartType = ChartType.songs,
  }) {
    final from = weekStart.subtract(Duration(days: 7 * weeksBefore));
    return ChartSnapshot(
      id: 'week-$weeksBefore',
      chartType: chartType,
      weekStartUtc: from,
      weekEndUtc: from.add(const Duration(days: 7)),
      finalizedAt: from.add(const Duration(days: 7)),
      entries: [
        for (var rank = 1; rank <= 100; rank++)
          rank <= top.length
              ? entry(
                  '${top[rank - 1]}-$rank-$weeksBefore',
                  top[rank - 1],
                  rank,
                )
              : entry('other-$rank-$weeksBefore', 'other-$rank', rank),
      ],
    );
  }

  /// Every song credited only to its own artist.
  Map<String, ChartSongCredits> soloCredits(ChartSnapshot snapshot) => {
    for (final e in snapshot.entries)
      e.entity.entityId: ChartSongCredits(
        artistIds: {e.entity.artistId!},
        complete: true,
      ),
  };

  Map<String, String?> chartArtists(ChartSnapshot snapshot) => {
    for (final e in snapshot.entries) e.entity.entityId: e.entity.artistId,
  };

  List<ChartMomentEvent> detect(
    ChartSnapshot snapshot, {
    List<ChartSnapshot> history = const [],
    Map<String, ChartSongCredits>? credits,
    Map<String, String?>? artists,
  }) => detector.detect(
    snapshot: snapshot,
    history: history,
    createdAt: createdAt,
    credits: credits ?? soloCredits(snapshot),
    chartArtists: artists ?? chartArtists(snapshot),
  );

  List<(String, int, int, String)> facts(
    ChartSnapshot snapshot, {
    List<ChartSnapshot> history = const [],
    Map<String, ChartSongCredits>? credits,
    Map<String, String?>? artists,
  }) => [
    for (final event in detect(
      snapshot,
      history: history,
      credits: credits,
      artists: artists,
    ))
      if (ArtistJointControl.of(event) case final fact?)
        (
          event.entity.artistId!,
          fact.positions,
          event.milestoneValue!,
          fact.partnerArtistId,
        ),
  ];

  const a = 'artist-a';
  const b = 'artist-b';

  test('two artists holding #1–#N between them, two songs each: one row '
      'per artist, with its own count', () {
    expect(facts(week([a, b, a, b])), [(a, 4, 2, b), (b, 4, 2, a)]);
    expect(facts(week([a, a, b, a, b, b, a])), [(a, 7, 4, b), (b, 7, 3, a)]);
  });

  test('the largest N: the zone ends where a third artist appears', () {
    expect(facts(week([a, b, b, a, 'c', a])), [(a, 4, 2, b), (b, 4, 2, a)]);
  });

  test('never an ordinary Top 2 or Top 3 split', () {
    expect(facts(week([a, b])), isEmpty);
    expect(facts(week([a, b, a])), isEmpty);
    expect(facts(week([a, b, b, 'c'])), isEmpty);
  });

  test('each artist needs two songs in the zone', () {
    expect(facts(week([a, a, a, b])), isEmpty);
    expect(facts(week([a, a, a, a, b, 'c'])), isEmpty);
  });

  test('one artist alone is a sweep, never joint control', () {
    expect(facts(week([a, a, a, a, a])), isEmpty);
  });

  group('collaborations and unclear credits are excluded', () {
    final snapshot = week([a, b, a, b]);
    final songOfA = snapshot.entries.first.entity.entityId;

    test('a song in the zone credits both artists', () {
      expect(
        facts(
          snapshot,
          credits: {
            ...soloCredits(snapshot),
            songOfA: const ChartSongCredits(artistIds: {a, b}, complete: true),
          },
        ),
        isEmpty,
      );
    });

    test('a song credits the partner under the identity it charts as', () {
      final artists = {...chartArtists(snapshot), songOfA: 'a-project'};
      expect(
        facts(
          snapshot,
          artists: artists,
          credits: {
            ...soloCredits(snapshot),
            snapshot.entries[1].entity.entityId: const ChartSongCredits(
              artistIds: {b, 'a-project'},
              complete: true,
            ),
          },
        ),
        isEmpty,
      );
    });

    test('both artists chart under one shared identity', () {
      final artists = {
        for (final e in snapshot.entries.take(4))
          e.entity.entityId: 'shared-identity',
      };
      expect(facts(snapshot, artists: artists), isEmpty);
    });

    test('a song has unclear credits, or none known', () {
      expect(
        facts(
          snapshot,
          credits: {
            ...soloCredits(snapshot),
            songOfA: const ChartSongCredits(artistIds: {a}, complete: false),
          },
        ),
        isEmpty,
      );
      expect(
        facts(snapshot, credits: {...soloCredits(snapshot)}..remove(songOfA)),
        isEmpty,
      );
    });

    test('a featured third artist is no collaboration between the pair', () {
      expect(
        facts(
          snapshot,
          credits: {
            ...soloCredits(snapshot),
            songOfA: const ChartSongCredits(
              artistIds: {a, 'guest'},
              complete: true,
            ),
          },
        ),
        [(a, 4, 2, b), (b, 4, 2, a)],
      );
    });
  });

  group('new, grown and held', () {
    test('held or smaller for the same pair: quiet', () {
      for (final before in [
        [a, b, a, b],
        [a, b, b, a, a],
      ]) {
        expect(
          facts(week([b, a, a, b]), history: [week(before, weeksBefore: 1)]),
          isEmpty,
          reason: 'the pair, read either way',
        );
      }
    });

    test('grown, or a new pair: told', () {
      expect(
        facts(
          week([a, b, a, b, a]),
          history: [
            week([a, b, a, b], weeksBefore: 1),
          ],
        ),
        [(a, 5, 3, b), (b, 5, 2, a)],
      );
      expect(
        facts(
          week([a, b, a, b]),
          history: [
            week([a, 'c', a, 'c'], weeksBefore: 1),
          ],
        ),
        [(a, 4, 2, b), (b, 4, 2, a)],
      );
    });
  });

  test('kept distinct from the artists\' own achievements: a sweep inside '
      'the zone is still recorded by the dominance detector', () {
    final snapshot = week([a, a, a, b, b]);
    expect(facts(snapshot), [(a, 5, 3, b), (b, 5, 2, a)]);
    final sweep = const ChartMomentArtistDominanceDetector().detect(
      snapshot: snapshot,
      history: const [],
      createdAt: createdAt,
    );
    expect([for (final e in sweep) ArtistDominance.of(e)?.tier], contains(3));
  });

  test('the album chart and unfinalized weeks are never read', () {
    expect(facts(week([a, b, a, b], chartType: ChartType.albums)), isEmpty);
    final live = ChartSnapshot(
      id: 'live',
      chartType: ChartType.songs,
      weekStartUtc: weekStart,
      weekEndUtc: weekStart.add(const Duration(days: 7)),
      entries: const [],
    );
    expect(() => detect(live, credits: const {}), throwsArgumentError);
  });

  group('compatibility', () {
    test('stored as the existing type: each row is a true "N songs in the '
        'Top T" for its own artist', () {
      final events = detect(week([a, b, a, b, a]));
      expect(events, hasLength(2));
      final first = events.first;
      expect(
        first.eventType,
        ChartMomentEventType.artistSimultaneousThresholdSongs,
      );
      expect(first.scope, ChartMomentScope.finalized);
      expect((first.threshold, first.milestoneValue), (5, 3));
      expect(first.currentRank, 1);
      expect(first.entity.artistId, a);
      expect(first.relatedEntity?.artistId, b);
      expect(first.sourceId, 'joint:5:$b:week-0');
      expect(
        first.deduplicationKey,
        'moment:finalized:songs:${weekStart.millisecondsSinceEpoch}:$a:'
        'joint:5:$b:week-0',
      );
      expect(events.map((e) => e.deduplicationKey).toSet(), hasLength(2));
      expect(
        [for (final e in events) ArtistDominance.of(e)],
        everyElement(isNull),
        reason: 'never read as a dominance row',
      );
    });

    test('malformed sources are not joint control', () {
      ChartMomentEvent stored(String? source) => ChartMomentEvent(
        id: 'id',
        deduplicationKey: 'key',
        chartType: ChartType.songs,
        scope: ChartMomentScope.finalized,
        eventType: ChartMomentEventType.artistSimultaneousThresholdSongs,
        entity: entry('s', a, 1).entity,
        weekStartUtc: weekStart,
        weekEndUtc: weekStart.add(const Duration(days: 7)),
        occurredAt: weekStart,
        createdAt: createdAt,
        sourceId: source,
      );
      for (final source in [
        null,
        'joint:3:$b:w',
        'joint:x:$b:w',
        'joint:5::w',
        'joint:5:$b:',
        'joint:5:$b',
        'dominance:sweep:5:-:w',
      ]) {
        expect(ArtistJointControl.of(stored(source)), isNull, reason: source);
      }
      expect(ArtistJointControl.of(stored('joint:6:$b:w'))?.positions, 6);
    });

    test('deterministic: the same week gives the same rows', () {
      expect(
        [
          for (final e in detect(week([a, b, a, b]))) e.sourceId,
        ],
        [
          for (final e in detect(week([a, b, a, b]))) e.sourceId,
        ],
      );
    });
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/charts/domain/entities/chart_entry.dart';
import 'package:sonus_next/features/charts/domain/entities/chart_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_entity_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_movement.dart';
import 'package:sonus_next/features/charts/domain/models/chart_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_artist_achievement_detector.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_scope.dart';

void main() {
  const detector = ChartMomentArtistAchievementDetector();

  final currentStart = DateTime.utc(2026, 9, 27);
  final currentEnd = DateTime.utc(2026, 10, 4);
  final createdAt = DateTime.utc(2026, 10, 4, 1);

  ChartEntitySnapshot song(
    String id, {
    String artistId = 'artist-a',
    String artistName = 'Artist A',
  }) {
    return ChartEntitySnapshot(
      entityId: id,
      title: 'Song $id',
      artistId: artistId,
      artistName: artistName,
      albumTitle: 'Album A',
    );
  }

  ChartEntitySnapshot album(String id, {String artistId = 'artist-a'}) {
    return ChartEntitySnapshot(
      entityId: id,
      title: 'Album $id',
      artistId: artistId,
      artistName: 'Artist A',
    );
  }

  ChartEntry entry(
    ChartEntitySnapshot entity, {
    required int rank,
    int? peakRank,
  }) {
    return ChartEntry(
      entity: entity,
      rank: rank,
      qualifiedStreamCount: 10,
      lastQualifiedAt: DateTime.utc(2026, 10, 3, 20),
      previousFinalRank: null,
      peakRank: peakRank ?? rank,
      peakAchievedAt: DateTime.utc(2026, 10, 3, 20),
      weeksOnChart: 1,
      movement: ChartMovement.newEntry,
    );
  }

  ChartSnapshot finalized({
    required String id,
    required DateTime start,
    required DateTime end,
    required List<ChartEntry> entries,
    ChartType chartType = ChartType.songs,
  }) {
    return ChartSnapshot(
      id: id,
      chartType: chartType,
      weekStartUtc: start,
      weekEndUtc: end,
      finalizedAt: end,
      entries: entries,
    );
  }

  List<ChartMomentEvent> detect({
    required ChartSnapshot snapshot,
    Iterable<ChartSnapshot> history = const [],
  }) {
    return detector.detect(
      snapshot: snapshot,
      history: history,
      createdAt: createdAt,
    );
  }

  List<ChartMomentEvent> ofType(
    Iterable<ChartMomentEvent> events,
    ChartMomentEventType type,
  ) {
    return events
        .where((event) => event.eventType == type)
        .toList(growable: false);
  }

  group('ChartMomentArtistAchievementDetector', () {
    test('rejects live snapshots', () {
      final live = ChartSnapshot(
        id: 'live',
        chartType: ChartType.songs,
        weekStartUtc: currentStart,
        weekEndUtc: currentEnd,
        entries: [entry(song('song-a'), rank: 10)],
      );

      expect(() => detect(snapshot: live), throwsArgumentError);
    });

    test('first charting song establishes first threshold accomplishments', () {
      final snapshot = finalized(
        id: 'current',
        start: currentStart,
        end: currentEnd,
        entries: [entry(song('song-a'), rank: 10)],
      );

      final events = detect(snapshot: snapshot);

      final thresholds = ofType(
        events,
        ChartMomentEventType.artistFirstThresholdSong,
      );

      expect(thresholds.map((event) => event.threshold).toList(), [
        200,
        100,
        75,
        50,
        40,
        30,
        25,
        20,
        15,
        10,
      ]);

      expect(thresholds.every((event) => event.milestoneValue == 1), isTrue);

      expect(
        ofType(events, ChartMomentEventType.artistHighestChartingSong),
        hasLength(1),
      );

      expect(
        ofType(events, ChartMomentEventType.artistFirstNumberOneSong),
        isEmpty,
      );
    });

    test('second distinct Top 10 song emits nth threshold accomplishment', () {
      final old = finalized(
        id: 'old',
        start: DateTime.utc(2026, 9, 20),
        end: currentStart,
        entries: [entry(song('song-old'), rank: 7)],
      );

      final snapshot = finalized(
        id: 'current',
        start: currentStart,
        end: currentEnd,
        entries: [entry(song('song-new'), rank: 9)],
      );

      final events = detect(snapshot: snapshot, history: [old]);

      final top10 = ofType(
        events,
        ChartMomentEventType.artistNthThresholdSong,
      ).singleWhere((event) => event.threshold == 10);

      expect(top10.milestoneValue, 2);

      expect(
        ofType(events, ChartMomentEventType.artistHighestChartingSong),
        isEmpty,
      );
    });

    test(
      'returning same song to threshold does not increment catalog count',
      () {
        final old = finalized(
          id: 'old',
          start: DateTime.utc(2026, 9, 13),
          end: DateTime.utc(2026, 9, 20),
          entries: [entry(song('song-a'), rank: 8)],
        );

        final snapshot = finalized(
          id: 'current',
          start: currentStart,
          end: currentEnd,
          entries: [entry(song('song-a'), rank: 10, peakRank: 8)],
        );

        final events = detect(snapshot: snapshot, history: [old]);

        expect(
          ofType(events, ChartMomentEventType.artistFirstThresholdSong),
          isEmpty,
        );

        expect(
          ofType(events, ChartMomentEventType.artistNthThresholdSong),
          isEmpty,
        );
      },
    );

    test('new career-best song records prior record holder', () {
      final oldEntity = song('song-old');

      final old = finalized(
        id: 'old',
        start: DateTime.utc(2026, 9, 20),
        end: currentStart,
        entries: [entry(oldEntity, rank: 7)],
      );

      final snapshot = finalized(
        id: 'current',
        start: currentStart,
        end: currentEnd,
        entries: [entry(song('song-new'), rank: 4)],
      );

      final events = detect(snapshot: snapshot, history: [old]);

      final achievement = ofType(
        events,
        ChartMomentEventType.artistHighestChartingSong,
      ).single;

      expect(achievement.previousPeakRank, 7);
      expect(achievement.currentPeakRank, 4);
      expect(achievement.relatedEntity, isNotNull);
      expect(achievement.relatedEntity!.entityId, 'song-old');
    });

    test('same entity improving its own career best also emits record', () {
      final old = finalized(
        id: 'old',
        start: DateTime.utc(2026, 9, 20),
        end: currentStart,
        entries: [entry(song('song-a'), rank: 7)],
      );

      final snapshot = finalized(
        id: 'current',
        start: currentStart,
        end: currentEnd,
        entries: [entry(song('song-a'), rank: 3, peakRank: 3)],
      );

      final events = detect(snapshot: snapshot, history: [old]);

      final achievement = ofType(
        events,
        ChartMomentEventType.artistHighestChartingSong,
      ).single;

      expect(achievement.previousPeakRank, 7);
      expect(achievement.currentPeakRank, 3);
    });

    test(
      'matching career best does not emit highest-charting accomplishment',
      () {
        final old = finalized(
          id: 'old',
          start: DateTime.utc(2026, 9, 20),
          end: currentStart,
          entries: [entry(song('song-old'), rank: 3)],
        );

        final snapshot = finalized(
          id: 'current',
          start: currentStart,
          end: currentEnd,
          entries: [entry(song('song-new'), rank: 3)],
        );

        final events = detect(snapshot: snapshot, history: [old]);

        expect(
          ofType(events, ChartMomentEventType.artistHighestChartingSong),
          isEmpty,
        );
      },
    );

    test('first and nth distinct number-one songs use dedicated events', () {
      final firstSnapshot = finalized(
        id: 'first',
        start: DateTime.utc(2026, 9, 20),
        end: currentStart,
        entries: [entry(song('song-one'), rank: 1)],
      );

      final firstEvents = detect(snapshot: firstSnapshot);

      final firstNumberOne = ofType(
        firstEvents,
        ChartMomentEventType.artistFirstNumberOneSong,
      ).single;

      expect(firstNumberOne.threshold, 1);
      expect(firstNumberOne.milestoneValue, 1);

      expect(
        ofType(
          firstEvents,
          ChartMomentEventType.artistFirstThresholdSong,
        ).where((event) => event.threshold == 1),
        isEmpty,
      );

      final current = finalized(
        id: 'current',
        start: currentStart,
        end: currentEnd,
        entries: [entry(song('song-two'), rank: 1)],
      );

      final secondEvents = detect(snapshot: current, history: [firstSnapshot]);

      final secondNumberOne = ofType(
        secondEvents,
        ChartMomentEventType.artistNthNumberOneSong,
      ).single;

      expect(secondNumberOne.milestoneValue, 2);
    });

    test(
      'repeat number one by same song does not increment number-one count',
      () {
        final old = finalized(
          id: 'old',
          start: DateTime.utc(2026, 9, 20),
          end: currentStart,
          entries: [entry(song('song-a'), rank: 1)],
        );

        final current = finalized(
          id: 'current',
          start: currentStart,
          end: currentEnd,
          entries: [entry(song('song-a'), rank: 1, peakRank: 1)],
        );

        final events = detect(snapshot: current, history: [old]);

        expect(
          ofType(events, ChartMomentEventType.artistFirstNumberOneSong),
          isEmpty,
        );

        expect(
          ofType(events, ChartMomentEventType.artistNthNumberOneSong),
          isEmpty,
        );
      },
    );

    test('artists with the same display name remain separate by artistId', () {
      final old = finalized(
        id: 'old',
        start: DateTime.utc(2026, 9, 20),
        end: currentStart,
        entries: [
          entry(
            song(
              'song-other',
              artistId: 'artist-other',
              artistName: 'Same Name',
            ),
            rank: 1,
          ),
        ],
      );

      final current = finalized(
        id: 'current',
        start: currentStart,
        end: currentEnd,
        entries: [
          entry(
            song(
              'song-current',
              artistId: 'artist-current',
              artistName: 'Same Name',
            ),
            rank: 1,
          ),
        ],
      );

      final events = detect(snapshot: current, history: [old]);

      expect(
        ofType(events, ChartMomentEventType.artistFirstNumberOneSong),
        hasLength(1),
      );

      expect(
        ofType(events, ChartMomentEventType.artistNthNumberOneSong),
        isEmpty,
      );
    });

    test(
      'missing stable artist identity is ignored rather than grouped by name',
      () {
        final current = finalized(
          id: 'current',
          start: currentStart,
          end: currentEnd,
          entries: [
            entry(
              const ChartEntitySnapshot(
                entityId: 'legacy-song',
                title: 'Legacy Song',
                artistName: 'Legacy Artist',
              ),
              rank: 1,
            ),
          ],
        );

        expect(detect(snapshot: current), isEmpty);
      },
    );

    test('same-week stale and future snapshots do not affect career state', () {
      final earlier = finalized(
        id: 'earlier',
        start: DateTime.utc(2026, 9, 20),
        end: currentStart,
        entries: [entry(song('song-old'), rank: 20)],
      );

      final staleCurrent = finalized(
        id: 'stale-current',
        start: currentStart,
        end: currentEnd,
        entries: [entry(song('song-stale'), rank: 1)],
      );

      final future = finalized(
        id: 'future',
        start: currentEnd,
        end: DateTime.utc(2026, 10, 11),
        entries: [entry(song('song-future'), rank: 1)],
      );

      final current = finalized(
        id: 'current',
        start: currentStart,
        end: currentEnd,
        entries: [entry(song('song-new'), rank: 10)],
      );

      final events = detect(
        snapshot: current,
        history: [earlier, staleCurrent, future],
      );

      final achievement = ofType(
        events,
        ChartMomentEventType.artistHighestChartingSong,
      ).single;

      expect(achievement.previousPeakRank, 20);
      expect(achievement.currentPeakRank, 10);
    });

    test(
      'album achievements use album event types with identical semantics',
      () {
        final old = finalized(
          id: 'old-albums',
          start: DateTime.utc(2026, 9, 20),
          end: currentStart,
          chartType: ChartType.albums,
          entries: [entry(album('album-old'), rank: 8)],
        );

        final current = finalized(
          id: 'current-albums',
          start: currentStart,
          end: currentEnd,
          chartType: ChartType.albums,
          entries: [entry(album('album-new'), rank: 5)],
        );

        final events = detect(snapshot: current, history: [old]);

        expect(
          ofType(
            events,
            ChartMomentEventType.artistNthThresholdAlbum,
          ).where((event) => event.threshold == 10),
          hasLength(1),
        );

        expect(
          ofType(events, ChartMomentEventType.artistHighestChartingAlbum),
          hasLength(1),
        );

        expect(
          events.every((event) => event.chartType == ChartType.albums),
          isTrue,
        );
      },
    );

    test(
      'multiple same-week entries advance catalog ordinals and emit one career best',
      () {
        final current = finalized(
          id: 'current',
          start: currentStart,
          end: currentEnd,
          entries: [
            entry(song('song-a'), rank: 5),
            entry(song('song-b'), rank: 8),
          ],
        );

        final events = detect(snapshot: current);

        final firstTop10 = ofType(
          events,
          ChartMomentEventType.artistFirstThresholdSong,
        ).where((event) => event.threshold == 10).toList();

        final nthTop10 = ofType(
          events,
          ChartMomentEventType.artistNthThresholdSong,
        ).where((event) => event.threshold == 10).toList();

        expect(firstTop10, hasLength(1));
        expect(firstTop10.single.entity.entityId, 'song-a');
        expect(firstTop10.single.milestoneValue, 1);

        expect(nthTop10, hasLength(1));
        expect(nthTop10.single.entity.entityId, 'song-b');
        expect(nthTop10.single.milestoneValue, 2);

        final careerBest = ofType(
          events,
          ChartMomentEventType.artistHighestChartingSong,
        );

        expect(careerBest, hasLength(1));
        expect(careerBest.single.entity.entityId, 'song-a');
        expect(careerBest.single.currentPeakRank, 5);
      },
    );
    test('artist returning to number one after a gap records gap length', () {
      final oldNumberOne = finalized(
        id: 'old-number-one',
        start: DateTime.utc(2026, 9, 6),
        end: DateTime.utc(2026, 9, 13),
        entries: [entry(song('song-old'), rank: 1)],
      );

      final gapWeekOne = finalized(
        id: 'gap-one',
        start: DateTime.utc(2026, 9, 13),
        end: DateTime.utc(2026, 9, 20),
        entries: [entry(song('song-old'), rank: 4, peakRank: 1)],
      );

      final gapWeekTwo = finalized(
        id: 'gap-two',
        start: DateTime.utc(2026, 9, 20),
        end: currentStart,
        entries: [entry(song('song-old'), rank: 6, peakRank: 1)],
      );

      final current = finalized(
        id: 'current',
        start: currentStart,
        end: currentEnd,
        entries: [entry(song('song-new'), rank: 1)],
      );

      final events = detect(
        snapshot: current,
        history: [oldNumberOne, gapWeekOne, gapWeekTwo],
      );

      final returned = ofType(
        events,
        ChartMomentEventType.artistReturnsToNumberOneSong,
      ).single;

      expect(returned.threshold, 1);
      expect(returned.milestoneValue, 2);
      expect(returned.entity.entityId, 'song-new');
      expect(returned.relatedEntity!.entityId, 'song-old');
    });

    test('consecutive artist number-one weeks do not emit return event', () {
      final previous = finalized(
        id: 'previous',
        start: DateTime.utc(2026, 9, 20),
        end: currentStart,
        entries: [entry(song('song-old'), rank: 1)],
      );

      final current = finalized(
        id: 'current',
        start: currentStart,
        end: currentEnd,
        entries: [entry(song('song-new'), rank: 1)],
      );

      final events = detect(snapshot: current, history: [previous]);

      expect(
        ofType(events, ChartMomentEventType.artistReturnsToNumberOneSong),
        isEmpty,
      );
    });

    test(
      'simultaneous threshold event records increased current occupancy',
      () {
        final previous = finalized(
          id: 'previous',
          start: DateTime.utc(2026, 9, 20),
          end: currentStart,
          entries: [entry(song('song-a'), rank: 7)],
        );

        final current = finalized(
          id: 'current',
          start: currentStart,
          end: currentEnd,
          entries: [
            entry(song('song-a'), rank: 5),
            entry(song('song-b'), rank: 8),
          ],
        );

        final events = detect(snapshot: current, history: [previous]);

        final top10 = ofType(
          events,
          ChartMomentEventType.artistSimultaneousThresholdSongs,
        ).singleWhere((event) => event.threshold == 10);

        expect(top10.milestoneValue, 2);
        expect(top10.entity.entityId, 'song-a');
        expect(top10.relatedEntity!.entityId, 'song-b');
      },
    );

    test('unchanged simultaneous threshold occupancy does not repeat', () {
      final previous = finalized(
        id: 'previous',
        start: DateTime.utc(2026, 9, 20),
        end: currentStart,
        entries: [
          entry(song('song-a'), rank: 5),
          entry(song('song-b'), rank: 8),
        ],
      );

      final current = finalized(
        id: 'current',
        start: currentStart,
        end: currentEnd,
        entries: [
          entry(song('song-a'), rank: 4),
          entry(song('song-b'), rank: 7),
        ],
      );

      final events = detect(snapshot: current, history: [previous]);

      expect(
        ofType(
          events,
          ChartMomentEventType.artistSimultaneousThresholdSongs,
        ).where((event) => event.threshold == 10),
        isEmpty,
      );
    });

    test('album rich career facts use album event types', () {
      final oldNumberOne = finalized(
        id: 'old',
        start: DateTime.utc(2026, 9, 6),
        end: DateTime.utc(2026, 9, 13),
        chartType: ChartType.albums,
        entries: [entry(album('album-old'), rank: 1)],
      );

      final current = finalized(
        id: 'current',
        start: currentStart,
        end: currentEnd,
        chartType: ChartType.albums,
        entries: [
          entry(album('album-a'), rank: 1),
          entry(album('album-b'), rank: 5),
        ],
      );

      final events = detect(snapshot: current, history: [oldNumberOne]);

      expect(
        ofType(events, ChartMomentEventType.artistReturnsToNumberOneAlbum),
        hasLength(1),
      );

      final simultaneous = ofType(
        events,
        ChartMomentEventType.artistSimultaneousThresholdAlbums,
      );

      expect(
        simultaneous.any(
          (event) => event.threshold == 5 && event.milestoneValue == 2,
        ),
        isTrue,
      );
    });
    test('rebuild produces stable artist-achievement identities', () {
      final snapshot = finalized(
        id: 'current',
        start: currentStart,
        end: currentEnd,
        entries: [entry(song('song-a'), rank: 3)],
      );

      final first = detector.detect(
        snapshot: snapshot,
        history: const [],
        createdAt: createdAt,
      );

      final rebuilt = detector.detect(
        snapshot: snapshot,
        history: const [],
        createdAt: createdAt.add(const Duration(hours: 4)),
      );

      expect(
        first.map((event) => event.id).toList(),
        rebuilt.map((event) => event.id).toList(),
      );

      expect(
        first.map((event) => event.deduplicationKey).toList(),
        rebuilt.map((event) => event.deduplicationKey).toList(),
      );

      expect(
        first.every(
          (event) =>
              event.id == event.deduplicationKey &&
              event.scope == ChartMomentScope.finalized &&
              event.sourceId == snapshot.id,
        ),
        isTrue,
      );
    });
  });
}

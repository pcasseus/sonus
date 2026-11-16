// The text rules kept from the pre-Chart Studio card tests (App Update 1.3):
// they now describe an entry's row and details.
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/charts/domain/entities/chart_entry.dart';
import 'package:sonus_next/features/charts/domain/models/all_time_entry_stats.dart';
import 'package:sonus_next/features/charts/domain/models/chart_entity_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_movement.dart';
import 'package:sonus_next/features/charts/domain/models/chart_type.dart';
import 'package:sonus_next/features/charts/presentation/models/chart_entry_text.dart';

ChartEntry _entry({int rank = 7, int? previousFinalRank}) => ChartEntry(
  entity: ChartEntitySnapshot(
    entityId: 's$rank',
    title: 'Song $rank',
    artistName: 'Artist $rank',
    albumTitle: 'Album $rank',
  ),
  rank: rank,
  qualifiedStreamCount: 12,
  lastQualifiedAt: DateTime.utc(2026, 9, 28),
  peakRank: 2,
  peakAchievedAt: DateTime.utc(2026, 9, 28),
  weeksOnChart: 1,
  previousFinalRank: previousFinalRank,
  movement: previousFinalRank == null
      ? ChartMovement.newEntry
      : ChartMovement.up,
);

void main() {
  group('weekly change', () {
    String text(int now, int before) => WeeklyChange.of(
      AllTimeEntryStats(streamsThisWeek: now, streamsSameTimeLastWeek: before),
    ).text;

    test('is written once, rounded to a tenth', () {
      expect(text(10, 8), '+25%');
      expect(text(9, 8), '+12.5%');
      expect(text(0, 4), '−100%');
      expect(text(4, 4), '0%');
    });

    test('says when there is nothing to compare with', () {
      expect(text(3, 0), 'New activity');
      expect(text(0, 0), '—');
    });
  });

  group('the position compared with', () {
    test('a weekly chart: last week, neutral without an official rank', () {
      expect(
        ChartEntryText.lastWeekText(_entry(previousFinalRank: 9)),
        'Last week #9',
      );
      expect(ChartEntryText.lastWeekText(_entry()), 'Last week —');
    });

    test('the career standings: the start of the week, never last week', () {
      expect(
        ChartEntryText.lastWeekText(
          _entry(previousFinalRank: 9),
          isAllTime: true,
        ),
        'Start of week #9',
      );
      // Bubbling Under context is a weekly-chart fact only.
      expect(
        ChartEntryText.lastWeekText(
          _entry(),
          isAllTime: true,
          previousExtendedRank: 150,
        ),
        'Start of week —',
      );
    });

    test('last week in Bubbling Under is context, named plainly', () {
      expect(
        ChartEntryText.lastWeekText(
          _entry(rank: 80),
          previousExtendedRank: 150,
        ),
        'Last week #150 (Bubbling Under)',
      );
      expect(
        ChartEntryText.lastWeekText(
          _entry(rank: 80),
          previousExtendedRank: 120,
          chartType: ChartType.albums,
        ),
        'Last week #120 (#101–200)',
      );
    });
  });

  test('songs show artist and album, albums the artist alone', () {
    expect(
      ChartEntryText.subtitleFor(_entry(), ChartType.songs),
      'Artist 7 • Album 7',
    );
    expect(ChartEntryText.subtitleFor(_entry(), ChartType.albums), 'Artist 7');
  });

  test('status is words, never colour alone', () {
    for (final status in ChartEntryStatus.values) {
      expect(status.label, isNotEmpty);
      expect(status.spokenLabel, isNotEmpty);
    }
  });
}

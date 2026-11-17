import '../../domain/entities/chart_entry.dart';
import '../../domain/models/all_time_entry_stats.dart';
import '../../domain/models/chart_type.dart';

/// Why a chart entry cannot be opened, shown as words, never colour alone.
enum ChartEntryStatus {
  blacklisted('BLACKLISTED', 'Blacklisted'),
  unavailable('UNAVAILABLE', 'Unavailable'),
  historical('HISTORICAL', 'No longer in your library');

  const ChartEntryStatus(this.label, this.spokenLabel);

  final String label;
  final String spokenLabel;
}

/// The words a chart entry is described with, shared by its row and its
/// details (moved from the pre-Chart Studio cards, App Update 1.3).
abstract final class ChartEntryText {
  /// "Artist • Album" for songs, the artist alone for albums.
  static String subtitleFor(ChartEntry entry, ChartType chartType) {
    final album = entry.entity.albumTitle?.trim();

    return [
      entry.entity.artistName,
      if (chartType == ChartType.songs && album != null && album.isNotEmpty)
        album,
    ].join(' • ');
  }

  /// The position being compared with: last week's official rank on a
  /// weekly chart, or the standings rank at the start of this week on the
  /// career chart. Without one, a weekly chart names last week's Bubbling
  /// Under position when known; otherwise a neutral dash.
  static String lastWeekText(
    ChartEntry entry, {
    bool isAllTime = false,
    int? previousExtendedRank,
    ChartType chartType = ChartType.songs,
  }) {
    final previous = entry.previousFinalRank;
    final label = isAllTime ? 'Start of week' : 'Last week';

    if (previous != null) return '$label #$previous';
    if (!isAllTime && previousExtendedRank != null) {
      return '$label #$previousExtendedRank (${_lowerZoneName(chartType)})';
    }
    return '$label —';
  }

  static String _lowerZoneName(ChartType chartType) => switch (chartType) {
    ChartType.songs => 'Bubbling Under',
    ChartType.albums => '#101–200',
  };
}

enum WeeklyTrend { up, down, flat, fresh, none }

/// The weekly change, written once: "+12.5%", "New activity" or "—".
class WeeklyChange {
  const WeeklyChange._(this.text, this.spoken, this.trend);

  factory WeeklyChange.of(AllTimeEntryStats stats) {
    final percent = stats.weeklyChangePercent;

    if (percent == null) {
      return stats.isNewActivity
          ? const WeeklyChange._(
              'New activity',
              'new activity this week, none at this time last week',
              WeeklyTrend.fresh,
            )
          : const WeeklyChange._(
              '—',
              'no plays this week or at this time last week',
              WeeklyTrend.none,
            );
    }

    final rounded = (percent * 10).round() / 10;
    final digits = rounded == rounded.roundToDouble()
        ? rounded.abs().toStringAsFixed(0)
        : rounded.abs().toStringAsFixed(1);
    final trend = rounded > 0
        ? WeeklyTrend.up
        : rounded < 0
        ? WeeklyTrend.down
        : WeeklyTrend.flat;
    final sign = switch (trend) {
      WeeklyTrend.up => '+',
      WeeklyTrend.down => '−',
      _ => '',
    };

    return WeeklyChange._('$sign$digits%', switch (trend) {
      WeeklyTrend.up => 'up $digits percent on this time last week',
      WeeklyTrend.down => 'down $digits percent on this time last week',
      _ => 'level with this time last week',
    }, trend);
  }

  final String text;
  final String spoken;
  final WeeklyTrend trend;
}

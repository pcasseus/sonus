import '../../application/models/chart_moment_feed_item.dart';
import '../../domain/models/chart_type.dart';
import '../../domain/moments/chart_moment_event_type.dart';
import '../../domain/moments/chart_moment_scope.dart';
import '../models/chart_moment_feed_copy.dart';

/// The two Sonus News editions.
enum SonusNewsEdition {
  /// Chart news: debuts, re-entries, peaks, number ones and exits.
  sonusDaily('Sonus Daily'),

  /// Momentum (climbs), artist accomplishments and personal listening
  /// milestones.
  pulsePop('PulsePop');

  const SonusNewsEdition(this.label);

  final String label;
}

/// How much room a story gets.
enum SonusNewsFormat { featured, standard, compact }

/// One story in the Sonus News Feed. Every field comes from a real Chart
/// Moment: the headline and body are the existing Moments copy, the
/// kicker says which weekly chart (or listening milestone) it belongs to.
class SonusNewsStory {
  const SonusNewsStory({
    required this.id,
    required this.edition,
    required this.format,
    required this.kicker,
    required this.headline,
    required this.body,
    required this.occurredAt,
    required this.isFinal,
    this.artworkPath,
    this.relatedArtworkPath,
  });

  final String id;
  final SonusNewsEdition edition;
  final SonusNewsFormat format;

  /// For example "Weekly Hot 100 · Final" or "Listening milestone".
  final String kicker;
  final String headline;
  final String body;
  final DateTime occurredAt;

  /// Whether the story comes from a finalized (closed) chart week rather
  /// than the week in progress.
  final bool isFinal;
  final String? artworkPath;
  final String? relatedArtworkPath;
}

/// Turns Chart Moment feed items into News stories. Presentation only: it
/// detects nothing and calculates nothing, so it can never invent news.
class SonusNewsDesk {
  const SonusNewsDesk({
    required this.copyFor,
    this.artworkFor,
    this.relatedArtworkFor,
  });

  /// The existing Moments copy (ChartMomentFeedCopyFormatter.format).
  final ChartMomentFeedCopy Function(ChartMomentFeedItem item) copyFor;
  final String? Function(ChartMomentFeedItem item)? artworkFor;
  final String? Function(ChartMomentFeedItem item)? relatedArtworkFor;

  /// Stories in the feed's own order (most important first). The first
  /// headline-worthy story is featured; routine movement is compact.
  List<SonusNewsStory> stories(Iterable<ChartMomentFeedItem> items) {
    var featuredUsed = false;
    final result = <SonusNewsStory>[];

    for (final item in items) {
      final copy = copyFor(item);
      final type = item.dominantEventType;
      final SonusNewsFormat format;

      if (!featuredUsed && _headlineTypes.contains(type)) {
        format = SonusNewsFormat.featured;
        featuredUsed = true;
      } else if (_compactTypes.contains(type)) {
        format = SonusNewsFormat.compact;
      } else {
        format = SonusNewsFormat.standard;
      }

      result.add(
        SonusNewsStory(
          id: item.id,
          edition: editionFor(type),
          format: format,
          kicker: kickerFor(item),
          headline: copy.headline,
          body: copy.body,
          occurredAt: item.occurredAt,
          isFinal: item.scope == ChartMomentScope.finalized,
          artworkPath: artworkFor?.call(item),
          relatedArtworkPath: relatedArtworkFor?.call(item),
        ),
      );
    }

    return List.unmodifiable(result);
  }

  static SonusNewsEdition editionFor(ChartMomentEventType type) {
    return _pulsePopTypes.contains(type)
        ? SonusNewsEdition.pulsePop
        : SonusNewsEdition.sonusDaily;
  }

  /// Names the chart and, for weekly charts, its state, so weekly Moments
  /// are never mistaken for the all-time leaderboard or the reverse.
  static String kickerFor(ChartMomentFeedItem item) {
    if (item.dominantEventType ==
        ChartMomentEventType.lifetimeStreamMilestone) {
      return 'Listening milestone';
    }

    if (item.isAllTime) {
      return switch (item.chartType) {
        ChartType.songs => 'All-time Hot 100',
        ChartType.albums => 'All-time Top 200 Albums',
      };
    }

    final chart = switch (item.chartType) {
      ChartType.songs => 'Weekly Hot 100',
      ChartType.albums => 'Weekly Top 200',
    };
    final state = item.scope == ChartMomentScope.finalized
        ? 'Final'
        : 'This week';

    return '$chart · $state';
  }

  static const Set<ChartMomentEventType> _headlineTypes = {
    ChartMomentEventType.firstNumberOne,
    ChartMomentEventType.returnToNumberOne,
    ChartMomentEventType.artistFirstNumberOneSong,
    ChartMomentEventType.artistFirstNumberOneAlbum,
    ChartMomentEventType.artistNthNumberOneSong,
    ChartMomentEventType.artistNthNumberOneAlbum,
    ChartMomentEventType.artistReturnsToNumberOneSong,
    ChartMomentEventType.artistReturnsToNumberOneAlbum,
    ChartMomentEventType.newPeak,
    ChartMomentEventType.debut,
  };

  static const Set<ChartMomentEventType> _compactTypes = {
    ChartMomentEventType.rankRise,
    ChartMomentEventType.rankFall,
    ChartMomentEventType.rankSame,
    ChartMomentEventType.chartExit,
    ChartMomentEventType.thresholdExit,
    ChartMomentEventType.losesNumberOne,
  };

  static const Set<ChartMomentEventType> _pulsePopTypes = {
    // Momentum, as the legacy PulsePop desk covered it.
    ChartMomentEventType.rankRise,
    ChartMomentEventType.lifetimeStreamMilestone,
    ChartMomentEventType.consecutiveWeeksMilestone,
    ChartMomentEventType.totalWeeksMilestone,
    ChartMomentEventType.consecutiveThresholdWeeksMilestone,
    ChartMomentEventType.totalThresholdWeeksMilestone,
    ChartMomentEventType.artistFirstThresholdSong,
    ChartMomentEventType.artistFirstThresholdAlbum,
    ChartMomentEventType.artistNthThresholdSong,
    ChartMomentEventType.artistNthThresholdAlbum,
    ChartMomentEventType.artistHighestChartingSong,
    ChartMomentEventType.artistHighestChartingAlbum,
    ChartMomentEventType.artistFirstNumberOneSong,
    ChartMomentEventType.artistFirstNumberOneAlbum,
    ChartMomentEventType.artistNthNumberOneSong,
    ChartMomentEventType.artistNthNumberOneAlbum,
    ChartMomentEventType.artistReturnsToNumberOneSong,
    ChartMomentEventType.artistReturnsToNumberOneAlbum,
    ChartMomentEventType.artistSimultaneousThresholdSongs,
    ChartMomentEventType.artistSimultaneousThresholdAlbums,
  };
}

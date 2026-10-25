import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/design/sonus_count_label.dart';
import '../../../../core/design/sonus_theme.dart';
import '../../../../core/design/widgets/sonus_artwork_frame.dart';
import '../../../../core/design/widgets/sonus_bar_strip.dart';
import '../../../../core/design/widgets/sonus_comparison_indicator.dart';
import '../../../../core/design/widgets/sonus_decorations.dart';
import '../../../../core/design/widgets/sonus_heat_grid.dart';
import '../../../../core/design/widgets/sonus_metric_tile.dart';
import '../../../../core/design/widgets/sonus_numeric_table.dart';
import '../../application/models/monthly_insights/monthly_album_insight_row.dart';
import '../../application/models/monthly_insights/monthly_artist_insight_row.dart';
import '../../application/models/monthly_insights/monthly_daily_listening.dart';
import '../../application/models/monthly_insights/monthly_listening_insights.dart';
import '../../application/models/monthly_insights/monthly_listening_insights_presentation_data.dart';
import '../../application/models/monthly_insights/monthly_track_insight_row.dart';
import '../../../library/application/models/library_track.dart';
import '../../../library/presentation/pages/album_profile_page.dart';
import '../../../library/presentation/pages/artist_profile_page.dart';
import '../../../player/application/controllers/playback_coordinator.dart';
import '../../../playlists/presentation/widgets/add_to_playlist_sheet.dart';
import '../controllers/monthly_listening_insights_controller.dart';

class MonthlyListeningInsightsPage extends StatelessWidget {
  const MonthlyListeningInsightsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<MonthlyListeningInsightsController?>();

    if (controller == null) {
      return const _InsightsMessage(
        key: ValueKey<String>('monthly-insights-initializing'),
        icon: Icons.query_stats_rounded,
        title: 'Insights are getting ready',
        message: 'Your listening analytics are still initializing.',
      );
    }

    final insights = controller.insights;

    if (controller.isLoading && insights == null) {
      return const Center(
        key: ValueKey<String>('monthly-insights-loading'),
        child: CircularProgressIndicator(),
      );
    }

    if (controller.hasError && insights == null) {
      return _InsightsMessage(
        key: const ValueKey<String>('monthly-insights-error'),
        icon: Icons.error_outline_rounded,
        title: 'Monthly Insights could not be loaded',
        message: 'Try loading your listening analytics again.',
        action: FilledButton.icon(
          onPressed: () {
            unawaited(controller.load());
          },
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Retry'),
        ),
      );
    }

    if (insights == null) {
      return const _InsightsMessage(
        icon: Icons.query_stats_rounded,
        title: 'No insights available',
        message: 'Start listening in Sonus to build your monthly statistics.',
      );
    }

    final gutter = SonusTheme.of(context).metrics.pageGutter;

    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: ListView(
        key: const PageStorageKey<String>('monthly-insights-scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(gutter, 22, gutter, 40),
        children: [
          const _InsightsHeader(),
          const SizedBox(height: 14),
          _MonthNavigator(controller: controller),
          const SizedBox(height: 20),

          if (controller.hasError) ...[
            _RefreshErrorBanner(onRetry: controller.refresh),
            const SizedBox(height: 16),
          ],

          if (!insights.hasListening)
            const _EmptyMonth()
          else ...[
            _HeadlineMetrics(insights: insights),
            const SizedBox(height: 30),
            _ActivitySection(insights: insights),
            const SizedBox(height: 30),
            _DailySection(insights: insights),
            const SizedBox(height: 30),
            _RankingTables(data: controller.presentationData),
          ],
        ],
      ),
    );
  }
}

class _InsightsHeader extends StatelessWidget {
  const _InsightsHeader();

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final theme = Theme.of(context);

    // The page's featured header carries the theme texture and motif.
    return Stack(
      children: [
        const Positioned.fill(child: SonusSurfaceTexture()),
        Column(
          key: const ValueKey<String>('monthly-insights-header'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'SONUS',
              style: theme.textTheme.labelLarge?.copyWith(
                letterSpacing: 2.4,
                fontWeight: FontWeight.w800,
                color: tokens.colors.textSecondary,
              ),
            ),
            const SizedBox(height: 3),
            Semantics(
              header: true,
              child: Text(
                'Monthly Insights',
                key: const ValueKey<String>('monthly-insights-title'),
                style: tokens.text.pageTitle.copyWith(
                  color: tokens.colors.textPrimary,
                  fontWeight: FontWeight.w900,
                  height: 1.05,
                ),
              ),
            ),
            if (tokens.decoration.showMarks) ...[
              SizedBox(height: tokens.metrics.spaceSm),
              const SonusMotifMark(),
            ],
          ],
        ),
      ],
    );
  }
}

class _MonthNavigator extends StatelessWidget {
  const _MonthNavigator({required this.controller});

  final MonthlyListeningInsightsController controller;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);

    return Row(
      key: const ValueKey<String>('monthly-insights-month-navigation'),
      children: [
        IconButton(
          key: const ValueKey<String>('monthly-insights-previous-month'),
          tooltip: 'Previous month',
          onPressed: () {
            unawaited(controller.previousMonth());
          },
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Expanded(
          child: Text(
            _formatMonth(controller.selectedMonth),
            key: const ValueKey<String>('monthly-insights-month-label'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: tokens.colors.textPrimary,
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        IconButton(
          key: const ValueKey<String>('monthly-insights-next-month'),
          tooltip: 'Next month',
          onPressed: controller.canGoNext
              ? () {
                  unawaited(controller.nextMonth());
                }
              : null,
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );
  }
}

/// A major section title with the theme motif and an optional caption.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.detail, this.caption});

  final String title;

  /// Short trailing text, e.g. "Top 25 of 26".
  final String? detail;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final theme = Theme.of(context);
    final detail = this.detail;
    final caption = this.caption;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.end,
          spacing: 12,
          runSpacing: 4,
          children: [
            SonusSectionHeading(title: title),
            if (detail != null)
              Text(
                detail,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: tokens.colors.textSecondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
          ],
        ),
        if (caption != null) ...[
          const SizedBox(height: 4),
          Text(
            caption,
            style: theme.textTheme.bodySmall?.copyWith(
              color: tokens.colors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}

/// Monthly comparison for a metric, worded exactly as before.
SonusComparison _comparison(
  double? percentChange, {
  required bool increased,
  required bool decreased,
  required String suffix,
}) {
  final text = '${_formatPercentChange(percentChange)} $suffix';

  if (percentChange == null) {
    return SonusComparison(
      direction: SonusComparisonDirection.isNew,
      text: text,
      spokenLabel: 'New this month',
    );
  }

  final percent = (percentChange * 100).abs().toStringAsFixed(1);

  if (increased) {
    return SonusComparison(
      direction: SonusComparisonDirection.up,
      text: text,
      spokenLabel: 'Up $percent percent on the previous month',
    );
  }

  if (decreased) {
    return SonusComparison(
      direction: SonusComparisonDirection.down,
      text: text,
      spokenLabel: 'Down $percent percent on the previous month',
    );
  }

  return SonusComparison(
    direction: SonusComparisonDirection.unchanged,
    text: text,
    spokenLabel: 'No change on the previous month',
  );
}

class _HeadlineMetrics extends StatelessWidget {
  const _HeadlineMetrics({required this.insights});

  final MonthlyListeningInsights insights;

  @override
  Widget build(BuildContext context) {
    final current = insights.currentSummary;
    final previous = insights.previousSummary;
    final previousMonth = _shortMonthName(insights.previousMonth.month);

    final featured = [
      SonusMetricTile(
        label: 'Streams',
        value: '${current.qualifiedStreamCount}',
        previousLabel: '$previousMonth: ${previous.qualifiedStreamCount}',
        featured: true,
        comparison: _comparison(
          insights.streamChange.percentChange,
          increased: insights.streamChange.increased,
          decreased: insights.streamChange.decreased,
          suffix: 'vs previous month',
        ),
      ),
      SonusMetricTile(
        label: 'Listening',
        value: _formatDuration(insights.currentAudibleListeningDuration),
        previousLabel:
            '$previousMonth: '
            '${_formatDuration(insights.previousAudibleListeningDuration)}',
        featured: true,
        comparison: _comparison(
          insights.listeningTimeChange.percentChange,
          increased: insights.listeningTimeChange.increased,
          decreased: insights.listeningTimeChange.decreased,
          suffix: 'vs previous month',
        ),
      ),
    ];

    final compact = [
      for (final (label, value, previousValue, change) in [
        (
          'Tracks',
          current.distinctSongCount,
          previous.distinctSongCount,
          insights.trackCountChange,
        ),
        (
          'Artists',
          current.distinctArtistCount,
          previous.distinctArtistCount,
          insights.artistCountChange,
        ),
        (
          'Albums',
          current.distinctAlbumCount,
          previous.distinctAlbumCount,
          insights.albumCountChange,
        ),
      ])
        SonusMetricTile(
          label: label,
          value: '$value',
          previousLabel: '$previousMonth: $previousValue',
          comparison: _comparison(
            change.percentChange,
            increased: change.increased,
            decreased: change.decreased,
            suffix: 'vs prev',
          ),
        ),
    ];

    return Column(
      key: const ValueKey<String>('monthly-insights-headline-metrics'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionTitle(
          title: 'This month',
          caption: 'Compared with the previous month.',
        ),
        const SizedBox(height: 12),
        _TileGrid(tiles: featured, columnsAtWidth: _featuredColumns),
        const SizedBox(height: 10),
        _TileGrid(tiles: compact, columnsAtWidth: _compactColumns),
      ],
    );
  }

  /// Columns for the large tiles at an effective (text-scaled) width.
  static int _featuredColumns(double effectiveWidth) =>
      effectiveWidth >= 300 ? 2 : 1;

  static int _compactColumns(double effectiveWidth) => effectiveWidth >= 360
      ? 3
      : effectiveWidth >= 240
      ? 2
      : 1;
}

/// Lays tiles out in equal columns; the column count follows the width
/// divided by the text scale, so large text gets fewer, wider tiles.
class _TileGrid extends StatelessWidget {
  const _TileGrid({required this.tiles, required this.columnsAtWidth});

  final List<Widget> tiles;
  final int Function(double effectiveWidth) columnsAtWidth;

  @override
  Widget build(BuildContext context) {
    const gap = 10.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(1);
        final columns = columnsAtWidth(constraints.maxWidth / scale);
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final tile in tiles) SizedBox(width: width, child: tile),
          ],
        );
      },
    );
  }
}

class _ActivitySection extends StatelessWidget {
  const _ActivitySection({required this.insights});

  final MonthlyListeningInsights insights;

  @override
  Widget build(BuildContext context) {
    final distribution = insights.distribution;
    final busiestDay = distribution.busiestDay;
    final mostActiveHour = distribution.mostActiveHour;

    final rows = [
      (
        'Busiest day',
        busiestDay == null
            ? '—'
            : '${_shortMonthName(busiestDay.localDate.month)} '
                  '${busiestDay.localDate.day} · '
                  '${busiestDay.streams} ${sonusCountNoun(busiestDay.streams, 'stream')}',
      ),
      (
        'Most active hour',
        mostActiveHour == null
            ? '—'
            : '${_formatHour(mostActiveHour.hour)} · '
                  '${_formatDuration(mostActiveHour.listeningDuration)}',
      ),
      (
        'Active days',
        '${insights.behavior.activeQualifiedDayCount} / '
            '${insights.distribution.days.length}',
      ),
      (
        'Average streams / active day',
        insights.behavior.activeQualifiedDayCount == 0
            ? '0'
            : insights.behavior.averageQualifiedStreamsPerActiveDay
                  .toStringAsFixed(1),
      ),
      ('Completion rate', _formatRate(insights.behavior.completionRate)),
      ('Skip rate', _formatRate(insights.behavior.skipRate)),
    ];

    return Column(
      key: const ValueKey<String>('monthly-insights-activity'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionTitle(title: 'Listening activity'),
        const SizedBox(height: 12),
        _Ledger(rows: rows),
        if (distribution.hours.isNotEmpty) ...[
          const SizedBox(height: 20),
          _HourlyActivity(insights: insights),
        ],
      ],
    );
  }
}

/// Label–value rows in a bordered ledger, values in tabular figures.
class _Ledger extends StatelessWidget {
  const _Ledger({required this.rows});

  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.divider),
        borderRadius: BorderRadius.circular(tokens.metrics.cardRadius),
      ),
      child: Column(
        children: [
          for (final (index, (label, value)) in rows.indexed) ...[
            if (index > 0) Divider(height: 1, color: colors.divider),
            // One node per row, so the label is read with its value.
            Semantics(
              container: true,
              child: MergeSemantics(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    spacing: 16,
                    runSpacing: 4,
                    children: [
                      Text(
                        label,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                      Text(
                        value,
                        textAlign: TextAlign.end,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w800,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Listening time across the 24 hours of the day, most active hour
/// highlighted.
class _HourlyActivity extends StatelessWidget {
  const _HourlyActivity({required this.insights});

  final MonthlyListeningInsights insights;

  static const _axis = {0: '12a', 6: '6a', 12: '12p', 18: '6p'};

  @override
  Widget build(BuildContext context) {
    final byHour = {
      for (final hour in insights.distribution.hours) hour.hour % 24: hour,
    };
    final peak = insights.distribution.mostActiveHour;

    return Column(
      key: const ValueKey<String>('monthly-insights-hourly'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Listening by hour of day',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: SonusTheme.of(context).colors.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        SonusBarStrip(
          highlightIndex: peak == null ? null : peak.hour % 24,
          highlightLabel: 'most active hour',
          bars: [
            for (var hour = 0; hour < 24; hour++)
              SonusBar(
                // Listening time, the same measure that picks the most
                // active hour, so the highlighted bar is always the tallest.
                value: (byHour[hour]?.listeningDuration.inSeconds ?? 0)
                    .toDouble(),
                axisLabel: _axis[hour],
                spokenLabel: byHour[hour] == null
                    ? '${_formatHour(hour)}, no listening'
                    : '${_formatHour(hour)}, '
                          '${_formatDuration(byHour[hour]!.listeningDuration)} '
                          'listening, ${byHour[hour]!.streams} ${sonusCountNoun(byHour[hour]!.streams, 'stream')}',
              ),
          ],
        ),
      ],
    );
  }
}

class _DailySection extends StatelessWidget {
  const _DailySection({required this.insights});

  final MonthlyListeningInsights insights;

  static const _weekdays = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final month = insights.selectedMonth;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final byDay = {
      for (final day in insights.distribution.days)
        if (day.localDate.year == month.year &&
            day.localDate.month == month.month)
          day.localDate.day: day,
    };
    // Monday-first calendar.
    final leadingBlanks = DateTime(month.year, month.month).weekday - 1;
    final monthName = _monthName(month.month);

    return Column(
      key: const ValueKey<String>('monthly-insights-daily-timeline'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionTitle(
          title: 'Daily listening',
          caption:
              'Taller, deeper fills mean more streams. Every day is also '
              'listed below.',
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SonusHeatGrid(
              leadingBlanks: leadingBlanks,
              columnLabels: _weekdays,
              cells: [
                for (var day = 1; day <= daysInMonth; day++)
                  SonusHeatCell(
                    key: ValueKey<String>(
                      'monthly-insights-heat-${month.year}-${month.month}-$day',
                    ),
                    label: '$day',
                    value: (byDay[day]?.streams ?? 0).toDouble(),
                    spokenLabel: byDay[day] == null
                        ? '$monthName $day, no listening'
                        : '$monthName $day, ${byDay[day]!.streams} ${sonusCountNoun(byDay[day]!.streams, 'stream')}, '
                              '${_formatDuration(byDay[day]!.listeningDuration)} '
                              'listening',
                  ),
              ],
            ),
          ),
        ),
        if (insights.distribution.days.isNotEmpty) ...[
          const SizedBox(height: 18),
          _DayByDay(days: insights.distribution.days),
        ],
      ],
    );
  }
}

/// Every active day with its streams and audible listening time.
class _DayByDay extends StatelessWidget {
  const _DayByDay({required this.days});

  final List<MonthlyDailyListening> days;

  @override
  Widget build(BuildContext context) {
    var maxStreams = 0;
    var maxListeningMinutes = 0;

    for (final day in days) {
      if (day.streams > maxStreams) {
        maxStreams = day.streams;
      }

      if (day.listeningDuration.inMinutes > maxListeningMinutes) {
        maxListeningMinutes = day.listeningDuration.inMinutes;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Day by day',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: SonusTheme.of(context).colors.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          // Its own PageStorage slot: without it the rail shares the page's
          // slot and reopens at the page's vertical offset.
          key: const PageStorageKey<String>('monthly-insights-timeline-scroll'),
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final day in days) ...[
                _DayCell(
                  day: day,
                  maxStreams: maxStreams,
                  maxListeningMinutes: maxListeningMinutes,
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.maxStreams,
    required this.maxListeningMinutes,
  });

  final MonthlyDailyListening day;
  final int maxStreams;
  final int maxListeningMinutes;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final theme = Theme.of(context);
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final streamFraction = maxStreams == 0 ? 0.0 : day.streams / maxStreams;
    final listeningFraction = maxListeningMinutes == 0
        ? 0.0
        : day.listeningDuration.inMinutes / maxListeningMinutes;
    final numberStyle = theme.textTheme.bodySmall?.copyWith(
      color: colors.textPrimary,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return Container(
      key: ValueKey<String>(
        'monthly-insights-day-'
        '${day.localDate.year}-'
        '${day.localDate.month}-'
        '${day.localDate.day}',
      ),
      width: 88 * scale,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.divider),
        borderRadius: BorderRadius.circular(tokens.metrics.cardRadius),
      ),
      child: Column(
        children: [
          Text(
            '${_shortMonthName(day.localDate.month)} ${day.localDate.day}',
            style: theme.textTheme.labelMedium?.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 48,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _MiniBar(fraction: streamFraction, color: colors.accentPrimary),
                const SizedBox(width: 6),
                _MiniBar(
                  fraction: listeningFraction,
                  color: colors.accentSecondary,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${day.streams} ${sonusCountNoun(day.streams, 'stream')}',
            style: numberStyle,
          ),
          Text(_formatDuration(day.listeningDuration), style: numberStyle),
        ],
      ),
    );
  }
}

class _MiniBar extends StatelessWidget {
  const _MiniBar({required this.fraction, required this.color});

  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: 12,
        height: 48 * fraction.clamp(0.06, 1.0),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }
}

class _RankingTables extends StatelessWidget {
  const _RankingTables({required this.data});

  static const _trackLimit = 25;
  static const _artistLimit = 15;
  static const _albumLimit = 15;

  final MonthlyListeningInsightsPresentationData? data;

  @override
  Widget build(BuildContext context) {
    final data = this.data;

    if (data == null) {
      return const SizedBox.shrink();
    }

    final tracks = data.tracks.take(_trackLimit).toList(growable: false);
    final artists = data.artists.take(_artistLimit).toList(growable: false);
    final albums = data.albums.take(_albumLimit).toList(growable: false);

    return Column(
      key: const ValueKey<String>('monthly-insights-rankings'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (tracks.isNotEmpty) ...[
          _SectionTitle(
            title: 'Tracks',
            detail: _rankingCountLabel(
              visible: tracks.length,
              total: data.tracks.length,
            ),
          ),
          const SizedBox(height: 10),
          _InsightTable(
            storageId: 'monthly-tracks',
            identityLabel: 'TRACK',
            rows: [for (final row in tracks) _trackRow(context, row)],
          ),
        ],
        if (tracks.isNotEmpty && artists.isNotEmpty) const SizedBox(height: 28),
        if (artists.isNotEmpty) ...[
          _SectionTitle(
            title: 'Artists',
            detail: _rankingCountLabel(
              visible: artists.length,
              total: data.artists.length,
            ),
          ),
          const SizedBox(height: 10),
          _InsightTable(
            storageId: 'monthly-artists',
            identityLabel: 'ARTIST',
            rows: [for (final row in artists) _artistRow(context, row)],
          ),
        ],
        if (artists.isNotEmpty && albums.isNotEmpty) const SizedBox(height: 28),
        if (albums.isNotEmpty) ...[
          _SectionTitle(
            title: 'Albums',
            detail: _rankingCountLabel(
              visible: albums.length,
              total: data.albums.length,
            ),
          ),
          const SizedBox(height: 10),
          _InsightTable(
            storageId: 'monthly-albums',
            identityLabel: 'ALBUM',
            rows: [for (final row in albums) _albumRow(context, row)],
          ),
        ],
      ],
    );
  }

  SonusTableRow _trackRow(BuildContext context, MonthlyTrackInsightRow row) {
    final track = row.track;
    final badge = !row.hasCurrentLibraryEntity
        ? 'HISTORICAL'
        : row.isBlocked
        ? 'BLACKLISTED'
        : !row.isAvailable
        ? 'UNAVAILABLE'
        : null;

    return _tableRow(
      key: ValueKey<String>('monthly-insights-track-${row.entityId}'),
      identity: _IdentityCell(
        rank: row.rank,
        movement: row.rankMovement,
        isNew: row.isNew,
        artworkPath: row.artworkPath,
        fallbackIcon: Icons.music_note_rounded,
        title: row.title,
        subtitle: row.artistName,
        badge: badge,
      ),
      rank: row.rank,
      title: row.title,
      subtitle: row.artistName,
      badge: badge,
      streams: row.streams,
      change: row.streamChange,
      percentChange: row.streamPercentChange,
      isNew: row.isNew,
      listeningDuration: row.listeningDuration,
      lifetimeStreams: row.lifetimeStreams,
      onTap: track == null
          ? null
          : () {
              unawaited(_showInsightTrackContext(context, track));
            },
    );
  }

  SonusTableRow _artistRow(BuildContext context, MonthlyArtistInsightRow row) {
    final artist = row.artist;
    final badge = row.hasCurrentLibraryEntity ? null : 'HISTORICAL';

    return _tableRow(
      key: ValueKey<String>('monthly-insights-artist-${row.entityId}'),
      identity: _IdentityCell(
        rank: row.rank,
        movement: row.rankMovement,
        isNew: row.isNew,
        artworkPath: row.artworkPath,
        fallbackIcon: Icons.person_rounded,
        title: row.name,
        subtitle: row.subtitle,
        badge: badge,
        circularArtwork: true,
      ),
      rank: row.rank,
      title: row.name,
      subtitle: row.subtitle,
      badge: badge,
      streams: row.streams,
      change: row.streamChange,
      percentChange: row.streamPercentChange,
      isNew: row.isNew,
      listeningDuration: row.listeningDuration,
      lifetimeStreams: row.lifetimeStreams,
      onTap: artist == null
          ? null
          : () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ArtistProfilePage(
                    artistId: artist.artistId,
                    initialArtistName: artist.name,
                  ),
                ),
              );
            },
    );
  }

  SonusTableRow _albumRow(BuildContext context, MonthlyAlbumInsightRow row) {
    final album = row.album;
    final badge = row.hasCurrentLibraryEntity ? null : 'HISTORICAL';

    return _tableRow(
      key: ValueKey<String>('monthly-insights-album-${row.entityId}'),
      identity: _IdentityCell(
        rank: row.rank,
        movement: row.rankMovement,
        isNew: row.isNew,
        artworkPath: row.artworkPath,
        fallbackIcon: Icons.album_rounded,
        title: row.title,
        subtitle: row.artistName,
        badge: badge,
      ),
      rank: row.rank,
      title: row.title,
      subtitle: row.artistName,
      badge: badge,
      streams: row.streams,
      change: row.streamChange,
      percentChange: row.streamPercentChange,
      isNew: row.isNew,
      listeningDuration: row.listeningDuration,
      lifetimeStreams: row.lifetimeStreams,
      onTap: album == null
          ? null
          : () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => AlbumProfilePage(
                    albumId: album.albumId,
                    initialAlbumTitle: album.title,
                  ),
                ),
              );
            },
    );
  }
}

SonusTableRow _tableRow({
  required Key key,
  required Widget identity,
  required int rank,
  required String title,
  required String subtitle,
  required String? badge,
  required int streams,
  required int change,
  required double? percentChange,
  required bool isNew,
  required Duration listeningDuration,
  required int lifetimeStreams,
  required VoidCallback? onTap,
}) {
  final changeText = isNew ? 'NEW' : _signedInteger(change);
  final changeSpoken = isNew
      ? 'new this month'
      : change == 0
      ? 'no change in streams'
      : change > 0
      ? '$change more streams than last month'
      : '${change.abs()} fewer streams than last month';

  return SonusTableRow(
    key: key,
    identity: identity,
    onTap: onTap,
    spokenLabel: [
      'Rank $rank',
      title,
      subtitle,
      '$streams ${sonusCountNoun(streams, 'stream')}',
      changeSpoken,
      '${_formatDuration(listeningDuration)} listening',
      '$lifetimeStreams lifetime ${sonusCountNoun(lifetimeStreams, 'stream')}',
      ?badge?.toLowerCase(),
    ].join(', '),
    cells: [
      _NumericCell('$streams', strong: true),
      _NumericCell(changeText, strong: isNew || change != 0),
      _NumericCell(_tablePercent(percentChange, isNew: isNew)),
      _NumericCell(_formatDuration(listeningDuration)),
      _NumericCell('$lifetimeStreams'),
    ],
  );
}

class _InsightTable extends StatelessWidget {
  const _InsightTable({
    required this.storageId,
    required this.identityLabel,
    required this.rows,
  });

  final String storageId;
  final String identityLabel;
  final List<SonusTableRow> rows;

  @override
  Widget build(BuildContext context) {
    return SonusNumericTable(
      storageId: storageId,
      identityLabel: identityLabel,
      identityWidth: 230,
      // Room for title, subtitle and a status badge.
      rowHeight: 72,
      columns: const [
        SonusTableColumn(label: 'STREAMS', width: 84),
        SonusTableColumn(label: 'CHANGE', width: 76),
        SonusTableColumn(label: '%', width: 76),
        SonusTableColumn(label: 'LISTENING', width: 100),
        SonusTableColumn(label: 'LIFETIME', width: 92),
      ],
      rows: rows,
    );
  }
}

class _NumericCell extends StatelessWidget {
  const _NumericCell(this.value, {this.strong = false});

  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Text(
      value,
      textAlign: TextAlign.right,
      maxLines: 1,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: SonusTheme.of(context).colors.textPrimary,
        fontWeight: strong ? FontWeight.w800 : FontWeight.w500,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

/// The frozen identifying cell: rank and movement, artwork, title.
class _IdentityCell extends StatelessWidget {
  const _IdentityCell({
    required this.rank,
    required this.movement,
    required this.isNew,
    required this.artworkPath,
    required this.fallbackIcon,
    required this.title,
    required this.subtitle,
    this.badge,
    this.circularArtwork = false,
  });

  final int rank;
  final int? movement;
  final bool isNew;
  final String? artworkPath;
  final IconData fallbackIcon;
  final String title;
  final String subtitle;
  final String? badge;
  final bool circularArtwork;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final theme = Theme.of(context);
    final badge = this.badge;

    return Row(
      children: [
        // At least 32px, scaled with the text, and wider when a rank needs
        // it, so "10" or "100" never wraps at large text sizes.
        ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: MediaQuery.textScalerOf(context).scale(32),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$rank',
                maxLines: 1,
                softWrap: false,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w900,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              _RankMovementLabel(movement: movement, isNew: isNew),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _Thumbnail(
          path: artworkPath,
          fallbackIcon: fallbackIcon,
          circular: circularArtwork,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              if (badge != null)
                Text(
                  badge,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RankMovementLabel extends StatelessWidget {
  const _RankMovementLabel({required this.movement, required this.isNew});

  final int? movement;
  final bool isNew;

  @override
  Widget build(BuildContext context) {
    final label = isNew
        ? 'NEW'
        : movement == null || movement == 0
        ? '-'
        : movement! > 0
        ? '+${movement!}'
        : '${movement!}';

    return Text(
      label,
      maxLines: 1,
      softWrap: false,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: SonusTheme.of(context).colors.textSecondary,
        fontWeight: FontWeight.w800,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

/// Artwork thumbnail decoded at its display size, so a full-resolution
/// cover never occupies the image cache for a 40px tile.
class _Thumbnail extends StatelessWidget {
  const _Thumbnail({
    required this.path,
    required this.fallbackIcon,
    this.circular = false,
  });

  static const double size = 40;

  final String? path;
  final IconData fallbackIcon;
  final bool circular;

  @override
  Widget build(BuildContext context) {
    final normalizedPath = path?.trim();
    final fallback = SonusArtworkPlaceholder(icon: fallbackIcon, iconSize: 20);
    final decodeSize = (size * MediaQuery.devicePixelRatioOf(context)).round();

    return SonusArtworkFrame(
      size: size,
      circular: circular,
      child: normalizedPath == null || normalizedPath.isEmpty
          ? fallback
          : Image.file(
              File(normalizedPath),
              fit: BoxFit.cover,
              cacheWidth: decodeSize,
              errorBuilder: (_, _, _) => fallback,
            ),
    );
  }
}

class _EmptyMonth extends StatelessWidget {
  const _EmptyMonth();

  @override
  Widget build(BuildContext context) {
    return const _InsightsMessage(
      key: ValueKey<String>('monthly-insights-empty'),
      icon: Icons.query_stats_rounded,
      title: 'No listening this month',
      message:
          'Qualified streams and listening time will appear here as you listen.',
    );
  }
}

class _RefreshErrorBanner extends StatelessWidget {
  const _RefreshErrorBanner({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Material(
      key: const ValueKey<String>('monthly-insights-refresh-error'),
      color: scheme.errorContainer,
      borderRadius: BorderRadius.circular(tokens.metrics.cardRadius),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(Icons.error_outline_rounded, color: scheme.onErrorContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Insights could not refresh. Showing the last available data.',
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _InsightsMessage extends StatelessWidget {
  const _InsightsMessage({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: colors.textSecondary),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.textSecondary,
              ),
            ),
            if (action != null) ...[const SizedBox(height: 18), action!],
          ],
        ),
      ),
    );
  }
}

String _rankingCountLabel({required int visible, required int total}) {
  if (visible == total) {
    return '$total ranked';
  }

  return 'Top $visible of $total';
}

String _signedInteger(int value) {
  if (value > 0) {
    return '+$value';
  }

  return '$value';
}

String _tablePercent(double? value, {required bool isNew}) {
  if (isNew || value == null) {
    return '-';
  }

  final percent = value * 100;
  final prefix = percent > 0 ? '+' : '';

  return '$prefix${percent.toStringAsFixed(1)}%';
}

Future<void> _showInsightTrackContext(
  BuildContext context,
  LibraryTrack track,
) async {
  final canPlay =
      !track.isBlocked &&
      track.isAvailable &&
      track.filePath != null &&
      track.filePath!.trim().isNotEmpty;

  final playback = context.read<PlaybackCoordinator?>();

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                title: Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${track.artistName} / ${track.albumTitle}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.play_arrow_rounded),
                title: const Text('Play'),
                enabled: canPlay && playback != null,
                onTap: !canPlay || playback == null
                    ? null
                    : () {
                        Navigator.of(sheetContext).pop();
                        unawaited(playback.playTrack(track));
                      },
              ),
              ListTile(
                leading: const Icon(Icons.playlist_play_rounded),
                title: const Text('Play next'),
                enabled: canPlay && playback != null,
                onTap: !canPlay || playback == null
                    ? null
                    : () {
                        Navigator.of(sheetContext).pop();
                        unawaited(playback.playNext(track));
                      },
              ),
              ListTile(
                leading: const Icon(Icons.queue_music_rounded),
                title: const Text('Add to queue'),
                enabled: canPlay && playback != null,
                onTap: !canPlay || playback == null
                    ? null
                    : () {
                        Navigator.of(sheetContext).pop();
                        unawaited(playback.addToQueue(track));
                      },
              ),
              ListTile(
                leading: const Icon(Icons.playlist_add_rounded),
                title: const Text('Add to playlist'),
                enabled: canPlay,
                onTap: !canPlay
                    ? null
                    : () {
                        Navigator.of(sheetContext).pop();
                        unawaited(showAddToPlaylistFlow(context, track));
                      },
              ),
              ListTile(
                leading: const Icon(Icons.album_outlined),
                title: const Text('Go to album'),
                onTap: () {
                  Navigator.of(sheetContext).pop();

                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => AlbumProfilePage(
                        albumId: track.albumId,
                        initialAlbumTitle: track.albumTitle,
                      ),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.person_outline_rounded),
                title: const Text('Go to artist'),
                onTap: () {
                  Navigator.of(sheetContext).pop();

                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ArtistProfilePage(
                        artistId: track.artistId,
                        initialArtistName: track.artistName,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      );
    },
  );
}

String _formatMonth(DateTime month) {
  return '${_monthName(month.month)} ${month.year}';
}

String _monthName(int month) {
  return const [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ][month - 1];
}

String _shortMonthName(int month) {
  return const [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ][month - 1];
}

String _formatDuration(Duration duration) {
  final totalMinutes = duration.inMinutes;

  if (totalMinutes < 60) {
    return '${totalMinutes}m';
  }

  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;

  if (minutes == 0) {
    return '${hours}h';
  }

  return '${hours}h ${minutes}m';
}

String _formatPercentChange(double? value) {
  if (value == null) {
    return 'NEW';
  }

  final percent = value * 100;

  if (percent == 0) {
    return '0%';
  }

  final prefix = percent > 0 ? '+' : '';

  return '$prefix${percent.toStringAsFixed(1)}%';
}

String _formatRate(double value) {
  return '${(value * 100).toStringAsFixed(1)}%';
}

String _formatHour(int hour) {
  final normalized = hour % 24;

  if (normalized == 0) {
    return '12 AM';
  }

  if (normalized < 12) {
    return '$normalized AM';
  }

  if (normalized == 12) {
    return '12 PM';
  }

  return '${normalized - 12} PM';
}

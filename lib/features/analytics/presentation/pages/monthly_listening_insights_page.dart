import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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

    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: ListView(
        key: const PageStorageKey<String>('monthly-insights-scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 40),
        children: [
          const _InsightsHeader(),
          const SizedBox(height: 18),
          _MonthNavigator(controller: controller),
          const SizedBox(height: 22),

          if (controller.hasError) ...[
            _RefreshErrorBanner(onRetry: controller.refresh),
            const SizedBox(height: 16),
          ],

          if (!insights.hasListening)
            const _EmptyMonth()
          else ...[
            _HeadlineMetrics(insights: insights),
            const SizedBox(height: 24),
            _ActivitySection(insights: insights),
            const SizedBox(height: 26),
            _DailyTimeline(insights: insights),
            const SizedBox(height: 26),
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
    final theme = Theme.of(context);

    return Column(
      key: const ValueKey<String>('monthly-insights-header'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'SONUS',
          style: theme.textTheme.labelLarge?.copyWith(
            letterSpacing: 2.4,
            fontWeight: FontWeight.w800,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          'Monthly Insights',
          key: const ValueKey<String>('monthly-insights-title'),
          style: theme.textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.w900,
            height: 1,
          ),
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
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
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

class _HeadlineMetrics extends StatelessWidget {
  const _HeadlineMetrics({required this.insights});

  final MonthlyListeningInsights insights;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey<String>('monthly-insights-headline-metrics'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _PrimaryMetric(
                label: 'STREAMS',
                value: '${insights.currentSummary.qualifiedStreamCount}',
                comparison: _formatPercentChange(
                  insights.streamChange.percentChange,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _PrimaryMetric(
                label: 'LISTENING',
                value: _formatDuration(
                  insights.currentAudibleListeningDuration,
                ),
                comparison: _formatPercentChange(
                  insights.listeningTimeChange.percentChange,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _CompactMetric(
                label: 'TRACKS',
                value: insights.currentSummary.distinctSongCount,
                comparison: _formatPercentChange(
                  insights.trackCountChange.percentChange,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _CompactMetric(
                label: 'ARTISTS',
                value: insights.currentSummary.distinctArtistCount,
                comparison: _formatPercentChange(
                  insights.artistCountChange.percentChange,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _CompactMetric(
                label: 'ALBUMS',
                value: insights.currentSummary.distinctAlbumCount,
                comparison: _formatPercentChange(
                  insights.albumCountChange.percentChange,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PrimaryMetric extends StatelessWidget {
  const _PrimaryMetric({
    required this.label,
    required this.value,
    required this.comparison,
  });

  final String label;
  final String value;
  final String comparison;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              letterSpacing: 1,
              fontWeight: FontWeight.w800,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            '$comparison vs previous month',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactMetric extends StatelessWidget {
  const _CompactMetric({
    required this.label,
    required this.value,
    required this.comparison,
  });

  final String label;
  final int value;
  final String comparison;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(
            '$value',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              letterSpacing: 0.7,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$comparison vs prev',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
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

    return Column(
      key: const ValueKey<String>('monthly-insights-activity'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Listening activity',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        _ActivityRow(
          label: 'Busiest day',
          value: busiestDay == null
              ? '—'
              : '${_shortMonthName(busiestDay.localDate.month)} '
                    '${busiestDay.localDate.day} · '
                    '${busiestDay.streams} streams',
        ),
        const Divider(height: 1),
        _ActivityRow(
          label: 'Most active hour',
          value: mostActiveHour == null
              ? '—'
              : '${_formatHour(mostActiveHour.hour)} · '
                    '${_formatDuration(mostActiveHour.listeningDuration)}',
        ),
        const Divider(height: 1),
        _ActivityRow(
          label: 'Active days',
          value:
              '${insights.behavior.activeQualifiedDayCount} / '
              '${insights.distribution.days.length}',
        ),
        const Divider(height: 1),
        _ActivityRow(
          label: 'Average streams / active day',
          value: insights.behavior.activeQualifiedDayCount == 0
              ? '0'
              : insights.behavior.averageQualifiedStreamsPerActiveDay
                    .toStringAsFixed(1),
        ),
        const Divider(height: 1),
        _ActivityRow(
          label: 'Completion rate',
          value: _formatRate(insights.behavior.completionRate),
        ),
        const Divider(height: 1),
        _ActivityRow(
          label: 'Skip rate',
          value: _formatRate(insights.behavior.skipRate),
        ),
      ],
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 13),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 18),
          Text(
            value,
            textAlign: TextAlign.end,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _DailyTimeline extends StatelessWidget {
  const _DailyTimeline({required this.insights});

  final MonthlyListeningInsights insights;

  @override
  Widget build(BuildContext context) {
    final days = insights.distribution.days;

    if (days.isEmpty) {
      return const SizedBox.shrink();
    }

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

    final theme = Theme.of(context);

    return Column(
      key: const ValueKey<String>('monthly-insights-daily-timeline'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Daily timeline',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Streams and audible listening time by day',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 14),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final day in days) ...[
                _DailyTimelineCell(
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

class _DailyTimelineCell extends StatelessWidget {
  const _DailyTimelineCell({
    required this.day,
    required this.maxStreams,
    required this.maxListeningMinutes,
  });

  final MonthlyDailyListening day;
  final int maxStreams;
  final int maxListeningMinutes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final streamFraction = maxStreams == 0 ? 0.0 : day.streams / maxStreams;

    final listeningFraction = maxListeningMinutes == 0
        ? 0.0
        : day.listeningDuration.inMinutes / maxListeningMinutes;

    return Container(
      key: ValueKey<String>(
        'monthly-insights-day-'
        '${day.localDate.year}-'
        '${day.localDate.month}-'
        '${day.localDate.day}',
      ),
      width: 86,
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${_shortMonthName(day.localDate.month)} '
            '${day.localDate.day}',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 70,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _TimelineBar(
                  fraction: streamFraction,
                  icon: Icons.play_arrow_rounded,
                ),
                const SizedBox(width: 7),
                _TimelineBar(
                  fraction: listeningFraction,
                  icon: Icons.schedule_rounded,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${day.streams} streams',
            maxLines: 1,
            style: theme.textTheme.labelSmall,
          ),
          const SizedBox(height: 2),
          Text(
            _formatDuration(day.listeningDuration),
            maxLines: 1,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineBar extends StatelessWidget {
  const _TimelineBar({required this.fraction, required this.icon});

  final double fraction;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final normalized = fraction.clamp(0.0, 1.0);

    return SizedBox(
      width: 22,
      height: 70,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: FractionallySizedBox(
                heightFactor: normalized,
                child: Container(
                  width: 18,
                  constraints: normalized > 0
                      ? const BoxConstraints(minHeight: 4)
                      : null,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Icon(icon, size: 13, color: theme.colorScheme.onSurfaceVariant),
        ],
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
          _TrackTable(rows: tracks),
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
          _ArtistTable(rows: artists),
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
          _AlbumTable(rows: albums),
        ],
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.detail});

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Text(
          detail,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _TrackTable extends StatelessWidget {
  const _TrackTable({required this.rows});

  final List<MonthlyTrackInsightRow> rows;

  @override
  Widget build(BuildContext context) {
    return _HorizontalInsightTable(
      minWidth: 940,
      header: const _TableHeader(entityLabel: 'TRACK'),
      rows: [
        for (final row in rows)
          _TrackInsightTableRow(
            key: ValueKey<String>('monthly-insights-track-${row.entityId}'),
            row: row,
          ),
      ],
    );
  }
}

class _ArtistTable extends StatelessWidget {
  const _ArtistTable({required this.rows});

  final List<MonthlyArtistInsightRow> rows;

  @override
  Widget build(BuildContext context) {
    return _HorizontalInsightTable(
      minWidth: 900,
      header: const _TableHeader(entityLabel: 'ARTIST'),
      rows: [
        for (final row in rows)
          _ArtistInsightTableRow(
            key: ValueKey<String>('monthly-insights-artist-${row.entityId}'),
            row: row,
          ),
      ],
    );
  }
}

class _AlbumTable extends StatelessWidget {
  const _AlbumTable({required this.rows});

  final List<MonthlyAlbumInsightRow> rows;

  @override
  Widget build(BuildContext context) {
    return _HorizontalInsightTable(
      minWidth: 920,
      header: const _TableHeader(entityLabel: 'ALBUM'),
      rows: [
        for (final row in rows)
          _AlbumInsightTableRow(
            key: ValueKey<String>('monthly-insights-album-${row.entityId}'),
            row: row,
          ),
      ],
    );
  }
}

class _HorizontalInsightTable extends StatelessWidget {
  const _HorizontalInsightTable({
    required this.minWidth,
    required this.header,
    required this.rows,
  });

  final double minWidth;
  final Widget header;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(16),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: minWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                for (final row in rows) ...[const Divider(height: 1), row],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TableHeader extends StatelessWidget {
  const _TableHeader({required this.entityLabel});

  final String entityLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final style = theme.textTheme.labelSmall?.copyWith(
      fontWeight: FontWeight.w800,
      letterSpacing: 0.6,
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Container(
      color: theme.colorScheme.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
      child: Row(
        children: [
          _HeaderCell(
            width: 42,
            text: '#',
            style: style,
            alignment: Alignment.center,
          ),
          _HeaderCell(width: 330, text: entityLabel, style: style),
          _HeaderCell(
            width: 84,
            text: 'STREAMS',
            style: style,
            alignment: Alignment.centerRight,
          ),
          _HeaderCell(
            width: 72,
            text: 'CHANGE',
            style: style,
            alignment: Alignment.centerRight,
          ),
          _HeaderCell(
            width: 72,
            text: '%',
            style: style,
            alignment: Alignment.centerRight,
          ),
          _HeaderCell(
            width: 120,
            text: 'LISTENING',
            style: style,
            alignment: Alignment.centerRight,
          ),
          _HeaderCell(
            width: 110,
            text: 'LIFETIME',
            style: style,
            alignment: Alignment.centerRight,
          ),
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({
    required this.width,
    required this.text,
    required this.style,
    this.alignment = Alignment.centerLeft,
  });

  final double width;
  final String text;
  final TextStyle? style;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Align(
        alignment: alignment,
        child: Text(text, maxLines: 1, style: style),
      ),
    );
  }
}

class _TrackInsightTableRow extends StatelessWidget {
  const _TrackInsightTableRow({super.key, required this.row});

  final MonthlyTrackInsightRow row;

  @override
  Widget build(BuildContext context) {
    final track = row.track;

    return InkWell(
      onTap: track == null
          ? null
          : () {
              unawaited(_showInsightTrackContext(context, track));
            },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: _DataRowLayout(
          rank: row.rank,
          entity: _EntityCell(
            artworkPath: row.artworkPath,
            fallbackIcon: Icons.music_note_rounded,
            title: row.title,
            subtitle: row.artistName,
            badge: !row.hasCurrentLibraryEntity
                ? 'HISTORICAL'
                : row.isBlocked
                ? 'BLACKLISTED'
                : !row.isAvailable
                ? 'UNAVAILABLE'
                : null,
          ),
          streams: row.streams,
          change: row.streamChange,
          percentChange: row.streamPercentChange,
          isNew: row.isNew,
          listeningDuration: row.listeningDuration,
          lifetimeStreams: row.lifetimeStreams,
          movement: row.rankMovement,
        ),
      ),
    );
  }
}

class _ArtistInsightTableRow extends StatelessWidget {
  const _ArtistInsightTableRow({super.key, required this.row});

  final MonthlyArtistInsightRow row;

  @override
  Widget build(BuildContext context) {
    final artist = row.artist;

    return InkWell(
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
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: _DataRowLayout(
          rank: row.rank,
          entity: _EntityCell(
            artworkPath: row.artworkPath,
            fallbackIcon: Icons.person_rounded,
            title: row.name,
            subtitle: row.subtitle,
            badge: row.hasCurrentLibraryEntity ? null : 'HISTORICAL',
            circularArtwork: true,
          ),
          streams: row.streams,
          change: row.streamChange,
          percentChange: row.streamPercentChange,
          isNew: row.isNew,
          listeningDuration: row.listeningDuration,
          lifetimeStreams: row.lifetimeStreams,
          movement: row.rankMovement,
        ),
      ),
    );
  }
}

class _AlbumInsightTableRow extends StatelessWidget {
  const _AlbumInsightTableRow({super.key, required this.row});

  final MonthlyAlbumInsightRow row;

  @override
  Widget build(BuildContext context) {
    final album = row.album;

    return InkWell(
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
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: _DataRowLayout(
          rank: row.rank,
          entity: _EntityCell(
            artworkPath: row.artworkPath,
            fallbackIcon: Icons.album_rounded,
            title: row.title,
            subtitle: row.artistName,
            badge: row.hasCurrentLibraryEntity ? null : 'HISTORICAL',
          ),
          streams: row.streams,
          change: row.streamChange,
          percentChange: row.streamPercentChange,
          isNew: row.isNew,
          listeningDuration: row.listeningDuration,
          lifetimeStreams: row.lifetimeStreams,
          movement: row.rankMovement,
        ),
      ),
    );
  }
}

class _DataRowLayout extends StatelessWidget {
  const _DataRowLayout({
    required this.rank,
    required this.entity,
    required this.streams,
    required this.change,
    required this.percentChange,
    required this.isNew,
    required this.listeningDuration,
    required this.lifetimeStreams,
    required this.movement,
  });

  final int rank;
  final Widget entity;
  final int streams;
  final int change;
  final double? percentChange;
  final bool isNew;
  final Duration listeningDuration;
  final int lifetimeStreams;
  final int? movement;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        SizedBox(
          width: 42,
          child: Column(
            children: [
              Text(
                '$rank',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              _RankMovementLabel(movement: movement, isNew: isNew),
            ],
          ),
        ),
        SizedBox(width: 330, child: entity),
        _NumericCell(width: 84, value: '$streams'),
        _NumericCell(
          width: 72,
          value: isNew ? 'NEW' : _signedInteger(change),
          emphasized: isNew || change != 0,
        ),
        _NumericCell(
          width: 72,
          value: _tablePercent(percentChange, isNew: isNew),
        ),
        _NumericCell(width: 120, value: _formatDuration(listeningDuration)),
        _NumericCell(width: 110, value: '$lifetimeStreams'),
      ],
    );
  }
}

class _EntityCell extends StatelessWidget {
  const _EntityCell({
    required this.artworkPath,
    required this.fallbackIcon,
    required this.title,
    required this.subtitle,
    this.badge,
    this.circularArtwork = false,
  });

  final String? artworkPath;
  final IconData fallbackIcon;
  final String title;
  final String subtitle;
  final String? badge;
  final bool circularArtwork;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        _SmallArtwork(
          path: artworkPath,
          fallbackIcon: fallbackIcon,
          circular: circularArtwork,
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (badge != null) ...[
                const SizedBox(height: 3),
                Text(
                  badge!,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SmallArtwork extends StatelessWidget {
  const _SmallArtwork({
    required this.path,
    required this.fallbackIcon,
    this.circular = false,
  });

  final String? path;
  final IconData fallbackIcon;
  final bool circular;

  @override
  Widget build(BuildContext context) {
    final normalizedPath = path?.trim();

    final child = SizedBox.square(
      dimension: 46,
      child: normalizedPath == null || normalizedPath.isEmpty
          ? _SmallArtworkFallback(icon: fallbackIcon)
          : Image.file(
              File(normalizedPath),
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) =>
                  _SmallArtworkFallback(icon: fallbackIcon),
            ),
    );

    if (circular) {
      return ClipOval(child: child);
    }

    return ClipRRect(borderRadius: BorderRadius.circular(9), child: child);
  }
}

class _SmallArtworkFallback extends StatelessWidget {
  const _SmallArtworkFallback({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          icon,
          size: 22,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _NumericCell extends StatelessWidget {
  const _NumericCell({
    required this.width,
    required this.value,
    this.emphasized = false,
  });

  final double width;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: width,
      child: Text(
        value,
        textAlign: TextAlign.right,
        maxLines: 1,
        style: theme.textTheme.bodySmall?.copyWith(
          fontWeight: emphasized ? FontWeight.w800 : FontWeight.w600,
        ),
      ),
    );
  }
}

class _RankMovementLabel extends StatelessWidget {
  const _RankMovementLabel({required this.movement, required this.isNew});

  final int? movement;
  final bool isNew;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final label = isNew
        ? 'NEW'
        : movement == null || movement == 0
        ? '-'
        : movement! > 0
        ? '+${movement!}'
        : '${movement!}';

    return Text(
      label,
      style: theme.textTheme.labelSmall?.copyWith(
        fontWeight: FontWeight.w800,
        color: isNew
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurfaceVariant,
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
    return Material(
      key: const ValueKey<String>('monthly-insights-refresh-error'),
      color: Theme.of(context).colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Insights could not refresh. Showing the last available data.',
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
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (action != null) ...[const SizedBox(height: 18), action!],
          ],
        ),
      ),
    );
  }
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

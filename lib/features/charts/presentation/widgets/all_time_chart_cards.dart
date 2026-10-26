import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/design/sonus_count_label.dart';
import '../../../../core/design/sonus_theme.dart';
import '../../../../core/design/widgets/sonus_artwork_frame.dart';
import '../../../../core/design/widgets/sonus_decorations.dart';
import '../../../../core/design/widgets/sonus_word_fit_text.dart';
import '../../domain/entities/chart_entry.dart';
import '../../domain/models/all_time_entry_stats.dart';
import '../../domain/models/chart_type.dart';
import '../../domain/services/all_time_history_replay.dart';
import 'chart_extended_divider.dart';
import 'chart_entry_card.dart';
import 'chart_movement_indicator.dart';

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

/// "Top 3: 2 · Top 10: 3": the two most selective zones it spent weeks in.
String zoneWeeksSummary(ZoneWeeks zones) {
  final reached = [
    for (final zone in ZoneWeeks.zones)
      if (zones.weeksIn(zone) > 0) 'Top $zone: ${zones.weeksIn(zone)}',
  ];

  return reached.isEmpty
      ? 'No completed weeks yet'
      : reached.take(2).join(' · ');
}

/// Every zone, as a sheet opened from a chart card.
Future<void> showZoneWeeksSheet(
  BuildContext context, {
  required String title,
  required ZoneWeeks zones,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      final colors = SonusTheme.of(sheetContext).colors;
      final theme = Theme.of(sheetContext);

      return SafeArea(
        child: ListView(
          key: const ValueKey<String>('charts-zone-weeks-sheet'),
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          children: [
            Semantics(
              header: true,
              child: Text(
                'Weeks in zones',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '$title · completed chart weeks on the all-time chart. A week '
              'at #3 counts for the Top 3 and every larger zone.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            for (final zone in ZoneWeeks.zones)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Top $zone'),
                trailing: Text(
                  '${zones.weeksIn(zone)} '
                  '${sonusCountNoun(zones.weeksIn(zone), 'week')}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}

/// What NEW and RE-ENTRY mean on the all-time chart.
class AllTimeMovementLegend extends StatelessWidget {
  const AllTimeMovementLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;

    return Text(
      'NEW: in the standings for the first time this week. '
      'RE-ENTRY: back after dropping out. Arrows compare with the start of '
      'the week; change compares streams with the same time last week.',
      key: const ValueKey<String>('charts-movement-legend'),
      style: Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
    );
  }
}

String _summary(
  ChartEntry entry,
  ChartType chartType,
  AllTimeEntryStats stats,
  ChartEntryStatus? status,
  int? weeklyPeakRank,
) {
  return [
    ChartEntryCard.semanticLabelFor(
      entry,
      subtitle: ChartEntryCard.subtitleFor(entry, chartType),
      status: status,
      isAllTime: true,
      weeklyPeakRank: weeklyPeakRank,
    ),
    WeeklyChange.of(stats).spoken,
    'weeks in zones ${zoneWeeksSummary(stats.zones)}',
  ].join(', ');
}

/// The all-time #1, given the room of a spotlight.
class AllTimeSpotlightCard extends StatelessWidget {
  const AllTimeSpotlightCard({
    super.key,
    required this.entry,
    required this.chartType,
    required this.stats,
    required this.artworkPath,
    this.status,
    this.weeklyPeakRank,
    this.onTap,
  });

  final ChartEntry entry;
  final ChartType chartType;
  final AllTimeEntryStats stats;
  final String? artworkPath;
  final ChartEntryStatus? status;
  final int? weeklyPeakRank;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final theme = Theme.of(context);
    final change = WeeklyChange.of(stats);
    final id = entry.entity.entityId;
    final top3 = stats.zones.weeksIn(3);

    return Material(
      key: ValueKey<String>('charts-spotlight-$id'),
      color: colors.raisedSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.metrics.cardRadius + 6),
        side: BorderSide(color: colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onTap,
            child: Semantics(
              button: onTap != null,
              label: _summary(entry, chartType, stats, status, weeklyPeakRank),
              excludeSemantics: true,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Text(
                          '#${entry.rank}',
                          key: ValueKey<String>('charts-rank-$id'),
                          style: tokens.text.chartRank.copyWith(
                            color: colors.accentPrimary,
                            fontSize: 34,
                          ),
                        ),
                        const Spacer(),
                        ChartMovementIndicator(entry: entry),
                      ],
                    ),
                    const SizedBox(height: 12),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final size = constraints.maxWidth.clamp(0.0, 320.0);
                        return Center(
                          child: _Artwork(
                            key: ValueKey<String>('charts-artwork-$id'),
                            path: artworkPath,
                            size: size,
                            chartType: chartType,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 14),
                    Text(
                      entry.entity.title,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      ChartEntryCard.subtitleFor(entry, chartType),
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                    if (status != null) ...[
                      const SizedBox(height: 8),
                      _StatusBadge(status: status!),
                    ],
                    const SizedBox(height: 14),
                    _TileGrid(
                      columns: 2,
                      tiles: [
                        _StatTile(
                          label: 'TOTAL STREAMS',
                          value: '${entry.qualifiedStreamCount}',
                        ),
                        _StatTile(
                          label: 'WEEKLY CHANGE',
                          value: change.text,
                          trend: change.trend,
                        ),
                        _StatTile(
                          label: 'ALL-TIME PEAK',
                          value: '#${entry.peakRank}',
                          detail: weeklyPeakRank == null
                              ? null
                              : 'Weekly peak #$weeklyPeakRank',
                        ),
                        _StatTile(label: 'WEEKS IN TOP 3', value: '$top3'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          _ZonesButton(entry: entry, stats: stats),
        ],
      ),
    );
  }
}

/// Positions 2–200: rank, artwork and title, the weekly change once, then
/// streams, peak and the start-of-week position, and weeks in zones.
class AllTimeEntryCard extends StatelessWidget {
  const AllTimeEntryCard({
    super.key,
    required this.entry,
    required this.chartType,
    required this.stats,
    required this.artworkPath,
    this.status,
    this.weeklyPeakRank,
    this.onTap,
  });

  final ChartEntry entry;
  final ChartType chartType;
  final AllTimeEntryStats stats;
  final String? artworkPath;
  final ChartEntryStatus? status;
  final int? weeklyPeakRank;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final theme = Theme.of(context);
    final id = entry.entity.entityId;
    final isExtended = entry.isOffChartStanding;
    final change = WeeklyChange.of(stats);
    final scaler = MediaQuery.textScalerOf(context);
    final previous = entry.previousFinalRank;

    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          entry.entity.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium?.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          ChartEntryCard.subtitleFor(entry, chartType),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.textSecondary,
          ),
        ),
      ],
    );
    final changeLabel = _TrendText(
      key: ValueKey<String>('charts-change-$id'),
      change: change,
    );

    return Material(
      key: ValueKey<String>('charts-rich-$id'),
      color: isExtended ? Colors.transparent : colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.metrics.cardRadius),
        side: BorderSide(color: isExtended ? colors.divider : colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onTap,
            child: Semantics(
              button: onTap != null,
              label: _summary(entry, chartType, stats, status, weeklyPeakRank),
              excludeSemantics: true,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final besides =
                            scaler.scale(ChartEntryCard.rankColumnWidth) +
                            12 +
                            ChartEntryCard.artworkSize +
                            12;
                        final compact =
                            constraints.maxWidth - besides <
                            ChartEntryCard.minDetailsWidth + 60;
                        final lead = [
                          _Rank(entry: entry),
                          const SizedBox(width: 12),
                          _Artwork(
                            key: ValueKey<String>('charts-artwork-$id'),
                            path: artworkPath,
                            size: ChartEntryCard.artworkSize,
                            chartType: chartType,
                          ),
                          const SizedBox(width: 12),
                        ];

                        if (compact) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: lead),
                              const SizedBox(height: 10),
                              heading,
                              const SizedBox(height: 6),
                              changeLabel,
                            ],
                          );
                        }

                        // The change sits under the title, so the title
                        // keeps the full width and never breaks mid-word.
                        return Row(
                          children: [
                            ...lead,
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  heading,
                                  const SizedBox(height: 6),
                                  changeLabel,
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    if (isExtended || status != null) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          if (isExtended)
                            _Badge(
                              key: ValueKey<String>('charts-extended-$id'),
                              label: ChartZoneNames.lowerZoneBadge(chartType),
                              borderColor: colors.border,
                            ),
                          if (status != null) _StatusBadge(status: status!),
                        ],
                      ),
                    ],
                    const SizedBox(height: 10),
                    Divider(height: 1, color: colors.divider),
                    const SizedBox(height: 10),
                    _TileGrid(
                      columns: 3,
                      tiles: [
                        _StatTile(
                          label: 'STREAMS',
                          value: '${entry.qualifiedStreamCount}',
                        ),
                        _StatTile(
                          label: 'PEAK',
                          value: '#${entry.peakRank}',
                          detail: weeklyPeakRank == null
                              ? null
                              : 'Weekly #$weeklyPeakRank',
                        ),
                        _StatTile(
                          key: ValueKey<String>('charts-last-week-$id'),
                          label: 'WEEK START',
                          value: previous == null ? '—' : '#$previous',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          _ZonesButton(entry: entry, stats: stats),
        ],
      ),
    );
  }
}

class _ZonesButton extends StatelessWidget {
  const _ZonesButton({required this.entry, required this.stats});

  final ChartEntry entry;
  final AllTimeEntryStats stats;

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;
    final theme = Theme.of(context);
    final summary = zoneWeeksSummary(stats.zones);

    return InkWell(
      key: ValueKey<String>('charts-zones-${entry.entity.entityId}'),
      onTap: () => showZoneWeeksSheet(
        context,
        title: entry.entity.title,
        zones: stats.zones,
      ),
      child: Semantics(
        button: true,
        label: 'Weeks in zones: $summary. Show every zone',
        excludeSemantics: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Weeks in zones · $summary',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.textSecondary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: colors.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TileGrid extends StatelessWidget {
  const _TileGrid({required this.columns, required this.tiles});

  final int columns;
  final List<Widget> tiles;

  static const double _gap = 8;

  @override
  Widget build(BuildContext context) {
    // Scaled like body text: Android scales large sizes less, so scaling
    // the width itself would underestimate the room 2x text needs.
    final textGrowth = MediaQuery.textScalerOf(context).scale(14) / 14;
    final minTile = 92 * textGrowth;

    return LayoutBuilder(
      builder: (context, constraints) {
        var perRow = columns;
        while (perRow > 1 &&
            (constraints.maxWidth - _gap * (perRow - 1)) / perRow < minTile) {
          perRow--;
        }
        final width = (constraints.maxWidth - _gap * (perRow - 1)) / perRow;

        return Wrap(
          spacing: _gap,
          runSpacing: _gap,
          children: [
            for (final tile in tiles) SizedBox(width: width, child: tile),
          ],
        );
      },
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    super.key,
    required this.label,
    required this.value,
    this.detail,
    this.trend,
  });

  final String label;
  final String value;
  final String? detail;
  final WeeklyTrend? trend;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final theme = Theme.of(context);
    final trend = this.trend;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.background.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(tokens.metrics.controlRadius + 4),
        border: Border.all(color: colors.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SonusWordFitText(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.textSecondary,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                if (trend != null) ...[
                  _TrendIcon(trend: trend),
                  const SizedBox(width: 2),
                ],
                Flexible(
                  child: SonusWordFitText(
                    value,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
            if (detail != null)
              Text(
                detail!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TrendText extends StatelessWidget {
  const _TrendText({super.key, required this.change});

  final WeeklyChange change;

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _TrendIcon(trend: change.trend),
        const SizedBox(width: 2),
        Flexible(
          child: Text(
            change.text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

/// The direction as an icon in the chart colours; the text carries the
/// meaning, so colour is never the only signal.
class _TrendIcon extends StatelessWidget {
  const _TrendIcon({required this.trend});

  final WeeklyTrend trend;

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;
    final (icon, color) = switch (trend) {
      WeeklyTrend.up => (Icons.trending_up_rounded, colors.chartUp),
      WeeklyTrend.down => (Icons.trending_down_rounded, colors.chartDown),
      WeeklyTrend.flat => (Icons.trending_flat_rounded, colors.chartSteady),
      WeeklyTrend.fresh => (Icons.auto_awesome_rounded, colors.chartNew),
      WeeklyTrend.none => (Icons.remove_rounded, colors.chartSteady),
    };

    return Icon(icon, size: 18, color: color);
  }
}

class _Rank extends StatelessWidget {
  const _Rank({required this.entry});

  final ChartEntry entry;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);

    return SizedBox(
      width: MediaQuery.textScalerOf(
        context,
      ).scale(ChartEntryCard.rankColumnWidth),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${entry.rank}',
            key: ValueKey<String>('charts-rank-${entry.entity.entityId}'),
            textAlign: TextAlign.center,
            style: tokens.text.chartRank.copyWith(
              color: entry.isOffChartStanding
                  ? tokens.colors.textSecondary
                  : tokens.colors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: ChartMovementIndicator(entry: entry),
          ),
        ],
      ),
    );
  }
}

class _Artwork extends StatelessWidget {
  const _Artwork({
    super.key,
    required this.path,
    required this.size,
    required this.chartType,
  });

  final String? path;
  final double size;
  final ChartType chartType;

  @override
  Widget build(BuildContext context) {
    final trimmed = path?.trim();
    final fallback = SonusArtworkPlaceholder(
      icon: chartType == ChartType.songs
          ? Icons.music_note_rounded
          : Icons.album_rounded,
      iconSize: size * 0.4,
    );

    return SonusArtworkFrame(
      size: size,
      child: trimmed == null || trimmed.isEmpty
          ? fallback
          : Image.file(
              File(trimmed),
              fit: BoxFit.cover,
              cacheWidth: (size * MediaQuery.devicePixelRatioOf(context))
                  .round(),
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => fallback,
            ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final ChartEntryStatus status;

  @override
  Widget build(BuildContext context) {
    return _Badge(
      label: status.label,
      borderColor: status == ChartEntryStatus.historical
          ? SonusTheme.of(context).colors.border
          : Theme.of(context).colorScheme.error,
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({super.key, required this.label, required this.borderColor});

  final String label;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(tokens.metrics.controlRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: tokens.colors.textPrimary,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        ),
      ),
    );
  }
}

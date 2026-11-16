import 'package:flutter/material.dart';

import '../../../../core/design/sonus_greyscale_theme.dart';
import '../../../../core/design/sonus_theme.dart';
import '../../domain/entities/chart_entry.dart';
import '../../domain/models/all_time_entry_stats.dart';
import '../../domain/models/chart_type.dart';
import '../../domain/services/all_time_history_replay.dart';
import '../../../../core/design/sonus_count_label.dart';
import '../models/chart_entry_text.dart';
import '../models/chart_longevity.dart';
import '../models/chart_rank_trend.dart';
import 'chart_extended_divider.dart';
import 'chart_longevity_facts.dart';

/// "186420771" → "186,420,771".
String chartGroupedCount(int value) {
  final digits = value.abs().toString();
  final out = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}

/// Every zone, as a sheet opened from an entry's details.
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
              '$title · completed chart weeks in the career standings. A '
              'week at #3 counts for the Top 3 and every larger zone.',
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

/// One statistic in the expanded entry.
class ChartDetailStat {
  const ChartDetailStat({
    required this.id,
    required this.label,
    required this.value,
    this.detail,
    this.trend,
    this.onTap,
    this.tapHint,
  });

  /// Names the tile in keys: `charts-detail-<id>-<entity>`.
  final String id;
  final String label;
  final String value;
  final String? detail;

  /// Colours the value as a rise or fall.
  final WeeklyTrend? trend;
  final VoidCallback? onTap;

  /// Spoken after the value when [onTap] is set, e.g. "show every zone".
  final String? tapHint;
}

/// What the expanded entry shows (App Update 1.3 Chart Studio). Every value
/// is one Sonus already calculates; nothing is estimated for display.
class ChartDetailsData {
  const ChartDetailsData({
    required this.stats,
    this.chips = const [],
    this.facts = const [],
    this.trend,
  });

  /// The career standings: total streams, the change against this time last
  /// week, the career peak (with the weekly peak) and weeks in the most
  /// selective zone reached.
  factory ChartDetailsData.career({
    required ChartEntry entry,
    required ChartType chartType,
    required AllTimeEntryStats stats,
    required int? weeklyPeakRank,
    required ChartLongevity? longevity,
    required bool isSingle,
    required ChartEntryStatus? status,
    required ChartRankTrend? trend,
    required String? movementNote,
    required VoidCallback onShowZones,
  }) {
    final change = WeeklyChange.of(stats);
    final zone = _bestZone(stats.zones);
    return ChartDetailsData(
      chips: _chips(entry, chartType, isSingle: isSingle, status: status),
      stats: [
        ChartDetailStat(
          id: 'streams',
          label: 'Total streams',
          value: chartGroupedCount(entry.qualifiedStreamCount),
        ),
        ChartDetailStat(
          id: 'change',
          label: 'Weekly change',
          value: change.text,
          detail: 'vs this time last week',
          trend: change.trend,
        ),
        ChartDetailStat(
          id: 'peak',
          label: 'Career peak',
          value: '#${entry.peakRank}',
          detail: weeklyPeakRank == null
              ? null
              : 'Weekly peak #$weeklyPeakRank',
        ),
        if (zone == null)
          ChartDetailStat(
            id: 'zones',
            label: 'Weeks in zones',
            value: '—',
            detail: 'No completed weeks yet',
          )
        else
          ChartDetailStat(
            id: 'zones',
            label: 'Weeks in Top $zone',
            value: '${stats.zones.weeksIn(zone)}',
            detail: 'All zones',
            onTap: onShowZones,
            tapHint: 'show every zone',
          ),
      ],
      facts: [
        ChartEntryText.lastWeekText(
          entry,
          isAllTime: true,
          previousExtendedRank: null,
          chartType: chartType,
        ),
        ?_capitalised(movementNote),
        for (final fact in chartLongevityFacts(longevity)) fact.text,
      ],
      trend: trend,
    );
  }

  /// A weekly chart (a finalized week or the week in progress): that week's
  /// streams, its peak, last week and weeks on the chart.
  factory ChartDetailsData.weekly({
    required ChartEntry entry,
    required ChartType chartType,
    required int? previousExtendedRank,
    required int? bestSoFarRank,
    required int? weeklyPeakRank,
    required ChartLongevity? longevity,
    required bool isSingle,
    required ChartEntryStatus? status,
    required ChartRankTrend? trend,
    required String? movementNote,
  }) {
    final weeks = entry.weeksOnChart;
    return ChartDetailsData(
      chips: _chips(entry, chartType, isSingle: isSingle, status: status),
      stats: [
        ChartDetailStat(
          id: 'streams',
          label: 'Streams this week',
          value: chartGroupedCount(entry.qualifiedStreamCount),
        ),
        if (bestSoFarRank != null)
          ChartDetailStat(
            id: 'peak',
            label: 'Best so far',
            value: '#$bestSoFarRank',
            detail: weeklyPeakRank == null ? null : 'Peak #$weeklyPeakRank',
          )
        else
          ChartDetailStat(
            id: 'peak',
            label: 'Peak',
            value: '#${entry.peakRank}',
          ),
        ChartDetailStat(id: 'weeks', label: 'Weeks on chart', value: '$weeks'),
      ],
      facts: [
        ChartEntryText.lastWeekText(
          entry,
          isAllTime: false,
          previousExtendedRank: previousExtendedRank,
          chartType: chartType,
        ),
        ?_capitalised(movementNote),
        for (final fact in chartLongevityFacts(
          longevity,
          includeOfficialWeeks: false,
        ))
          fact.text,
      ],
      trend: trend,
    );
  }

  final List<ChartDetailStat> stats;
  final List<String> chips;
  final List<String> facts;

  /// Finalized weekly positions; null when there are too few to draw.
  final ChartRankTrend? trend;

  /// The row's movement note ("+4% position", "from Bubbling Under"),
  /// shown here since the row keeps only the arrow under its rank.
  static String? _capitalised(String? note) => note == null || note.isEmpty
      ? null
      : '${note[0].toUpperCase()}${note.substring(1)}';

  static int? _bestZone(ZoneWeeks zones) {
    for (final zone in ZoneWeeks.zones) {
      if (zones.weeksIn(zone) > 0) return zone;
    }
    return null;
  }

  static List<String> _chips(
    ChartEntry entry,
    ChartType chartType, {
    required bool isSingle,
    required ChartEntryStatus? status,
  }) => [
    if (isSingle) 'Single',
    if (entry.isOffChartStanding) ChartZoneNames.lowerZoneBadge(chartType),
    ?status?.spokenLabel,
  ];
}

/// The expanded entry: a continuation of its chart row, never a second card
/// (App Update 1.3 Chart Studio). Chips, a two-column statistics grid, the
/// entry's milestones, a finalized weekly trend when there is one, and the
/// way into the full statistics.
class ChartEntryDetails extends StatelessWidget {
  const ChartEntryDetails({
    super.key,
    required this.entityId,
    required this.data,
    this.openLabel,
    this.onOpen,
  });

  final String entityId;
  final ChartDetailsData data;

  /// "Song stats" or "Open release"; no button without [onOpen].
  final String? openLabel;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final theme = Theme.of(context);
    final factStyle = theme.textTheme.bodySmall?.copyWith(
      color: colors.textSecondary,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return Padding(
      key: ValueKey<String>('charts-details-$entityId'),
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Divider(height: 1, color: colors.divider),
          const SizedBox(height: 10),
          if (data.chips.isNotEmpty) ...[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [for (final chip in data.chips) _Chip(label: chip)],
            ),
            const SizedBox(height: 10),
          ],
          _StatGrid(entityId: entityId, stats: data.stats),
          if (data.facts.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              data.facts.join(' · '),
              key: ValueKey<String>('charts-details-facts-$entityId'),
              style: factStyle,
            ),
          ],
          if (data.trend case final trend?) ...[
            const SizedBox(height: 10),
            ChartRankSparkline(
              key: ValueKey<String>('charts-details-trend-$entityId'),
              trend: trend,
            ),
          ],
          if (onOpen != null && openLabel != null)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                key: ValueKey<String>('charts-details-open-$entityId'),
                onPressed: onOpen,
                style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                icon: const Icon(Icons.insights_rounded, size: 18),
                label: Text(openLabel!),
              ),
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.border),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: colors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Two columns, or one when the text is too large for two.
class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.entityId, required this.stats});

  final String entityId;
  final List<ChartDetailStat> stats;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scaler = MediaQuery.textScalerOf(context);
        final columns = constraints.maxWidth / scaler.scale(1) < 260 ? 1 : 2;
        final rows = <Widget>[];
        for (var i = 0; i < stats.length; i += columns) {
          final cells = [
            for (var c = 0; c < columns; c++)
              Expanded(
                child: i + c < stats.length
                    ? _StatCell(entityId: entityId, stat: stats[i + c])
                    : const SizedBox.shrink(),
              ),
          ];
          if (rows.isNotEmpty) rows.add(const SizedBox(height: 6));
          rows.add(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var c = 0; c < cells.length; c++) ...[
                    if (c > 0) const SizedBox(width: 6),
                    cells[c],
                  ],
                ],
              ),
            ),
          );
        }
        return Column(children: rows);
      },
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({required this.entityId, required this.stat});

  final String entityId;
  final ChartDetailStat stat;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final theme = Theme.of(context);
    final grey = sonusThemeIsGreyscale(colors.accentPrimary);
    final valueColor = grey
        ? colors.textPrimary
        : switch (stat.trend) {
            WeeklyTrend.up || WeeklyTrend.fresh => colors.chartUp,
            WeeklyTrend.down => colors.chartDown,
            _ => colors.textPrimary,
          };
    final arrow = switch (stat.trend) {
      WeeklyTrend.up => Icons.trending_up_rounded,
      WeeklyTrend.down => Icons.trending_down_rounded,
      _ => null,
    };
    final spoken = [
      stat.label,
      stat.value == '—' ? 'none' : stat.value,
      ?stat.detail,
      if (stat.onTap != null) ?stat.tapHint,
    ].join(', ');

    final body = Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            stat.label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              if (arrow != null) ...[
                Icon(arrow, size: 18, color: valueColor),
                const SizedBox(width: 4),
              ],
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    stat.value,
                    key: ValueKey<String>('charts-detail-${stat.id}-$entityId'),
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: valueColor,
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (stat.detail case final detail?)
            Row(
              children: [
                Flexible(
                  child: Text(
                    detail,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
                if (stat.onTap != null)
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: colors.textSecondary,
                  ),
              ],
            ),
        ],
      ),
    );

    final radius = BorderRadius.circular(tokens.metrics.controlRadius);
    // Each statistic is its own TalkBack stop.
    return Semantics(
      container: true,
      button: stat.onTap != null,
      label: spoken,
      excludeSemantics: true,
      child: Material(
        // A dark inset over the open tile's gradient, never a grey block.
        color: tokens.decoration.allowGradients
            ? colors.background.withValues(alpha: 0.42)
            : colors.textPrimary.withValues(alpha: 0.05),
        borderRadius: radius,
        child: stat.onTap == null
            ? body
            : InkWell(
                key: ValueKey<String>('charts-detail-tap-${stat.id}-$entityId'),
                onTap: stat.onTap,
                borderRadius: radius,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: body,
                ),
              ),
      ),
    );
  }
}

/// A small line of finalized weekly positions, #1 at the top. Weeks off the
/// chart are gaps: no line is drawn across them.
class ChartRankSparkline extends StatelessWidget {
  const ChartRankSparkline({super.key, required this.trend});

  final ChartRankTrend trend;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final theme = Theme.of(context);
    final grey = sonusThemeIsGreyscale(colors.accentPrimary);
    final gradient = tokens.decoration.allowGradients && !grey;
    final latest = trend.latestRank;
    final caption = [
      'Weekly chart · last ${trend.weeks.length} finalized weeks',
      'Best #${trend.bestRank}',
      latest == null ? 'Off the latest chart' : 'Latest #$latest',
    ].join(' · ');

    return Semantics(
      label: trend.spokenLabel,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 44,
            child: CustomPaint(
              painter: _SparklinePainter(
                ranks: [for (final week in trend.weeks) week.rank],
                start: grey ? colors.textSecondary : colors.accentPrimary,
                end: grey
                    ? colors.textPrimary
                    : gradient
                    ? colors.accentSecondary
                    : colors.accentPrimary,
                axis: colors.divider,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            caption,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({
    required this.ranks,
    required this.start,
    required this.end,
    required this.axis,
  });

  final List<int?> ranks;
  final Color start;
  final Color end;
  final Color axis;

  @override
  void paint(Canvas canvas, Size size) {
    final known = ranks.whereType<int>();
    final best = known.reduce((a, b) => a < b ? a : b);
    final worst = known.reduce((a, b) => a > b ? a : b);
    const inset = 5.0;
    final width = size.width - inset * 2;
    final height = size.height - inset * 2;
    Offset at(int index, int rank) {
      final x = ranks.length == 1
          ? size.width / 2
          : inset + width * index / (ranks.length - 1);
      final t = worst == best ? 0.5 : (rank - best) / (worst - best);
      return Offset(x, inset + height * t);
    }

    canvas.drawLine(
      Offset(inset, size.height - 0.5),
      Offset(size.width - inset, size.height - 0.5),
      Paint()
        ..color = axis
        ..strokeWidth = 1,
    );

    final shader = LinearGradient(
      colors: [start, end],
    ).createShader(Offset.zero & size);
    final line = Paint()
      ..shader = shader
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (var i = 1; i < ranks.length; i++) {
      final a = ranks[i - 1], b = ranks[i];
      if (a != null && b != null) canvas.drawLine(at(i - 1, a), at(i, b), line);
    }
    final dot = Paint()..shader = shader;
    for (var i = 0; i < ranks.length; i++) {
      final rank = ranks[i];
      if (rank == null) continue;
      canvas.drawCircle(at(i, rank), i == ranks.length - 1 ? 4 : 2.5, dot);
    }
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.start != start ||
      old.end != end ||
      old.axis != axis ||
      !_sameRanks(old.ranks, ranks);

  static bool _sameRanks(List<int?> a, List<int?> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

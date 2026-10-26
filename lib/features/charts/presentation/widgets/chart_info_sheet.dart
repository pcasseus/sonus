import 'package:flutter/material.dart';

import '../../../../core/design/sonus_theme.dart';
import '../../domain/models/chart_type.dart';
import 'chart_extended_divider.dart';

/// SN-49: what the chart's positions, badges and numbers mean, opened from
/// the information button beside the chart's name instead of taking room
/// above the chart. Every line describes how Sonus actually ranks.
Future<void> showChartInfoSheet(BuildContext context, ChartType chartType) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ChartInfoSheet(chartType: chartType),
    );

class ChartInfoSheet extends StatelessWidget {
  const ChartInfoSheet({super.key, required this.chartType});

  final ChartType chartType;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = SonusTheme.of(context).colors;
    final name = ChartZoneNames.chart(chartType);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, controller) => ListView(
        key: const ValueKey<String>('charts-info-sheet'),
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children: [
          Semantics(
            header: true,
            child: Text(
              'About the $name',
              style: theme.textTheme.titleLarge?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          for (final (title, body) in _sections(chartType)) ...[
            const SizedBox(height: 18),
            Semantics(
              header: true,
              child: Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              body,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.textSecondary,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static List<(String, String)> _sections(ChartType chartType) => [
    switch (chartType) {
      ChartType.songs => (
        'Positions',
        'Songs at #1–100 are the ${ChartZoneNames.hot100}. Choose Top 200 '
            'to see #101–200 as well: those songs are '
            '${ChartZoneNames.bubblingUnder}, shown at their real positions.',
      ),
      ChartType.albums => (
        'Positions',
        'EPs and Albums are ranked by the streams of every song on them, '
            'whoever performs it, counted once even when a song is on '
            'several editions. Singles chart only through their songs, and '
            'so does a release of one to three songs until you choose its '
            'format in Edit Release. Choose '
            'Top 200 to see #101–200 at their real positions.',
      ),
    },
    (
      'Streams',
      'Only qualified streams count: at least 30 seconds of listening, or '
          'for a song shorter than 30 seconds, half of it (at least 5 '
          'seconds). Skips and short previews never move a chart.',
    ),
    (
      'All time and weekly charts',
      'All time is the permanent chart: every qualified stream since you '
          'started counts, and it changes as you listen. A chart week runs '
          'from Sunday to Saturday; when it ends, its chart is kept as a '
          'final weekly chart you can open with the week controls.',
    ),
    (
      'NEW and RE-ENTRY',
      'NEW: in the standings for the first time this week. RE-ENTRY: back '
          'in the standings after dropping out.',
    ),
    (
      'Movement',
      'Arrows compare a position with where it stood at the start of this '
          'chart week.',
    ),
    (
      'Percentage change',
      'Compares streams so far this week with streams at the same time '
          'last week. "New activity" means streams this week and none at '
          'that time last week.',
    ),
    (
      'Weeks in a zone',
      'Counts completed chart weeks on the all-time chart in the Top 3, 5, '
          '10, 25, 50, 75, 100 and 200. A week at #3 counts for the Top 3 '
          'and every larger zone.',
    ),
  ];
}

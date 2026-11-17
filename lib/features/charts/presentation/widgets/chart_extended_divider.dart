import 'package:flutter/material.dart';

import '../../../../core/design/sonus_theme.dart';
import '../../domain/models/chart_type.dart';

/// The names of the chart's two zones (SN-45). The song chart's permanent
/// Top 200 is the Sonus Hot 100 (#1–100) and Sonus Bubbling Under
/// (#101–200), always at their real positions: #101 is never "#1".
abstract final class ChartZoneNames {
  static const String hot100 = 'Sonus Hot 100';
  static const String bubblingUnder = 'Sonus Bubbling Under';
  static const String releases = 'Sonus Albums & EPs';

  /// The chart's own name: the Hot 100 for songs, Albums & EPs otherwise.
  static String chart(ChartType type) => switch (type) {
    ChartType.songs => hot100,
    ChartType.albums => releases,
  };

  /// The divider before position 101.
  static String lowerZone(ChartType type) => switch (type) {
    ChartType.songs => '$bubblingUnder · #101–200',
    ChartType.albums => 'Positions #101–200',
  };

  /// The badge on positions 101–200.
  static String lowerZoneBadge(ChartType type) => switch (type) {
    ChartType.songs => 'BUBBLING UNDER',
    ChartType.albums => '#101–200',
  };

  /// App Update 1.3 (REF-1.3-06): labels that say which chart a position
  /// belongs to. The career standings (the permanent Top 200, by lifetime
  /// streams) and the weekly charts (one week's streams) share the zone
  /// names, so every label outside a story's own headline names the chart
  /// too. "Career" is the approved name for the permanent chart (SN-50
  /// E-Q15A retired "all time" from the Charts page). Headlines keep the
  /// wording they were written with.
  static const String careerTop200 = 'Career Top 200';

  /// The chart a view or story belongs to.
  static String chartOf(ChartType type, {required bool allTime}) =>
      switch ((type, allTime)) {
        (ChartType.songs, true) => careerTop200,
        (ChartType.songs, false) => 'Weekly Hot 100',
        (ChartType.albums, true) => 'Career Albums & EPs',
        (ChartType.albums, false) => 'Weekly Albums & EPs',
      };

  /// The zone [rank] is in, on the career or weekly chart: "Career Hot
  /// 100", "Weekly Bubbling Under", "Weekly Albums & EPs #101–200".
  static String zoneOf(ChartType type, int rank, {required bool allTime}) {
    final scope = allTime ? 'Career' : 'Weekly';
    final lower = rank > 100;
    return switch (type) {
      ChartType.songs => '$scope ${lower ? 'Bubbling Under' : 'Hot 100'}',
      ChartType.albums => '$scope Albums & EPs${lower ? ' #101–200' : ''}',
    };
  }
}

/// Marks where the Hot 100 ends and Bubbling Under begins (or, for
/// releases, where positions 101–200 begin).
class ChartExtendedDivider extends StatelessWidget {
  const ChartExtendedDivider({super.key, this.chartType = ChartType.songs});

  final ChartType chartType;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final line = Expanded(
      child: Divider(color: tokens.colors.border, thickness: 1, height: 1),
    );

    return Padding(
      key: const ValueKey<String>('charts-extended-divider'),
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          line,
          // Loose, so the label wraps instead of overflowing with large text.
          Flexible(
            flex: 8,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Semantics(
                header: true,
                child: Text(
                  ChartZoneNames.lowerZone(chartType),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: tokens.colors.textSecondary,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ),
          ),
          line,
        ],
      ),
    );
  }
}

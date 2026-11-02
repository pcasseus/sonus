import 'package:flutter/material.dart';

import '../../../../core/design/sonus_count_label.dart';
import '../models/chart_longevity.dart';
import '../models/chart_week_label.dart';

/// One longevity fact as shown and as spoken.
typedef ChartLongevityFact = ({String text, String spoken});

/// The official longevity facts for a card (SN-50 E-Q10A/E-Q10B): weeks at
/// #1, the longest #1 run, the current Top 10 streak, the debut and, when
/// [includeOfficialWeeks], the total official weeks. Facts that are zero
/// are left out; nothing is invented for an entity without a debut.
List<ChartLongevityFact> chartLongevityFacts(
  ChartLongevity? longevity, {
  bool includeOfficialWeeks = true,
}) {
  if (longevity == null) return const [];

  final atOne = longevity.weeksAtNumberOne;
  final run = longevity.longestNumberOneRun;
  final topTen = longevity.topTenStreak;
  final official = longevity.officialWeeks;
  final debutStart = longevity.debutWeekStartUtc;
  final debutRank = longevity.debutRank;

  return [
    if (atOne > 0)
      (
        text: '${sonusCount(atOne, 'week')} at #1',
        spoken: '${sonusCount(atOne, 'week')} at number 1',
      ),
    if (run > 0)
      (
        text: 'Longest #1 run: ${sonusCount(run, 'week')}',
        spoken: 'longest run at number 1, ${sonusCount(run, 'week')} in a row',
      ),
    if (topTen > 0)
      (
        text: 'Top 10 streak: ${sonusCount(topTen, 'week')}',
        spoken: 'in the Top 10 for ${sonusCount(topTen, 'week')} in a row',
      ),
    if (debutStart != null && debutRank != null)
      (
        text: 'Debut #$debutRank · ${chartShortDate(debutStart)}',
        spoken:
            'debuted at number $debutRank in the week of '
            '${chartShortDate(debutStart)}',
      ),
    if (includeOfficialWeeks && official > 0)
      (
        text: sonusCount(official, 'official week'),
        spoken: '${sonusCount(official, 'official week')} on the weekly chart',
      ),
  ];
}

/// The facts as a wrapping row: with large text they flow onto more lines
/// instead of being cut.
class ChartLongevityFacts extends StatelessWidget {
  const ChartLongevityFacts({
    super.key,
    required this.facts,
    required this.style,
  });

  final List<ChartLongevityFact> facts;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 4,
      children: [for (final fact in facts) Text(fact.text, style: style)],
    );
  }
}

import 'package:flutter/material.dart';

import '../../../../core/design/sonus_theme.dart';
import '../../application/models/pulse/pulse_period.dart';
import '../../application/models/pulse/pulse_period_data.dart';
import '../../application/models/year_in_sonus/year_in_sonus_recap.dart';
import 'pulse_colors.dart';
import 'pulse_format.dart';

/// Per-month totals of a year, from the year's own day buckets, so they add
/// up to the year exactly.
List<PulseMetrics> pulseMonthTotals(PulsePeriodData year) {
  final ms = List<int>.filled(12, 0);
  final streams = List<int>.filled(12, 0);
  final plays = List<int>.filled(12, 0);
  for (final day in year.days) {
    final m = day.localDate.month - 1;
    ms[m] += day.metrics.listened.inMilliseconds;
    streams[m] += day.metrics.streams;
    plays[m] += day.metrics.allPlays;
  }
  return [
    for (var m = 0; m < 12; m++)
      PulseMetrics(
        listened: Duration(milliseconds: ms[m]),
        streams: streams[m],
        allPlays: plays[m],
      ),
  ];
}

/// The longest run of consecutive days with a qualified stream.
int pulseLongestStreak(PulsePeriodData data) {
  var best = 0;
  var run = 0;
  for (final day in data.days) {
    run = day.metrics.streams > 0 ? run + 1 : 0;
    if (run > best) best = run;
  }
  return best;
}

/// Year view: twelve month bars; tapping one opens that month.
class PulseMonthsCard extends StatelessWidget {
  const PulseMonthsCard({
    super.key,
    required this.data,
    required this.measure,
    required this.palette,
    required this.nowLocal,
    this.onOpenMonth,
  });

  final PulsePeriodData data;
  final PulseMeasure measure;
  final PulsePalette palette;
  final DateTime nowLocal;
  final ValueChanged<PulsePeriod>? onOpenMonth;

  @override
  Widget build(BuildContext context) {
    final theme = SonusTheme.of(context);
    final colors = theme.colors;
    final totals = pulseMonthTotals(data);
    final values = [for (final t in totals) t.valueOf(measure)];
    final top = values.fold<num>(0, (a, b) => b > a ? b : a);
    final ramp = palette.rampFor(measure);
    final first = data.firstHistoryAt?.toLocal();

    return _Card(
      title: 'Months',
      child: SizedBox(
        height: 132,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var m = 0; m < 12; m++)
              Expanded(
                child: _MonthBar(
                  label: PulseFormat.shortMonth(m + 1).substring(0, 1),
                  semantic: _semantic(m, totals[m], first),
                  share: top <= 0 ? 0 : (values[m] / top).toDouble(),
                  colour: ramp.at(top <= 0 ? 0 : 0.3 + 0.7 * values[m] / top),
                  base: colors.divider,
                  muted: colors.textSecondary,
                  onTap: _isFuture(m) || onOpenMonth == null
                      ? null
                      : () => onOpenMonth!(
                          PulsePeriod.month(data.period.year, m + 1),
                        ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  bool _isFuture(int monthIndex) =>
      DateTime(data.period.year, monthIndex + 1).isAfter(nowLocal);

  String _semantic(int m, PulseMetrics t, DateTime? first) {
    final name = PulseFormat.months[m];
    if (_isFuture(m)) return '$name: not yet';
    final monthEnd = DateTime(data.period.year, m + 2);
    if (first == null || !monthEnd.isAfter(first)) {
      return '$name: before your history starts';
    }
    return '$name: ${PulseFormat.grouped(t.listened.inMinutes)} minutes, '
        '${PulseFormat.grouped(t.streams)} '
        '${t.streams == 1 ? 'stream' : 'streams'}';
  }
}

class _MonthBar extends StatelessWidget {
  const _MonthBar({
    required this.label,
    required this.semantic,
    required this.share,
    required this.colour,
    required this.base,
    required this.muted,
    required this.onTap,
  });

  final String label;
  final String semantic;
  final double share;
  final Color colour;
  final Color base;
  final Color muted;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onTap != null,
      label: semantic,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: FractionallySizedBox(
                    heightFactor: share <= 0 ? null : share,
                    child: share <= 0
                        ? Container(height: 2, color: base)
                        : DecoratedBox(
                            decoration: BoxDecoration(
                              color: colour,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(3),
                              ),
                            ),
                            child: const SizedBox.expand(),
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(label, style: TextStyle(color: muted, fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Year view milestones: from the year's own data, plus the existing Year
/// in Sonus discoveries (first-ever plays) when they have loaded.
class PulseMilestonesCard extends StatelessWidget {
  const PulseMilestonesCard({
    super.key,
    required this.data,
    required this.palette,
    this.recap,
  });

  final PulsePeriodData data;
  final PulsePalette palette;
  final YearInSonusRecap? recap;

  static List<(String, String)> rows(
    PulsePeriodData data,
    YearInSonusRecap? recap,
  ) {
    final totals = pulseMonthTotals(data);
    var best = -1;
    for (var m = 0; m < 12; m++) {
      if (totals[m].streams <= 0) continue;
      if (best < 0 || totals[m].streams > totals[best].streams) best = m;
    }
    final streak = pulseLongestStreak(data);
    return [
      (
        'Most active month',
        best < 0
            ? '—'
            : '${PulseFormat.months[best]} · '
                  '${PulseFormat.grouped(totals[best].streams)} '
                  '${totals[best].streams == 1 ? 'stream' : 'streams'}',
      ),
      (
        'Longest streak',
        streak == 0 ? '—' : '$streak ${streak == 1 ? 'day' : 'days'}',
      ),
      if (recap != null && recap.year == data.period.year) ...[
        ('New artists', PulseFormat.grouped(recap.newArtistIds.length)),
        ('New releases', PulseFormat.grouped(recap.newAlbumIds.length)),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;
    return _Card(
      title: 'Milestones',
      child: Column(
        children: [
          for (final (label, value) in rows(data, recap))
            Semantics(
              label: '$label: $value',
              excludeSemantics: true,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(color: colors.textSecondary),
                      ),
                    ),
                    Flexible(
                      child: Text(
                        value,
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = SonusTheme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: theme.colors.surface,
        borderRadius: BorderRadius.circular(theme.metrics.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(title, style: theme.text.sectionHeading),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/design/sonus_theme.dart';
import '../../../../core/design/sonus_text_scale.dart';
import '../../application/models/pulse/pulse_delta.dart';
import '../../application/models/pulse/pulse_period.dart';
import '../../application/models/pulse/pulse_period_data.dart';
import '../../data/pulse_preferences_store.dart';
import 'pulse_colors.dart';
import 'pulse_format.dart';

/// The six overview tiles (spec §4). Minutes, Streams and All plays carry
/// their metric colour; the other three stay neutral.
class PulseOverviewGrid extends StatelessWidget {
  const PulseOverviewGrid({
    super.key,
    required this.overview,
    required this.deltas,
    required this.palette,
    this.onInfo,
  });

  final PulseOverview overview;
  final PulseOverviewDeltas deltas;
  final PulsePalette palette;

  /// Opens the explanation of the three counts.
  final VoidCallback? onInfo;

  @override
  Widget build(BuildContext context) {
    final tiles = [
      _TileSpec(
        'Minutes',
        PulseFormat.grouped(overview.listened.inMinutes),
        'minutes',
        deltas.minutes,
        palette.minutes,
      ),
      _TileSpec(
        'Streams',
        PulseFormat.grouped(overview.streams),
        'streams',
        deltas.streams,
        palette.streams,
      ),
      _TileSpec(
        'All plays',
        PulseFormat.grouped(overview.allPlays),
        'plays',
        deltas.allPlays,
        palette.allPlays,
      ),
      _TileSpec(
        'Active days',
        PulseFormat.grouped(overview.activeDays),
        'days',
        deltas.activeDays,
        null,
      ),
      _TileSpec(
        'Artists',
        PulseFormat.grouped(overview.artists),
        'artists',
        deltas.artists,
        null,
      ),
      _TileSpec(
        'Tracks',
        PulseFormat.grouped(overview.tracks),
        'tracks',
        deltas.tracks,
        null,
      ),
    ];
    final theme = SonusTheme.of(context);
    final textScale = MediaQuery.textScalerOf(context).scale(1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  'Listening overview',
                  style: theme.text.sectionHeading,
                ),
              ),
            ),
            if (onInfo != null)
              IconButton(
                key: const ValueKey('pulse-overview-info'),
                tooltip: 'About these numbers',
                icon: const Icon(Icons.info_outline),
                onPressed: onInfo,
              ),
          ],
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            // Two columns from exactly 1.3 too, unlike the other rows
            // (`>`); kept as approved until a decision (register R21).
            final columns =
                constraints.maxWidth < 340 || textScale >= sonusLargeTextScale
                ? 2
                : 3;
            final rows = <Widget>[];
            for (var i = 0; i < tiles.length; i += columns) {
              final chunk = tiles.sublist(
                i,
                math.min(i + columns, tiles.length),
              );
              rows.add(
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var j = 0; j < columns; j++) ...[
                        if (j > 0) const SizedBox(width: 10),
                        Expanded(
                          child: j < chunk.length
                              ? _PulseStatTile(spec: chunk[j], palette: palette)
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }
            return Column(
              key: ValueKey('pulse-overview-$columns-columns'),
              children: [
                for (var r = 0; r < rows.length; r++) ...[
                  if (r > 0) const SizedBox(height: 10),
                  rows[r],
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _TileSpec {
  const _TileSpec(this.label, this.value, this.unit, this.delta, this.ramp);

  final String label;
  final String value;
  final String unit;
  final PulseDelta delta;

  /// The metric family; null for the neutral tiles.
  final PulseRamp? ramp;
}

class _PulseStatTile extends StatelessWidget {
  const _PulseStatTile({required this.spec, required this.palette});

  final _TileSpec spec;
  final PulsePalette palette;

  @override
  Widget build(BuildContext context) {
    final theme = SonusTheme.of(context);
    final colors = theme.colors;
    final ramp = spec.ramp;
    final tint = ramp != null && palette.haloStrength > 0;
    final radius = BorderRadius.circular(theme.metrics.cardRadius);
    final delta = spec.delta;
    final deltaColor = switch (delta.kind) {
      PulseDeltaKind.up => palette.chartUp,
      PulseDeltaKind.down => palette.chartDown,
      PulseDeltaKind.newValue => palette.allPlays.tip,
      _ => palette.textSecondary,
    };
    final spokenDelta = delta.spokenLabel(spec.unit);

    return Semantics(
      container: true,
      label:
          '${spec.label}: ${spec.value}'
          '${spokenDelta.isEmpty ? '' : '. $spokenDelta'}',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          color: colors.raisedSurface,
          gradient: tint
              ? LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color.alphaBlend(
                      ramp.base.withValues(
                        alpha: 0.16 * palette.haloStrength / 0.2,
                      ),
                      colors.raisedSurface,
                    ),
                    colors.raisedSurface,
                  ],
                )
              : null,
          border: palette.highContrast
              ? Border.all(color: colors.border)
              : null,
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 3,
                child: ramp == null
                    ? const SizedBox.shrink()
                    : CustomPaint(painter: _StripePainter(ramp)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      spec.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: AnimatedSwitcher(
                        duration: theme.motion.short,
                        child: Text(
                          spec.value,
                          key: ValueKey(spec.value),
                          style: theme.text.featuredStat.copyWith(
                            fontSize: 26,
                            color: ramp?.at(0.85) ?? colors.textPrimary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ),
                    if (delta.kind != PulseDeltaKind.none) ...[
                      const SizedBox(height: 4),
                      Text(
                        delta.label,
                        key: ValueKey('pulse-delta-${spec.label}'),
                        style: TextStyle(
                          color: deltaColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                      if (delta.kind == PulseDeltaKind.up ||
                          delta.kind == PulseDeltaKind.down)
                        Text(
                          '${delta.signedDifference} ${spec.unit}',
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The metric stripe: the family's gradient, or solid steps; Monochrome
/// adds its pattern so metrics differ by more than tone.
class _StripePainter extends CustomPainter {
  _StripePainter(this.ramp);

  final PulseRamp ramp;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint();
    if (ramp.fill == PulseFill.gradient) {
      paint.shader = LinearGradient(
        colors: [ramp.base, ramp.tip],
      ).createShader(rect);
    } else {
      paint.color = ramp.tip;
    }
    switch (ramp.pattern) {
      case PulseBarPattern.solid:
        canvas.drawRect(rect, paint);
      case PulseBarPattern.stripe:
        for (var x = 0.0; x < size.width; x += 6) {
          canvas.drawRect(Rect.fromLTWH(x, 0, 4, size.height), paint);
        }
      case PulseBarPattern.dotted:
        for (var x = 1.5; x < size.width; x += 5) {
          canvas.drawCircle(Offset(x, size.height / 2), 1.5, paint);
        }
    }
  }

  @override
  bool shouldRepaint(_StripePainter old) => old.ramp != ramp;
}

/// The comparison chips (spec §5). A comparison that starts before
/// recorded history reads "· partial history", is drawn dashed, and when
/// chosen explains why its numbers are not compared.
class PulseComparisonChips extends StatelessWidget {
  const PulseComparisonChips({
    super.key,
    required this.period,
    required this.choice,
    required this.previous,
    required this.samePeriodLastYear,
    required this.firstHistoryAt,
    required this.palette,
    required this.onChanged,
  });

  final PulsePeriod period;
  final PulseComparisonChoice choice;
  final PulseComparison previous;
  final PulseComparison samePeriodLastYear;
  final DateTime? firstHistoryAt;
  final PulsePalette palette;
  final ValueChanged<PulseComparisonChoice> onChanged;

  @override
  Widget build(BuildContext context) {
    final isYear = period.kind == PulsePeriodKind.year;
    final options = <(PulseComparisonChoice, String, PulseComparison?)>[
      (
        PulseComparisonChoice.previous,
        isYear ? 'vs ${period.previous.year}' : 'vs previous month',
        previous,
      ),
      if (!isYear)
        (
          PulseComparisonChoice.samePeriodLastYear,
          'vs ${PulseFormat.periodTitle(samePeriodLastYear.period)}',
          samePeriodLastYear,
        ),
      (PulseComparisonChoice.none, 'No comparison', null),
    ];
    final selected = options.where((o) => o.$1 == choice).firstOrNull;
    final explanation = selected?.$3 != null && !selected!.$3!.isAvailable
        ? explain(selected.$3!.period, firstHistoryAt)
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (value, label, comparison) in options)
              _ComparisonChip(
                key: ValueKey('pulse-comparison-${value.name}'),
                label: comparison != null && !comparison.isAvailable
                    ? '$label · partial history'
                    : label,
                selected: value == choice,
                partial: comparison != null && !comparison.isAvailable,
                palette: palette,
                onTap: () => onChanged(value),
              ),
          ],
        ),
        if (explanation != null) ...[
          const SizedBox(height: 8),
          Text(
            explanation,
            key: const ValueKey('pulse-comparison-explanation'),
            style: TextStyle(color: palette.textSecondary),
          ),
        ],
      ],
    );
  }

  /// "Your history starts 12 Oct 2025, so October 2025 is incomplete."
  static String explain(PulsePeriod comparison, DateTime? firstHistoryAt) {
    final title = PulseFormat.periodTitle(comparison);
    if (firstHistoryAt == null) {
      return 'No listening was recorded before, so $title can’t be compared.';
    }
    final first = firstHistoryAt.toLocal();
    return 'Your history starts ${first.day} '
        '${PulseFormat.shortMonth(first.month)} ${first.year}, '
        'so $title is incomplete.';
  }
}

class _ComparisonChip extends StatelessWidget {
  const _ComparisonChip({
    super.key,
    required this.label,
    required this.selected,
    required this.partial,
    required this.palette,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool partial;
  final PulsePalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = SonusTheme.of(context);
    final colors = theme.colors;
    final accent = palette.minutes.at(0.7);
    final fill = selected
        ? Color.alphaBlend(accent.withValues(alpha: 0.22), colors.raisedSurface)
        : colors.raisedSurface;
    final border = selected ? accent : colors.border;

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: onTap,
            // Foreground, so the chip's fill never hides the (dashed) border.
            child: CustomPaint(
              foregroundPainter: _ChipBorderPainter(
                color: border,
                dashed: partial,
                width: selected || palette.highContrast ? 1.6 : 1,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: fill,
                  borderRadius: BorderRadius.circular(22),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: selected ? colors.textPrimary : colors.textSecondary,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChipBorderPainter extends CustomPainter {
  _ChipBorderPainter({
    required this.color,
    required this.dashed,
    required this.width,
  });

  final Color color;
  final bool dashed;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(width / 2),
      Radius.circular(size.height / 2),
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..color = color;
    if (!dashed) {
      canvas.drawRRect(rrect, paint);
      return;
    }
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 9) {
        canvas.drawPath(
          metric.extractPath(d, math.min(d + 5, metric.length)),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_ChipBorderPainter old) =>
      old.color != color || old.dashed != dashed || old.width != width;
}

/// "More about {period}": the existing Insights statistics, kept with their
/// existing meaning (spec §1, approved: preserve completion and skip rates,
/// active days, peak day).
class PulseMoreStats extends StatefulWidget {
  const PulseMoreStats({super.key, required this.data, required this.palette});

  final PulsePeriodData data;
  final PulsePalette palette;

  /// The rows, in order. Rates follow the existing definitions: completed or
  /// skipped plays as a share of plays that ended.
  static List<(String, String)> rows(PulsePeriodData data) {
    final behavior = data.behavior;
    final days = data.days;
    final overview = data.overview;
    PulseDay? busiest;
    for (final day in days) {
      if (day.metrics.streams <= 0) continue;
      if (busiest == null || day.metrics.streams > busiest.metrics.streams) {
        busiest = day;
      }
    }
    PulseHour? hour;
    for (final h in data.hours) {
      if (h.listened <= Duration.zero) continue;
      if (hour == null || h.listened > hour.listened) hour = h;
    }
    String rate(double value) => '${(value * 100).toStringAsFixed(1)}%';
    final ended = behavior?.endedSessionCount ?? 0;
    return [
      ('Active days', '${overview.activeDays} / ${days.length}'),
      (
        'Average streams / active day',
        overview.activeDays == 0
            ? '0'
            : (overview.streams / overview.activeDays).toStringAsFixed(1),
      ),
      (
        'Busiest day',
        busiest == null
            ? '—'
            : '${PulseFormat.shortDay(busiest.localDate)} · '
                  '${busiest.metrics.streams} '
                  '${busiest.metrics.streams == 1 ? 'stream' : 'streams'}',
      ),
      (
        'Longest listening day',
        PulseFormat.longestHint(
              data,
              PulseMeasure.minutes,
            )?.replaceFirst('The longest spoke is ', '') ??
            '—',
      ),
      (
        'Most active hour',
        hour == null
            ? '—'
            : '${_hour(hour.hour)} · ${PulseFormat.duration(hour.listened)}',
      ),
      ('Completion rate', ended == 0 ? '—' : rate(behavior!.completionRate)),
      ('Skip rate', ended == 0 ? '—' : rate(behavior!.skipRate)),
    ];
  }

  static String _hour(int hour) {
    final h = hour % 12 == 0 ? 12 : hour % 12;
    return '$h ${hour < 12 ? 'AM' : 'PM'}';
  }

  @override
  State<PulseMoreStats> createState() => _PulseMoreStatsState();
}

class _PulseMoreStatsState extends State<PulseMoreStats> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final theme = SonusTheme.of(context);
    final colors = theme.colors;
    final title = 'More about ${PulseFormat.periodTitle(widget.data.period)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          expanded: _open,
          label: title,
          excludeSemantics: true,
          child: InkWell(
            key: const ValueKey('pulse-more-toggle'),
            onTap: () => setState(() => _open = !_open),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Row(
                children: [
                  Expanded(
                    child: Text(title, style: theme.text.sectionHeading),
                  ),
                  AnimatedRotation(
                    turns: _open ? 0.5 : 0,
                    duration: theme.motion.medium,
                    child: Icon(Icons.expand_more, color: colors.textSecondary),
                  ),
                ],
              ),
            ),
          ),
        ),
        // AnimatedSize asserts with a zero duration, so reduced motion
        // swaps the rows in directly.
        if (theme.motion.reduced)
          !_open
              ? const SizedBox(width: double.infinity)
              : Column(
                  key: const ValueKey('pulse-more-rows'),
                  children: [
                    for (final (label, value) in PulseMoreStats.rows(
                      widget.data,
                    ))
                      Semantics(
                        label: '$label: $value',
                        excludeSemantics: true,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  label,
                                  style: TextStyle(color: colors.textSecondary),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Flexible(
                                child: Text(
                                  value,
                                  textAlign: TextAlign.end,
                                  style: TextStyle(
                                    color: colors.textPrimary,
                                    fontWeight: FontWeight.w600,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                )
        else
          AnimatedSize(
            duration: theme.motion.medium,
            curve: theme.motion.curve,
            alignment: Alignment.topCenter,
            child: !_open
                ? const SizedBox(width: double.infinity)
                : Column(
                    key: const ValueKey('pulse-more-rows'),
                    children: [
                      for (final (label, value) in PulseMoreStats.rows(
                        widget.data,
                      ))
                        Semantics(
                          label: '$label: $value',
                          excludeSemantics: true,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    label,
                                    style: TextStyle(
                                      color: colors.textSecondary,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Flexible(
                                  child: Text(
                                    value,
                                    textAlign: TextAlign.end,
                                    style: TextStyle(
                                      color: colors.textPrimary,
                                      fontWeight: FontWeight.w600,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
      ],
    );
  }
}

/// The info sheet's text (spec §4). New strings are subject to the wording
/// review before release.
abstract final class PulseOverviewInfo {
  static const paragraphs = [
    'Minutes is all the time music was audible, from every play of any '
        'length.',
    'Streams are qualified plays: a song counts once it plays for 30 '
        'seconds, or half of a shorter song (at least 5 seconds). These are '
        'the plays your charts use.',
    'All plays counts every play that was audible at all, including ones '
        'shorter than a stream.',
    'Days follow the time zone your phone is in now, so plays made while '
        'travelling can land on a neighbouring day.',
    'Blocked and removed songs are included and labelled.',
  ];
}

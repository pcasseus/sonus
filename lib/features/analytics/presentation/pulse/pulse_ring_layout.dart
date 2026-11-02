import 'dart:math' as math;
import 'dart:ui';

import '../../application/models/pulse/pulse_period.dart';
import '../../application/models/pulse/pulse_period_data.dart';

/// Where each day's spoke sits on the ring (spec §3.1). Angles are radians,
/// measured clockwise from 12 o'clock.
class PulseRingGeometry {
  PulseRingGeometry._({
    required this.size,
    required this.center,
    required this.innerRadius,
    required this.outerRadius,
    required this.angles,
    required this.spokeWidth,
  });

  /// Gap between month arcs in the year view, in degrees.
  static const double yearMonthGapDegrees = 2.4;

  /// The inner ring as a share of the outer radius.
  static const double innerRatio = 0.4;

  factory PulseRingGeometry.of(PulsePeriod period, Size size) {
    final side = math.min(size.width, size.height);
    final outer = side / 2 - 6;
    final inner = outer * innerRatio;
    final days = period.days;
    final List<double> angles;
    if (period.kind == PulsePeriodKind.month) {
      final step = 2 * math.pi / days.length;
      angles = [for (var i = 0; i < days.length; i++) i * step];
    } else {
      const gap = yearMonthGapDegrees * math.pi / 180;
      final step = (2 * math.pi - 12 * gap) / days.length;
      angles = [];
      var dayIndex = 0;
      for (var month = 1; month <= 12; month++) {
        final inMonth = days.where((d) => d.month == month).length;
        final start = dayIndex * step + (month - 1) * gap + gap / 2;
        for (var j = 0; j < inMonth; j++) {
          angles.add(start + (j + 0.5) * step);
        }
        dayIndex += inMonth;
      }
    }
    final circumference = 2 * math.pi * inner;
    final width = period.kind == PulsePeriodKind.month
        ? (circumference / days.length * 0.55).clamp(2.0, 7.0)
        : 1.2;
    return PulseRingGeometry._(
      size: size,
      center: Offset(size.width / 2, size.height / 2),
      innerRadius: inner,
      outerRadius: outer,
      angles: List.unmodifiable(angles),
      spokeWidth: width.toDouble(),
    );
  }

  final Size size;
  final Offset center;
  final double innerRadius;
  final double outerRadius;
  final List<double> angles;
  final double spokeWidth;

  double get maxLength => outerRadius - innerRadius;

  /// The point at [radius] along the spoke at [angle].
  Offset point(double angle, double radius) => Offset(
    center.dx + radius * math.sin(angle),
    center.dy - radius * math.cos(angle),
  );

  /// The day under [position], or null for the centre or outside the ring
  /// (both clear the selection, spec §3.2).
  int? hitTest(Offset position) {
    final delta = position - center;
    final distance = delta.distance;
    if (distance < innerRadius * 0.75 || distance > outerRadius + 20) {
      return null;
    }
    var angle = math.atan2(delta.dx, -delta.dy);
    if (angle < 0) angle += 2 * math.pi;
    var best = 0;
    var bestGap = double.infinity;
    for (var i = 0; i < angles.length; i++) {
      var gap = (angles[i] - angle).abs();
      if (gap > math.pi) gap = 2 * math.pi - gap;
      if (gap < bestGap) {
        bestGap = gap;
        best = i;
      }
    }
    return best;
  }
}

/// One day's spoke, as data.
class PulseSpoke {
  const PulseSpoke({
    required this.index,
    required this.state,
    required this.value,
    required this.fraction,
    required this.tipPosition,
    required this.itemFraction,
    required this.ghostFraction,
  });

  final int index;
  final PulseDayState state;

  /// The day's value in the measure (minutes as a fraction, or streams).
  final num value;

  /// Spoke length as a share of the maximum length.
  final double fraction;

  /// Where the tip sits on the measure's ramp (0 quietest, 1 busiest).
  final double tipPosition;

  /// The selected item's part, as a share of the maximum length; never more
  /// than [fraction]. Zero without an item or on days without it.
  final double itemFraction;

  /// The comparison day's length, or null when there is no ghost for it.
  final double? ghostFraction;
}

/// Turns a period's days into spokes for one measure.
class PulseRingLayout {
  PulseRingLayout._(this.spokes, this.averageFraction, this.maxValue);

  /// [comparisonDays] are aligned by day of month (or day of year) and share
  /// the scale, so a ghost may be longer than any current spoke. [itemDays]
  /// is the selected item's series from [PulsePeriodData.daySeriesFor].
  factory PulseRingLayout.build({
    required PulsePeriodData data,
    required PulseMeasure measure,
    List<PulseMetrics>? comparisonDays,
    List<PulseMetrics>? itemDays,
  }) {
    final days = data.days;
    num currentMax = 0;
    num total = 0;
    var recorded = 0;
    for (final day in days) {
      if (day.state != PulseDayState.recorded) continue;
      final v = day.metrics.valueOf(measure);
      currentMax = math.max(currentMax, v);
      total += v;
      recorded++;
    }
    var scaleMax = currentMax;
    if (comparisonDays != null) {
      for (final day in comparisonDays) {
        scaleMax = math.max(scaleMax, day.valueOf(measure));
      }
    }
    final spokes = <PulseSpoke>[];
    for (var i = 0; i < days.length; i++) {
      final day = days[i];
      final v = day.state == PulseDayState.recorded
          ? day.metrics.valueOf(measure)
          : 0;
      final fraction = scaleMax > 0 ? v / scaleMax : 0.0;
      final itemValue = itemDays == null || i >= itemDays.length
          ? 0
          : itemDays[i].valueOf(measure);
      final ghost = comparisonDays == null || i >= comparisonDays.length
          ? null
          : (scaleMax > 0
                ? comparisonDays[i].valueOf(measure) / scaleMax
                : 0.0);
      spokes.add(
        PulseSpoke(
          index: i,
          state: day.state,
          value: v,
          fraction: fraction.toDouble(),
          tipPosition: currentMax > 0 ? (v / currentMax).toDouble() : 0,
          itemFraction: scaleMax > 0
              ? math.min(itemValue / scaleMax, fraction).toDouble()
              : 0,
          ghostFraction: ghost?.toDouble(),
        ),
      );
    }
    final average = recorded == 0 || scaleMax == 0
        ? 0.0
        : (total / recorded) / scaleMax;
    return PulseRingLayout._(
      List.unmodifiable(spokes),
      average.toDouble(),
      scaleMax,
    );
  }

  final List<PulseSpoke> spokes;

  /// The dotted average ring: the mean per recorded day, as a share.
  final double averageFraction;

  /// The value the outer radius stands for.
  final num maxValue;
}

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../core/design/sonus_greyscale_theme.dart';
import '../../../../core/design/sonus_theme.dart';
import '../../../charts/presentation/models/chart_week_label.dart';
import '../../application/song_stats_models.dart';
import '../../application/song_stats_service.dart';

/// One point on the rank history: a finalized week, or the live week.
class SongRankPoint {
  const SongRankPoint({
    required this.week,
    required this.rank,
    required this.weekStartUtc,
    required this.live,
  });

  /// Chart week number; gaps are weeks off the chart.
  final int week;
  final int rank;
  final DateTime weekStartUtc;
  final bool live;
}

/// The song's position week by week: #1 at the top, a line at #100 between
/// the Hot 100 and Bubbling Under, breaks for weeks off the chart, and the
/// live week as a hollow, dashed point (provisional). Static: no motion.
class SongRankHistoryChart extends StatelessWidget {
  const SongRankHistoryChart({super.key, required this.history});

  final SongChartHistory history;

  static List<SongRankPoint> pointsOf(SongChartHistory history) => [
    for (final week in history.weeks)
      SongRankPoint(
        week: SongStatsService.weekIndex(week.weekStartUtc),
        rank: week.rank,
        weekStartUtc: week.weekStartUtc,
        live: false,
      ),
    if (history.live case final live?)
      SongRankPoint(
        week: SongStatsService.weekIndex(live.weekStartUtc),
        rank: live.rank,
        weekStartUtc: live.weekStartUtc,
        live: true,
      ),
  ];

  @override
  Widget build(BuildContext context) {
    final points = pointsOf(history);
    if (points.isEmpty) return const SizedBox.shrink();
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final grey = sonusThemeIsGreyscale(colors.accentPrimary);
    final scaler = MediaQuery.textScalerOf(context);
    final labelStyle = Theme.of(
      context,
    ).textTheme.labelSmall!.copyWith(color: colors.textSecondary);

    final finalized = points.where((p) => !p.live).toList();
    final peak = history.peakRank;
    final spoken = StringBuffer('Chart position history. ');
    if (finalized.isNotEmpty) {
      spoken.write(
        '${finalized.length} finalized '
        '${finalized.length == 1 ? 'week' : 'weeks'}, '
        'from number ${finalized.first.rank} to number ${finalized.last.rank}',
      );
      if (peak != null) spoken.write(', peak number $peak');
      spoken.write('. ');
    }
    if (history.live case final live?) {
      spoken.write('This week, live: number ${live.rank}, provisional.');
    }

    return Semantics(
      container: true,
      label: spoken.toString().trim(),
      excludeSemantics: true,
      child: SizedBox(
        key: const ValueKey<String>('song-stats-rank-chart'),
        height: 150 + scaler.scale(28),
        child: CustomPaint(
          size: Size.infinite,
          painter: _RankPainter(
            points: points,
            peak: peak,
            line: grey ? colors.textPrimary : colors.accentPrimary,
            lineEnd: grey || !tokens.decoration.allowGradients
                ? (grey ? colors.textPrimary : colors.accentPrimary)
                : colors.accentSecondary,
            peakColor: grey ? colors.textPrimary : colors.accentTertiary,
            grid: colors.divider,
            zone: colors.textSecondary,
            surface: colors.surface,
            labelStyle: labelStyle,
            textScaler: scaler,
          ),
        ),
      ),
    );
  }
}

class _RankPainter extends CustomPainter {
  _RankPainter({
    required this.points,
    required this.peak,
    required this.line,
    required this.lineEnd,
    required this.peakColor,
    required this.grid,
    required this.zone,
    required this.surface,
    required this.labelStyle,
    required this.textScaler,
  });

  final List<SongRankPoint> points;
  final int? peak;
  final Color line;
  final Color lineEnd;
  final Color peakColor;
  final Color grid;
  final Color zone;
  final Color surface;
  final TextStyle labelStyle;
  final TextScaler textScaler;

  TextPainter _text(String value) => TextPainter(
    text: TextSpan(text: value, style: labelStyle),
    textDirection: TextDirection.ltr,
    textScaler: textScaler,
    maxLines: 1,
  )..layout();

  @override
  void paint(Canvas canvas, Size size) {
    final worst = points.map((p) => p.rank).reduce(math.max);
    final bottomRank = worst > 100 ? 200 : 100;
    final ticks = bottomRank == 200 ? [1, 100, 200] : [1, 50, 100];

    final tickLabels = [for (final t in ticks) _text('#$t')];
    final left =
        tickLabels.map((t) => t.width).reduce(math.max) + 8; // axis gutter
    final bottomLabel = _text('Ag');
    final top = 8.0;
    final bottom = size.height - bottomLabel.height - 8;
    final right = size.width - 10;
    final plotLeft = left + 8;

    double y(int rank) => top + (rank - 1) / (bottomRank - 1) * (bottom - top);

    final first = points.map((p) => p.week).reduce(math.min);
    final last = points.map((p) => p.week).reduce(math.max);
    double x(int week) => first == last
        ? (plotLeft + right) / 2
        : plotLeft + (week - first) / (last - first) * (right - plotLeft);

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final (i, t) in ticks.indexed) {
      final ty = y(t);
      canvas.drawLine(Offset(plotLeft, ty), Offset(right, ty), gridPaint);
      final label = tickLabels[i];
      label.paint(canvas, Offset(left - label.width, ty - label.height / 2));
    }

    // The Hot 100 / Bubbling Under boundary.
    if (bottomRank == 200) {
      final zonePaint = Paint()
        ..color = zone.withValues(alpha: 0.6)
        ..strokeWidth = 1.2;
      _dashed(
        canvas,
        Offset(plotLeft, y(100)),
        Offset(right, y(100)),
        zonePaint,
      );
      final bu = _text('Bubbling Under');
      bu.paint(canvas, Offset(right - bu.width, y(100) + 3));
    }

    final sorted = [...points]..sort((a, b) => a.week.compareTo(b.week));
    final shader = ui.Gradient.linear(Offset(plotLeft, 0), Offset(right, 0), [
      line,
      lineEnd,
    ]);
    final stroke = Paint()
      ..shader = shader
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (var i = 1; i < sorted.length; i++) {
      final a = sorted[i - 1];
      final b = sorted[i];
      if (b.week - a.week != 1) continue; // off the chart in between
      final from = Offset(x(a.week), y(a.rank));
      final to = Offset(x(b.week), y(b.rank));
      if (b.live || a.live) {
        _dashed(canvas, from, to, stroke);
      } else {
        canvas.drawLine(from, to, stroke);
      }
    }

    for (final p in sorted) {
      final c = Offset(x(p.week), y(p.rank));
      final isPeak = !p.live && p.rank == peak;
      if (p.live) {
        canvas.drawCircle(c, 5, Paint()..color = surface);
        canvas.drawCircle(
          c,
          5,
          Paint()
            ..color = lineEnd
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      } else {
        canvas.drawCircle(c, isPeak ? 6 : 4, Paint()..color = surface);
        canvas.drawCircle(
          c,
          isPeak ? 5 : 3.5,
          Paint()..color = isPeak ? peakColor : line,
        );
      }
    }

    // First and last week, as dates.
    final firstLabel = _text(chartShortDate(sorted.first.weekStartUtc));
    firstLabel.paint(canvas, Offset(plotLeft, bottom + 6));
    if (sorted.last.week != sorted.first.week) {
      final lastText = sorted.last.live
          ? 'This week'
          : chartShortDate(sorted.last.weekStartUtc);
      final lastLabel = _text(lastText);
      if (lastLabel.width + firstLabel.width + 12 < right - plotLeft) {
        lastLabel.paint(canvas, Offset(right - lastLabel.width, bottom + 6));
      }
    }
  }

  static void _dashed(Canvas canvas, Offset a, Offset b, Paint paint) {
    final length = (b - a).distance;
    if (length == 0) return;
    final direction = (b - a) / length;
    const dash = 5.0;
    const gap = 4.0;
    var travelled = 0.0;
    while (travelled < length) {
      final end = math.min(travelled + dash, length);
      canvas.drawLine(a + direction * travelled, a + direction * end, paint);
      travelled += dash + gap;
    }
  }

  @override
  bool shouldRepaint(_RankPainter old) =>
      old.points != points ||
      old.line != line ||
      old.lineEnd != lineEnd ||
      old.labelStyle != labelStyle ||
      old.textScaler != textScaler;
}

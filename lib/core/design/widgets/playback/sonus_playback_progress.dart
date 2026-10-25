import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../sonus_theme.dart';
import '../../sonus_theme_definition.dart';

/// Playback progress with seeking, drawn in the theme's progress treatment
/// (SN-48E): Spray Wave, Tape Strip, Frequency Bars, Soft Wave, Chrome
/// Linear or Minimal Linear.
///
/// Every treatment shares one linear seek contract: tapping or dragging
/// anywhere along the track seeks to that point; arrow keys and screen
/// reader increase/decrease actions step by [keyboardStep]. Nothing
/// animates on its own: the drawing changes only when [position] does, so
/// there is no continuous repaint, and Reduced motion or Low effects need
/// no special handling beyond the flat colours they already imply.
///
/// When [duration] is unknown (null or zero) the track is drawn empty, the
/// times read "--:--" and seeking is disabled.
class SonusPlaybackProgress extends StatefulWidget {
  const SonusPlaybackProgress({
    super.key,
    required this.position,
    required this.duration,
    this.onSeek,
    this.style,
    this.keyboardStep = const Duration(seconds: 5),
    this.showTimes = true,
    this.accentColor,
    this.elapsedKey,
  });

  final Duration position;
  final Duration? duration;

  /// Called with the chosen position; null makes the bar read-only.
  final ValueChanged<Duration>? onSeek;

  /// Overrides the theme's treatment, for previews and tests.
  final SonusProgressStyle? style;
  final Duration keyboardStep;
  final bool showTimes;

  /// The played colour; the theme accent by default (artwork atmosphere
  /// pages pass their accent).
  final Color? accentColor;

  /// Key of the elapsed-time label, for players that test it.
  final Key? elapsedKey;

  @override
  State<SonusPlaybackProgress> createState() => _SonusPlaybackProgressState();
}

class _SonusPlaybackProgressState extends State<SonusPlaybackProgress> {
  /// While dragging, the thumb follows the finger without waiting for the
  /// player to report the new position.
  double? _dragFraction;
  bool _focused = false;

  Duration? get _knownDuration {
    final duration = widget.duration;
    return duration == null || duration <= Duration.zero ? null : duration;
  }

  bool get _canSeek => widget.onSeek != null && _knownDuration != null;

  double get _fraction {
    final drag = _dragFraction;
    if (drag != null) return drag;
    final duration = _knownDuration;
    if (duration == null) return 0;
    return (widget.position.inMilliseconds / duration.inMilliseconds).clamp(
      0.0,
      1.0,
    );
  }

  void _seekToFraction(double fraction) {
    final duration = _knownDuration;
    final onSeek = widget.onSeek;
    if (duration == null || onSeek == null) return;
    onSeek(
      Duration(
        milliseconds: (duration.inMilliseconds * fraction.clamp(0.0, 1.0))
            .round(),
      ),
    );
  }

  void _step(int direction) {
    final duration = _knownDuration;
    final onSeek = widget.onSeek;
    if (duration == null || onSeek == null) return;
    final target = widget.position + widget.keyboardStep * direction;
    onSeek(
      target < Duration.zero
          ? Duration.zero
          : target > duration
          ? duration
          : target,
    );
  }

  double _fractionAt(Offset local, double width) =>
      width <= 0 ? 0 : (local.dx / width).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final theme = Theme.of(context);
    final style = widget.style ?? tokens.decoration.progressStyle;
    // High contrast already gives progressActive its strongest colour.
    final accent = widget.accentColor ?? colors.progressActive;
    final duration = _knownDuration;
    final shownPosition = duration == null
        ? widget.position
        : Duration(milliseconds: (duration.inMilliseconds * _fraction).round());

    final painter = SonusProgressPainter(
      style: style,
      fraction: _fraction,
      active: accent,
      inactive: colors.progressInactive,
      thumb: accent,
      focusColor: _focused ? colors.focus : null,
      gradients: tokens.decoration.allowGradients,
      known: duration != null,
    );

    final bar = LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: _canSeek
              ? (details) =>
                    _seekToFraction(_fractionAt(details.localPosition, width))
              : null,
          onHorizontalDragStart: _canSeek
              ? (details) => setState(() {
                  _dragFraction = _fractionAt(details.localPosition, width);
                })
              : null,
          onHorizontalDragUpdate: _canSeek
              ? (details) => setState(() {
                  _dragFraction = _fractionAt(details.localPosition, width);
                })
              : null,
          onHorizontalDragEnd: _canSeek
              ? (_) {
                  final fraction = _dragFraction;
                  setState(() => _dragFraction = null);
                  if (fraction != null) _seekToFraction(fraction);
                }
              : null,
          onHorizontalDragCancel: () => setState(() => _dragFraction = null),
          // 48dp tall so the whole bar is an easy touch target.
          child: SizedBox(
            height: 48,
            width: double.infinity,
            child: RepaintBoundary(child: CustomPaint(painter: painter)),
          ),
        );
      },
    );

    final timeStyle = theme.textTheme.labelMedium?.copyWith(
      color: colors.textSecondary,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return Semantics(
      slider: true,
      label: 'Playback position',
      value: duration == null
          ? 'Unknown length'
          : '${_spoken(shownPosition)} of ${_spoken(duration)}',
      increasedValue: duration == null
          ? null
          : _spoken(_clamped(shownPosition + widget.keyboardStep, duration)),
      decreasedValue: duration == null
          ? null
          : _spoken(_clamped(shownPosition - widget.keyboardStep, duration)),
      onIncrease: _canSeek ? () => _step(1) : null,
      onDecrease: _canSeek ? () => _step(-1) : null,
      child: FocusableActionDetector(
        enabled: _canSeek,
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.arrowRight): _StepIntent(1),
          SingleActivator(LogicalKeyboardKey.arrowUp): _StepIntent(1),
          SingleActivator(LogicalKeyboardKey.arrowLeft): _StepIntent(-1),
          SingleActivator(LogicalKeyboardKey.arrowDown): _StepIntent(-1),
        },
        actions: {
          _StepIntent: CallbackAction<_StepIntent>(
            onInvoke: (intent) {
              _step(intent.direction);
              return null;
            },
          ),
        },
        child: ExcludeSemantics(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              bar,
              if (widget.showTimes)
                Row(
                  children: [
                    Text(
                      _clock(shownPosition),
                      key: widget.elapsedKey,
                      style: timeStyle,
                    ),
                    const Spacer(),
                    Text(
                      duration == null
                          ? '--:--'
                          : '-${_clock(duration - shownPosition)}',
                      style: timeStyle,
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  static Duration _clamped(Duration value, Duration max) =>
      value < Duration.zero
      ? Duration.zero
      : value > max
      ? max
      : value;

  static String _clock(Duration value) {
    final safe = value.isNegative ? Duration.zero : value;
    final hours = safe.inHours;
    final minutes = safe.inMinutes % 60;
    final seconds = (safe.inSeconds % 60).toString().padLeft(2, '0');
    return hours > 0
        ? '$hours:${minutes.toString().padLeft(2, '0')}:$seconds'
        : '$minutes:$seconds';
  }

  static String _spoken(Duration value) {
    final safe = value.isNegative ? Duration.zero : value;
    String unit(int count, String name) =>
        '$count $name${count == 1 ? '' : 's'}';
    final hours = safe.inHours;
    final minutes = safe.inMinutes % 60;
    final seconds = unit(safe.inSeconds % 60, 'second');
    if (hours > 0) {
      return '${unit(hours, 'hour')} ${unit(minutes, 'minute')} $seconds';
    }
    return minutes == 0 ? seconds : '${unit(minutes, 'minute')} $seconds';
  }
}

class _StepIntent extends Intent {
  const _StepIntent(this.direction);

  final int direction;
}

/// Draws one progress treatment. Shapes are deterministic (no randomness
/// at paint time), so equal inputs paint identical frames.
class SonusProgressPainter extends CustomPainter {
  const SonusProgressPainter({
    required this.style,
    required this.fraction,
    required this.active,
    required this.inactive,
    required this.thumb,
    required this.gradients,
    required this.known,
    this.focusColor,
  });

  final SonusProgressStyle style;
  final double fraction;
  final Color active;
  final Color inactive;
  final Color thumb;
  final bool gradients;

  /// False while the duration is unknown: only the empty track is drawn.
  final bool known;
  final Color? focusColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.height / 2;
    final split = size.width * (known ? fraction : 0);

    switch (style) {
      case SonusProgressStyle.minimalLinear:
        _line(canvas, size, center, split, thickness: 3);
      case SonusProgressStyle.chromeLinear:
        _chrome(canvas, size, center, split);
      case SonusProgressStyle.softWave:
        _wave(canvas, size, center, split, amplitude: 4, wavelength: 28);
      case SonusProgressStyle.sprayWave:
        _wave(canvas, size, center, split, amplitude: 3, wavelength: 18);
        _spray(canvas, size, center, split);
      case SonusProgressStyle.frequencyBars:
        _bars(canvas, size, center, split);
      case SonusProgressStyle.tapeStrip:
        _tape(canvas, size, center, split);
    }

    if (known) _thumb(canvas, Offset(split, center));
  }

  Paint _stroke(Color color, double width) => Paint()
    ..color = color
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke;

  void _line(
    Canvas canvas,
    Size size,
    double center,
    double split, {
    required double thickness,
  }) {
    canvas.drawLine(
      Offset(0, center),
      Offset(size.width, center),
      _stroke(inactive, thickness),
    );
    if (split > 0) {
      canvas.drawLine(
        Offset(0, center),
        Offset(split, center),
        _stroke(active, thickness),
      );
    }
  }

  void _chrome(Canvas canvas, Size size, double center, double split) {
    const height = 6.0;
    final track = RRect.fromLTRBR(
      0,
      center - height / 2,
      size.width,
      center + height / 2,
      const Radius.circular(height / 2),
    );
    canvas.drawRRect(track, Paint()..color = inactive);
    if (split <= 0) return;
    final played = RRect.fromLTRBR(
      0,
      center - height / 2,
      split,
      center + height / 2,
      const Radius.circular(height / 2),
    );
    final paint = Paint()..color = active;
    if (gradients) {
      // A chrome highlight across the top half of the played bar.
      paint.shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color.lerp(active, Colors.white, 0.45)!,
          active,
          Color.lerp(active, Colors.black, 0.2)!,
        ],
      ).createShader(played.outerRect);
    }
    canvas.drawRRect(played, paint);
  }

  Path _wavePath(
    double from,
    double to,
    double center, {
    required double amplitude,
    required double wavelength,
  }) {
    final path = Path()
      ..moveTo(
        from,
        center + amplitude * math.sin(from / wavelength * 2 * math.pi),
      );
    for (var x = from; x <= to; x += 2) {
      path.lineTo(
        x,
        center + amplitude * math.sin(x / wavelength * 2 * math.pi),
      );
    }
    return path;
  }

  void _wave(
    Canvas canvas,
    Size size,
    double center,
    double split, {
    required double amplitude,
    required double wavelength,
  }) {
    // Unplayed audio is a flat line; played audio becomes the wave.
    canvas.drawLine(
      Offset(split, center),
      Offset(size.width, center),
      _stroke(inactive, 3),
    );
    if (split > 0) {
      canvas.drawPath(
        _wavePath(
          0,
          split,
          center,
          amplitude: amplitude,
          wavelength: wavelength,
        ),
        _stroke(active, 3),
      );
    }
  }

  void _spray(Canvas canvas, Size size, double center, double split) {
    // A few fixed speckles trailing the played wave, like spray paint.
    final paint = Paint()..color = active.withValues(alpha: 0.55);
    for (var i = 0; i < 24; i++) {
      final x = ((i * 37) % 100) / 100 * split;
      final y = center + (((i * 53) % 13) - 6).toDouble();
      canvas.drawCircle(Offset(x, y), 1 + (i % 3) * 0.4, paint);
    }
  }

  void _bars(Canvas canvas, Size size, double center, double split) {
    const gap = 3.0;
    const width = 3.0;
    final count = (size.width / (width + gap)).floor();
    for (var i = 0; i < count; i++) {
      final x = i * (width + gap) + width / 2;
      // Deterministic heights between 30% and 100% of 22dp.
      final height = 22 * (0.3 + 0.7 * (((i * 7919) % 97) / 96));
      canvas.drawLine(
        Offset(x, center - height / 2),
        Offset(x, center + height / 2),
        _stroke(x <= split ? active : inactive, width),
      );
    }
  }

  void _tape(Canvas canvas, Size size, double center, double split) {
    const height = 12.0;
    final strip = Rect.fromLTRB(
      0,
      center - height / 2,
      size.width,
      center + height / 2,
    );
    canvas.drawRect(strip, Paint()..color = inactive);
    if (split > 0) {
      canvas.drawRect(
        Rect.fromLTRB(0, strip.top, split, strip.bottom),
        Paint()..color = active,
      );
    }
    // Tape ticks every 12dp, drawn over both parts.
    final tick = _stroke(
      Color.lerp(inactive, active, 0.5)!.withValues(alpha: 0.6),
      1,
    );
    for (var x = 6.0; x < size.width; x += 12) {
      canvas.drawLine(Offset(x, strip.top + 2), Offset(x, strip.top + 5), tick);
    }
  }

  void _thumb(Canvas canvas, Offset at) {
    final focus = focusColor;
    if (focus != null) {
      canvas.drawCircle(at, 12, _stroke(focus, 2));
    }
    canvas.drawCircle(at, 7, Paint()..color = thumb);
  }

  @override
  bool shouldRepaint(SonusProgressPainter oldDelegate) =>
      oldDelegate.style != style ||
      oldDelegate.fraction != fraction ||
      oldDelegate.active != active ||
      oldDelegate.inactive != inactive ||
      oldDelegate.thumb != thumb ||
      oldDelegate.gradients != gradients ||
      oldDelegate.known != known ||
      oldDelegate.focusColor != focusColor;
}

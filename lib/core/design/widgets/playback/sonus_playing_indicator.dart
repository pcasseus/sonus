import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../sonus_theme.dart';

/// The row marker for the current song (SN-45): three small equalizer bars
/// in the theme's accent, moving gently while it plays and still while it
/// is paused. Reduced motion keeps them still. Always [size] square, so a
/// row never changes size when it becomes current.
class SonusPlayingIndicator extends StatefulWidget {
  const SonusPlayingIndicator({
    super.key,
    required this.isPlaying,
    this.size = 18,
    this.color,
  });

  final bool isPlaying;
  final double size;
  final Color? color;

  @override
  State<SonusPlayingIndicator> createState() => _SonusPlayingIndicatorState();
}

class _SonusPlayingIndicatorState extends State<SonusPlayingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  bool _animates(BuildContext context) =>
      widget.isPlaying &&
      !SonusTheme.of(context).motion.reduced &&
      !MediaQuery.disableAnimationsOf(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant SonusPlayingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (_animates(context)) {
      if (!_motion.isAnimating) _motion.repeat();
    } else if (_motion.isAnimating) {
      _motion.stop();
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? SonusTheme.of(context).colors.accentPrimary;

    return Semantics(
      label: widget.isPlaying ? 'Now playing' : 'Paused',
      child: SizedBox.square(
        dimension: widget.size,
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: _motion,
            builder: (context, _) => CustomPaint(
              painter: _BarsPainter(
                color: color,
                phase: _animates(context) ? _motion.value : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  const _BarsPainter({required this.color, required this.phase});

  final Color color;

  /// Null draws the still pose.
  final double? phase;

  static const List<double> _still = [0.55, 0.9, 0.4];
  static const List<double> _offsets = [0, 0.33, 0.66];

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final barWidth = size.width / 5;
    final radius = Radius.circular(barWidth / 2);

    for (var i = 0; i < 3; i++) {
      final phase = this.phase;
      final level = phase == null
          ? _still[i]
          : 0.3 +
                0.7 *
                    (0.5 + 0.5 * math.sin((phase + _offsets[i]) * 2 * math.pi));
      final height = size.height * level;
      final left = barWidth * (i * 2);
      canvas.drawRRect(
        RRect.fromLTRBR(
          left,
          size.height - height,
          left + barWidth,
          size.height,
          radius,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BarsPainter oldDelegate) =>
      oldDelegate.phase != phase || oldDelegate.color != color;
}

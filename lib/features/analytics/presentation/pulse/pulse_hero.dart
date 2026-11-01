import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../../../../core/design/sonus_artwork_palette.dart';
import '../../../../core/design/sonus_theme.dart';
import '../../application/models/pulse/pulse_period.dart';
import '../../application/models/pulse/pulse_period_data.dart';
import 'pulse_colors.dart';
import 'pulse_format.dart';
import 'pulse_ring_layout.dart';
import 'pulse_ring_painter.dart';

/// The item whose share of each day is highlighted (an open ranking
/// detail).
@immutable
class PulseItemFocus {
  const PulseItemFocus({
    required this.kind,
    required this.id,
    required this.name,
  });

  final PulseEntityKind kind;
  final String id;
  final String name;

  @override
  bool operator ==(Object other) =>
      other is PulseItemFocus && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);
}

/// The temporary artwork accent of an open detail (spec §7.4). Holds
/// nothing persistent and never changes the global theme: [reset] returns
/// to theme colours while the detail stays open; the page clears it when
/// the detail closes, another item opens, the period or view changes, or
/// Insights is left.
class PulseAccentController extends ChangeNotifier {
  SonusArtworkColors? _artwork;

  SonusArtworkColors? get artwork => _artwork;
  bool get isApplied => _artwork != null;

  void apply(SonusArtworkColors? artwork) {
    if (_artwork == artwork) return;
    _artwork = artwork;
    notifyListeners();
  }

  /// "Reset colours".
  void reset() => apply(null);
}

/// The Sonus Pulse hero (spec §3): one spoke per local day, length and
/// colour from recorded listening only.
class PulseHero extends StatefulWidget {
  const PulseHero({
    super.key,
    required this.data,
    required this.measure,
    required this.palette,
    this.comparison,
    this.item,
    this.onOpenMonth,
    this.onShowList,
    this.onSelectedDayChanged,
  });

  final PulsePeriodData data;

  /// Minutes or Streams.
  final PulseMeasure measure;
  final PulsePalette palette;

  /// Drawn as a ghost only when available (eligible).
  final PulseComparison? comparison;
  final PulseItemFocus? item;

  /// Year view: a second tap on a day, or "Open {month}".
  final ValueChanged<PulsePeriod>? onOpenMonth;

  /// "Show as list": the accessible day-by-day table.
  final VoidCallback? onShowList;
  final ValueChanged<int?>? onSelectedDayChanged;

  static const Duration sweepDuration = Duration(milliseconds: 520);

  @override
  State<PulseHero> createState() => PulseHeroState();
}

@visibleForTesting
class PulseHeroState extends State<PulseHero> with TickerProviderStateMixin {
  late final AnimationController _sweep;
  late final AnimationController _ghost;
  late final AnimationController _bloom;
  final FocusNode _focus = FocusNode(debugLabel: 'Sonus Pulse');

  late PulseRingLayout _layout;
  List<double> _fromFractions = const [];
  List<Color> _fromTips = const [];
  int? _selected;
  int? _lastHaptic;

  int? get selectedDay => _selected;

  @override
  void initState() {
    super.initState();
    _sweep = AnimationController(vsync: this, value: 1);
    _ghost = AnimationController(vsync: this, value: _showGhost ? 1 : 0);
    _bloom = AnimationController(
      vsync: this,
      value: widget.item != null ? 1 : 0,
    );
    _layout = _buildLayout();
  }

  bool get _showGhost {
    final c = widget.comparison;
    return c != null && c.isAvailable && c.days != null;
  }

  PulseRingLayout _buildLayout() {
    final item = widget.item;
    return PulseRingLayout.build(
      data: widget.data,
      measure: widget.measure,
      comparisonDays: _showGhost ? widget.comparison!.days : null,
      itemDays: item == null
          ? null
          : widget.data.daySeriesFor(item.kind, item.id),
    );
  }

  @override
  void didUpdateWidget(PulseHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    final motion = SonusTheme.of(context).motion;
    final dataChanged =
        oldWidget.data != widget.data || oldWidget.measure != widget.measure;
    if (oldWidget.data.period != widget.data.period) {
      _setSelected(null, notify: true);
    }
    if (dataChanged ||
        oldWidget.comparison != widget.comparison ||
        oldWidget.item != widget.item ||
        oldWidget.palette != widget.palette) {
      if (dataChanged) {
        // Sweep from what is on screen now to the new real values.
        final frames = _frames(_sweep.value);
        _fromFractions = [for (final f in frames) f.fraction];
        _fromTips = [for (final f in frames) f.tip];
      }
      _layout = _buildLayout();
      if (dataChanged) {
        _sweep
          ..duration = motion.reduced ? Duration.zero : PulseHero.sweepDuration
          ..forward(from: 0);
      }
    }
    if (oldWidget.comparison != widget.comparison) {
      _ghost.duration = motion.short;
      _showGhost ? _ghost.forward() : _ghost.reverse();
    }
    if (oldWidget.item != widget.item) {
      _bloom.duration = motion.medium;
      if (widget.item == null) {
        _bloom.value = 0;
      } else {
        _bloom.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    _ghost.dispose();
    _bloom.dispose();
    _focus.dispose();
    super.dispose();
  }

  PulseRamp get _ramp => widget.palette.rampFor(widget.measure);

  /// Spoke frames at sweep progress [t]: each spoke starts a little after
  /// the one before, clockwise.
  List<PulseSpokeFrame> _frames(double t) {
    final spokes = _layout.spokes;
    final n = spokes.length;
    const maxDelay = 0.4;
    final curve = SonusTheme.of(context).motion.curve;
    return [
      for (var i = 0; i < n; i++)
        () {
          final s = spokes[i];
          final delay = n <= 1 ? 0.0 : maxDelay * i / (n - 1);
          final local = t >= 1
              ? 1.0
              : curve.transform(((t - delay) / (1 - maxDelay)).clamp(0.0, 1.0));
          final from = i < _fromFractions.length ? _fromFractions[i] : 0.0;
          final targetTip = _ramp.at(s.tipPosition);
          final fromTip = i < _fromTips.length ? _fromTips[i] : _ramp.base;
          return PulseSpokeFrame(
            state: s.state,
            fraction: from + (s.fraction - from) * local,
            tip: Color.lerp(fromTip, targetTip, local)!,
            itemFraction: s.itemFraction * _bloom.value,
            ghostFraction: s.ghostFraction,
            hasValue: s.value > 0 || from > 0 && local < 1,
          );
        }(),
    ];
  }

  void _setSelected(int? index, {bool notify = true}) {
    if (_selected == index) return;
    setState(() => _selected = index);
    if (notify) widget.onSelectedDayChanged?.call(index);
  }

  void _handleTap(Offset position, PulseRingGeometry geometry) {
    final hit = geometry.hitTest(position);
    if (hit == null) {
      _setSelected(null);
      return;
    }
    if (widget.data.period.kind == PulsePeriodKind.year && hit == _selected) {
      _openMonthOf(hit);
      return;
    }
    _setSelected(hit);
  }

  void _handleDrag(Offset position, PulseRingGeometry geometry) {
    final hit = geometry.hitTest(position);
    if (hit == null || hit == _selected) return;
    if (_lastHaptic != hit) {
      HapticFeedback.selectionClick();
      _lastHaptic = hit;
    }
    _setSelected(hit);
  }

  void _openMonthOf(int index) {
    final day = widget.data.days[index].localDate;
    widget.onOpenMonth?.call(PulsePeriod.month(day.year, day.month));
  }

  void _move(int delta) {
    final count = widget.data.days.length;
    final current = _selected ?? (delta > 0 ? -1 : count);
    _setSelected((current + delta).clamp(0, count - 1));
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowRight) {
      _move(1);
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      _move(-1);
    } else if (key == LogicalKeyboardKey.home) {
      _setSelected(0);
    } else if (key == LogicalKeyboardKey.end) {
      _setSelected(widget.data.days.length - 1);
    } else if (key == LogicalKeyboardKey.escape) {
      _setSelected(null);
    } else if (key == LogicalKeyboardKey.enter &&
        _selected != null &&
        widget.data.period.kind == PulsePeriodKind.year) {
      _openMonthOf(_selected!);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  String _readout() {
    final selected = _selected;
    if (selected == null) {
      return PulseFormat.longestHint(widget.data, widget.measure) ??
          'No listening recorded in '
              '${PulseFormat.periodTitle(widget.data.period)}';
    }
    final item = widget.item;
    return PulseFormat.readout(
      widget.data.days[selected],
      itemName: item?.name,
      item: item == null
          ? null
          : widget.data.daySeriesFor(item.kind, item.id)[selected],
      measure: widget.measure,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = SonusTheme.of(context);
    final palette = widget.palette;
    final (value, unit) = PulseFormat.centre(
      widget.data.totals,
      widget.measure,
    );
    final readout = _readout();
    final selected = _selected;
    final isYear = widget.data.period.kind == PulsePeriodKind.year;
    final increased = _neighbourReadout(1);
    final decreased = _neighbourReadout(-1);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          container: true,
          focusable: true,
          label: PulseFormat.summary(widget.data, widget.measure),
          value: readout,
          // Adjust actions only where there is a day to move to.
          increasedValue: increased,
          decreasedValue: decreased,
          onIncrease: increased == null ? null : () => _move(1),
          onDecrease: decreased == null ? null : () => _move(-1),
          customSemanticsActions: {
            if (widget.onShowList != null)
              const CustomSemanticsAction(label: 'Show as list'):
                  widget.onShowList!,
          },
          child: ExcludeSemantics(
            child: Focus(
              focusNode: _focus,
              onKeyEvent: _onKey,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final side = math.max(
                    220.0,
                    math.min(
                      constraints.maxWidth,
                      constraints.maxHeight.isFinite
                          ? constraints.maxHeight
                          : constraints.maxWidth,
                    ),
                  );
                  final size = Size.square(side);
                  final geometry = PulseRingGeometry.of(
                    widget.data.period,
                    size,
                  );
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (d) {
                      _focus.requestFocus();
                      _handleTap(d.localPosition, geometry);
                    },
                    onPanStart: (d) => _handleDrag(d.localPosition, geometry),
                    onPanUpdate: (d) => _handleDrag(d.localPosition, geometry),
                    onPanEnd: (_) => _lastHaptic = null,
                    child: SizedBox.fromSize(
                      size: size,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          AnimatedBuilder(
                            animation: Listenable.merge([
                              _sweep,
                              _ghost,
                              _bloom,
                            ]),
                            builder: (context, _) => CustomPaint(
                              size: size,
                              painter: PulseRingPainter(
                                period: widget.data.period,
                                spokes: _frames(_sweep.value),
                                palette: palette,
                                ramp: _ramp,
                                averageFraction: _layout.averageFraction,
                                ghostOpacity: _ghost.value,
                                itemActive: widget.item != null,
                                itemColor: palette.itemColorFor(widget.measure),
                                selected: selected,
                                haloColor: palette.haloFor(widget.measure),
                              ),
                            ),
                          ),
                          SizedBox(
                            width: geometry.innerRadius * 1.6,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    value,
                                    key: const ValueKey('pulse-centre-value'),
                                    style: theme.text.featuredStat.copyWith(
                                      fontSize: 34,
                                      color: palette.text,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    unit,
                                    style: TextStyle(
                                      color: _ramp.at(0.85),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        ExcludeSemantics(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  readout,
                  key: const ValueKey('pulse-readout'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: selected == null
                        ? palette.textSecondary
                        : palette.text,
                  ),
                ),
              ),
              if (isYear && selected != null && widget.onOpenMonth != null)
                TextButton(
                  key: const ValueKey('pulse-open-month'),
                  onPressed: () => _openMonthOf(selected),
                  child: Text(
                    'Open '
                    '${PulseFormat.months[widget.data.days[selected].localDate.month - 1]}',
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  String? _neighbourReadout(int delta) {
    final count = widget.data.days.length;
    final current = _selected ?? (delta > 0 ? -1 : count);
    final next = current + delta;
    if (next < 0 || next >= count) return null;
    return PulseFormat.readout(widget.data.days[next]);
  }
}

/// The accessible day-by-day alternative to the ring ("Show as list").
class PulseDayList extends StatelessWidget {
  const PulseDayList({super.key, required this.data});

  final PulsePeriodData data;

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final day in data.days)
          Semantics(
            label: _label(day),
            excludeSemantics: true,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(child: Text(PulseFormat.day(day.localDate))),
                  ..._values(day, colors.textSecondary),
                ],
              ),
            ),
          ),
      ],
    );
  }

  static String _label(PulseDay day) {
    final date = PulseFormat.day(day.localDate);
    return switch (day.state) {
      PulseDayState.future => '$date: not yet',
      PulseDayState.beforeHistory => '$date: before your history starts',
      PulseDayState.recorded =>
        '$date: ${PulseFormat.minutes(day.metrics.listened)} minutes, '
            '${day.metrics.streams} '
            '${day.metrics.streams == 1 ? 'stream' : 'streams'}',
    };
  }

  static List<Widget> _values(PulseDay day, Color muted) => switch (day.state) {
    PulseDayState.recorded => [
      SizedBox(
        width: 72,
        child: Text(
          '${PulseFormat.grouped(PulseFormat.minutes(day.metrics.listened))} min',
          textAlign: TextAlign.end,
        ),
      ),
      SizedBox(
        width: 72,
        child: Text(
          PulseFormat.grouped(day.metrics.streams),
          textAlign: TextAlign.end,
        ),
      ),
    ],
    _ => [
      Text(
        day.state == PulseDayState.future ? 'Not yet' : 'No history',
        style: TextStyle(color: muted),
      ),
    ],
  };
}

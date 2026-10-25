import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/design/sonus_theme.dart';
import '../models/alphabet_index.dart';

/// A slim A–Z fast-scroll rail for long alphabetical lists (SN-45).
///
/// Tap or drag through the letters to jump. Screen readers treat it as an
/// adjustable control (swipe up or down to move a letter), and with
/// keyboard focus the arrow keys do the same.
class AlphabetRail extends StatefulWidget {
  const AlphabetRail({
    super.key,
    required this.available,
    required this.onLetter,
    this.onScrubbing,
  });

  final Set<String> available;
  final ValueChanged<String> onLetter;

  /// The letter under the finger while dragging, then null when released.
  final ValueChanged<String?>? onScrubbing;

  static const double width = 24;

  /// Below this height per letter, every other letter is drawn (all of
  /// them still respond).
  static const double _minLetterHeight = 13;

  @override
  State<AlphabetRail> createState() => _AlphabetRailState();
}

class _AlphabetRailState extends State<AlphabetRail> {
  String? _current;
  bool _focused = false;

  List<String> get _letters => AlphabetIndex.letters;

  void _select(String letter) {
    if (letter == _current) return;
    setState(() => _current = letter);
    widget.onLetter(letter);
  }

  String _letterAt(double dy, double height) {
    final fraction = (dy / height).clamp(0.0, 0.9999);
    return _letters[(fraction * _letters.length).floor()];
  }

  void _scrubTo(Offset local, double height) {
    final letter = _letterAt(local.dy, height);
    widget.onScrubbing?.call(letter);
    _select(letter);
  }

  void _endScrub() => widget.onScrubbing?.call(null);

  String? _step(int direction) {
    final start = _current == null ? -1 : _letters.indexOf(_current!);
    for (
      var i = start + direction;
      i >= 0 && i < _letters.length;
      i += direction
    ) {
      if (widget.available.contains(_letters[i])) return _letters[i];
    }
    return null;
  }

  void _move(int direction) {
    final next = _step(direction);
    if (next != null) _select(next);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final theme = Theme.of(context);

    final next = _step(1);
    final previous = _step(-1);

    return Semantics(
      key: const ValueKey<String>('alphabet-rail'),
      label: 'Jump to letter',
      value: _current ?? 'none',
      increasedValue: next,
      decreasedValue: previous,
      onIncrease: next == null ? null : () => _move(1),
      onDecrease: previous == null ? null : () => _move(-1),
      child: FocusableActionDetector(
        onShowFocusHighlight: (focused) => setState(() => _focused = focused),
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.arrowDown): _MoveIntent(1),
          SingleActivator(LogicalKeyboardKey.arrowUp): _MoveIntent(-1),
        },
        actions: {
          _MoveIntent: CallbackAction<_MoveIntent>(
            onInvoke: (intent) {
              _move(intent.direction);
              return null;
            },
          ),
        },
        child: LayoutBuilder(
          builder: (context, constraints) {
            final height = constraints.maxHeight;
            final perLetter = height / _letters.length;
            final step = perLetter < AlphabetRail._minLetterHeight ? 2 : 1;
            final fontSize = (perLetter * 0.72).clamp(8.0, 11.0);

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) => _scrubTo(details.localPosition, height),
              onTapUp: (_) => _endScrub(),
              onTapCancel: _endScrub,
              onVerticalDragStart: (details) =>
                  _scrubTo(details.localPosition, height),
              onVerticalDragUpdate: (details) =>
                  _scrubTo(details.localPosition, height),
              onVerticalDragEnd: (_) => _endScrub(),
              onVerticalDragCancel: _endScrub,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AlphabetRail.width),
                  border: _focused
                      ? Border.all(color: colors.focus, width: 2)
                      : null,
                ),
                child: SizedBox(
                  width: AlphabetRail.width,
                  height: height,
                  child: ExcludeSemantics(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        for (var i = 0; i < _letters.length; i += step)
                          Text(
                            _letters[i],
                            key: ValueKey<String>(
                              'alphabet-rail-${_letters[i]}',
                            ),
                            textScaler: TextScaler.noScaling,
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontSize: fontSize,
                              height: 1,
                              fontWeight: FontWeight.w700,
                              color: _letters[i] == _current
                                  ? colors.accentPrimary
                                  : widget.available.contains(_letters[i])
                                  ? colors.textSecondary
                                  : colors.textSecondary.withValues(
                                      alpha: 0.35,
                                    ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _MoveIntent extends Intent {
  const _MoveIntent(this.direction);

  final int direction;
}

/// The large letter shown in the middle of the list while scrubbing.
class AlphabetScrubBubble extends StatelessWidget {
  const AlphabetScrubBubble({super.key, required this.letter});

  final String letter;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;

    return IgnorePointer(
      child: ExcludeSemantics(
        child: Container(
          key: const ValueKey<String>('alphabet-scrub-bubble'),
          width: 72,
          height: 72,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colors.raisedSurface.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(tokens.metrics.cardRadius),
            border: Border.all(color: colors.divider),
          ),
          child: Text(
            letter,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: colors.accentPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

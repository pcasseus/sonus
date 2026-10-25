import 'package:flutter/material.dart';

import '../sonus_theme.dart';

/// One option of a [SonusSegmentedSelector].
@immutable
class SonusSegment<T> {
  const SonusSegment({required this.value, required this.label, this.icon});

  final T value;
  final String label;

  /// Decorative only. It is dropped with large text so the label keeps its
  /// width; the meaning must be carried by [label].
  final IconData? icon;
}

/// A Sonus-styled single-choice segmented control.
///
/// Styled locally from Sonus tokens, so it never changes the global
/// [SegmentedButton] theme used elsewhere. The selected segment keeps its
/// checkmark, so selection never relies on colour alone.
class SonusSegmentedSelector<T> extends StatelessWidget {
  const SonusSegmentedSelector({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
  });

  /// Text scale above which decorative segment icons are dropped.
  static const double largeTextScale = 1.3;

  final List<SonusSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final isLargeText =
        MediaQuery.textScalerOf(context).scale(1) > largeTextScale;

    return SegmentedButton<T>(
      style: SegmentedButton.styleFrom(
        foregroundColor: colors.textSecondary,
        selectedForegroundColor: colors.textPrimary,
        selectedBackgroundColor: colors.selection,
        side: BorderSide(color: colors.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.metrics.controlRadius),
        ),
      ),
      segments: [
        for (final segment in segments)
          ButtonSegment<T>(
            value: segment.value,
            label: Text(segment.label),
            icon: isLargeText || segment.icon == null
                ? null
                : Icon(segment.icon),
          ),
      ],
      selected: {selected},
      onSelectionChanged: (selection) {
        if (selection.isNotEmpty) {
          onChanged(selection.first);
        }
      },
    );
  }
}

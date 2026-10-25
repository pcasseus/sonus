import 'package:flutter/material.dart';

import '../../sonus_theme.dart';

/// How repeat is set, for display only; players map their own modes to it.
enum SonusRepeatDisplay { off, all, one }

/// Shuffle, previous, play or pause, next and repeat, in the Sonus style.
///
/// Presentation only: every action is a callback, and a null callback
/// disables its button. Tooltips double as screen reader labels and match
/// the player's existing wording.
class SonusPlaybackControls extends StatelessWidget {
  const SonusPlaybackControls({
    super.key,
    required this.isPlaying,
    this.isLoading = false,
    this.shuffleEnabled = false,
    this.repeat = SonusRepeatDisplay.off,
    this.onPlayPause,
    this.onPrevious,
    this.onNext,
    this.onToggleShuffle,
    this.onCycleRepeat,
    this.accentColor,
    this.onAccentColor,
    this.keyPrefix,
  });

  final bool isPlaying;

  /// Shows a spinner in the play button and disables it.
  final bool isLoading;
  final bool shuffleEnabled;
  final SonusRepeatDisplay repeat;
  final VoidCallback? onPlayPause;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onToggleShuffle;
  final VoidCallback? onCycleRepeat;

  /// The play button's colours; the theme's playback control by default
  /// (atmosphere pages pass their accent).
  final Color? accentColor;
  final Color? onAccentColor;

  /// Keys the buttons `<prefix>-shuffle`, `-previous`, `-play-pause`,
  /// `-next` and `-repeat`, for players with their own tests.
  final String? keyPrefix;

  Key? _key(String name) {
    final prefix = keyPrefix;
    return prefix == null ? null : ValueKey<String>('$prefix-$name');
  }

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;
    final accent = accentColor ?? colors.playbackControl;
    final onAccent = onAccentColor ?? colors.onPlaybackControl;

    Widget toggle({
      required Key? key,
      required IconData icon,
      required String tooltip,
      required bool selected,
      required VoidCallback? onPressed,
    }) {
      return IconButton(
        key: key,
        tooltip: tooltip,
        isSelected: selected,
        onPressed: onPressed,
        iconSize: 26,
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        color: colors.textSecondary,
        selectedIcon: Icon(icon, color: accent),
        icon: Icon(icon),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Tighter play button on very narrow layouts (320dp at 2x).
        final playSize = constraints.maxWidth < 300 ? 64.0 : 76.0;

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            toggle(
              key: _key('shuffle'),
              icon: shuffleEnabled
                  ? Icons.shuffle_on_rounded
                  : Icons.shuffle_rounded,
              tooltip: shuffleEnabled ? 'Shuffle on' : 'Shuffle off',
              selected: shuffleEnabled,
              onPressed: onToggleShuffle,
            ),
            IconButton(
              key: _key('previous'),
              tooltip: 'Previous',
              onPressed: onPrevious,
              iconSize: 34,
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              color: colors.textPrimary,
              icon: const Icon(Icons.skip_previous_rounded),
            ),
            SizedBox.square(
              dimension: playSize,
              child: IconButton.filled(
                key:
                    _key('play-pause') ??
                    const ValueKey<String>('sonus-play-pause-button'),
                tooltip: isPlaying ? 'Pause' : 'Play',
                onPressed: isLoading ? null : onPlayPause,
                style: IconButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: onAccent,
                  disabledBackgroundColor: accent.withValues(alpha: 0.5),
                ),
                iconSize: playSize * 0.5,
                icon: isLoading
                    ? SizedBox.square(
                        dimension: playSize * 0.36,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: onAccent,
                        ),
                      )
                    : Icon(
                        isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
              ),
            ),
            IconButton(
              key: _key('next'),
              tooltip: 'Next',
              onPressed: onNext,
              iconSize: 34,
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              color: colors.textPrimary,
              icon: const Icon(Icons.skip_next_rounded),
            ),
            toggle(
              key: _key('repeat'),
              icon: repeat == SonusRepeatDisplay.one
                  ? Icons.repeat_one_rounded
                  : Icons.repeat_rounded,
              tooltip: switch (repeat) {
                SonusRepeatDisplay.off => 'Repeat off',
                SonusRepeatDisplay.all => 'Repeat all',
                SonusRepeatDisplay.one => 'Repeat one',
              },
              selected: repeat != SonusRepeatDisplay.off,
              onPressed: onCycleRepeat,
            ),
          ],
        );
      },
    );
  }
}

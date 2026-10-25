import 'package:flutter/material.dart';

/// Tells the listener that the current song could not be played.
///
/// Shown while the playback state is failed, which stays recoverable:
/// Next, Previous and the queue still work. Announced as a live region so
/// screen readers report it without the listener looking for it.
class PlaybackErrorNotice extends StatelessWidget {
  const PlaybackErrorNotice({
    super.key,
    required this.message,
    this.compact = false,
  });

  /// Short wording for the mini-player.
  static const String shortMessage = 'Song unavailable';

  /// Full wording for Now Playing.
  static const String fullMessage =
      "This song couldn't be played. It may have been moved or deleted. "
      'Skip to another song to continue.';

  final String message;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = compact
        ? theme.textTheme.bodyMedium
        : theme.textTheme.bodyLarge;

    return Semantics(
      liveRegion: true,
      child: Row(
        mainAxisSize: compact ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: compact ? 16 : 20,
            color: theme.colorScheme.error,
          ),
          SizedBox(width: compact ? 6 : 8),
          Flexible(
            child: Text(
              message,
              maxLines: compact ? 1 : 3,
              overflow: TextOverflow.ellipsis,
              style: style?.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

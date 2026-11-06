import 'playback/sonus_playing_indicator.dart';
import 'package:flutter/material.dart';

import '../sonus_text_scale.dart';
import '../sonus_theme.dart';
import 'sonus_artwork_image.dart';

/// One song row in the Sonus style: artwork, title, a supporting line,
/// a tabular duration and trailing actions (usually an overflow menu).
///
/// At large text sizes the leading number is dropped and the duration
/// joins the supporting line, so titles keep their room. A disabled row
/// (unavailable media) dims its text, keeps its actions and ignores taps.
class SonusTrackTile extends StatelessWidget {
  const SonusTrackTile({
    super.key,
    required this.title,
    this.subtitle,
    this.detail,
    this.artworkPath,
    this.leadingNumber,
    this.duration,
    this.trailing,
    this.onTap,
    this.enabled = true,
    this.isCurrent = false,
    this.isPlaying = true,
    this.tileColor,
    this.titleKey,
    this.inkKey,
    this.durationKey,
    this.status,
    this.showArtwork = true,
    this.selected,
    this.onLongPress,
  });

  final String title;
  final String? subtitle;

  /// A quieter third line, such as the album title.
  final String? detail;
  final String? artworkPath;

  /// A track number or rank shown before the artwork.
  final String? leadingNumber;

  /// Already formatted, for example "3:41".
  final String? duration;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool enabled;

  /// The song now playing: an accent marker and a "Now playing" label for
  /// screen readers.
  final bool isCurrent;

  /// Whether the current song is playing (moving bars) or paused.
  final bool isPlaying;
  final Color? tileColor;
  final Key? titleKey;

  /// Key on the tappable surface, for screens whose tests find the row.
  final Key? inkKey;

  /// Key on the duration text.
  final Key? durationKey;

  /// A short state line under the subtitle, such as "Unavailable".
  final Widget? status;
  final bool showArtwork;

  /// Non-null while the list is in selection mode: the row shows a
  /// checkbox, hides [trailing] and [onTap] toggles it, even when disabled.
  final bool? selected;

  /// Usually starts selection mode.
  final VoidCallback? onLongPress;

  static const double artworkSize = 44;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final theme = Theme.of(context);
    final largeText =
        MediaQuery.textScalerOf(context).scale(1) > sonusLargeTextScale;
    const tabular = [FontFeature.tabularFigures()];
    final number = largeText ? null : leadingNumber;
    final duration = this.duration;
    final subtitleParts = [
      if (subtitle != null && subtitle!.isNotEmpty) subtitle!,
      if (largeText && duration != null) duration,
    ];
    final textColor = enabled ? colors.textPrimary : colors.textSecondary;
    final selected = this.selected;
    final selecting = selected != null;

    final leading = [
      if (selecting)
        ExcludeFocus(
          child: ExcludeSemantics(
            child: Checkbox(value: selected, onChanged: (_) => onTap?.call()),
          ),
        )
      else if (isCurrent)
        SizedBox(
          width: 28,
          child: Align(
            alignment: Alignment.centerLeft,
            child: SonusPlayingIndicator(isPlaying: isPlaying),
          ),
        )
      else if (number != null)
        SizedBox(
          width: 28,
          child: Text(
            number,
            maxLines: 1,
            softWrap: false,
            style: theme.textTheme.labelLarge?.copyWith(
              color: colors.textSecondary,
              fontWeight: FontWeight.w700,
              fontFeatures: tabular,
            ),
          ),
        ),
      if (showArtwork)
        Opacity(
          opacity: enabled ? 1 : 0.55,
          child: SonusArtworkImage(path: artworkPath, size: artworkSize),
        ),
    ];

    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected == true
            ? colors.accentPrimary.withValues(alpha: 0.16)
            : tileColor ?? Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.metrics.cardRadius),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: inkKey,
          onTap: enabled || selecting ? onTap : null,
          onLongPress: onLongPress,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 2, 6),
              child: Row(
                children: [
                  if (leading.isNotEmpty) ...[
                    ...leading,
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          key: titleKey,
                          maxLines: largeText ? 3 : 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: isCurrent ? colors.accentPrimary : textColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (subtitleParts.isNotEmpty)
                          Text(
                            subtitleParts.join(' • '),
                            maxLines: largeText ? 3 : 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.textSecondary,
                              fontFeatures: tabular,
                            ),
                          ),
                        if (detail != null && detail!.isNotEmpty)
                          Text(
                            detail!,
                            maxLines: largeText ? 2 : 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                        ?status,
                      ],
                    ),
                  ),
                  if (!largeText && duration != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      duration,
                      key: durationKey,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                        fontFeatures: tabular,
                      ),
                    ),
                  ],
                  if (trailing != null && !selecting)
                    trailing!
                  else
                    const SizedBox(width: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (!selecting) {
      return row;
    }

    return Semantics(checked: selected, selected: selected, child: row);
  }
}

/// Formats seconds as m:ss or h:mm:ss for track durations.
String sonusFormatDuration(int seconds) {
  final safe = seconds < 0 ? 0 : seconds;
  final hours = safe ~/ 3600;
  final minutes = (safe % 3600) ~/ 60;
  final rest = (safe % 60).toString().padLeft(2, '0');

  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:$rest';
  }
  return '$minutes:$rest';
}

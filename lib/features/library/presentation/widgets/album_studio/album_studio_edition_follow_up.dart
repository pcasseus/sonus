import 'package:flutter/material.dart';

import '../../../../../core/design/sonus_theme.dart';
import '../../../application/services/edition_follow_up.dart';

/// What the user decided about songs offered to another edition.
enum EditionFollowUpChoice {
  /// Add the chosen songs to the chosen editions.
  add,

  /// Keep those editions as they are, and stop offering these songs.
  keep,

  /// Decide later (the dialog was closed). Nothing is remembered.
  later,
}

class EditionFollowUpDecision {
  const EditionFollowUpDecision(this.choice, [this.accepted = const []]);

  final EditionFollowUpChoice choice;

  /// The follow-ups to apply when [choice] is [EditionFollowUpChoice.add].
  final List<EditionFollowUp> accepted;
}

/// Asks whether songs just added to one edition (Standard) should also be
/// added to the editions built on it (Deluxe).
///
/// The safe answer is the default: the focused button keeps every other
/// edition as it is, and nothing is pre-selected.
Future<EditionFollowUpDecision> showEditionFollowUpDialog({
  required BuildContext context,
  required String sourceTitle,
  required List<EditionFollowUp> followUps,
  required String Function(String songId) songTitle,
}) async {
  final decision = await showDialog<EditionFollowUpDecision>(
    context: context,
    builder: (_) => _EditionFollowUpDialog(
      sourceTitle: sourceTitle,
      followUps: followUps,
      songTitle: songTitle,
    ),
  );
  return decision ?? const EditionFollowUpDecision(EditionFollowUpChoice.later);
}

class _EditionFollowUpDialog extends StatefulWidget {
  const _EditionFollowUpDialog({
    required this.sourceTitle,
    required this.followUps,
    required this.songTitle,
  });

  final String sourceTitle;
  final List<EditionFollowUp> followUps;
  final String Function(String songId) songTitle;

  @override
  State<_EditionFollowUpDialog> createState() => _EditionFollowUpDialogState();
}

class _EditionFollowUpDialogState extends State<_EditionFollowUpDialog> {
  // Nothing is chosen until the user chooses it.
  final Set<String> _targets = {};

  bool get _single => widget.followUps.length == 1;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = SonusTheme.of(context).colors;
    final songIds = <String>{
      for (final followUp in widget.followUps) ...followUp.songIds,
    }.toList(growable: false);
    final count = songIds.length;
    final songsLabel = count == 1 ? 'this song' : 'these $count songs';
    final single = _single ? widget.followUps.single : null;

    return AlertDialog(
      key: const ValueKey<String>('album-studio-follow-up-dialog'),
      title: Text(
        single == null
            ? 'Also add to other editions?'
            : 'Also add to ${single.targetTitle}?',
      ),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            single == null
                ? 'Some editions include every song on '
                      '${widget.sourceTitle}. Choose which should also get '
                      '$songsLabel. Unchosen editions stay as they are.'
                : '${single.targetTitle} includes every song on '
                      '${widget.sourceTitle}. Add $songsLabel to '
                      '${single.targetTitle} too? If you keep it as it is, '
                      'nothing on ${single.targetTitle} changes.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          for (final songId in songIds.take(8))
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Icon(
                    Icons.music_note_rounded,
                    size: 18,
                    color: colors.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.songTitle(songId),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          if (songIds.length > 8)
            Text(
              'and ${songIds.length - 8} more',
              style: theme.textTheme.bodySmall,
            ),
          if (single == null) ...[
            const SizedBox(height: 8),
            for (final followUp in widget.followUps)
              CheckboxListTile(
                key: ValueKey<String>(
                  'album-studio-follow-up-${followUp.targetEditionId}',
                ),
                value: _targets.contains(followUp.targetEditionId),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(followUp.targetTitle),
                onChanged: (value) => setState(() {
                  if (value == true) {
                    _targets.add(followUp.targetEditionId);
                  } else {
                    _targets.remove(followUp.targetEditionId);
                  }
                }),
              ),
          ],
        ],
      ),
      actions: [
        TextButton(
          key: const ValueKey<String>('album-studio-follow-up-keep'),
          autofocus: true,
          onPressed: () => Navigator.of(
            context,
          ).pop(const EditionFollowUpDecision(EditionFollowUpChoice.keep)),
          child: Text(
            single == null
                ? 'Keep editions as they are'
                : 'Keep ${single.targetTitle} as it is',
          ),
        ),
        FilledButton(
          key: const ValueKey<String>('album-studio-follow-up-add'),
          onPressed: single == null && _targets.isEmpty
              ? null
              : () => Navigator.of(context).pop(
                  EditionFollowUpDecision(EditionFollowUpChoice.add, [
                    for (final followUp in widget.followUps)
                      if (single != null ||
                          _targets.contains(followUp.targetEditionId))
                        followUp,
                  ]),
                ),
          child: Text(
            single == null ? 'Add to chosen' : 'Add to ${single.targetTitle}',
          ),
        ),
      ],
    );
  }
}

/// A quiet notice in Album Studio when songs reached Standard after Deluxe
/// was built on it (for example from a later import).
class AlbumStudioEditionFollowUpNotice extends StatelessWidget {
  const AlbumStudioEditionFollowUpNotice({
    super.key,
    required this.followUp,
    required this.sourceTitle,
    required this.onReview,
  });

  final EditionFollowUp followUp;
  final String sourceTitle;
  final VoidCallback? onReview;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final count = followUp.songIds.length;

    return DecoratedBox(
      key: ValueKey<String>(
        'album-studio-follow-up-notice-${followUp.targetEditionId}',
      ),
      decoration: BoxDecoration(
        color: colors.raisedSurface,
        borderRadius: BorderRadius.circular(tokens.metrics.cardRadius),
        border: Border.all(color: colors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              count == 1
                  ? '1 song added to $sourceTitle is not on '
                        '${followUp.targetTitle}.'
                  : '$count songs added to $sourceTitle are not on '
                        '${followUp.targetTitle}.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: colors.textPrimary),
            ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                key: ValueKey<String>(
                  'album-studio-follow-up-review-${followUp.targetEditionId}',
                ),
                onPressed: onReview,
                child: const Text('Review'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

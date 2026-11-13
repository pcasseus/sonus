import 'package:flutter/material.dart';

import '../../../../../core/design/sonus_theme.dart';
import '../../../domain/entities/album_edition_disc_label.dart';

// Release Studio's disc actions (App Update 1.2): choosing where songs go
// and deleting a disc (PATCH-02).

/// Asks which disc [count] songs move to: one of [discs] or a new disc
/// numbered [newDisc]. Null when cancelled.
Future<int?> chooseDestinationDisc(
  BuildContext context, {
  required int count,
  required List<int> discs,
  required Map<int, String> labels,
  int? newDisc,
}) {
  final songs = count == 1 ? '1 song' : '$count songs';
  return showDialog<int>(
    context: context,
    builder: (context) => SimpleDialog(
      key: const ValueKey<String>('album-studio-move-to-disc-dialog'),
      title: Text('Move $songs to'),
      children: [
        for (final disc in discs)
          _Option(
            key: ValueKey<String>('album-studio-move-to-disc-$disc'),
            label: discTitle(disc, label: labels[disc]),
            onPressed: () => Navigator.of(context).pop(disc),
          ),
        if (newDisc != null)
          _Option(
            key: const ValueKey<String>('album-studio-move-to-new-disc'),
            label: 'A new disc (Disc $newDisc)',
            onPressed: () => Navigator.of(context).pop(newDisc),
          ),
        _Option(
          key: const ValueKey<String>('album-studio-move-to-disc-cancel'),
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    ),
  );
}

/// What to do with the songs of a disc being deleted.
sealed class DiscDeletionChoice {
  const DiscDeletionChoice();
}

/// Move them to another disc, chosen next.
class MoveDiscSongs extends DiscDeletionChoice {
  const MoveDiscSongs();
}

/// Remove their listings from this edition; the songs stay in the library.
class RemoveDiscSongs extends DiscDeletionChoice {
  const RemoveDiscSongs();
}

/// Asks what happens to the [songCount] songs of [disc] before it is
/// deleted. [removeBlockedReason], when given, says why they cannot be
/// removed from the edition, and that choice is unavailable. Null when
/// cancelled.
Future<DiscDeletionChoice?> chooseDiscDeletion(
  BuildContext context, {
  required String discName,
  required int songCount,
  String? removeBlockedReason,
}) {
  final songs = songCount == 1 ? '1 song' : '$songCount songs';
  return showDialog<DiscDeletionChoice>(
    context: context,
    builder: (context) {
      final colors = SonusTheme.of(context).colors;
      final theme = Theme.of(context);
      return SimpleDialog(
        key: const ValueKey<String>('album-studio-delete-disc-dialog'),
        title: Text('Delete $discName?'),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              '$discName has $songs. Choose what happens to them. Songs are '
              'never deleted from your library, and their listening history '
              'and playlists stay.',
            ),
          ),
          _Option(
            key: const ValueKey<String>('album-studio-delete-disc-move'),
            label: 'Move the songs to another disc',
            onPressed: () => Navigator.of(context).pop(const MoveDiscSongs()),
          ),
          _Option(
            key: const ValueKey<String>('album-studio-delete-disc-remove'),
            label: 'Remove the songs from this edition',
            onPressed: removeBlockedReason == null
                ? () => Navigator.of(context).pop(const RemoveDiscSongs())
                : null,
          ),
          if (removeBlockedReason != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                removeBlockedReason,
                key: const ValueKey<String>(
                  'album-studio-delete-disc-remove-blocked',
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ),
          _Option(
            key: const ValueKey<String>('album-studio-delete-disc-cancel'),
            label: 'Cancel',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      );
    },
  );
}

/// One disc of a tracklist preview: its title and song titles in order.
class DiscPreview {
  const DiscPreview({required this.title, required this.songs});

  final String title;
  final List<String> songs;
}

/// Shows the edition's tracklist as it will be and asks to go ahead.
/// [removed] lists songs leaving this edition. False when cancelled.
Future<bool> confirmDiscLayout(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  required List<DiscPreview> discs,
  List<String> removed = const [],
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      return AlertDialog(
        key: const ValueKey<String>('album-studio-disc-preview'),
        title: Text(title),
        scrollable: true,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('The edition will be:'),
            for (final disc in discs) ...[
              const SizedBox(height: 12),
              Semantics(
                header: true,
                child: Text(disc.title, style: theme.textTheme.titleSmall),
              ),
              for (final (index, song) in disc.songs.indexed)
                Text('${index + 1}. $song'),
            ],
            if (removed.isNotEmpty) ...[
              const SizedBox(height: 12),
              Semantics(
                header: true,
                child: Text(
                  'Removed from this edition (they stay in your library)',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              for (final song in removed) Text(song),
            ],
          ],
        ),
        actions: [
          TextButton(
            key: const ValueKey<String>('album-studio-disc-preview-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey<String>('album-studio-disc-preview-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return confirmed ?? false;
}

class _Option extends StatelessWidget {
  const _Option({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;
    return SimpleDialogOption(
      onPressed: onPressed,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      child: Text(
        label,
        style: TextStyle(
          color: onPressed == null ? colors.textSecondary : colors.textPrimary,
        ),
      ),
    );
  }
}

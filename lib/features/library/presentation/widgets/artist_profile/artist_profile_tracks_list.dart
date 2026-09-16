import 'dart:async';

import 'package:flutter/material.dart';

import '../../../application/models/library_track.dart';

class ArtistProfileTracksList extends StatelessWidget {
  const ArtistProfileTracksList({
    super.key,
    required this.tracks,
    required this.isTrackPlayable,
    required this.canEditArtwork,
    required this.canEditTrack,
    required this.onPlay,
    required this.onPlayNext,
    required this.onAddToQueue,
    required this.onEditTrack,
    required this.onChangeArtwork,
    required this.onClearArtwork,
  });

  final List<LibraryTrack> tracks;
  final bool Function(LibraryTrack track) isTrackPlayable;
  final bool canEditArtwork;
  final bool canEditTrack;

  final Future<void> Function(LibraryTrack track) onPlay;
  final Future<void> Function(LibraryTrack track) onPlayNext;
  final Future<void> Function(LibraryTrack track) onAddToQueue;
  final Future<void> Function(LibraryTrack track) onEditTrack;
  final Future<void> Function(LibraryTrack track) onChangeArtwork;
  final Future<void> Function(LibraryTrack track) onClearArtwork;

  @override
  Widget build(BuildContext context) {
    if (tracks.isEmpty) {
      return const _EmptySection(message: 'No songs yet');
    }

    return Column(
      key: const ValueKey<String>('artist-profile-tracks-list'),
      children: [
        for (final track in tracks)
          _TrackTile(
            track: track,
            isPlayable: isTrackPlayable(track),
            canEditArtwork: canEditArtwork,
            canEditTrack: canEditTrack,
            onPlay: () => onPlay(track),
            onPlayNext: () => onPlayNext(track),
            onAddToQueue: () => onAddToQueue(track),
            onEditTrack: () => onEditTrack(track),
            onChangeArtwork: () => onChangeArtwork(track),
            onClearArtwork: () => onClearArtwork(track),
          ),
      ],
    );
  }
}

class _TrackTile extends StatelessWidget {
  const _TrackTile({
    required this.track,
    required this.isPlayable,
    required this.canEditArtwork,
    required this.canEditTrack,
    required this.onPlay,
    required this.onPlayNext,
    required this.onAddToQueue,
    required this.onEditTrack,
    required this.onChangeArtwork,
    required this.onClearArtwork,
  });

  final LibraryTrack track;
  final bool isPlayable;
  final bool canEditArtwork;
  final bool canEditTrack;

  final Future<void> Function() onPlay;
  final Future<void> Function() onPlayNext;
  final Future<void> Function() onAddToQueue;
  final Future<void> Function() onEditTrack;
  final Future<void> Function() onChangeArtwork;
  final Future<void> Function() onClearArtwork;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: ListTile(
        key: ValueKey<String>('artist-track-${track.songId}'),
        enabled: isPlayable,
        tileColor: colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        contentPadding: const EdgeInsets.only(left: 12, right: 4),
        leading: SizedBox(
          width: 34,
          child: Center(
            child: Text(
              '${track.trackNumber}',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        title: Text(
          track.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: track.albumTitle.trim().isEmpty
            ? null
            : Text(
                track.albumTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _formatDuration(track.durationSeconds),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            PopupMenuButton<_TrackMenuAction>(
              key: ValueKey<String>('artist-track-menu-${track.songId}'),
              enabled: isPlayable || canEditArtwork || canEditTrack,
              onSelected: (action) {
                switch (action) {
                  case _TrackMenuAction.playNext:
                    unawaited(onPlayNext());
                  case _TrackMenuAction.addToQueue:
                    unawaited(onAddToQueue());
                  case _TrackMenuAction.editDetails:
                    unawaited(onEditTrack());
                  case _TrackMenuAction.changeArtwork:
                    unawaited(onChangeArtwork());
                  case _TrackMenuAction.clearArtwork:
                    unawaited(onClearArtwork());
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: _TrackMenuAction.playNext,
                  enabled: isPlayable,
                  child: const ListTile(
                    leading: Icon(Icons.skip_next_rounded),
                    title: Text('Play next'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: _TrackMenuAction.addToQueue,
                  enabled: isPlayable,
                  child: const ListTile(
                    leading: Icon(Icons.queue_music_rounded),
                    title: Text('Add to queue'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: _TrackMenuAction.editDetails,
                  enabled: canEditTrack,
                  child: const ListTile(
                    leading: Icon(Icons.edit_outlined),
                    title: Text('Edit song details'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: _TrackMenuAction.changeArtwork,
                  enabled: canEditArtwork,
                  child: const ListTile(
                    leading: Icon(Icons.image_rounded),
                    title: Text('Change artwork'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: _TrackMenuAction.clearArtwork,
                  enabled: canEditArtwork,
                  child: const ListTile(
                    leading: Icon(Icons.hide_image_rounded),
                    title: Text('Clear artwork'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ],
        ),
        onTap: isPlayable
            ? () {
                unawaited(onPlay());
              }
            : null,
      ),
    );
  }

  String _formatDuration(int seconds) {
    final safeSeconds = seconds < 0 ? 0 : seconds;
    final minutes = safeSeconds ~/ 60;
    final remainder = safeSeconds % 60;

    return '$minutes:${remainder.toString().padLeft(2, '0')}';
  }
}

enum _TrackMenuAction {
  playNext,
  addToQueue,
  editDetails,
  changeArtwork,
  clearArtwork,
}

class _EmptySection extends StatelessWidget {
  const _EmptySection({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: Text(message, style: Theme.of(context).textTheme.bodyMedium),
      ),
    );
  }
}

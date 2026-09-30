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
    required this.canSetBlocked,
    required this.onPlay,
    required this.onPlayNext,
    required this.onAddToQueue,
    required this.onAddToPlaylist,
    required this.onEditTrack,
    required this.onChangeArtwork,
    required this.onClearArtwork,
    required this.onSetBlocked,
  });

  final List<LibraryTrack> tracks;
  final bool Function(LibraryTrack track) isTrackPlayable;
  final bool canEditArtwork;
  final bool canEditTrack;
  final bool canSetBlocked;

  final Future<void> Function(LibraryTrack track) onPlay;
  final Future<void> Function(LibraryTrack track) onPlayNext;
  final Future<void> Function(LibraryTrack track) onAddToQueue;
  final Future<void> Function(LibraryTrack track) onAddToPlaylist;
  final Future<void> Function(LibraryTrack track) onEditTrack;
  final Future<void> Function(LibraryTrack track) onChangeArtwork;
  final Future<void> Function(LibraryTrack track) onClearArtwork;
  final Future<void> Function(LibraryTrack track, bool isBlocked) onSetBlocked;

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
            canSetBlocked: canSetBlocked,
            onPlay: () => onPlay(track),
            onPlayNext: () => onPlayNext(track),
            onAddToQueue: () => onAddToQueue(track),
            onAddToPlaylist: () => onAddToPlaylist(track),
            onEditTrack: () => onEditTrack(track),
            onChangeArtwork: () => onChangeArtwork(track),
            onClearArtwork: () => onClearArtwork(track),
            onSetBlocked: (isBlocked) => onSetBlocked(track, isBlocked),
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
    required this.canSetBlocked,
    required this.onPlay,
    required this.onPlayNext,
    required this.onAddToQueue,
    required this.onAddToPlaylist,
    required this.onEditTrack,
    required this.onChangeArtwork,
    required this.onClearArtwork,
    required this.onSetBlocked,
  });

  final LibraryTrack track;
  final bool isPlayable;
  final bool canEditArtwork;
  final bool canEditTrack;
  final bool canSetBlocked;

  final Future<void> Function() onPlay;
  final Future<void> Function() onPlayNext;
  final Future<void> Function() onAddToQueue;
  final Future<void> Function() onAddToPlaylist;
  final Future<void> Function() onEditTrack;
  final Future<void> Function() onChangeArtwork;
  final Future<void> Function() onClearArtwork;
  final Future<void> Function(bool isBlocked) onSetBlocked;

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
        subtitle: _subtitle(track, theme, colorScheme),
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
              enabled:
                  isPlayable || canEditArtwork || canEditTrack || canSetBlocked,
              onSelected: (action) {
                switch (action) {
                  case _TrackMenuAction.playNext:
                    unawaited(onPlayNext());
                  case _TrackMenuAction.addToQueue:
                    unawaited(onAddToQueue());
                  case _TrackMenuAction.addToPlaylist:
                    unawaited(onAddToPlaylist());
                  case _TrackMenuAction.editDetails:
                    unawaited(onEditTrack());
                  case _TrackMenuAction.changeArtwork:
                    unawaited(onChangeArtwork());
                  case _TrackMenuAction.clearArtwork:
                    unawaited(onClearArtwork());
                  case _TrackMenuAction.toggleBlocked:
                    unawaited(onSetBlocked(!track.isSongBlocked));
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
                  value: _TrackMenuAction.addToPlaylist,
                  child: const ListTile(
                    leading: Icon(Icons.playlist_add_rounded),
                    title: Text('Add to playlist'),
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
                  value: _TrackMenuAction.toggleBlocked,
                  enabled: canSetBlocked,
                  child: ListTile(
                    leading: Icon(
                      track.isSongBlocked
                          ? Icons.lock_open_rounded
                          : Icons.block_rounded,
                    ),
                    title: Text(
                      track.isSongBlocked
                          ? 'Remove from blacklist'
                          : 'Blacklist song',
                    ),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuDivider(),
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

  Widget? _subtitle(
    LibraryTrack track,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final parts = <String>[];

    if (track.isBlocked) {
      parts.add('Blacklisted');
    } else if (!track.isAvailable ||
        track.filePath == null ||
        track.filePath!.trim().isEmpty) {
      parts.add('Unavailable');
    }

    final albumTitle = track.albumTitle.trim();

    if (albumTitle.isNotEmpty) {
      parts.add(albumTitle);
    }

    if (parts.isEmpty) {
      return null;
    }

    return Text(
      parts.join(' \u2022 '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodySmall?.copyWith(
        color: colorScheme.onSurfaceVariant,
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
  addToPlaylist,
  editDetails,
  changeArtwork,
  clearArtwork,
  toggleBlocked,
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

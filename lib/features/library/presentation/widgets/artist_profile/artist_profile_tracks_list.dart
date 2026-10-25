import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../../core/design/sonus_theme.dart';
import '../../../application/models/library_track.dart';

/// Text scale above which rows switch to their large-text layout, as in
/// the shared Sonus data components.
const double _largeTextScale = 1.3;

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
    this.keyPrefix = 'artist-track',
    this.streamCounts,
    this.tileColor,
    this.profileArtistId,
  });

  final List<LibraryTrack> tracks;

  /// When given, rows whose primary artist is someone else name them.
  final String? profileArtistId;

  /// Prefix of each row's key (`<prefix>-<songId>`) and menu key
  /// (`<prefix>-menu-<songId>`), so one song can appear in two sections.
  final String keyPrefix;

  /// All-time qualified streams per song. When given, rows show their rank
  /// and stream count, in the order of [tracks].
  final Map<String, int>? streamCounts;

  final Color? tileColor;
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

    final largeText =
        MediaQuery.textScalerOf(context).scale(1) > _largeTextScale;

    return Column(
      key: ValueKey<String>('$keyPrefix-list'),
      children: [
        for (final (index, track) in tracks.indexed)
          _TrackTile(
            track: track,
            keyPrefix: keyPrefix,
            rank: streamCounts == null ? null : index + 1,
            streamCount: streamCounts?[track.songId],
            largeText: largeText,
            tileColor: tileColor,
            showArtist:
                profileArtistId != null && track.artistId != profileArtistId,
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
    required this.keyPrefix,
    required this.rank,
    required this.streamCount,
    required this.largeText,
    required this.tileColor,
    required this.showArtist,
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
  final String keyPrefix;
  final int? rank;
  final int? streamCount;
  final bool largeText;
  final Color? tileColor;
  final bool showArtist;
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
    final colors = SonusTheme.of(context).colors;
    final rank = this.rank;
    const tabular = [FontFeature.tabularFigures()];
    final duration = _formatDuration(track.durationSeconds);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: ListTile(
        key: ValueKey<String>('$keyPrefix-${track.songId}'),
        enabled: isPlayable,
        tileColor: tileColor ?? colors.surface,
        textColor: colors.textPrimary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            SonusTheme.of(context).metrics.cardRadius,
          ),
        ),
        contentPadding: const EdgeInsets.only(left: 12, right: 4),
        minVerticalPadding: 8,
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The rank column would squeeze titles at large text sizes.
            if (rank != null && !largeText)
              SizedBox(
                width: 26,
                child: Text(
                  '$rank',
                  key: ValueKey<String>('$keyPrefix-rank-${track.songId}'),
                  maxLines: 1,
                  softWrap: false,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: colors.textSecondary,
                    fontWeight: FontWeight.w800,
                    fontFeatures: tabular,
                  ),
                ),
              ),
            _TrackArtwork(track: track, size: 44),
          ],
        ),
        title: Text(
          track.title,
          maxLines: largeText ? 3 : 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: _subtitle(
          track,
          theme,
          colors.textSecondary,
          duration: largeText ? duration : null,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!largeText)
              Text(
                duration,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                  fontFeatures: tabular,
                ),
              ),
            PopupMenuButton<_TrackMenuAction>(
              key: ValueKey<String>('$keyPrefix-menu-${track.songId}'),
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
                  case _TrackMenuAction.trackStudio:
                    unawaited(onEditTrack());
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
                  value: _TrackMenuAction.trackStudio,
                  enabled: canEditTrack || canEditArtwork,
                  child: const ListTile(
                    leading: Icon(Icons.edit_outlined),
                    title: Text('Track Studio'),
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
    Color color, {
    String? duration,
  }) {
    final parts = <String>[];

    if (track.isBlocked) {
      parts.add('Blacklisted');
    } else if (!track.isAvailable ||
        track.filePath == null ||
        track.filePath!.trim().isEmpty) {
      parts.add('Unavailable');
    }

    final streamCount = this.streamCount;

    if (streamCount != null) {
      parts.add(streamCount == 1 ? '1 stream' : '$streamCount streams');
    }

    final artistName = track.artistName.trim();

    if (showArtist && artistName.isNotEmpty) {
      parts.add(artistName);
    }

    final albumTitle = track.albumTitle.trim();

    if (albumTitle.isNotEmpty) {
      parts.add(albumTitle);
    }

    if (duration != null) {
      parts.add(duration);
    }

    if (parts.isEmpty) {
      return null;
    }

    return Text(
      parts.join(' • '),
      maxLines: largeText ? 3 : 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodySmall?.copyWith(
        color: color,
        fontFeatures: const [FontFeature.tabularFigures()],
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
  trackStudio,
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
        child: Text(
          message,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: SonusTheme.of(context).colors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _TrackArtwork extends StatelessWidget {
  const _TrackArtwork({required this.track, required this.size});

  final LibraryTrack track;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final path = track.artworkPath?.trim();
    final fallback = ColoredBox(
      color: tokens.colors.artworkPlaceholder,
      child: Icon(
        Icons.music_note_rounded,
        size: size * 0.5,
        color: tokens.colors.onArtworkPlaceholder,
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(tokens.metrics.artworkRadius / 2),
      child: SizedBox.square(
        dimension: size,
        child: path == null || path.isEmpty
            ? fallback
            : Image.file(
                File(path),
                fit: BoxFit.cover,
                // Decoded at its display size, never at full resolution.
                cacheWidth: (size * MediaQuery.devicePixelRatioOf(context))
                    .round(),
                errorBuilder: (context, error, stackTrace) => fallback,
              ),
      ),
    );
  }
}

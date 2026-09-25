import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../application/controllers/playback_coordinator.dart';
import '../../domain/models/lyric_line.dart';
import '../../domain/models/track_lyrics.dart';
import '../controllers/lyrics_controller.dart';
import '../controllers/lyrics_state.dart';
import '../controllers/playback_state_controller.dart';

class LyricsPage extends StatelessWidget {
  const LyricsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final playbackState = context.watch<PlaybackStateController>().state;
    final lyricsController = context.watch<LyricsController?>();
    final track = playbackState.queue.currentTrack;

    return Scaffold(
      key: const ValueKey<String>('lyrics-page'),
      appBar: AppBar(
        leading: IconButton(
          key: const ValueKey<String>('lyrics-close'),
          tooltip: 'Close',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
        ),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Lyrics'),
            if (track != null)
              Text(
                track.title,
                key: const ValueKey<String>('lyrics-track-title'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium,
              ),
          ],
        ),
        centerTitle: true,
      ),
      body: track == null
          ? const _LyricsMessage(
              key: ValueKey<String>('lyrics-no-track'),
              icon: Icons.music_note_rounded,
              title: 'Nothing is playing',
              message: 'Play a song to view its lyrics.',
            )
          : lyricsController == null
          ? const _LyricsLoading(key: ValueKey<String>('lyrics-initializing'))
          : _LyricsBody(
              state: lyricsController.state,
              playbackPosition: playbackState.position,
            ),
    );
  }
}

class _LyricsBody extends StatelessWidget {
  const _LyricsBody({required this.state, required this.playbackPosition});

  final LyricsState state;
  final Duration playbackPosition;

  @override
  Widget build(BuildContext context) {
    switch (state.status) {
      case LyricsStatus.idle:
      case LyricsStatus.loading:
        return const _LyricsLoading(key: ValueKey<String>('lyrics-loading'));

      case LyricsStatus.empty:
        return const _LyricsMessage(
          key: ValueKey<String>('lyrics-empty'),
          icon: Icons.lyrics_outlined,
          title: 'No lyrics available',
          message: 'Lyrics have not been saved for this song yet.',
        );

      case LyricsStatus.failed:
        return const _LyricsMessage(
          key: ValueKey<String>('lyrics-error'),
          icon: Icons.error_outline_rounded,
          title: 'Lyrics unavailable',
          message: 'The saved lyrics could not be loaded.',
        );

      case LyricsStatus.loaded:
        final lyrics = state.lyrics;

        if (lyrics == null || !lyrics.hasLyrics) {
          return const _LyricsMessage(
            key: ValueKey<String>('lyrics-empty'),
            icon: Icons.lyrics_outlined,
            title: 'No lyrics available',
            message: 'Lyrics have not been saved for this song yet.',
          );
        }

        if (lyrics.hasSyncedLyrics) {
          return _SyncedLyricsView(
            lyrics: lyrics,
            playbackPosition: playbackPosition,
          );
        }

        return _PlainLyricsView(lyrics: lyrics);
    }
  }
}

class _SyncedLyricsView extends StatefulWidget {
  const _SyncedLyricsView({
    required this.lyrics,
    required this.playbackPosition,
  });

  final TrackLyrics lyrics;
  final Duration playbackPosition;

  @override
  State<_SyncedLyricsView> createState() => _SyncedLyricsViewState();
}

class _SyncedLyricsViewState extends State<_SyncedLyricsView> {
  static const double _estimatedLineExtent = 76;

  final ScrollController _scrollController = ScrollController();

  int? _activeIndex;

  @override
  void initState() {
    super.initState();
    _activeIndex = _findActiveIndex();
    _scheduleFollow();
  }

  @override
  void didUpdateWidget(covariant _SyncedLyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);

    final nextActiveIndex = _findActiveIndex();

    if (nextActiveIndex != _activeIndex ||
        oldWidget.lyrics.songId != widget.lyrics.songId) {
      _activeIndex = nextActiveIndex;
      _scheduleFollow();
    }
  }

  int? _findActiveIndex() {
    final activeLine = widget.lyrics.activeLineAt(widget.playbackPosition);

    if (activeLine == null) {
      return null;
    }

    final index = widget.lyrics.syncedLines.indexOf(activeLine);
    return index < 0 ? null : index;
  }

  void _scheduleFollow() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients || _activeIndex == null) {
        return;
      }

      final viewport = _scrollController.position.viewportDimension;
      final target =
          (_activeIndex! * _estimatedLineExtent) -
          (viewport / 2) +
          (_estimatedLineExtent / 2);

      final clamped = target.clamp(
        _scrollController.position.minScrollExtent,
        _scrollController.position.maxScrollExtent,
      );

      _scrollController.animateTo(
        clamped.toDouble(),
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final lines = widget.lyrics.syncedLines;
    final coordinator = context.read<PlaybackCoordinator>();

    return ListView.builder(
      key: const ValueKey<String>('synced-lyrics-list'),
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 48),
      itemCount: lines.length,
      itemBuilder: (context, index) {
        final line = lines[index];
        final isActive = index == _activeIndex;

        return _SyncedLyricLine(
          line: line,
          index: index,
          isActive: isActive,
          onTap: () {
            unawaited(coordinator.seek(line.timestamp));
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}

class _SyncedLyricLine extends StatelessWidget {
  const _SyncedLyricLine({
    required this.line,
    required this.index,
    required this.isActive,
    required this.onTap,
  });

  final LyricLine line;
  final int index;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Semantics(
      button: true,
      selected: isActive,
      label: isActive ? 'Current lyric: ${line.text}' : line.text,
      child: InkWell(
        key: ValueKey<String>('lyrics-line-$index'),
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: AnimatedContainer(
          key: ValueKey<String>('lyrics-line-container-$index'),
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 68),
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: isActive ? colorScheme.primaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            line.text,
            key: isActive ? const ValueKey<String>('lyrics-active-line') : null,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              color: isActive
                  ? colorScheme.onPrimaryContainer
                  : colorScheme.onSurfaceVariant,
              fontWeight: isActive ? FontWeight.w800 : FontWeight.w500,
              height: 1.35,
            ),
          ),
        ),
      ),
    );
  }
}

class _PlainLyricsView extends StatelessWidget {
  const _PlainLyricsView({required this.lyrics});

  final TrackLyrics lyrics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      key: const ValueKey<String>('plain-lyrics-scroll'),
      padding: const EdgeInsets.fromLTRB(28, 32, 28, 48),
      child: SelectionArea(
        child: Text(
          lyrics.plainText!.trim(),
          key: const ValueKey<String>('plain-lyrics-text'),
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.7,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _LyricsLoading extends StatelessWidget {
  const _LyricsLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SizedBox.square(
        dimension: 32,
        child: CircularProgressIndicator(strokeWidth: 3),
      ),
    );
  }
}

class _LyricsMessage extends StatelessWidget {
  const _LyricsMessage({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

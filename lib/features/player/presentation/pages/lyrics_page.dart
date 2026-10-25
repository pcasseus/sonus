import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/design/widgets/playback/sonus_lyrics_view.dart';
import '../../../../core/design/widgets/sonus_artwork_atmosphere_builder.dart';
import '../../../../core/design/widgets/sonus_state_view.dart';
import '../../application/controllers/playback_coordinator.dart';
import '../../domain/models/track_lyrics.dart';
import '../controllers/lyrics_controller.dart';
import '../controllers/lyrics_state.dart';
import '../controllers/playback_state_controller.dart';

class LyricsPage extends StatefulWidget {
  const LyricsPage({super.key});

  @override
  State<LyricsPage> createState() => _LyricsPageState();
}

class _LyricsPageState extends State<LyricsPage> {
  @override
  void initState() {
    super.initState();
    // Lyrics can be imported or changed while a song plays; opening the
    // page reads them again (unless a read is already under way).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final controller = context.read<LyricsController?>();
      if (controller != null &&
          controller.state.status != LyricsStatus.loading) {
        unawaited(controller.reload());
      }
    });
  }

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
          ? const SonusStateView(
              key: ValueKey<String>('lyrics-no-track'),
              icon: Icons.music_note_rounded,
              title: 'Nothing is playing',
              message: 'Play a song to view its lyrics.',
            )
          : lyricsController == null
          ? const SonusStateView.loading(
              key: ValueKey<String>('lyrics-initializing'),
            )
          : SonusArtworkAtmosphereBuilder(
              artworkPath: track.artworkPath,
              builder: (context, atmosphere) => _LyricsBody(
                state: lyricsController.state,
                playbackPosition: playbackState.position,
                accentColor: atmosphere.isTinted ? atmosphere.accent : null,
              ),
            ),
    );
  }
}

class _LyricsBody extends StatelessWidget {
  const _LyricsBody({
    required this.state,
    required this.playbackPosition,
    required this.accentColor,
  });

  final LyricsState state;
  final Duration playbackPosition;
  final Color? accentColor;

  static const _empty = SonusStateView(
    key: ValueKey<String>('lyrics-empty'),
    icon: Icons.lyrics_outlined,
    title: 'No lyrics available',
    message: 'Lyrics have not been saved for this song yet.',
  );

  @override
  Widget build(BuildContext context) {
    switch (state.status) {
      case LyricsStatus.idle:
      case LyricsStatus.loading:
        return const SonusStateView.loading(
          key: ValueKey<String>('lyrics-loading'),
        );

      case LyricsStatus.empty:
        return _empty;

      case LyricsStatus.failed:
        return SonusStateView(
          key: const ValueKey<String>('lyrics-error'),
          icon: Icons.error_outline_rounded,
          title: 'Lyrics unavailable',
          message: 'The saved lyrics could not be loaded.',
          isError: true,
          action: TextButton(
            key: const ValueKey<String>('lyrics-retry'),
            onPressed: () {
              unawaited(context.read<LyricsController?>()?.reload());
            },
            child: const Text('Try again'),
          ),
        );

      case LyricsStatus.loaded:
        final lyrics = state.lyrics;

        if (lyrics == null || !lyrics.hasLyrics) return _empty;

        return _LyricsLines(
          lyrics: lyrics,
          playbackPosition: playbackPosition,
          accentColor: accentColor,
        );
    }
  }
}

/// Maps saved lyrics onto the Sonus lyrics view. Timings are passed through
/// unchanged, and the current line is the one [TrackLyrics.activeLineAt]
/// chooses, as before.
class _LyricsLines extends StatefulWidget {
  const _LyricsLines({
    required this.lyrics,
    required this.playbackPosition,
    required this.accentColor,
  });

  final TrackLyrics lyrics;
  final Duration playbackPosition;
  final Color? accentColor;

  @override
  State<_LyricsLines> createState() => _LyricsLinesState();
}

class _LyricsLinesState extends State<_LyricsLines> {
  TrackLyrics? _mappedFrom;
  List<SonusLyricLine> _lines = const [];

  /// Mapped once per lyrics, not on every position update, so the view
  /// only re-follows when the song's lines really change.
  List<SonusLyricLine> _linesFor(TrackLyrics lyrics) {
    if (!identical(lyrics, _mappedFrom)) {
      _mappedFrom = lyrics;
      _lines = lyrics.hasSyncedLyrics
          ? [
              for (final line in lyrics.syncedLines)
                SonusLyricLine(text: line.text, start: line.timestamp),
            ]
          : [SonusLyricLine(text: lyrics.plainText!.trim())];
    }
    return _lines;
  }

  @override
  Widget build(BuildContext context) {
    final lyrics = widget.lyrics;
    final synced = lyrics.hasSyncedLyrics;
    final coordinator = context.read<PlaybackCoordinator>();
    final active = synced ? lyrics.activeLineAt(widget.playbackPosition) : null;

    return SonusLyricsView(
      lines: _linesFor(lyrics),
      position: widget.playbackPosition,
      activeIndex: synced
          ? (active == null ? -1 : lyrics.syncedLines.indexOf(active))
          : null,
      accentColor: widget.accentColor,
      scrollKey: ValueKey<String>(
        synced ? 'synced-lyrics-list' : 'plain-lyrics-scroll',
      ),
      lineKeyPrefix: 'lyrics',
      plainTextKey: const ValueKey<String>('plain-lyrics-text'),
      onSeek: (position) {
        unawaited(coordinator.seek(position));
      },
    );
  }
}

import 'package:flutter/material.dart';

import '../../../../../core/design/sonus_theme.dart';
import '../../../../../core/design/widgets/sonus_artwork_frame.dart';
import '../../../../../core/design/widgets/sonus_decorations.dart';

enum AppearancePreviewKind { home, nowPlaying }

/// A live sample of Home or Now Playing in the active appearance.
///
/// It uses placeholder labels rather than library data, never touches
/// playback, and its controls only move the sample itself.
class AppearancePreview extends StatefulWidget {
  const AppearancePreview({super.key});

  @override
  State<AppearancePreview> createState() => _AppearancePreviewState();
}

class _AppearancePreviewState extends State<AppearancePreview> {
  AppearancePreviewKind _kind = AppearancePreviewKind.home;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<AppearancePreviewKind>(
          key: const ValueKey<String>('appearance-preview-toggle'),
          segments: const [
            ButtonSegment(
              value: AppearancePreviewKind.home,
              label: Text('Home'),
              icon: Icon(Icons.home_outlined),
            ),
            ButtonSegment(
              value: AppearancePreviewKind.nowPlaying,
              label: Text('Now Playing'),
              icon: Icon(Icons.play_circle_outline_rounded),
            ),
          ],
          selected: {_kind},
          onSelectionChanged: (selection) {
            setState(() => _kind = selection.single);
          },
        ),
        SizedBox(height: tokens.metrics.spaceMd),
        DecoratedBox(
          key: const ValueKey<String>('appearance-preview'),
          decoration: BoxDecoration(
            color: tokens.colors.background,
            borderRadius: BorderRadius.circular(tokens.metrics.cardRadius),
            border: Border.all(color: tokens.colors.divider),
          ),
          child: Padding(
            padding: EdgeInsets.all(tokens.metrics.spaceLg),
            child: switch (_kind) {
              AppearancePreviewKind.home => const _HomePreview(),
              AppearancePreviewKind.nowPlaying => const _NowPlayingPreview(),
            },
          ),
        ),
      ],
    );
  }
}

class _HomePreview extends StatelessWidget {
  const _HomePreview();

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);

    return Column(
      key: const ValueKey<String>('appearance-preview-home'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          children: [
            const Positioned.fill(child: SonusSurfaceTexture()),
            const SonusSectionHeading(title: 'Your week'),
          ],
        ),
        SizedBox(height: tokens.metrics.spaceMd),
        const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _PreviewCard(rank: 1, title: 'Sample song')),
            SizedBox(width: 12),
            Expanded(child: _PreviewCard(rank: 2, title: 'Another song')),
          ],
        ),
      ],
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.rank, required this.title});

  final int rank;
  final String title;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final textTheme = Theme.of(context).textTheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                SonusArtworkFrame(
                  size: constraints.maxWidth,
                  child: const SonusArtworkPlaceholder(iconSize: 32),
                ),
                Positioned(
                  top: 8,
                  left: 8,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: tokens.colors.accentPrimary,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: Text(
                        '#$rank',
                        semanticsLabel: 'Rank $rank',
                        style: textTheme.labelMedium?.copyWith(
                          color: tokens.colors.onAccentPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: tokens.metrics.spaceSm),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: textTheme.titleSmall?.copyWith(
                color: tokens.colors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              'Sample artist',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodySmall?.copyWith(
                color: tokens.colors.textSecondary,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _NowPlayingPreview extends StatefulWidget {
  const _NowPlayingPreview();

  @override
  State<_NowPlayingPreview> createState() => _NowPlayingPreviewState();
}

class _NowPlayingPreviewState extends State<_NowPlayingPreview> {
  static const _sampleLength = Duration(minutes: 3, seconds: 30);

  bool _playing = false;
  double _position = 0.35;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final elapsed = _sampleLength * _position;

    return Column(
      key: const ValueKey<String>('appearance-preview-now-playing'),
      children: [
        const SonusArtworkFrame(
          size: 132,
          child: SonusArtworkPlaceholder(iconSize: 48),
        ),
        SizedBox(height: tokens.metrics.spaceMd),
        Text(
          'Sample song',
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: textTheme.titleLarge?.copyWith(
            color: tokens.colors.textPrimary,
          ),
        ),
        Text(
          'Sample artist',
          textAlign: TextAlign.center,
          style: textTheme.bodyMedium?.copyWith(
            color: tokens.colors.textSecondary,
          ),
        ),
        Slider(
          key: const ValueKey<String>('appearance-preview-seek'),
          value: _position,
          semanticFormatterCallback: (value) =>
              '${_format(_sampleLength * value)} of ${_format(_sampleLength)}',
          onChanged: (value) => setState(() => _position = value),
        ),
        Row(
          children: [
            Text(_format(elapsed), style: tokens.text.numeric),
            const Spacer(),
            Text(_format(_sampleLength), style: tokens.text.numeric),
          ],
        ),
        IconButton.filled(
          key: const ValueKey<String>('appearance-preview-play-pause'),
          tooltip: _playing ? 'Pause preview' : 'Play preview',
          iconSize: 32,
          style: IconButton.styleFrom(
            backgroundColor: tokens.colors.playbackControl,
            foregroundColor: tokens.colors.onPlaybackControl,
          ),
          onPressed: () => setState(() => _playing = !_playing),
          icon: Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
        ),
      ],
    );
  }

  static String _format(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;

    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

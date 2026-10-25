import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../sonus_theme.dart';
import '../sonus_state_view.dart';

/// One lyric line. [start] is null for unsynchronised lyrics. Players map
/// their parsed lines (timings unchanged) to this.
@immutable
class SonusLyricLine {
  const SonusLyricLine({required this.text, this.start});

  final String text;
  final Duration? start;
}

/// Immersive lyrics (SN-48E): large readable lines, the current line
/// highlighted and kept in view while it plays.
///
/// Scrolling by hand pauses following; "Back to current line" resumes it.
/// With reduced motion the view jumps instead of gliding. Unsynchronised
/// lyrics show as plain text with no highlight; no lines shows a message.
/// Timing comes only from [lines] and [position]: nothing is re-timed.
class SonusLyricsView extends StatefulWidget {
  const SonusLyricsView({
    super.key,
    required this.lines,
    required this.position,
    this.onSeek,
    this.accentColor,
  });

  final List<SonusLyricLine> lines;
  final Duration position;

  /// Tapping a synchronised line seeks to it, when given.
  final ValueChanged<Duration>? onSeek;
  final Color? accentColor;

  @override
  State<SonusLyricsView> createState() => _SonusLyricsViewState();
}

class _SonusLyricsViewState extends State<SonusLyricsView> {
  final _scrollController = ScrollController();
  final _lineKeys = <int, GlobalKey>{};
  bool _following = true;
  int _shownActive = -1;

  bool get _synced =>
      widget.lines.isNotEmpty && widget.lines.every((l) => l.start != null);

  /// The last line whose start has passed, or -1 before the first line.
  int get _active {
    if (!_synced) return -1;
    var active = -1;
    for (var i = 0; i < widget.lines.length; i++) {
      if (widget.lines[i].start! <= widget.position) {
        active = i;
      } else {
        break;
      }
    }
    return active;
  }

  GlobalKey _keyFor(int index) => _lineKeys.putIfAbsent(index, GlobalKey.new);

  void _follow(int active) {
    if (!_following || active < 0 || active == _shownActive) return;
    _shownActive = active;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _keyFor(active).currentContext;
      if (!mounted || context == null) return;
      final tokens = SonusTheme.of(this.context);
      final reduce =
          tokens.motion.reduced || MediaQuery.disableAnimationsOf(this.context);
      Scrollable.ensureVisible(
        context,
        alignment: 0.35,
        duration: reduce ? Duration.zero : tokens.motion.baseMedium,
        curve: tokens.motion.curve,
      );
    });
  }

  bool _onScroll(UserScrollNotification notification) {
    if (notification.direction != ScrollDirection.idle && _following) {
      setState(() => _following = false);
    }
    return false;
  }

  void _resume() {
    setState(() {
      _following = true;
      _shownActive = -1;
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.lines.isEmpty) {
      return const SonusStateView(
        key: ValueKey<String>('sonus-lyrics-empty'),
        icon: Icons.lyrics_outlined,
        title: 'No lyrics for this song',
        message: 'Lyrics appear here when a lyrics file is available.',
      );
    }

    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final theme = Theme.of(context);
    final accent = widget.accentColor ?? colors.accentPrimary;
    final active = _active;
    _follow(active);

    final base = theme.textTheme.headlineSmall?.copyWith(
      fontWeight: FontWeight.w800,
      height: 1.3,
    );

    final list = NotificationListener<UserScrollNotification>(
      onNotification: _onScroll,
      child: SingleChildScrollView(
        key: const PageStorageKey<String>('sonus-lyrics-scroll'),
        controller: _scrollController,
        padding: EdgeInsets.fromLTRB(
          tokens.metrics.pageGutter,
          24,
          tokens.metrics.pageGutter,
          120,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < widget.lines.length; i++)
              _LyricLine(
                key: _keyFor(i),
                text: widget.lines[i].text,
                state: !_synced
                    ? _LineState.plain
                    : i == active
                    ? _LineState.active
                    : i < active
                    ? _LineState.past
                    : _LineState.upcoming,
                style: base,
                accent: accent,
                onTap: _synced && widget.onSeek != null
                    ? () => widget.onSeek!(widget.lines[i].start!)
                    : null,
              ),
          ],
        ),
      ),
    );

    return Stack(
      children: [
        Positioned.fill(child: list),
        if (_synced && !_following)
          Positioned(
            left: 0,
            right: 0,
            bottom: 24,
            child: Center(
              child: FilledButton.tonalIcon(
                key: const ValueKey<String>('sonus-lyrics-resume'),
                onPressed: _resume,
                icon: const Icon(Icons.my_location_rounded),
                label: const Text('Back to current line'),
              ),
            ),
          ),
      ],
    );
  }
}

enum _LineState { plain, past, active, upcoming }

class _LyricLine extends StatelessWidget {
  const _LyricLine({
    super.key,
    required this.text,
    required this.state,
    required this.style,
    required this.accent,
    required this.onTap,
  });

  final String text;
  final _LineState state;
  final TextStyle? style;
  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;
    // Colour and weight both mark the current line, never colour alone.
    final color = switch (state) {
      _LineState.active => accent,
      _LineState.plain => colors.textPrimary,
      _LineState.past || _LineState.upcoming => colors.textSecondary,
    };
    final isActive = state == _LineState.active;
    final display = text.trim().isEmpty ? '♪' : text;

    return Semantics(
      selected: isActive,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Text(
            display,
            style: style?.copyWith(
              color: color,
              fontWeight: isActive ? FontWeight.w900 : FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

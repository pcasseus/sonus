import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';

import '../../../../core/design/sonus_theme.dart';
import '../../../../core/design/widgets/sonus_state_view.dart';
import '../../../library/application/models/library_album.dart';
import '../../../library/application/models/library_track.dart';
import '../../../library/application/repositories/library_query_repository.dart';
import '../../application/models/chart_moment_feed_item.dart';
import '../../application/services/chart_moment_feed_aggregator.dart';
import '../../domain/models/chart_type.dart';
import '../../domain/repositories/chart_moment_repository.dart';
import '../formatters/chart_moment_feed_copy_formatter.dart';
import '../models/chart_moment_feed_copy.dart';
import 'sonus_news_feed_view.dart';
import 'sonus_news_story.dart';

/// A full page for the Sonus News Feed, fed by the same Chart Moments
/// repository and aggregator as the Charts Moments view. It reads only;
/// it never detects, writes or recalculates Moments.
///
/// Integration contract (SN-48G): the Charts experience opens it with
/// `Navigator.push(MaterialPageRoute(builder: (_) => SonusNewsFeedPage(
/// moments: ..., library: ...)))`, or embeds [SonusNewsFeedView] with
/// stories from [SonusNewsDesk]. Not yet linked from Charts, whose files
/// are being changed by the functional rankings work.
class SonusNewsFeedPage extends StatefulWidget {
  const SonusNewsFeedPage({
    super.key,
    required this.moments,
    this.library,
    this.copyFor,
    this.aggregator = const ChartMomentFeedAggregator(),
  });

  final ChartMomentRepository? moments;

  /// Supplies artwork for stories; optional.
  final LibraryQueryRepository? library;

  /// The Moments copy; the shared Charts formatter by default.
  final ChartMomentFeedCopy Function(ChartMomentFeedItem item)? copyFor;
  final ChartMomentFeedAggregator aggregator;

  @override
  State<SonusNewsFeedPage> createState() => _SonusNewsFeedPageState();
}

class _SonusNewsFeedPageState extends State<SonusNewsFeedPage> {
  List<SonusNewsStory> _stories = const [];
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final moments = widget.moments;

    if (moments == null) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      final items = widget.aggregator.aggregate(await moments.getRecent());
      final artwork = await _artwork(items);
      final copy =
          widget.copyFor ?? const ChartMomentFeedCopyFormatter().format;
      final stories = SonusNewsDesk(
        copyFor: copy,
        artworkFor: (item) => artwork(item.chartType, item.entity.entityId),
        relatedArtworkFor: (item) {
          final related = item.relatedEntity;
          return related == null
              ? null
              : artwork(item.chartType, related.entityId);
        },
      ).stories(items);

      if (!mounted) return;
      setState(() {
        _stories = stories;
        _isLoading = false;
      });
    } catch (error, stackTrace) {
      developer.log(
        'Could not load Sonus News (${error.runtimeType})',
        name: 'sonus.charts.news',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _isLoading = false;
      });
    }
  }

  /// Artwork lookups by chart and entity, read once per load.
  Future<String? Function(ChartType, String)> _artwork(
    List<ChartMomentFeedItem> items,
  ) async {
    final library = widget.library;

    if (library == null || items.isEmpty) {
      return (ChartType _, String _) => null;
    }

    final results = await Future.wait<Object>([
      library.getTracks(),
      library.getAlbums(),
    ]);
    final tracks = {
      for (final track in results[0] as List<LibraryTrack>)
        track.songId: track.artworkPath,
    };
    final albums = {
      for (final album in results[1] as List<LibraryAlbum>)
        album.albumId: album.artworkPath,
    };

    return (ChartType type, String id) => switch (type) {
      ChartType.songs => tracks[id],
      ChartType.albums => albums[id],
    };
  }

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;

    return Scaffold(
      key: const ValueKey<String>('sonus-news-page'),
      backgroundColor: colors.background,
      appBar: AppBar(
        title: const Text('Sonus News'),
        backgroundColor: colors.background,
        surfaceTintColor: Colors.transparent,
      ),
      body: _isLoading
          ? const SonusStateView.loading()
          : _hasError
          ? SonusStateView(
              key: const ValueKey<String>('sonus-news-error'),
              icon: Icons.error_outline_rounded,
              isError: true,
              title: 'Could not load Sonus News.',
              action: FilledButton.tonalIcon(
                onPressed: () {
                  unawaited(_load());
                },
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try again'),
              ),
            )
          : SonusNewsFeedView(stories: _stories, onRefresh: _load),
    );
  }
}

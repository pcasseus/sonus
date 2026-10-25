import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/design/sonus_theme.dart';
import '../../../../core/design/widgets/sonus_page_header.dart';
import '../../../../core/design/widgets/sonus_state_view.dart';
import '../../application/models/library_artist.dart';
import '../../application/models/library_track.dart';
import '../../application/repositories/library_query_repository.dart';
import '../controllers/library_artists_controller.dart';
import '../widgets/library_artist_card.dart';
import 'artist_profile_page.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  LibraryArtistsController? _controller;
  LibraryQueryRepository? _repository;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final repository = context.watch<LibraryQueryRepository?>();

    if (repository == null || identical(repository, _repository)) {
      return;
    }

    _controller?.dispose();

    _repository = repository;
    _controller = LibraryArtistsController(repository: repository);

    unawaited(_controller!.load());
  }

  void _openArtist(LibraryArtist artist) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ArtistProfilePage(
          artistId: artist.artistId,
          initialArtistName: artist.name,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    if (controller == null) {
      return const SizedBox(
        key: ValueKey<String>('app-destination-library'),
        child: Center(child: Text('Loading library\u2026')),
      );
    }

    return SizedBox(
      key: const ValueKey<String>('app-destination-library'),
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          if (controller.isLoading && controller.artists.isEmpty) {
            return const SonusStateView.loading();
          }

          if (controller.hasError && controller.artists.isEmpty) {
            return _LibraryLoadError(onRetry: controller.load);
          }

          final albumOwnerById = {
            for (final album in controller.albums)
              album.albumId: album.artistId,
          };

          final visibleArtists = controller.artists
              .where(
                (artist) => controller.tracks.any(
                  (track) =>
                      _hasAvailableMedia(track) &&
                      (track.artistId == artist.artistId ||
                          albumOwnerById[track.albumId] == artist.artistId),
                ),
              )
              .toList(growable: false);

          final gutter = SonusTheme.of(context).metrics.pageGutter;

          return RefreshIndicator(
            onRefresh: controller.refresh,
            child: CustomScrollView(
              key: const PageStorageKey<String>('library-scroll'),
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: _LibraryHeader(artistCount: visibleArtists.length),
                ),
                if (visibleArtists.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: _LibraryEmptyState(),
                  )
                else
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      gutter,
                      4,
                      gutter,
                      32 + MediaQuery.paddingOf(context).bottom,
                    ),
                    sliver: SliverLayoutBuilder(
                      builder: (context, constraints) {
                        const spacing = 14.0;
                        // Two columns on phones; wider screens add one per
                        // 300dp instead of stretching the cards.
                        final columns = (constraints.crossAxisExtent / 300)
                            .floor()
                            .clamp(2, 5);
                        final tileWidth =
                            (constraints.crossAxisExtent -
                                spacing * (columns - 1)) /
                            columns;
                        final caption = MediaQuery.textScalerOf(
                          context,
                        ).scale(LibraryArtistCard.captionHeight);

                        return SliverGrid(
                          key: const PageStorageKey<String>('artists-grid'),
                          delegate: SliverChildBuilderDelegate((
                            context,
                            index,
                          ) {
                            final artist = visibleArtists[index];

                            return LibraryArtistCard(
                              artist: artist,
                              onTap: () => _openArtist(artist),
                            );
                          }, childCount: visibleArtists.length),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: columns,
                                crossAxisSpacing: spacing,
                                mainAxisSpacing: spacing,
                                mainAxisExtent: tileWidth + caption,
                              ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }
}

bool _hasAvailableMedia(LibraryTrack track) {
  return track.isAvailable &&
      track.filePath != null &&
      track.filePath!.trim().isNotEmpty;
}

class _LibraryHeader extends StatelessWidget {
  const _LibraryHeader({required this.artistCount});

  final int artistCount;

  @override
  Widget build(BuildContext context) {
    return SonusPageHeader(
      title: 'Library',
      subtitle: artistCount == 1
          ? '1 artist in your library'
          : '$artistCount artists in your library',
    );
  }
}

class _LibraryEmptyState extends StatelessWidget {
  const _LibraryEmptyState();

  @override
  Widget build(BuildContext context) {
    return const SonusStateView(
      icon: Icons.library_music_outlined,
      title: 'No artists yet',
      message: 'Artists will appear here as music is added to your library.',
    );
  }
}

class _LibraryLoadError extends StatelessWidget {
  const _LibraryLoadError({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return SonusStateView(
      icon: Icons.error_outline_rounded,
      isError: true,
      title: 'Could not load your artists.',
      message: 'Try again to reload your library.',
      action: FilledButton.tonalIcon(
        onPressed: () {
          unawaited(onRetry());
        },
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('Try again'),
      ),
    );
  }
}

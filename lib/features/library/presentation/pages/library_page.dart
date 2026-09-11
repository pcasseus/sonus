import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../application/models/library_artist.dart';
import '../../application/repositories/library_query_repository.dart';
import '../controllers/library_artists_controller.dart';

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

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    if (controller == null) {
      return const SizedBox(
        key: ValueKey<String>('app-destination-library'),
        child: Center(child: Text('Loading library…')),
      );
    }

    return SizedBox(
      key: const ValueKey<String>('app-destination-library'),
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          if (controller.isLoading && controller.artists.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (controller.hasError && controller.artists.isEmpty) {
            return _LibraryLoadError(onRetry: controller.load);
          }

          if (controller.isEmpty) {
            return RefreshIndicator(
              onRefresh: controller.refresh,
              child: GridView.count(
                physics: const AlwaysScrollableScrollPhysics(),
                crossAxisCount: 2,
                children: const [Center(child: Text('No artists yet'))],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: controller.refresh,
            child: GridView.builder(
              key: const PageStorageKey<String>('artists-grid'),
              padding: const EdgeInsets.all(16),
              physics: const AlwaysScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.95,
              ),
              itemCount: controller.artists.length,
              itemBuilder: (context, index) {
                return _ArtistCard(artist: controller.artists[index]);
              },
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

class _ArtistCard extends StatelessWidget {
  const _ArtistCard({required this.artist});

  final LibraryArtist artist;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: ValueKey<String>('artist-${artist.artistId}'),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Center(
                child: CircleAvatar(
                  radius: 42,
                  child: Text(
                    _initials(artist.name),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              artist.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              _artistSummary(artist),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  String _artistSummary(LibraryArtist artist) {
    final albumLabel = artist.albumCount == 1 ? 'album' : 'albums';
    final songLabel = artist.songCount == 1 ? 'song' : 'songs';

    return '${artist.albumCount} $albumLabel • '
        '${artist.songCount} $songLabel';
  }

  String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();

    if (parts.isEmpty) {
      return '?';
    }

    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }

    return '${parts.first.substring(0, 1)}'
            '${parts.last.substring(0, 1)}'
        .toUpperCase();
  }
}

class _LibraryLoadError extends StatelessWidget {
  const _LibraryLoadError({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 48),
            const SizedBox(height: 16),
            const Text(
              'Could not load your artists.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: () {
                unawaited(onRetry());
              },
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

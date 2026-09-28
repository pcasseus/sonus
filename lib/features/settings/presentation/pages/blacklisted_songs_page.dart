import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../account/application/controllers/account_controller.dart';
import '../../../library/application/models/library_track.dart';
import '../../../library/application/repositories/library_query_repository.dart';
import '../../../library/application/services/song_block_service.dart';

class BlacklistedSongsPage extends StatefulWidget {
  const BlacklistedSongsPage({super.key});

  @override
  State<BlacklistedSongsPage> createState() => _BlacklistedSongsPageState();
}

class _BlacklistedSongsPageState extends State<BlacklistedSongsPage> {
  LibraryQueryRepository? _repository;

  List<LibraryTrack> _tracks = const [];
  final Set<String> _removingSongIds = <String>{};

  bool _isLoading = false;
  Object? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final repository = context.watch<LibraryQueryRepository?>();

    if (identical(repository, _repository)) {
      return;
    }

    _repository = repository;

    if (repository == null) {
      _tracks = const [];
      _error = null;
      _isLoading = false;
      return;
    }

    unawaited(_load());
  }

  Future<void> _load() async {
    final repository = _repository;

    if (repository == null) {
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final tracks = await repository.getTracks();

      if (!mounted || !identical(repository, _repository)) {
        return;
      }

      setState(() {
        _tracks = tracks
            .where((track) => track.isSongBlocked)
            .toList(growable: false);
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted || !identical(repository, _repository)) {
        return;
      }

      setState(() {
        _error = error;
        _isLoading = false;
      });
    }
  }

  Future<void> _removeFromBlacklist(
    LibraryTrack track,
    String? userId,
    SongBlockService service,
  ) async {
    if (_removingSongIds.contains(track.songId)) {
      return;
    }

    setState(() {
      _removingSongIds.add(track.songId);
    });

    try {
      await service.setBlocked(
        userId: userId,
        songId: track.songId,
        isBlocked: false,
      );

      await _load();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Removed from blacklist.')),
        );
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Could not remove song from blacklist.'),
          ),
        );
    } finally {
      if (mounted) {
        setState(() {
          _removingSongIds.remove(track.songId);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final accountController = context.watch<AccountController?>();
    final userId = accountController?.user?.id.trim();

    final service = context.read<SongBlockService?>();

    return Scaffold(
      key: const ValueKey<String>('blacklisted-songs-page'),
      appBar: AppBar(title: const Text('Blacklisted songs')),
      body: _buildBody(userId: userId, service: service),
    );
  }

  Widget _buildBody({
    required String? userId,
    required SongBlockService? service,
  }) {
    if (_repository == null) {
      return const _BlacklistedSongsUnavailable();
    }

    if (_isLoading && _tracks.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(
          key: ValueKey<String>('blacklisted-songs-loading'),
        ),
      );
    }

    if (_error != null && _tracks.isEmpty) {
      return _BlacklistedSongsError(onRetry: _load);
    }

    if (_tracks.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(32),
          children: const [_BlacklistedSongsEmpty()],
        ),
      );
    }

    final canRemove = service != null;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        key: const ValueKey<String>('blacklisted-songs-list'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        itemCount: _tracks.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final track = _tracks[index];
          final isRemoving = _removingSongIds.contains(track.songId);

          return _BlacklistedSongTile(
            track: track,
            canRemove: canRemove && !isRemoving,
            isRemoving: isRemoving,
            onRemove: service == null
                ? null
                : () => _removeFromBlacklist(track, userId, service),
          );
        },
      ),
    );
  }
}

class _BlacklistedSongTile extends StatelessWidget {
  const _BlacklistedSongTile({
    required this.track,
    required this.canRemove,
    required this.isRemoving,
    required this.onRemove,
  });

  final LibraryTrack track;
  final bool canRemove;
  final bool isRemoving;
  final Future<void> Function()? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      key: ValueKey<String>('blacklisted-song-${track.songId}'),
      child: Opacity(
        opacity: 0.72,
        child: ListTile(
          enabled: false,
          leading: _BlacklistedSongArtwork(track: track),
          title: Text(
            track.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            _subtitle(track),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: isRemoving
              ? const SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : IconButton(
                  key: ValueKey<String>(
                    'remove-blacklisted-song-${track.songId}',
                  ),
                  tooltip: 'Remove from blacklist',
                  onPressed: canRemove
                      ? () {
                          final callback = onRemove;

                          if (callback != null) {
                            unawaited(callback());
                          }
                        }
                      : null,
                  icon: const Icon(Icons.remove_circle_outline_rounded),
                ),
          textColor: colorScheme.onSurface,
        ),
      ),
    );
  }

  String _subtitle(LibraryTrack track) {
    final parts = <String>[track.artistName, track.albumTitle];

    if (!track.isAvailable ||
        track.filePath == null ||
        track.filePath!.trim().isEmpty) {
      parts.add('Unavailable');
    }

    return parts.join(' • ');
  }
}

class _BlacklistedSongArtwork extends StatelessWidget {
  const _BlacklistedSongArtwork({required this.track});

  final LibraryTrack track;

  @override
  Widget build(BuildContext context) {
    const size = 52.0;
    final path = track.artworkPath?.trim();

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox.square(
        dimension: size,
        child: path == null || path.isEmpty
            ? const _ArtworkFallback()
            : _ArtworkImage(path: path),
      ),
    );
  }
}

class _ArtworkImage extends StatelessWidget {
  const _ArtworkImage({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final file = File(path);

    if (file.existsSync()) {
      return Image.file(
        file,
        fit: BoxFit.cover,
        cacheWidth: 160,
        cacheHeight: 160,
        errorBuilder: (_, _, _) => const _ArtworkFallback(),
      );
    }

    return Image.asset(
      path,
      fit: BoxFit.cover,
      cacheWidth: 160,
      cacheHeight: 160,
      errorBuilder: (_, _, _) => const _ArtworkFallback(),
    );
  }
}

class _ArtworkFallback extends StatelessWidget {
  const _ArtworkFallback();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Center(child: Icon(Icons.music_note_rounded)),
    );
  }
}

class _BlacklistedSongsEmpty extends StatelessWidget {
  const _BlacklistedSongsEmpty();

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey<String>('blacklisted-songs-empty'),
      children: [
        const Icon(Icons.check_circle_outline_rounded, size: 52),
        const SizedBox(height: 16),
        Text(
          'No blacklisted songs',
          style: Theme.of(context).textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        const Text(
          'Songs you blacklist will appear here.',
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _BlacklistedSongsError extends StatelessWidget {
  const _BlacklistedSongsError({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const ValueKey<String>('blacklisted-songs-error'),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 48),
            const SizedBox(height: 16),
            const Text(
              'Could not load blacklisted songs.',
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

class _BlacklistedSongsUnavailable extends StatelessWidget {
  const _BlacklistedSongsUnavailable();

  @override
  Widget build(BuildContext context) {
    return const Center(
      key: ValueKey<String>('blacklisted-songs-unavailable'),
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Text(
          'Your library is not available yet.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

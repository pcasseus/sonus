import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/design/sonus_theme.dart';
import '../../../../core/design/widgets/sonus_state_view.dart';
import '../../../../core/design/widgets/sonus_track_tile.dart';

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

    final colors = SonusTheme.of(context).colors;

    return Scaffold(
      key: const ValueKey<String>('blacklisted-songs-page'),
      backgroundColor: colors.background,
      appBar: AppBar(
        title: const Text('Blacklisted songs'),
        backgroundColor: colors.background,
        surfaceTintColor: Colors.transparent,
      ),
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
        child: const CustomScrollView(
          physics: AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: _BlacklistedSongsEmpty(),
            ),
          ],
        ),
      );
    }

    final canRemove = service != null;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        key: const ValueKey<String>('blacklisted-songs-list'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          SonusTheme.of(context).metrics.pageGutter - 6,
          8,
          SonusTheme.of(context).metrics.pageGutter - 6,
          32 + MediaQuery.paddingOf(context).bottom,
        ),
        itemCount: _tracks.length,
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
    final unavailable =
        !track.isAvailable ||
        track.filePath == null ||
        track.filePath!.trim().isEmpty;

    // Blacklisted songs never play from here, so the row has no tap action;
    // removing them from the blacklist is the one action.
    return SonusTrackTile(
      key: ValueKey<String>('blacklisted-song-${track.songId}'),
      title: track.title,
      subtitle: track.artistName,
      detail: [
        track.albumTitle,
        if (unavailable) 'Unavailable',
      ].where((part) => part.trim().isNotEmpty).join(' • '),
      artworkPath: track.artworkPath,
      enabled: false,
      tileColor: SonusTheme.of(context).colors.surface,
      trailing: isRemoving
          ? const SizedBox.square(
              dimension: 48,
              child: Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : IconButton(
              key: ValueKey<String>('remove-blacklisted-song-${track.songId}'),
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
    );
  }
}

class _BlacklistedSongsEmpty extends StatelessWidget {
  const _BlacklistedSongsEmpty();

  @override
  Widget build(BuildContext context) {
    return const SonusStateView(
      key: ValueKey<String>('blacklisted-songs-empty'),
      icon: Icons.check_circle_outline_rounded,
      title: 'No blacklisted songs',
      message: 'Songs you blacklist will appear here.',
    );
  }
}

class _BlacklistedSongsError extends StatelessWidget {
  const _BlacklistedSongsError({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return SonusStateView(
      key: const ValueKey<String>('blacklisted-songs-error'),
      icon: Icons.error_outline_rounded,
      isError: true,
      title: 'Could not load blacklisted songs.',
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

class _BlacklistedSongsUnavailable extends StatelessWidget {
  const _BlacklistedSongsUnavailable();

  @override
  Widget build(BuildContext context) {
    return const SonusStateView(
      key: ValueKey<String>('blacklisted-songs-unavailable'),
      icon: Icons.library_music_outlined,
      title: 'Your library is not available yet.',
    );
  }
}

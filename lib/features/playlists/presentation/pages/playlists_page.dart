import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../application/models/playlist_summary.dart';
import '../../application/services/playlist_service.dart';
import '../controllers/playlists_controller.dart';
import 'playlist_detail_page.dart';

class PlaylistsPage extends StatefulWidget {
  const PlaylistsPage({super.key});

  @override
  State<PlaylistsPage> createState() => _PlaylistsPageState();
}

class _PlaylistsPageState extends State<PlaylistsPage> {
  PlaylistService? _service;
  PlaylistsController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final service = context.watch<PlaylistService?>();

    if (identical(service, _service)) {
      return;
    }

    _controller?.dispose();
    _controller = null;
    _service = service;

    if (service == null) {
      return;
    }

    final controller = PlaylistsController(service: service);

    _controller = controller;

    unawaited(controller.load());
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    if (controller == null) {
      return const SizedBox(
        key: ValueKey<String>('app-destination-playlists'),
        child: Center(child: Text('Loading playlists...')),
      );
    }

    return SizedBox(
      key: const ValueKey<String>('app-destination-playlists'),
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          if (controller.isLoading && controller.playlists.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (controller.hasError && controller.playlists.isEmpty) {
            return _PlaylistsLoadError(onRetry: controller.load);
          }

          return RefreshIndicator(
            onRefresh: controller.refresh,
            child: CustomScrollView(
              key: const PageStorageKey<String>('playlists-scroll'),
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: _PlaylistsHeader(
                    playlistCount: controller.playlists.length,
                    isBusy: controller.isMutating,
                    onCreate: () => _createPlaylist(controller),
                  ),
                ),
                if (controller.hasError)
                  SliverToBoxAdapter(
                    child: _RefreshErrorBanner(onRetry: controller.refresh),
                  ),
                if (controller.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyPlaylistsState(),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
                    sliver: SliverList.separated(
                      itemCount: controller.playlists.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final summary = controller.playlists[index];

                        return _PlaylistCard(
                          summary: summary,
                          isBusy: controller.isMutating,
                          onOpen: () => _openPlaylist(controller, summary),
                          onRename: () => _renamePlaylist(controller, summary),
                          onDelete: () => _deletePlaylist(controller, summary),
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

  Future<void> _createPlaylist(PlaylistsController controller) async {
    final name = await _showPlaylistNameDialog(
      context,
      title: 'New playlist',
      actionLabel: 'Create',
    );

    if (!mounted || name == null) {
      return;
    }

    final created = await controller.createPlaylist(name);

    if (!mounted) {
      return;
    }

    if (!created) {
      _showError('Could not create playlist.');
    }
  }

  Future<void> _renamePlaylist(
    PlaylistsController controller,
    PlaylistSummary summary,
  ) async {
    final name = await _showPlaylistNameDialog(
      context,
      title: 'Rename playlist',
      actionLabel: 'Save',
      initialValue: summary.playlist.name,
    );

    if (!mounted || name == null) {
      return;
    }

    final renamed = await controller.renamePlaylist(
      playlistId: summary.playlist.id,
      name: name,
    );

    if (!mounted) {
      return;
    }

    if (!renamed) {
      _showError('Could not rename playlist.');
    }
  }

  Future<void> _deletePlaylist(
    PlaylistsController controller,
    PlaylistSummary summary,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete playlist?'),
          content: Text(
            'Delete "${summary.playlist.name}"? '
            'Your music files will not be deleted.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (!mounted || confirmed != true) {
      return;
    }

    final deleted = await controller.deletePlaylist(summary.playlist.id);

    if (!mounted) {
      return;
    }

    if (!deleted) {
      _showError('Could not delete playlist.');
    }
  }

  Future<void> _openPlaylist(
    PlaylistsController controller,
    PlaylistSummary summary,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlaylistDetailPage(
          playlistId: summary.playlist.id,
          initialName: summary.playlist.name,
        ),
      ),
    );

    if (mounted) {
      await controller.refresh();
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }
}

class _PlaylistsHeader extends StatelessWidget {
  const _PlaylistsHeader({
    required this.playlistCount,
    required this.isBusy,
    required this.onCreate,
  });

  final int playlistCount;
  final bool isBusy;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Playlists',
                  key: const ValueKey<String>('playlists-page-title'),
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.8,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  playlistCount == 1
                      ? '1 playlist'
                      : '$playlistCount playlists',
                  key: const ValueKey<String>('playlists-count-label'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          FilledButton.icon(
            key: const ValueKey<String>('playlists-create-button'),
            onPressed: isBusy ? null : onCreate,
            icon: const Icon(Icons.add_rounded),
            label: const Text('New'),
          ),
        ],
      ),
    );
  }
}

class _PlaylistCard extends StatelessWidget {
  const _PlaylistCard({
    required this.summary,
    required this.isBusy,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
  });

  final PlaylistSummary summary;
  final bool isBusy;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final playlist = summary.playlist;

    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey<String>('playlist-card-${playlist.id}'),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
          child: Row(
            children: [
              const _PlaylistCover(size: 62),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      playlist.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      summary.trackCount == 1
                          ? '1 song'
                          : '${summary.trackCount} songs',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<_PlaylistAction>(
                key: ValueKey<String>('playlist-menu-${playlist.id}'),
                enabled: !isBusy,
                tooltip: 'Playlist options',
                onSelected: (action) {
                  switch (action) {
                    case _PlaylistAction.rename:
                      onRename();
                    case _PlaylistAction.delete:
                      onDelete();
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: _PlaylistAction.rename,
                    child: ListTile(
                      leading: Icon(Icons.edit_outlined),
                      title: Text('Rename'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  PopupMenuItem(
                    value: _PlaylistAction.delete,
                    child: ListTile(
                      leading: Icon(Icons.delete_outline_rounded),
                      title: Text('Delete'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaylistCover extends StatelessWidget {
  const _PlaylistCover({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.primaryContainer, colors.secondaryContainer],
        ),
      ),
      child: Icon(
        Icons.queue_music_rounded,
        size: size * 0.46,
        color: colors.onPrimaryContainer,
      ),
    );
  }
}

class _EmptyPlaylistsState extends StatelessWidget {
  const _EmptyPlaylistsState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 24, 32, 96),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.surfaceContainerHighest,
              ),
              child: Icon(
                Icons.playlist_add_rounded,
                size: 42,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'No playlists yet',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Create a playlist to organize songs your way.',
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

class _PlaylistsLoadError extends StatelessWidget {
  const _PlaylistsLoadError({required this.onRetry});

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
            const Text('Could not load your playlists.'),
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

class _RefreshErrorBanner extends StatelessWidget {
  const _RefreshErrorBanner({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Material(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          child: Row(
            children: [
              Icon(Icons.error_outline_rounded, color: colors.onErrorContainer),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Playlists could not refresh.',
                  style: TextStyle(color: colors.onErrorContainer),
                ),
              ),
              TextButton(
                onPressed: () {
                  unawaited(onRetry());
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _PlaylistAction { rename, delete }

Future<String?> _showPlaylistNameDialog(
  BuildContext context, {
  required String title,
  required String actionLabel,
  String initialValue = '',
}) {
  return showDialog<String>(
    context: context,
    builder: (dialogContext) {
      return _PlaylistNameDialog(
        title: title,
        actionLabel: actionLabel,
        initialValue: initialValue,
      );
    },
  );
}

class _PlaylistNameDialog extends StatefulWidget {
  const _PlaylistNameDialog({
    required this.title,
    required this.actionLabel,
    required this.initialValue,
  });

  final String title;
  final String actionLabel;
  final String initialValue;

  @override
  State<_PlaylistNameDialog> createState() => _PlaylistNameDialogState();
}

class _PlaylistNameDialogState extends State<_PlaylistNameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();

    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  Widget build(BuildContext context) {
    final value = _controller.text.trim();

    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: const ValueKey<String>('playlist-name-field'),
        controller: _controller,
        autofocus: true,
        maxLength: 120,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(labelText: 'Playlist name'),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) {
          final submitted = _controller.text.trim();

          if (submitted.isNotEmpty) {
            Navigator.of(context).pop(submitted);
          }
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: value.isEmpty
              ? null
              : () => Navigator.of(context).pop(value),
          child: Text(widget.actionLabel),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

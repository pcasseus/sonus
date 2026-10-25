import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/design/sonus_theme.dart';
import '../../../../core/design/widgets/sonus_page_header.dart';
import '../../../../core/design/widgets/sonus_state_view.dart';
import '../../application/models/playlist_summary.dart';
import '../../application/services/playlist_service.dart';
import '../controllers/playlists_controller.dart';
import '../widgets/playlist_cover.dart';
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
            return const SonusStateView.loading();
          }

          if (controller.hasError && controller.playlists.isEmpty) {
            return _PlaylistsLoadError(onRetry: controller.load);
          }

          final gutter = SonusTheme.of(context).metrics.pageGutter;

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
                    padding: EdgeInsets.fromLTRB(
                      gutter,
                      4,
                      gutter,
                      120 + MediaQuery.paddingOf(context).bottom,
                    ),
                    sliver: SliverLayoutBuilder(
                      builder: (context, constraints) {
                        // One card per row on phones; wide screens place
                        // cards side by side instead of stretching them.
                        // Cards sharing a row take the tallest card's
                        // height, so no text size can overflow them.
                        final columns = (constraints.crossAxisExtent / 360)
                            .floor()
                            .clamp(1, 3);
                        final playlists = controller.playlists;
                        final rows = (playlists.length / columns).ceil();

                        Widget card(int index) {
                          final summary = playlists[index];

                          return _PlaylistCard(
                            summary: summary,
                            isBusy: controller.isMutating,
                            onOpen: () => _openPlaylist(controller, summary),
                            onRename: () =>
                                _renamePlaylist(controller, summary),
                            onDelete: () =>
                                _deletePlaylist(controller, summary),
                          );
                        }

                        return SliverList.builder(
                          itemCount: rows,
                          itemBuilder: (context, row) {
                            final first = row * columns;

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: columns == 1
                                  ? card(first)
                                  : IntrinsicHeight(
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          for (var c = 0; c < columns; c++) ...[
                                            if (c > 0)
                                              const SizedBox(width: 10),
                                            Expanded(
                                              child:
                                                  first + c < playlists.length
                                                  ? card(first + c)
                                                  : const SizedBox.shrink(),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                            );
                          },
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
              key: const ValueKey<String>('playlist-delete-confirm-button'),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.error,
                foregroundColor: Theme.of(dialogContext).colorScheme.onError,
              ),
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
    final tokens = SonusTheme.of(context);

    return SonusPageHeader(
      title: 'Playlists',
      titleKey: const ValueKey<String>('playlists-page-title'),
      subtitle: playlistCount == 1 ? '1 playlist' : '$playlistCount playlists',
      subtitleKey: const ValueKey<String>('playlists-count-label'),
      trailing: FilledButton.icon(
        key: const ValueKey<String>('playlists-create-button'),
        onPressed: isBusy ? null : onCreate,
        style: FilledButton.styleFrom(
          backgroundColor: tokens.colors.accentPrimary,
          foregroundColor: tokens.colors.onAccentPrimary,
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.metrics.controlRadius),
          ),
        ),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New'),
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
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final theme = Theme.of(context);
    final playlist = summary.playlist;

    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.metrics.cardRadius),
        side: BorderSide(color: colors.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey<String>('playlist-card-${playlist.id}'),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 2, 10),
          child: Row(
            children: [
              const PlaylistCover(size: 64),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      playlist.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      summary.trackCount == 1
                          ? '1 song'
                          : '${summary.trackCount} songs',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.textSecondary,
                        fontFeatures: const [FontFeature.tabularFigures()],
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

class _EmptyPlaylistsState extends StatelessWidget {
  const _EmptyPlaylistsState();

  @override
  Widget build(BuildContext context) {
    return const SonusStateView(
      icon: Icons.playlist_add_rounded,
      title: 'No playlists yet',
      message: 'Create a playlist to organize songs your way.',
    );
  }
}

class _PlaylistsLoadError extends StatelessWidget {
  const _PlaylistsLoadError({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return SonusStateView(
      icon: Icons.error_outline_rounded,
      isError: true,
      title: 'Could not load your playlists.',
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

class _RefreshErrorBanner extends StatelessWidget {
  const _RefreshErrorBanner({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        tokens.metrics.pageGutter,
        0,
        tokens.metrics.pageGutter,
        12,
      ),
      child: Semantics(
        liveRegion: true,
        child: Material(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(tokens.metrics.cardRadius),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
            child: Row(
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  color: scheme.onErrorContainer,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Playlists could not refresh.',
                    style: TextStyle(color: scheme.onErrorContainer),
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

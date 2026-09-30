import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../library/application/models/library_track.dart';
import '../../application/models/playlist_summary.dart';
import '../../application/services/playlist_service.dart';

Future<void> showAddToPlaylistFlow(
  BuildContext context,
  LibraryTrack track,
) async {
  final service = context.read<PlaylistService?>();

  if (service == null) {
    _showMessage(
      context,
      'Playlists are still loading. Try again in a moment.',
    );
    return;
  }

  try {
    final result = await showModalBottomSheet<_AddToPlaylistResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AddToPlaylistSheet(service: service, track: track),
    );

    if (!context.mounted || result == null) {
      return;
    }

    _showMessage(context, 'Added "${track.title}" to ${result.playlistName}.');
  } catch (_) {
    if (!context.mounted) {
      return;
    }

    _showMessage(context, 'Could not add "${track.title}" to a playlist.');
  }
}

void _showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

class _AddToPlaylistSheet extends StatefulWidget {
  const _AddToPlaylistSheet({required this.service, required this.track});

  final PlaylistService service;
  final LibraryTrack track;

  @override
  State<_AddToPlaylistSheet> createState() => _AddToPlaylistSheetState();
}

class _AddToPlaylistSheetState extends State<_AddToPlaylistSheet> {
  List<PlaylistSummary> _playlists = const [];
  bool _isLoading = true;
  bool _isMutating = false;
  Object? _error;

  @override
  void initState() {
    super.initState();

    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final playlists = await widget.service.getPlaylists();

      if (!mounted) {
        return;
      }

      setState(() {
        _playlists = List<PlaylistSummary>.unmodifiable(playlists);
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = error;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _addToPlaylist(PlaylistSummary summary) async {
    if (_isMutating) {
      return;
    }

    setState(() {
      _isMutating = true;
      _error = null;
    });

    try {
      await widget.service.addSong(
        playlistId: summary.playlist.id,
        songId: widget.track.songId,
      );

      if (!mounted) {
        return;
      }

      Navigator.of(
        context,
      ).pop(_AddToPlaylistResult(playlistName: summary.playlist.name));
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = error;
        _isMutating = false;
      });
    }
  }

  Future<void> _createPlaylist() async {
    if (_isMutating) {
      return;
    }

    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _NewPlaylistDialog(),
    );

    if (!mounted || name == null) {
      return;
    }

    setState(() {
      _isMutating = true;
      _error = null;
    });

    try {
      final playlist = await widget.service.createPlaylist(name: name);

      await widget.service.addSong(
        playlistId: playlist.id,
        songId: widget.track.songId,
      );

      if (!mounted) {
        return;
      }

      Navigator.of(
        context,
      ).pop(_AddToPlaylistResult(playlistName: playlist.name));
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = error;
        _isMutating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Add to playlist',
                key: const ValueKey<String>('add-to-playlist-title'),
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              ListTile(
                key: const ValueKey<String>('add-to-playlist-new'),
                enabled: !_isMutating,
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Icon(
                    Icons.add_rounded,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                title: const Text('New playlist'),
                subtitle: const Text('Create a playlist and add this song'),
                onTap: _isMutating
                    ? null
                    : () {
                        unawaited(_createPlaylist());
                      },
              ),
              const Divider(),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Icon(
                            Icons.error_outline_rounded,
                            color: theme.colorScheme.onErrorContainer,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Could not update playlists.',
                              style: TextStyle(
                                color: theme.colorScheme.onErrorContainer,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: _isMutating ? null : _load,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_playlists.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'No playlists yet. Create one above.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _playlists.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final summary = _playlists[index];

                      return ListTile(
                        key: ValueKey<String>(
                          'add-to-playlist-${summary.playlist.id}',
                        ),
                        enabled: !_isMutating,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.queue_music_rounded),
                        title: Text(
                          summary.playlist.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          summary.trackCount == 1
                              ? '1 song'
                              : '${summary.trackCount} songs',
                        ),
                        onTap: _isMutating
                            ? null
                            : () {
                                unawaited(_addToPlaylist(summary));
                              },
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NewPlaylistDialog extends StatefulWidget {
  const _NewPlaylistDialog();

  @override
  State<_NewPlaylistDialog> createState() => _NewPlaylistDialogState();
}

class _NewPlaylistDialogState extends State<_NewPlaylistDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final name = _controller.text.trim();

    return AlertDialog(
      title: const Text('New playlist'),
      content: TextField(
        key: const ValueKey<String>('add-to-playlist-name-field'),
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
          onPressed: name.isEmpty
              ? null
              : () => Navigator.of(context).pop(name),
          child: const Text('Create'),
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

class _AddToPlaylistResult {
  const _AddToPlaylistResult({required this.playlistName});

  final String playlistName;
}

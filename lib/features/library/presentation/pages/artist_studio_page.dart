import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/models/external_metadata_search_query.dart';
import '../../application/models/library_artist.dart';
import '../../application/repositories/library_query_repository.dart';
import '../../application/services/artist_merge_service.dart';
import '../../application/services/artist_profile_editing_service.dart';
import '../../application/services/external_metadata_application_service.dart';
import '../../application/services/metadata_provider.dart';
import '../controllers/artist_profile_controller.dart';
import '../widgets/musicbrainz_search_dialog.dart';

class ArtistStudioMergeResult {
  const ArtistStudioMergeResult({
    required this.targetArtistId,
    required this.targetArtistName,
  });

  final String targetArtistId;
  final String targetArtistName;
}

class ArtistStudioPage extends StatefulWidget {
  const ArtistStudioPage({
    super.key,
    required this.controller,
    required this.repository,
    required this.userId,
    this.mergeService,
    this.metadataProvider,
    this.externalMetadataApplicationService,
  });

  final ArtistProfileController controller;
  final LibraryQueryRepository repository;
  final String? userId;
  final ArtistMergeService? mergeService;
  final MetadataProvider? metadataProvider;
  final ExternalMetadataApplicationService? externalMetadataApplicationService;

  @override
  State<ArtistStudioPage> createState() => _ArtistStudioPageState();
}

class _ArtistStudioPageState extends State<ArtistStudioPage> {
  bool _isMerging = false;
  bool _isApplyingMusicBrainz = false;

  ArtistProfileController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final artist = controller.artist;

        return Scaffold(
          key: const ValueKey<String>('artist-studio-page'),
          appBar: AppBar(title: const Text('Artist Studio')),
          body: artist == null
              ? const Center(child: Text('Artist is unavailable.'))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  children: [
                    Text(
                      artist.name,
                      key: const ValueKey<String>('artist-studio-heading'),
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Library relationships',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Card(
                      key: const ValueKey<String>(
                        'artist-studio-relationship-summary',
                      ),
                      child: Column(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.album_outlined),
                            title: const Text('Albums'),
                            trailing: Text('${controller.albums.length}'),
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(Icons.music_note_outlined),
                            title: const Text('Primary songs'),
                            trailing: Text('${controller.tracks.length}'),
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(Icons.people_outline),
                            title: const Text('Collaborations'),
                            trailing: Text(
                              '${controller.featuredTracks.length}',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Identity',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Card(
                      child: Column(
                        children: [
                          ListTile(
                            key: const ValueKey<String>(
                              'artist-studio-edit-name',
                            ),
                            leading: const Icon(Icons.edit_outlined),
                            title: const Text('Edit artist name'),
                            subtitle: const Text(
                              'Change the display name without changing '
                              'the permanent artist identity.',
                            ),
                            enabled: controller.canEditArtist(widget.userId),
                            onTap: controller.canEditArtist(widget.userId)
                                ? () {
                                    unawaited(_editName());
                                  }
                                : null,
                          ),
                          const Divider(height: 1),
                          ListTile(
                            key: const ValueKey<String>(
                              'artist-studio-merge-artist',
                            ),
                            leading: const Icon(Icons.merge_rounded),
                            title: const Text('Merge artist'),
                            subtitle: const Text(
                              'Consolidate this identity into another '
                              'artist in your library.',
                            ),
                            enabled: widget.mergeService != null && !_isMerging,
                            onTap: widget.mergeService == null || _isMerging
                                ? null
                                : () {
                                    unawaited(_mergeArtist());
                                  },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Metadata',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Card(
                      child: ListTile(
                        key: const ValueKey<String>(
                          'artist-studio-search-musicbrainz',
                        ),
                        leading: const Icon(Icons.public_rounded),
                        title: const Text('Search MusicBrainz'),
                        subtitle: const Text(
                          'Find a MusicBrainz artist match and apply '
                          'allowed metadata.',
                        ),
                        enabled:
                            widget.metadataProvider != null &&
                            widget.externalMetadataApplicationService != null &&
                            !_isApplyingMusicBrainz,
                        onTap:
                            widget.metadataProvider == null ||
                                widget.externalMetadataApplicationService ==
                                    null ||
                                _isApplyingMusicBrainz
                            ? null
                            : () {
                                unawaited(_searchMusicBrainz());
                              },
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Artwork',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Card(
                      child: Column(
                        children: [
                          ListTile(
                            key: const ValueKey<String>(
                              'artist-studio-change-header',
                            ),
                            leading: const Icon(Icons.image_outlined),
                            title: const Text('Change header artwork'),
                            enabled: controller.canEditArtwork,
                            onTap: controller.canEditArtwork
                                ? () {
                                    unawaited(
                                      _runArtworkAction(
                                        controller.changeHeaderArtwork,
                                        'Header artwork updated.',
                                      ),
                                    );
                                  }
                                : null,
                          ),
                          ListTile(
                            key: const ValueKey<String>(
                              'artist-studio-clear-header',
                            ),
                            leading: const Icon(Icons.hide_image_outlined),
                            title: const Text('Clear header artwork'),
                            enabled: controller.canEditArtwork,
                            onTap: controller.canEditArtwork
                                ? () {
                                    unawaited(
                                      _runArtworkAction(
                                        controller.clearHeaderArtwork,
                                        'Header artwork cleared.',
                                      ),
                                    );
                                  }
                                : null,
                          ),
                          const Divider(height: 1),
                          ListTile(
                            key: const ValueKey<String>(
                              'artist-studio-change-top-artists',
                            ),
                            leading: const Icon(Icons.account_circle_outlined),
                            title: const Text('Change Top Artists artwork'),
                            enabled: controller.canEditArtwork,
                            onTap: controller.canEditArtwork
                                ? () {
                                    unawaited(
                                      _runArtworkAction(
                                        controller.changeTopArtistsArtwork,
                                        'Top Artists artwork updated.',
                                      ),
                                    );
                                  }
                                : null,
                          ),
                          ListTile(
                            key: const ValueKey<String>(
                              'artist-studio-clear-top-artists',
                            ),
                            leading: const Icon(Icons.person_off_outlined),
                            title: const Text('Clear Top Artists artwork'),
                            enabled: controller.canEditArtwork,
                            onTap: controller.canEditArtwork
                                ? () {
                                    unawaited(
                                      _runArtworkAction(
                                        controller.clearTopArtistsArtwork,
                                        'Top Artists artwork cleared.',
                                      ),
                                    );
                                  }
                                : null,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }

  Future<void> _searchMusicBrainz() async {
    final artist = controller.artist;
    final provider = widget.metadataProvider;
    final applicationService = widget.externalMetadataApplicationService;

    if (artist == null ||
        provider == null ||
        applicationService == null ||
        _isApplyingMusicBrainz) {
      return;
    }

    setState(() {
      _isApplyingMusicBrainz = true;
    });

    try {
      final selection = await showDialog<MusicBrainzSearchSelection>(
        context: context,
        builder: (dialogContext) {
          return MusicBrainzSearchDialog(
            provider: provider,
            query: ExternalMetadataSearchQuery(
              entityKind: ExternalMetadataEntityKind.artist,
              artistName: artist.name,
            ),
            applier: (candidate) {
              return applicationService.applyArtistCandidate(
                userId: widget.userId,
                artistId: artist.artistId,
                candidate: candidate,
              );
            },
          );
        },
      );

      if (!mounted || selection == null) {
        return;
      }

      await controller.refresh();

      if (!mounted) {
        return;
      }

      final result = selection.result;

      final message = result.requiresReview
          ? 'MusicBrainz match selected. Some fields still require review.'
          : result.hasProtectedFields
          ? 'MusicBrainz match selected. Protected fields were not changed.'
          : result.entityChanged
          ? 'MusicBrainz metadata applied.'
          : 'MusicBrainz metadata already matched this artist.';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const ValueKey<String>(
            'artist-studio-musicbrainz-result-message',
          ),
          content: Text(message),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isApplyingMusicBrainz = false;
        });
      }
    }
  }

  Future<void> _editName() async {
    final artist = controller.artist;

    if (artist == null || !controller.canEditArtist(widget.userId)) {
      return;
    }

    try {
      final name = await showDialog<String>(
        context: context,
        builder: (dialogContext) {
          return _ArtistStudioNameEditDialog(initialName: artist.name);
        },
      );

      if (!mounted || name == null) {
        return;
      }

      await controller.renameArtist(userId: widget.userId, name: name);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Artist name updated.')));
    } on ArtistNameCollisionException {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          key: ValueKey<String>('artist-studio-rename-collision-message'),
          content: Text(
            'Another artist already owns this identity. '
            'Use Merge artist to consolidate them.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update artist name.')),
      );
    }
  }

  Future<void> _mergeArtist() async {
    final sourceArtist = controller.artist;
    final mergeService = widget.mergeService;

    if (sourceArtist == null || mergeService == null || _isMerging) {
      return;
    }

    try {
      final artists =
          (await widget.repository.getArtists())
              .where((artist) => artist.artistId != sourceArtist.artistId)
              .toList(growable: false)
            ..sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
            );

      if (!mounted) {
        return;
      }

      if (artists.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'There are no other artists available to merge into.',
            ),
          ),
        );
        return;
      }

      final target = await showDialog<LibraryArtist>(
        context: context,
        builder: (dialogContext) {
          return SimpleDialog(
            key: const ValueKey<String>('artist-studio-merge-target-dialog'),
            title: const Text('Merge into artist'),
            children: [
              for (final artist in artists)
                SimpleDialogOption(
                  key: ValueKey<String>(
                    'artist-studio-merge-target-${artist.artistId}',
                  ),
                  onPressed: () => Navigator.of(dialogContext).pop(artist),
                  child: Text(artist.name),
                ),
            ],
          );
        },
      );

      if (!mounted || target == null) {
        return;
      }

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            key: const ValueKey<String>('artist-studio-merge-confirmation'),
            title: Text('Merge ${sourceArtist.name}?'),
            content: Text(
              'Albums, songs, collaboration links, and historical artist '
              'references will move to ${target.name}. '
              'The ${sourceArtist.name} identity will then be removed.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                key: const ValueKey<String>('artist-studio-merge-confirm'),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Merge'),
              ),
            ],
          );
        },
      );

      if (!mounted || confirmed != true) {
        return;
      }

      setState(() {
        _isMerging = true;
      });

      await mergeService.mergeArtists(
        userId: widget.userId,
        sourceArtistId: sourceArtist.artistId,
        targetArtistId: target.artistId,
      );

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop(
        ArtistStudioMergeResult(
          targetArtistId: target.artistId,
          targetArtistName: target.name,
        ),
      );
    } on ArtistMergeAlbumCollisionException {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          key: ValueKey<String>('artist-studio-album-collision-message'),
          content: Text(
            'These artists have matching album identities. '
            'Resolve the album collision before merging.',
          ),
        ),
      );
    } on ArtistMergeCreditCollisionException {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          key: ValueKey<String>('artist-studio-credit-collision-message'),
          content: Text(
            'A song already credits both artists. '
            'Resolve that credit relationship before merging.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not merge artists.')));
    } finally {
      if (mounted) {
        setState(() {
          _isMerging = false;
        });
      }
    }
  }

  Future<void> _runArtworkAction(
    Future<bool> Function() action,
    String successMessage,
  ) async {
    try {
      final changed = await action();

      if (!mounted || !changed) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(successMessage)));
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update artist artwork.')),
      );
    }
  }
}

class _ArtistStudioNameEditDialog extends StatefulWidget {
  const _ArtistStudioNameEditDialog({required this.initialName});

  final String initialName;

  @override
  State<_ArtistStudioNameEditDialog> createState() =>
      _ArtistStudioNameEditDialogState();
}

class _ArtistStudioNameEditDialogState
    extends State<_ArtistStudioNameEditDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();

    if (name.isEmpty) {
      return;
    }

    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const ValueKey<String>('artist-studio-name-dialog'),
      title: const Text('Edit artist name'),
      content: TextField(
        key: const ValueKey<String>('artist-studio-name-field'),
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(labelText: 'Artist name'),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey<String>('artist-studio-name-save'),
          onPressed: _submit,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';

import '../../../../../core/design/sonus_count_label.dart';
import '../../../../../core/design/sonus_theme.dart';
import '../../../application/models/library_album.dart';
import '../../../application/repositories/library_query_repository.dart';
import '../../../application/services/library_organization_service.dart';

/// Where an artist appears in the Library, and the reversible choices
/// "Assign to Project", "Show as its own artist" and "Undo my choice".
///
/// Only the Library's artist list changes: credits, search results, the
/// artist's profile and listening history stay as they are. An assignment
/// is always previewed first, offered only for projects the artist is
/// credited on, and refused (with the reason) when the artist owns albums
/// of its own. Several possible projects are never chosen automatically.
Future<void> showArtistLibraryPlacement(
  BuildContext context, {
  required String artistId,
  required String artistName,
  required LibraryOrganizationService service,
  required LibraryQueryRepository library,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => ArtistLibraryPlacementSheet(
      artistId: artistId,
      artistName: artistName,
      service: service,
      library: library,
    ),
  );
}

class ArtistLibraryPlacementSheet extends StatefulWidget {
  const ArtistLibraryPlacementSheet({
    super.key,
    required this.artistId,
    required this.artistName,
    required this.service,
    required this.library,
  });

  final String artistId;
  final String artistName;
  final LibraryOrganizationService service;
  final LibraryQueryRepository library;

  static String refusalMessage(
    ProjectAssignmentRefusal refusal,
    String artistName,
  ) => switch (refusal) {
    ProjectAssignmentRefusal.ownsAlbums =>
      '$artistName has albums of their own, so they always keep their own '
          'Library entry.',
    ProjectAssignmentRefusal.notCredited =>
      '$artistName isn\'t credited on this project.',
    ProjectAssignmentRefusal.ownProject => 'This is $artistName\'s own album.',
  };

  @override
  State<ArtistLibraryPlacementSheet> createState() =>
      _ArtistLibraryPlacementSheetState();
}

class _ArtistLibraryPlacementSheetState
    extends State<ArtistLibraryPlacementSheet> {
  ArtistLibraryPlacement? _placement;
  Map<String, LibraryAlbum> _albums = const {};

  /// Projects (albums owned by someone else) the artist is credited on,
  /// with the songs credited there.
  List<(LibraryAlbum, int)> _projects = const [];
  bool _loading = true;
  bool _busy = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final organization = await widget.service.load();
      final albums = {
        for (final album in await widget.library.getAlbums())
          album.albumId: album,
      };
      final credits = await widget.service.collaborators
          .getProjectCollaborators();

      final projects =
          <(LibraryAlbum, int)>[
            for (final credit in credits)
              if (credit.artistId == widget.artistId &&
                  albums[credit.albumId] != null &&
                  albums[credit.albumId]!.artistId != widget.artistId)
                (albums[credit.albumId]!, credit.songCount),
          ]..sort(
            (a, b) =>
                a.$1.title.toLowerCase().compareTo(b.$1.title.toLowerCase()),
          );

      if (!mounted) return;
      setState(() {
        _placement = organization.placementOf(widget.artistId);
        _albums = albums;
        _projects = projects;
        _loading = false;
        _failed = false;
      });
    } catch (error, stackTrace) {
      developer.log(
        'Library placement could not be read (${error.runtimeType})',
        name: 'sonus.library.organization',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  Future<void> _change(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      await action();
      await _load();
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('That could not be saved.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _assign(LibraryAlbum project) async {
    final name = widget.artistName;
    final ProjectAssignmentPreview preview;
    try {
      preview = await widget.service.previewAssignment(
        artistId: widget.artistId,
        albumId: project.albumId,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('The project could not be checked.')),
        );
      }
      return;
    }
    if (!mounted) return;

    final refusal = preview.refusal;
    if (refusal != null) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          key: const ValueKey<String>('artist-placement-refused'),
          title: const Text('Can\'t assign to this project'),
          content: Text(
            ArtistLibraryPlacementSheet.refusalMessage(refusal, name),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    final elsewhere = preview.songsElsewhere;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const ValueKey<String>('artist-placement-preview'),
        title: Text('List $name under ${project.title}?'),
        content: Text(
          '$name will appear in ${project.title}\'s collaborators instead of '
          'as their own Library entry. '
          '${sonusCount(preview.songsOnProject, 'song')} on ${project.title}.'
          '${elsewhere == 0 ? '' : ' ${sonusCount(elsewhere, 'song')} on other albums stay on $name\'s profile and in search.'}'
          '\n\nCredits, search and listening history don\'t change, and you '
          'can undo this at any time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey<String>('artist-placement-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Assign'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await _change(
      () => widget.service.assignToProject(
        artistId: widget.artistId,
        albumId: project.albumId,
      ),
      '$name is now listed under ${project.title}.',
    );
  }

  String _status(ArtistLibraryPlacement placement) {
    final project = _albums[placement.projectAlbumId]?.title ?? 'a project';
    return switch (placement.reason) {
      ArtistPlacementReason.standalone => 'Shown as its own artist.',
      ArtistPlacementReason.automatic =>
        'Listed under $project, because every song is on that soundtrack or '
            'cast recording.',
      ArtistPlacementReason.manual =>
        placement.isGrouped
            ? 'Listed under $project (your choice).'
            : 'Always shown as its own artist (your choice).',
    };
  }

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;
    final theme = Theme.of(context);
    final placement = _placement;
    final name = widget.artistName;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: _loading
            ? const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            : _failed || placement == null
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Library placement could not be read.'),
              )
            : SingleChildScrollView(
                key: const ValueKey<String>('artist-placement-sheet'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        'Where $name appears',
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _status(placement),
                      key: const ValueKey<String>('artist-placement-status'),
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'This only changes the Library\'s artist list. Songs, '
                      'credits, search and this profile stay the same.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                    if (_busy) ...[
                      const SizedBox(height: 12),
                      const LinearProgressIndicator(),
                    ],
                    const SizedBox(height: 16),
                    if (placement.reason == ArtistPlacementReason.manual)
                      OutlinedButton.icon(
                        key: const ValueKey<String>('artist-placement-undo'),
                        onPressed: _busy
                            ? null
                            : () => _change(
                                () => widget.service.clearAssignment(
                                  widget.artistId,
                                ),
                                'Your choice for $name was undone.',
                              ),
                        icon: const Icon(Icons.undo_rounded),
                        label: const Text('Undo my choice'),
                      ),
                    if (placement.reason == ArtistPlacementReason.automatic)
                      OutlinedButton.icon(
                        key: const ValueKey<String>('artist-placement-own'),
                        onPressed: _busy
                            ? null
                            : () => _change(
                                () => widget.service.showAsOwnArtist(
                                  widget.artistId,
                                ),
                                '$name is now shown as their own artist.',
                              ),
                        icon: const Icon(Icons.person_outline_rounded),
                        label: const Text('Show as its own artist'),
                      ),
                    if (!placement.isGrouped) ...[
                      const SizedBox(height: 8),
                      Semantics(
                        header: true,
                        child: Text(
                          'Assign to a project',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (_projects.isEmpty)
                        Text(
                          '$name isn\'t credited on another artist\'s album, '
                          'so there is no project to list them under.',
                          key: const ValueKey<String>(
                            'artist-placement-no-projects',
                          ),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.textSecondary,
                          ),
                        )
                      else
                        for (final (project, songs) in _projects)
                          ListTile(
                            key: ValueKey<String>(
                              'artist-placement-project-${project.albumId}',
                            ),
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.album_rounded),
                            title: Text(project.title),
                            subtitle: Text(
                              '${project.artistName} · '
                              '${sonusCount(songs, 'song')}',
                            ),
                            enabled: !_busy,
                            onTap: () => _assign(project),
                          ),
                    ],
                  ],
                ),
              ),
      ),
    );
  }
}

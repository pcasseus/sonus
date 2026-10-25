import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';

import '../../../../../core/design/sonus_theme.dart';
import '../../../application/models/library_album_edition.dart';
import '../../../application/models/library_track.dart';
import '../../../application/repositories/library_query_repository.dart';
import '../../../application/services/album_edition_management_service.dart';
import '../../../application/services/edition_follow_up.dart';
import '../../../data/services/edition_follow_up_dismissals.dart';
import '../../../domain/entities/album_edition.dart';
import '../../controllers/album_profile_controller.dart';
import 'album_studio_edition_follow_up.dart';

/// Album Studio's edition management (Standard, Deluxe and other
/// editions): create, rename or retype, choose the primary edition, choose
/// which of the album's songs an edition lists, and delete an empty one.
///
/// Every operation goes through [AlbumEditionManagementService], which
/// runs it as one transaction and refuses unsafe changes (for example the
/// last listing of a song, or deleting the primary edition). Songs, their
/// files and listening history are never deleted here. Nothing changes
/// unless the user asks: which edition is primary is never changed
/// automatically.
class AlbumStudioEditionsSection extends StatefulWidget {
  const AlbumStudioEditionsSection({
    super.key,
    required this.controller,
    required this.service,
    required this.library,
    required this.userId,
    this.dismissals,
  });

  final AlbumProfileController controller;
  final AlbumEditionManagementService service;
  final LibraryQueryRepository? library;
  final String? userId;

  /// Remembers "keep Deluxe as it is" answers; device-local (tests inject).
  final EditionFollowUpDismissals? dismissals;

  /// Plain wording for each refusal.
  static String messageFor(AlbumEditionRefusal refusal) => switch (refusal) {
    AlbumEditionRefusal.blankTitle => 'Enter an edition name.',
    AlbumEditionRefusal.duplicateTitle =>
      'This album already has an edition with that name.',
    AlbumEditionRefusal.lastEditionOfSong =>
      'Every song stays on at least one edition, so a song only on this '
          'edition was kept.',
    AlbumEditionRefusal.editionNotEmpty =>
      'Only an empty edition can be deleted. Choose no songs for it first.',
    AlbumEditionRefusal.primaryEdition =>
      'Make another edition primary before deleting this one.',
    AlbumEditionRefusal.onlyEdition => 'An album needs at least one edition.',
    AlbumEditionRefusal.albumNotFound ||
    AlbumEditionRefusal.editionNotFound ||
    AlbumEditionRefusal.songNotOnAlbum =>
      'This album changed in the meantime. Nothing was changed.',
  };

  static String typeLabel(AlbumEditionType type) => switch (type) {
    AlbumEditionType.standard => 'Standard',
    AlbumEditionType.deluxe => 'Deluxe',
    AlbumEditionType.expanded => 'Expanded',
    AlbumEditionType.anniversary => 'Anniversary',
    AlbumEditionType.remaster => 'Remaster',
    AlbumEditionType.other => 'Other',
  };

  @override
  State<AlbumStudioEditionsSection> createState() =>
      _AlbumStudioEditionsSectionState();
}

class _AlbumStudioEditionsSectionState
    extends State<AlbumStudioEditionsSection> {
  bool _busy = false;

  /// Every edition's songs, in edition order (SN-45: inheritance preview
  /// and follow-up offers). Empty when editions cannot be read.
  Map<String, List<LibraryTrack>> _listings = const {};

  /// Songs that reached Standard after Deluxe was built on it.
  List<EditionFollowUp> _pending = const [];

  String _listingSignature = '';
  int _loadVersion = 0;

  late final EditionFollowUpDismissals _dismissals =
      widget.dismissals ?? EditionFollowUpDismissals();

  AlbumProfileController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerChanged);
    _onControllerChanged();
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  /// Reloads the listings when the editions or the shown songs change.
  void _onControllerChanged() {
    final signature = [
      for (final edition in _controller.editions)
        '${edition.editionId}:${edition.title}',
      for (final track in _controller.tracks) track.songId,
    ].join('|');

    if (signature == _listingSignature) return;
    _listingSignature = signature;
    unawaited(_loadListings());
  }

  Future<void> _loadListings() async {
    final library = widget.library;
    final editions = _controller.editions;
    final version = ++_loadVersion;

    if (library is! AlbumEditionQueryRepository || editions.isEmpty) {
      if (mounted) {
        setState(() {
          _listings = const {};
          _pending = const [];
        });
      }
      return;
    }

    try {
      final query = library as AlbumEditionQueryRepository;
      final listings = <String, List<LibraryTrack>>{
        for (final edition in editions)
          edition.editionId: await query.getTracksByAlbumEditionId(
            edition.editionId,
          ),
      };
      final dismissed = <String, Set<String>>{
        for (final edition in editions)
          edition.editionId: await _dismissedFor(edition.editionId),
      };
      final addedAt = <String, DateTime>{
        for (final tracks in listings.values)
          for (final track in tracks) track.songId: track.dateAdded,
      };

      final pending = EditionFollowUps.laterAdditions(
        editions: [
          for (final edition in editions)
            _listingOf(edition, listings[edition.editionId]!),
        ],
        orderOf: (id) => [for (final t in listings[id]!) t.songId],
        addedAt: (songId) => addedAt[songId],
        dismissed: (target) => dismissed[target] ?? const {},
      );

      if (!mounted || version != _loadVersion) return;
      setState(() {
        _listings = listings;
        _pending = pending;
      });
    } catch (error, stackTrace) {
      // The offers are a convenience; editing still works without them.
      developer.log(
        'Edition listings could not be read (${error.runtimeType})',
        name: 'sonus.library.editions',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Remembered answers; unreadable preferences only mean the offer may
  /// appear again, so they never block the editions from loading.
  Future<Set<String>> _dismissedFor(String editionId) async {
    try {
      return await _dismissals.dismissed(editionId);
    } catch (error) {
      developer.log(
        'Edition offer answers could not be read (${error.runtimeType})',
        name: 'sonus.library.editions',
        level: 900,
      );
      return const {};
    }
  }

  static EditionListing _listingOf(
    LibraryAlbumEdition edition,
    List<LibraryTrack> tracks,
  ) => EditionListing(
    editionId: edition.editionId,
    title: edition.title,
    type: edition.type,
    createdAt: edition.dateAdded,
    songIds: {for (final track in tracks) track.songId},
  );

  String _songTitle(String songId) {
    for (final tracks in _listings.values) {
      for (final track in tracks) {
        if (track.songId == songId) return track.title;
      }
    }
    return 'Song';
  }

  /// Offers [followUps] and applies the answer.
  Future<void> _offer(
    String sourceTitle,
    List<EditionFollowUp> followUps,
  ) async {
    if (followUps.isEmpty || !mounted) return;

    final decision = await showEditionFollowUpDialog(
      context: context,
      sourceTitle: sourceTitle,
      followUps: followUps,
      songTitle: _songTitle,
    );
    if (!mounted) return;

    switch (decision.choice) {
      case EditionFollowUpChoice.later:
        return;
      case EditionFollowUpChoice.keep:
        try {
          for (final followUp in followUps) {
            await _dismissals.dismiss(
              followUp.targetEditionId,
              followUp.songIds,
            );
          }
        } catch (error) {
          // Nothing was added either way; the offer may simply return.
          developer.log(
            'Edition offer answer could not be saved (${error.runtimeType})',
            name: 'sonus.library.editions',
            level: 900,
          );
        }
      case EditionFollowUpChoice.add:
        final targets = decision.accepted;
        await _run(
          () async {
            for (final followUp in targets) {
              await widget.service.assignTracks(
                editionId: followUp.targetEditionId,
                songIds: followUp.songIds,
                userId: widget.userId,
              );
            }
          },
          done: targets.length == 1
              ? 'Added to ${targets.single.targetTitle}.'
              : 'Added to the chosen editions.',
        );
    }

    _listingSignature = '';
    _onControllerChanged();
  }

  /// Runs one edition operation, then reloads the album. Refusals and
  /// failures are explained; nothing is changed by a refused operation.
  Future<bool> _run(Future<void> Function() operation, {String? done}) async {
    if (_busy) return false;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      await operation();
      await _controller.refresh();
      if (done != null) {
        messenger.showSnackBar(SnackBar(content: Text(done)));
      }
      return true;
    } on AlbumEditionManagementException catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(AlbumStudioEditionsSection.messageFor(error.refusal)),
        ),
      );
      return false;
    } catch (error, stackTrace) {
      developer.log(
        'Edition change failed (${error.runtimeType})',
        name: 'sonus.library.editions',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
      messenger.showSnackBar(
        const SnackBar(
          content: Text('The edition could not be changed. Nothing was saved.'),
        ),
      );
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create() async {
    final album = _controller.album;
    if (album == null) return;

    final sources = [
      for (final edition in _controller.editions)
        if ((_listings[edition.editionId] ?? const []).isNotEmpty) edition,
    ];
    // A new edition starts from the Standard edition when there is one,
    // otherwise from the primary edition (SN-45).
    final defaultSource =
        sources.where((e) => e.type == AlbumEditionType.standard).firstOrNull ??
        sources.where((e) => e.isPrimary).firstOrNull ??
        sources.firstOrNull;

    final draft = await showDialog<_EditionDraft>(
      context: context,
      builder: (_) => _EditionDialog(
        title: 'New edition',
        sources: sources,
        listings: _listings,
        initialSourceId: defaultSource?.editionId,
      ),
    );
    if (draft == null || !mounted) return;

    String? createdId;
    final created = await _run(() async {
      final edition = await widget.service.createEdition(
        albumId: album.albumId,
        title: draft.title,
        type: draft.type,
        includeSongsFrom: draft.includeSongsFrom,
        userId: widget.userId,
      );
      createdId = edition.id;
    }, done: 'Edition "${draft.title.trim()}" created.');

    final id = createdId;
    if (created && id != null) {
      await _controller.selectEdition(id);
    }
  }

  Future<void> _edit(LibraryAlbumEdition edition) async {
    final draft = await showDialog<_EditionDraft>(
      context: context,
      builder: (_) => _EditionDialog(
        title: 'Rename or change type',
        initial: _EditionDraft(edition.title, edition.type),
      ),
    );
    if (draft == null || !mounted) return;

    await _run(
      () => widget.service.updateEdition(
        editionId: edition.editionId,
        title: draft.title.trim() == edition.title ? null : draft.title,
        type: draft.type,
        userId: widget.userId,
      ),
      done: 'Edition updated.',
    );
  }

  Future<void> _makePrimary(LibraryAlbumEdition edition) async {
    final confirmed = await _confirm(
      title: 'Make "${edition.title}" primary?',
      message:
          'The primary edition is the one Sonus shows first for this album. '
          'Songs, other editions and listening history stay as they are.',
      action: 'Make primary',
      key: 'album-studio-confirm-primary',
    );
    if (!confirmed) return;

    await _run(
      () => widget.service.setPrimary(
        editionId: edition.editionId,
        userId: widget.userId,
      ),
      done: '"${edition.title}" is now the primary edition.',
    );
  }

  Future<void> _chooseSongs(LibraryAlbumEdition edition) async {
    final album = _controller.album;
    final library = widget.library;
    if (album == null || library == null) return;

    final List<LibraryTrack> albumSongs;
    try {
      albumSongs = await library.getTracksByAlbumId(album.albumId);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('The album\'s songs could not be read.'),
          ),
        );
      }
      return;
    }
    if (!mounted) return;

    final listed = {for (final track in _controller.tracks) track.songId};
    final chosen = await showDialog<Set<String>>(
      context: context,
      builder: (_) => _ChooseSongsDialog(
        editionTitle: edition.title,
        songs: albumSongs,
        initiallyListed: listed,
      ),
    );
    if (chosen == null || !mounted) return;

    final added = chosen.difference(listed).toList(growable: false);
    final removed = listed.difference(chosen).toList(growable: false);
    if (added.isEmpty && removed.isEmpty) return;

    // Which editions build on this one, judged before the change.
    final followUps = EditionFollowUps.afterAdding(
      source: EditionListing(
        editionId: edition.editionId,
        title: edition.title,
        type: edition.type,
        createdAt: edition.dateAdded,
        songIds: listed,
      ),
      others: [
        for (final other in _controller.editions)
          if (other.editionId != edition.editionId &&
              _listings.containsKey(other.editionId))
            _listingOf(other, _listings[other.editionId]!),
      ],
      added: [
        for (final song in albumSongs)
          if (added.contains(song.songId)) song.songId,
      ],
    );

    var kept = 0;
    final saved = await _run(() async {
      if (added.isNotEmpty) {
        await widget.service.assignTracks(
          editionId: edition.editionId,
          songIds: added,
          userId: widget.userId,
        );
      }
      for (final songId in removed) {
        try {
          await widget.service.removeTrack(
            editionId: edition.editionId,
            songId: songId,
            userId: widget.userId,
          );
        } on AlbumEditionManagementException catch (error) {
          // The song's only listing: it stays, the rest still apply.
          if (error.refusal != AlbumEditionRefusal.lastEditionOfSong) rethrow;
          kept++;
        }
      }
    });

    if (saved && followUps.isNotEmpty && mounted) {
      await _offer(edition.title, followUps);
    }

    if (kept > 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            kept == 1
                ? 'One song is only on this edition, so it was kept.'
                : '$kept songs are only on this edition, so they were kept.',
          ),
        ),
      );
    }
  }

  Future<void> _delete(LibraryAlbumEdition edition) async {
    final confirmed = await _confirm(
      title: 'Delete "${edition.title}"?',
      message:
          'This empty edition is removed. No songs or listening history are '
          'affected.',
      action: 'Delete edition',
      key: 'album-studio-confirm-delete-edition',
      destructive: true,
    );
    if (!confirmed) return;

    final primary = _controller.editions.where((e) => e.isPrimary).firstOrNull;
    final deleted = await _run(
      () => widget.service.deleteEdition(
        editionId: edition.editionId,
        userId: widget.userId,
      ),
      done: 'Edition deleted.',
    );
    if (deleted && primary != null) {
      await _controller.selectEdition(primary.editionId);
    }
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String action,
    required String key,
    bool destructive = false,
  }) async {
    final scheme = Theme.of(context).colorScheme;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: ValueKey<String>(key),
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: scheme.error,
                    foregroundColor: scheme.onError,
                  )
                : null,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return result == true;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final theme = Theme.of(context);
    final edition = _controller.selectedEdition;
    final editions = _controller.editions;

    final canDelete =
        edition != null &&
        !edition.isPrimary &&
        editions.length > 1 &&
        _controller.tracks.isEmpty;

    return Material(
      key: const ValueKey<String>('album-studio-editions'),
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.metrics.cardRadius),
        side: BorderSide(color: colors.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                'Editions',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 4),
            if (edition == null)
              Text(
                'This album has no editions yet.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    edition.title,
                    key: const ValueKey<String>('album-studio-edition-title'),
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  _Badge(
                    label: AlbumStudioEditionsSection.typeLabel(edition.type),
                  ),
                  if (edition.isPrimary)
                    const _Badge(
                      key: ValueKey<String>('album-studio-edition-primary'),
                      label: 'Primary',
                      strong: true,
                    ),
                ],
              ),
            for (final followUp in _pending) ...[
              const SizedBox(height: 10),
              AlbumStudioEditionFollowUpNotice(
                followUp: followUp,
                sourceTitle: _titleOf(followUp.sourceEditionId),
                onReview: _busy
                    ? null
                    : () => _offer(_titleOf(followUp.sourceEditionId), [
                        followUp,
                      ]),
              ),
            ],
            if (_busy) ...[
              const SizedBox(height: 10),
              const LinearProgressIndicator(
                key: ValueKey<String>('album-studio-editions-busy'),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _action(
                  key: 'album-studio-new-edition',
                  icon: Icons.add_rounded,
                  label: 'New edition',
                  onPressed: _controller.album == null ? null : _create,
                ),
                if (edition != null) ...[
                  _action(
                    key: 'album-studio-edit-edition',
                    icon: Icons.edit_outlined,
                    label: 'Rename or change type',
                    onPressed: () => _edit(edition),
                  ),
                  _action(
                    key: 'album-studio-choose-songs',
                    icon: Icons.playlist_add_check_rounded,
                    label: 'Choose songs',
                    onPressed: widget.library == null
                        ? null
                        : () => _chooseSongs(edition),
                  ),
                  if (!edition.isPrimary)
                    _action(
                      key: 'album-studio-make-primary',
                      icon: Icons.star_outline_rounded,
                      label: 'Make primary',
                      onPressed: () => _makePrimary(edition),
                    ),
                  if (canDelete)
                    _action(
                      key: 'album-studio-delete-edition',
                      icon: Icons.delete_outline_rounded,
                      label: 'Delete edition',
                      onPressed: () => _delete(edition),
                    ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _titleOf(String editionId) =>
      _controller.editions
          .where((e) => e.editionId == editionId)
          .firstOrNull
          ?.title ??
      'this edition';

  Widget _action({
    required String key,
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
  }) {
    return OutlinedButton.icon(
      key: ValueKey<String>(key),
      onPressed: _busy || onPressed == null ? null : onPressed,
      icon: Icon(icon),
      label: Text(label),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({super.key, required this.label, this.strong = false});

  final String label;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: strong ? colors.selection : colors.raisedSurface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: strong ? colors.accentPrimary : colors.border,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _EditionDraft {
  const _EditionDraft(this.title, this.type, [this.includeSongsFrom]);

  final String title;
  final AlbumEditionType type;

  /// The edition whose songs a new edition starts with, if any.
  final String? includeSongsFrom;
}

class _EditionDialog extends StatefulWidget {
  const _EditionDialog({
    required this.title,
    this.initial,
    this.sources = const [],
    this.listings = const {},
    this.initialSourceId,
  });

  final String title;
  final _EditionDraft? initial;

  /// Editions a new edition can start from; empty when renaming.
  final List<LibraryAlbumEdition> sources;
  final Map<String, List<LibraryTrack>> listings;
  final String? initialSourceId;

  @override
  State<_EditionDialog> createState() => _EditionDialogState();
}

class _EditionDialogState extends State<_EditionDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initial?.title ?? '',
  );
  late AlbumEditionType _type = widget.initial?.type ?? AlbumEditionType.deluxe;
  late String? _sourceId = widget.initialSourceId;
  String? _error;

  /// Dropdown value for "start with no songs".
  static const String _noSource = '';

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Enter an edition name.');
      return;
    }
    Navigator.of(
      context,
    ).pop(_EditionDraft(_name.text.trim(), _type, _sourceId));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey<String>('album-studio-edition-name-field'),
            controller: _name,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
            decoration: InputDecoration(
              labelText: 'Edition name',
              hintText: 'For example Deluxe',
              errorText: _error,
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<AlbumEditionType>(
            key: const ValueKey<String>('album-studio-edition-type-field'),
            initialValue: _type,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Type'),
            items: [
              for (final type in AlbumEditionType.values)
                DropdownMenuItem(
                  value: type,
                  child: Text(AlbumStudioEditionsSection.typeLabel(type)),
                ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _type = value);
            },
          ),
          if (widget.sources.isNotEmpty) ...[
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              key: const ValueKey<String>('album-studio-edition-source-field'),
              initialValue: _sourceId ?? _noSource,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Start with songs from',
              ),
              items: [
                for (final source in widget.sources)
                  DropdownMenuItem(
                    value: source.editionId,
                    child: Text(
                      source.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                const DropdownMenuItem(
                  value: _noSource,
                  child: Text('No songs (start empty)'),
                ),
              ],
              onChanged: (value) => setState(() {
                _sourceId = value == null || value == _noSource ? null : value;
              }),
            ),
            const SizedBox(height: 8),
            _InheritedSongsPreview(
              tracks: _sourceId == null
                  ? const []
                  : widget.listings[_sourceId] ?? const [],
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey<String>('album-studio-save-edition'),
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// Which of the album's songs the edition lists. Unchecking only removes
/// this edition's listing; the song stays in the library.
class _ChooseSongsDialog extends StatefulWidget {
  const _ChooseSongsDialog({
    required this.editionTitle,
    required this.songs,
    required this.initiallyListed,
  });

  final String editionTitle;
  final List<LibraryTrack> songs;
  final Set<String> initiallyListed;

  @override
  State<_ChooseSongsDialog> createState() => _ChooseSongsDialogState();
}

class _ChooseSongsDialogState extends State<_ChooseSongsDialog> {
  late final Set<String> _chosen = {...widget.initiallyListed};

  @override
  Widget build(BuildContext context) {
    final songs = [...widget.songs]
      ..sort((a, b) {
        final disc = a.discNumber.compareTo(b.discNumber);
        if (disc != 0) return disc;
        final track = a.trackNumber.compareTo(b.trackNumber);
        return track != 0
            ? track
            : a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });

    return AlertDialog(
      key: const ValueKey<String>('album-studio-choose-songs-dialog'),
      title: Text('Songs on ${widget.editionTitle}'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Unchecking a song removes it from this edition only. It stays '
              'in your library and on its other editions.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final song in songs)
                    CheckboxListTile(
                      key: ValueKey<String>(
                        'album-studio-choose-song-${song.songId}',
                      ),
                      value: _chosen.contains(song.songId),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(
                        song.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: song.artistName.trim().isEmpty
                          ? null
                          : Text(
                              song.artistName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                      onChanged: (value) => setState(() {
                        if (value == true) {
                          _chosen.add(song.songId);
                        } else {
                          _chosen.remove(song.songId);
                        }
                      }),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey<String>('album-studio-save-songs'),
          onPressed: () => Navigator.of(context).pop(_chosen),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// The songs a new edition will start with, shown before saving. They are
/// the same songs, so their streams and playlist entries stay with them.
class _InheritedSongsPreview extends StatelessWidget {
  const _InheritedSongsPreview({required this.tracks});

  final List<LibraryTrack> tracks;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = SonusTheme.of(context).colors;

    if (tracks.isEmpty) {
      return Text(
        'The new edition starts with no songs.',
        key: const ValueKey<String>('album-studio-inherited-none'),
        style: theme.textTheme.bodySmall?.copyWith(color: colors.textSecondary),
      );
    }

    final count = tracks.length;
    return Column(
      key: const ValueKey<String>('album-studio-inherited-songs'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          count == 1
              ? 'Includes 1 song. It stays the same song, with its '
                    'streams and playlists.'
              : 'Includes $count songs. They stay the same songs, with '
                    'their streams and playlists.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        for (final (index, track) in tracks.take(12).indexed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              '${index + 1}. ${track.title}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        if (count > 12)
          Text(
            'and ${count - 12} more',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
            ),
          ),
      ],
    );
  }
}

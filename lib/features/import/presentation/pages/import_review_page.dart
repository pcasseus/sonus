import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/design/sonus_theme.dart';
import '../../../../core/design/widgets/sonus_notice_card.dart';
import '../../../../core/design/widgets/sonus_state_view.dart';
import '../../../../core/design/widgets/sonus_surface_card.dart';
import '../../../../core/design/widgets/sonus_track_tile.dart';
import '../../../artwork/application/services/artwork_assignment_service.dart';
import '../../../artwork/application/services/artwork_file_picker.dart';

import '../../../library/application/services/album_profile_editing_service.dart';
import '../../../library/presentation/widgets/album_profile_edit_dialog.dart';
import '../../../library/presentation/models/track_profile_edit_draft.dart';
import '../../../library/presentation/widgets/track_profile_edit_dialog.dart';
import '../../application/services/import_review_service.dart';
import '../../domain/entities/song_import_review.dart';
import '../controllers/import_review_controller.dart';

class ImportReviewPage extends StatefulWidget {
  const ImportReviewPage({
    super.key,
    required this.service,
    required this.userId,
    this.artworkAssignmentService,
    this.artworkFilePicker,
    this.albumProfileEditingService,
  });

  final ImportReviewService service;
  final String? userId;
  final ArtworkAssignmentService? artworkAssignmentService;
  final ArtworkFilePicker? artworkFilePicker;
  final AlbumProfileEditingService? albumProfileEditingService;

  @override
  State<ImportReviewPage> createState() => _ImportReviewPageState();
}

class _ImportReviewPageState extends State<ImportReviewPage> {
  late final ImportReviewController _controller;

  @override
  void initState() {
    super.initState();

    _controller = ImportReviewController(
      service: widget.service,
      userId: widget.userId,
      artworkAssignmentService: widget.artworkAssignmentService,
      artworkFilePicker: widget.artworkFilePicker,
      albumProfileEditingService: widget.albumProfileEditingService,
    );

    unawaited(_controller.load());
  }

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;

    return Scaffold(
      key: const ValueKey<String>('import-review-page'),
      backgroundColor: colors.background,
      appBar: AppBar(
        title: const Text('Review metadata'),
        backgroundColor: colors.background,
        surfaceTintColor: Colors.transparent,
      ),
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          if (_controller.isLoading && _controller.items.isEmpty) {
            return Center(
              child: CircularProgressIndicator(
                key: const ValueKey<String>('import-review-loading'),
                color: colors.accentPrimary,
              ),
            );
          }

          if (_controller.isComplete) {
            return const _ReviewCompleteState();
          }

          final item = _controller.currentItem;

          if (item == null) {
            return _ReviewErrorState(
              onRetry: () {
                unawaited(_controller.load());
              },
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
            children: [
              Text(
                '${_controller.remainingCount} '
                '${_controller.remainingCount == 1 ? 'song' : 'songs'} '
                'need review',
                key: const ValueKey<String>('import-review-count'),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Browse unresolved songs with Previous and Next. Correct '
                'anything that needs attention, then save when this song '
                'has been reviewed.',
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: 20),
              _ReviewNavigation(
                position: Text(
                  'Song ${_controller.currentPosition} of '
                  '${_controller.remainingCount}',
                  key: const ValueKey<String>('import-review-position'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                previous: OutlinedButton.icon(
                  key: const ValueKey<String>('import-review-previous-button'),
                  onPressed: _controller.isBusy || !_controller.canGoPrevious
                      ? null
                      : _controller.goPrevious,
                  icon: const Icon(Icons.chevron_left_rounded),
                  label: const Text('Previous'),
                ),
                next: OutlinedButton.icon(
                  key: const ValueKey<String>('import-review-next-button'),
                  onPressed: _controller.isBusy || !_controller.canGoNext
                      ? null
                      : _controller.goNext,
                  icon: const Icon(Icons.chevron_right_rounded),
                  label: const Text('Next'),
                ),
              ),
              const SizedBox(height: 16),
              SonusSurfaceCard(
                key: ValueKey<String>(
                  'import-review-item-${item.track.songId}',
                ),
                padding: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.track.title,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.track.artistName,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.track.albumTitle,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Why this needs review',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final reason in item.review.reasons)
                            Chip(label: Text(_labelForReason(reason))),
                        ],
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          key: const ValueKey<String>(
                            'import-review-edit-button',
                          ),
                          onPressed: _controller.isBusy
                              ? null
                              : () {
                                  unawaited(_editCurrent());
                                },
                          icon: _controller.isSaving
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.edit_outlined),
                          label: Text(
                            _controller.isSaving
                                ? 'Saving...'
                                : 'Review song details',
                          ),
                        ),
                      ),
                      if (_controller.canEditAlbum) ...[
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            key: const ValueKey<String>(
                              'import-review-edit-album-button',
                            ),
                            onPressed: _controller.isBusy
                                ? null
                                : () {
                                    unawaited(_editCurrentAlbum());
                                  },
                            icon: _controller.isUpdatingAlbum
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.album_outlined),
                            label: Text(
                              _controller.isUpdatingAlbum
                                  ? 'Saving album...'
                                  : 'Review album details',
                            ),
                          ),
                        ),
                      ],
                      if (_controller.canEditAlbumArtwork) ...[
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            key: const ValueKey<String>(
                              'import-review-change-album-artwork-button',
                            ),
                            onPressed: _controller.isBusy
                                ? null
                                : () {
                                    unawaited(_changeCurrentAlbumArtwork());
                                  },
                            icon: _controller.isUpdatingAlbumArtwork
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.image_rounded),
                            label: Text(
                              _controller.isUpdatingAlbumArtwork
                                  ? 'Updating album artwork...'
                                  : 'Change album artwork',
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: TextButton.icon(
                            key: const ValueKey<String>(
                              'import-review-clear-album-artwork-button',
                            ),
                            onPressed: _controller.isBusy
                                ? null
                                : () {
                                    unawaited(_clearCurrentAlbumArtwork());
                                  },
                            icon: const Icon(Icons.hide_image_rounded),
                            label: const Text('Clear album artwork'),
                          ),
                        ),
                      ],
                      if (_controller.canEditArtwork) ...[
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            key: const ValueKey<String>(
                              'import-review-change-artwork-button',
                            ),
                            onPressed: _controller.isBusy
                                ? null
                                : () {
                                    unawaited(_changeCurrentArtwork());
                                  },
                            icon: const Icon(Icons.image_rounded),
                            label: const Text('Change artwork'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: TextButton.icon(
                            key: const ValueKey<String>(
                              'import-review-clear-artwork-button',
                            ),
                            onPressed: _controller.isBusy
                                ? null
                                : () {
                                    unawaited(_clearCurrentArtwork());
                                  },
                            icon: const Icon(Icons.hide_image_rounded),
                            label: const Text('Clear artwork'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (_controller.hasError) ...[
                const SizedBox(height: 16),
                const SonusNoticeCard(
                  key: ValueKey<String>('import-review-error'),
                  tone: SonusNoticeTone.error,
                  title:
                      'Could not save this review. Your review remains '
                      'unresolved.',
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _changeCurrentAlbumArtwork() async {
    try {
      final changed = await _controller.changeCurrentAlbumArtwork();

      if (!mounted || !changed) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Album artwork updated.')));
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update album artwork.')),
      );
    }
  }

  Future<void> _clearCurrentAlbumArtwork() async {
    try {
      final changed = await _controller.clearCurrentAlbumArtwork();

      if (!mounted || !changed) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Album artwork cleared.')));
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update album artwork.')),
      );
    }
  }

  Future<void> _changeCurrentArtwork() async {
    try {
      final changed = await _controller.changeCurrentArtwork();

      if (!mounted || !changed) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Song artwork updated.')));
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update song artwork.')),
      );
    }
  }

  Future<void> _clearCurrentArtwork() async {
    try {
      final changed = await _controller.clearCurrentArtwork();

      if (!mounted || !changed) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Song artwork cleared.')));
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update song artwork.')),
      );
    }
  }

  Future<void> _editCurrentAlbum() async {
    final album = _controller.currentAlbum;

    if (album == null) {
      return;
    }

    final draft = await showDialog<AlbumProfileEditDraft>(
      context: context,
      builder: (_) =>
          AlbumProfileEditDialog(album: album, artists: _controller.artists),
    );

    if (draft == null || !mounted) {
      return;
    }

    try {
      final saved = await _controller.updateCurrentAlbum(
        title: draft.title,
        artistId: draft.artistId,
        editionTitle: draft.editionTitle,
        editionType: draft.editionType,
        releaseDate: draft.releaseDate,
        genre: draft.genre,
      );

      if (!mounted || !saved) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Album details updated. This song still needs review.'),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update album details.')),
      );
    }
  }

  Future<void> _editCurrent() async {
    final item = _controller.currentItem;

    if (item == null) {
      return;
    }

    final draft = await showDialog<TrackProfileEditDraft>(
      context: context,
      builder: (_) => TrackProfileEditDialog(
        track: item.track,
        artists: _controller.artists,
        albums: _controller.albums,
        onCreateArtist: _controller.createOrReuseArtist,
      ),
    );

    if (draft == null || !mounted) {
      return;
    }

    final saved = await _controller.resolveCurrent(
      title: draft.title,
      trackNumber: draft.trackNumber,
      discNumber: draft.discNumber,
      featuredArtists: draft.featuredArtists,
      isSingle: draft.isSingle,
      artistId: draft.artistId,
      albumId: draft.albumId,
      moveToEditionId: draft.moveToEditionId,
      placementEditionId: draft.placementEditionId,
    );

    if (!mounted || saved) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Could not save this review. The song still needs review.',
        ),
      ),
    );
  }

  String _labelForReason(ImportReviewReason reason) {
    switch (reason) {
      case ImportReviewReason.fallbackMetadata:
        return 'Metadata guessed from file or folder';
      case ImportReviewReason.unknownArtist:
        return 'Unknown artist';
      case ImportReviewReason.unknownAlbum:
        return 'Unknown album';
      case ImportReviewReason.missingTrackNumber:
        return 'Missing track number';
      case ImportReviewReason.missingDuration:
        return 'Missing duration';
      case ImportReviewReason.looseFolder:
        return 'Loose folder structure';
      case ImportReviewReason.ambiguousArtistCredit:
        return 'Artist credit needs confirmation';
      case ImportReviewReason.alternateRecording:
        return 'Possibly a different recording of an existing song';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

/// Previous, the position and Next in one row; the position moves above
/// the buttons on narrow screens or at large text so nothing overflows.
class _ReviewNavigation extends StatelessWidget {
  const _ReviewNavigation({
    required this.previous,
    required this.position,
    required this.next,
  });

  final Widget previous;
  final Widget position;
  final Widget next;

  @override
  Widget build(BuildContext context) {
    final stacked =
        MediaQuery.textScalerOf(context).scale(1) > sonusLargeTextScale ||
        MediaQuery.sizeOf(context).width < 380;

    if (stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          position,
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: previous),
              const SizedBox(width: 12),
              Expanded(child: next),
            ],
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(child: previous),
        const SizedBox(width: 12),
        position,
        const SizedBox(width: 12),
        Expanded(child: next),
      ],
    );
  }
}

class _ReviewCompleteState extends StatelessWidget {
  const _ReviewCompleteState();

  @override
  Widget build(BuildContext context) {
    return SonusStateView(
      key: const ValueKey<String>('import-review-complete'),
      icon: Icons.check_circle_outline_rounded,
      title: 'All caught up',
      message: 'There are no imported songs waiting for metadata review.',
      action: FilledButton.tonal(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Back to imports'),
      ),
    );
  }
}

class _ReviewErrorState extends StatelessWidget {
  const _ReviewErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return SonusStateView(
      icon: Icons.error_outline_rounded,
      isError: true,
      title: 'Could not load metadata reviews.',
      action: FilledButton.tonal(
        onPressed: onRetry,
        child: const Text('Try again'),
      ),
    );
  }
}

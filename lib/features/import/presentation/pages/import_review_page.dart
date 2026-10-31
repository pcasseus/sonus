import 'dart:async';
import 'dart:developer' as developer;

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
import '../../application/services/possible_recording_review_service.dart';
import '../../domain/entities/song_import_review.dart';
import '../../domain/models/pending_possible_recording.dart';
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

          final possibleRecordings = _controller.possibleRecordings;

          if (item == null && possibleRecordings.isEmpty) {
            return _ReviewErrorState(
              onRetry: () {
                unawaited(_controller.load());
              },
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
            children: [
              if (item != null) ...[
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
                    key: const ValueKey<String>(
                      'import-review-previous-button',
                    ),
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
                          item.track.displayTitle,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.track.creditLine,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.track.albumTitle,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'Why this needs review',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
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
              if (possibleRecordings.isNotEmpty) ...[
                if (item != null) const SizedBox(height: 28),
                _PossibleRecordingsSection(
                  items: possibleRecordings,
                  isBusy: _controller.isBusy,
                  onImportSeparately: (entry) {
                    unawaited(_importRecordingSeparately(entry));
                  },
                  onSameRecording: (entry) {
                    unawaited(_keepAsSameRecording(entry));
                  },
                  onNotNow: (entry) {
                    _controller.deferRecording(entry);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Left for later. It stays in Import Review.',
                        ),
                      ),
                    );
                  },
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _importRecordingSeparately(
    PendingPossibleRecording entry,
  ) async {
    final result = await _controller.importRecordingSeparately(entry);

    if (!mounted) {
      return;
    }

    final message = switch (result?.outcome) {
      PossibleRecordingOutcome.imported =>
        'Imported as its own song. It is listed for review.',
      PossibleRecordingOutcome.handledByImport =>
        'This file no longer matches that song. It was imported as usual.',
      PossibleRecordingOutcome.stillPending =>
        'This file now matches a different song. Review it again.',
      PossibleRecordingOutcome.alreadyImported =>
        'This file is already in your library. Removed from this list.',
      PossibleRecordingOutcome.fileUnavailable =>
        'This file is missing or cannot be read. Removed from this list; '
            'nothing was imported.',
      PossibleRecordingOutcome.permissionLost =>
        "Sonus can't read this folder any more. Reconnect it in Imports.",
      PossibleRecordingOutcome.checkFailed =>
        'Could not check this file. It stays in this list. Try again.',
      PossibleRecordingOutcome.candidateMissing =>
        'The song it may duplicate is no longer in your library. Removed '
            'from this list; rescan to import the file.',
      PossibleRecordingOutcome.failed ||
      null => 'Could not import this file. It stays in this list.',
    };

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _keepAsSameRecording(PendingPossibleRecording entry) async {
    final saved = await _controller.keepAsSameRecording(entry);

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          saved
              ? 'Marked as the same recording. Nothing was added to your '
                    'library.'
              : 'Could not save this choice. The file stays in this list.',
        ),
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
        releaseDatePrecision: draft.releaseDatePrecision,
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

    final List<TrackProfileCreditDraft> initialCredits;

    try {
      initialCredits = trackStudioInitialCredits(
        credits: await _controller.loadCurrentCredits(),
        legacyFeaturedArtists: item.track.featuredArtists,
        primaryArtistId: item.track.artistId,
        primaryArtistName: item.track.artistName,
      );
    } catch (error, stackTrace) {
      developer.log(
        'Import Review could not read song credits (${error.runtimeType})',
        name: 'sonus.import',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open song details. Try again.'),
          ),
        );
      }
      return;
    }

    if (!mounted) {
      return;
    }

    final draft = await showDialog<TrackProfileEditDraft>(
      context: context,
      builder: (_) => TrackProfileEditDialog(
        track: item.track,
        initialAdditionalCredits: initialCredits,
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
      additionalCredits: draft.additionalCredits.map(
        (credit) => credit.toInput(),
      ),
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

/// Files kept out of the library because they may be a different recording
/// of a song already in it, each with the user's three choices.
class _PossibleRecordingsSection extends StatelessWidget {
  const _PossibleRecordingsSection({
    required this.items,
    required this.isBusy,
    required this.onImportSeparately,
    required this.onSameRecording,
    required this.onNotNow,
  });

  final List<PossibleRecordingItem> items;
  final bool isBusy;
  final ValueChanged<PendingPossibleRecording> onImportSeparately;
  final ValueChanged<PendingPossibleRecording> onSameRecording;
  final ValueChanged<PendingPossibleRecording> onNotNow;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final secondary = SonusTheme.of(context).colors.textSecondary;

    return Column(
      key: const ValueKey<String>('import-review-possible-recordings'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Possible different recordings',
          style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          'These files have the same title as a song in your library but '
          'sit at another track position. They were not imported. Choose '
          'what each one is.',
          style: textTheme.bodyLarge?.copyWith(color: secondary),
        ),
        for (final item in items) ...[
          const SizedBox(height: 16),
          _PossibleRecordingCard(
            item: item,
            isBusy: isBusy,
            onImportSeparately: () => onImportSeparately(item.entry),
            onSameRecording: () => onSameRecording(item.entry),
            onNotNow: () => onNotNow(item.entry),
          ),
        ],
      ],
    );
  }
}

class _PossibleRecordingCard extends StatelessWidget {
  const _PossibleRecordingCard({
    required this.item,
    required this.isBusy,
    required this.onImportSeparately,
    required this.onSameRecording,
    required this.onNotNow,
  });

  final PossibleRecordingItem item;
  final bool isBusy;
  final VoidCallback onImportSeparately;
  final VoidCallback onSameRecording;
  final VoidCallback onNotNow;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final secondary = SonusTheme.of(context).colors.textSecondary;
    final entry = item.entry;
    final candidate = item.candidate;
    final key = entry.normalizedPath;

    return SonusSurfaceCard(
      key: ValueKey<String>('possible-recording-$key'),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            entry.title,
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            '${entry.artistName} · ${entry.albumTitle}',
            style: textTheme.bodyLarge,
          ),
          const SizedBox(height: 2),
          Text(
            _position(
              entry.discNumber,
              entry.trackNumber,
              entry.durationSeconds,
            ),
            style: textTheme.bodyMedium?.copyWith(color: secondary),
          ),
          const SizedBox(height: 2),
          Text(
            entry.displayPath,
            style: textTheme.bodySmall?.copyWith(color: secondary),
          ),
          const SizedBox(height: 12),
          Text(
            candidate == null
                ? 'The song it may duplicate is no longer in your library.'
                : 'May be the same as "${candidate.title}" '
                      '(${_position(candidate.discNumber, candidate.trackNumber, candidate.durationSeconds)})',
            style: textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                key: ValueKey<String>('possible-recording-import-$key'),
                onPressed: isBusy ? null : onImportSeparately,
                child: const Text('Import separately'),
              ),
              OutlinedButton(
                key: ValueKey<String>('possible-recording-same-$key'),
                onPressed: isBusy ? null : onSameRecording,
                child: const Text('Same recording'),
              ),
              TextButton(
                key: ValueKey<String>('possible-recording-later-$key'),
                onPressed: isBusy ? null : onNotNow,
                child: const Text('Not now'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _position(int disc, int track, int durationSeconds) {
    return [
      if (disc > 0) 'Disc $disc',
      track > 0 ? 'Track $track' : 'No track number',
      durationSeconds > 0 ? sonusFormatDuration(durationSeconds) : 'No length',
    ].join(' · ');
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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/design/sonus_theme.dart';
import '../../../../core/design/widgets/sonus_artwork_image.dart';
import '../../../../core/design/widgets/sonus_form_section.dart';
import '../../../../core/design/sonus_text_scale.dart';
import '../../../../core/identity/text_normalizer.dart';
import '../../application/models/external_metadata_search_query.dart';
import '../../application/models/library_album.dart';
import '../../application/models/library_artist.dart';
import '../../application/models/library_track.dart';
import '../../application/models/song_display_title.dart';
import '../../application/services/external_metadata_application_service.dart';
import '../../application/services/external_metadata_proposal_service.dart';
import '../../application/services/metadata_provider.dart';
import '../../application/services/song_artist_credit_service.dart';
import '../../application/services/track_profile_editing_service.dart';
import '../../domain/entities/song.dart';
import '../../domain/entities/song_artist_credit.dart';
import '../models/track_profile_edit_draft.dart';
import '../widgets/musicbrainz_search_dialog.dart';
import '../widgets/track_credit_editor_dialog.dart';

/// Saves Track Studio's credits at once (UI redesign E1) and returns them
/// as now stored, or null when nothing could be saved here.
typedef TrackStudioCreditSaver =
    Future<List<TrackProfileCreditDraft>?> Function(
      List<TrackProfileCreditDraft> credits,
    );

/// A [TrackStudioCreditSaver] from a save of the song's credits: converts
/// what was stored back into the editor's credits.
TrackStudioCreditSaver trackStudioCreditSaver({
  required LibraryTrack track,
  required Future<TrackCreditSaveResult?> Function(
    Iterable<SongArtistCreditInput> credits,
  )
  save,
}) {
  return (credits) async {
    final result = await save(credits.map((credit) => credit.toInput()));

    if (result == null) {
      return null;
    }

    return trackStudioInitialCredits(
      credits: result.credits,
      legacyFeaturedArtists: result.song.featuredArtists,
      primaryArtistId: result.song.artistId,
      primaryArtistName: track.artistName,
    );
  };
}

class TrackStudioPage extends StatefulWidget {
  const TrackStudioPage({
    super.key,
    required this.track,
    this.artists = const [],
    this.albums = const [],
    this.initialAdditionalCredits = const [],
    this.onCreateArtist,
    this.onSaveCredits,
    this.onChangeArtwork,
    this.onClearArtwork,
    this.canEditDetails = true,
    this.userId,
    this.metadataProvider,
    this.externalMetadataApplicationService,
    this.externalMetadataProposalService,
    this.onMetadataApplied,
  });

  final LibraryTrack track;
  final List<LibraryArtist> artists;
  final List<LibraryAlbum> albums;
  final List<TrackProfileCreditDraft> initialAdditionalCredits;
  final TrackArtistCreationCallback? onCreateArtist;

  /// When set, saving or removing a credit in the credit editor saves the
  /// song's credits at once (UI redesign E1, D7); the Studio's other edits
  /// stay unsaved drafts. Without it, credits save with the rest.
  final TrackStudioCreditSaver? onSaveCredits;
  final Future<void> Function()? onChangeArtwork;
  final Future<void> Function()? onClearArtwork;
  final bool canEditDetails;
  final String? userId;
  final MetadataProvider? metadataProvider;
  final ExternalMetadataApplicationService? externalMetadataApplicationService;
  final ExternalMetadataProposalService? externalMetadataProposalService;
  final Future<void> Function()? onMetadataApplied;

  @override
  State<TrackStudioPage> createState() => _TrackStudioPageState();
}

/// Artwork, title and credit of the song being edited.
class _TrackStudioSummary extends StatelessWidget {
  const _TrackStudioSummary({required this.track});

  final LibraryTrack track;

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;
    final theme = Theme.of(context);

    return MergeSemantics(
      child: Row(
        children: [
          SonusArtworkImage(path: track.artworkPath, size: 64),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.displayTitle,
                  key: const ValueKey<String>('track-studio-heading'),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  [
                    track.creditLine,
                    if (track.albumDisplayTitle.trim().isNotEmpty)
                      track.albumDisplayTitle,
                  ].join(' • '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TrackStudioPageState extends State<TrackStudioPage> {
  final _formKey = GlobalKey<FormState>();
  bool _isApplyingMusicBrainz = false;

  late final TextEditingController _titleController;
  late final TextEditingController _trackNumberController;
  late final TextEditingController _discNumberController;
  late final TextEditingController _versionLabelController;

  late List<TrackProfileCreditDraft> _additionalCredits;

  /// The credits as stored: the baseline the Studio's own Save compares
  /// against, updated after every credit save.
  late List<TrackProfileCreditDraft> _savedCredits;
  bool _isSavingCredits = false;

  /// Whether Back must ask first, kept current as text fields are typed in
  /// (they do not rebuild the page on their own).
  bool _guardsBack = false;
  late List<LibraryArtist> _artists;
  late String _artistId;
  late String _albumId;
  late bool _isSingle;
  late Set<SongVersionCharacteristic> _versionCharacteristics;
  late SongReleaseStatus _releaseStatus;
  late bool _isLeak;

  @override
  void initState() {
    super.initState();

    _titleController = TextEditingController(text: widget.track.title);
    _trackNumberController = TextEditingController(
      text: widget.track.trackNumber.toString(),
    );
    _discNumberController = TextEditingController(
      text: widget.track.discNumber.toString(),
    );
    _versionLabelController = TextEditingController(
      text: widget.track.versionLabel ?? '',
    );
    for (final controller in [
      _titleController,
      _trackNumberController,
      _discNumberController,
      _versionLabelController,
    ]) {
      controller.addListener(_onTextEdited);
    }
    _additionalCredits = List<TrackProfileCreditDraft>.from(
      widget.initialAdditionalCredits,
    );
    _savedCredits = List<TrackProfileCreditDraft>.unmodifiable(
      widget.initialAdditionalCredits,
    );
    _artists = List<LibraryArtist>.from(widget.artists);
    _artistId = widget.track.artistId;
    _albumId = widget.track.albumId;
    _isSingle = widget.track.isSingle;
    _versionCharacteristics = widget.track.versionCharacteristics.toSet();
    _releaseStatus = widget.track.releaseStatus;
    _isLeak = widget.track.isLeak;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _trackNumberController.dispose();
    _discNumberController.dispose();
    _versionLabelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final availableAlbums = widget.albums
        .where(
          (album) =>
              album.primaryEditionId != null &&
              album.primaryEditionId!.trim().isNotEmpty,
        )
        .toList(growable: false);

    final canSelectArtist = _artists.any(
      (artist) => artist.artistId == _artistId,
    );

    final canSelectAlbum = availableAlbums.any(
      (album) => album.albumId == _albumId,
    );

    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final gutter = tokens.metrics.pageGutter;
    final canSearchMusicBrainz =
        widget.canEditDetails &&
        widget.metadataProvider != null &&
        widget.externalMetadataApplicationService != null &&
        widget.externalMetadataProposalService != null &&
        widget.onMetadataApplied != null &&
        !_isApplyingMusicBrainz;
    // Number fields side by side only when both labels fit.
    final stackNumbers =
        MediaQuery.textScalerOf(context).scale(1) > sonusLargeTextScale ||
        MediaQuery.sizeOf(context).width < 360;

    final trackNumberField = TextFormField(
      key: const ValueKey<String>('track-number-field'),
      controller: _trackNumberController,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.next,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: const InputDecoration(labelText: 'Track number'),
      validator: (value) {
        final number = int.tryParse(value?.trim() ?? '');

        if (number == null || number < 0) {
          return 'Enter a valid track number.';
        }

        return null;
      },
    );
    final discNumberField = TextFormField(
      key: const ValueKey<String>('track-disc-number-field'),
      controller: _discNumberController,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.next,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: const InputDecoration(labelText: 'Disc number'),
      validator: (value) {
        final number = int.tryParse(value?.trim() ?? '');

        if (number == null || number < 0) {
          return 'Enter a valid disc number.';
        }

        return null;
      },
    );

    return PopScope<Object?>(
      // Saved credits stay saved; only the other, unsaved edits can be lost,
      // so leaving with any asks first.
      canPop: !(_guardsBack = _hasUnsavedChanges),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          unawaited(_confirmDiscard());
        }
      },
      child: Scaffold(
        key: const ValueKey<String>('track-studio-page'),
        backgroundColor: colors.background,
        appBar: AppBar(
          title: const Text('Track Studio'),
          backgroundColor: colors.background,
          surfaceTintColor: Colors.transparent,
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton(
                key: const ValueKey<String>('track-studio-save-button'),
                onPressed: widget.canEditDetails ? _submit : null,
                style: FilledButton.styleFrom(
                  backgroundColor: colors.accentPrimary,
                  foregroundColor: colors.onAccentPrimary,
                  minimumSize: const Size(64, 40),
                ),
                child: const Text('Save'),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: Form(
            key: _formKey,
            child: ListView(
              // Dragging the form hides the keyboard, so fields stay visible.
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(gutter, 8, gutter, 32),
              children: [
                _TrackStudioSummary(track: widget.track),
                const SizedBox(height: 16),
                SonusFormSection(
                  title: 'Metadata and artwork',
                  icon: Icons.image_outlined,
                  padding: const EdgeInsets.only(bottom: 6),
                  children: [
                    ListTile(
                      key: const ValueKey<String>(
                        'track-studio-search-musicbrainz',
                      ),
                      leading: const Icon(Icons.travel_explore_rounded),
                      title: const Text('Search MusicBrainz'),
                      subtitle: const Text(
                        'Match this recording and apply allowed metadata.',
                      ),
                      enabled: canSearchMusicBrainz,
                      onTap: canSearchMusicBrainz
                          ? () => unawaited(_searchMusicBrainz())
                          : null,
                    ),
                    ListTile(
                      key: const ValueKey<String>(
                        'track-studio-change-artwork',
                      ),
                      leading: const Icon(Icons.image_rounded),
                      title: const Text('Change artwork'),
                      enabled: widget.onChangeArtwork != null,
                      onTap: widget.onChangeArtwork == null
                          ? null
                          : () {
                              widget.onChangeArtwork!();
                            },
                    ),
                    ListTile(
                      key: const ValueKey<String>('track-studio-clear-artwork'),
                      leading: const Icon(Icons.hide_image_rounded),
                      title: const Text('Clear artwork'),
                      enabled: widget.onClearArtwork != null,
                      onTap: widget.onClearArtwork == null
                          ? null
                          : () {
                              widget.onClearArtwork!();
                            },
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                SonusFormSection(
                  title: 'Details',
                  icon: Icons.edit_outlined,
                  children: [
                    TextFormField(
                      key: const ValueKey<String>('track-title-field'),
                      controller: _titleController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Song title',
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Song title cannot be blank.';
                        }

                        return null;
                      },
                    ),
                    const SizedBox(height: 12),

                    if (canSelectArtist) ...[
                      DropdownButtonFormField<String>(
                        key: const ValueKey<String>(
                          'track-primary-artist-field',
                        ),
                        isExpanded: true,
                        initialValue: _artistId,
                        decoration: const InputDecoration(
                          labelText: 'Primary artist',
                        ),
                        items: [
                          for (final artist in _artists)
                            DropdownMenuItem(
                              value: artist.artistId,
                              child: Text(
                                artist.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }

                          setState(() {
                            _artistId = value;
                          });
                        },
                      ),
                      const SizedBox(height: 4),
                    ],

                    if (widget.onCreateArtist != null) ...[
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          key: const ValueKey<String>(
                            'track-add-primary-artist-button',
                          ),
                          onPressed: _createArtist,
                          icon: const Icon(Icons.person_add_alt_1_rounded),
                          label: const Text('Add new artist...'),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],

                    if (canSelectAlbum) ...[
                      DropdownButtonFormField<String>(
                        key: const ValueKey<String>('track-album-field'),
                        isExpanded: true,
                        initialValue: _albumId,
                        decoration: const InputDecoration(labelText: 'Album'),
                        items: [
                          for (final album in availableAlbums)
                            DropdownMenuItem(
                              value: album.albumId,
                              child: Text(
                                '${album.displayTitle} — ${album.artistName}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }

                          setState(() {
                            _albumId = value;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                    ],

                    if (stackNumbers) ...[
                      trackNumberField,
                      const SizedBox(height: 12),
                      discNumberField,
                    ] else
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: trackNumberField),
                          const SizedBox(width: 12),
                          Expanded(child: discNumberField),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 16),

                SonusFormSection(
                  title: 'Version',
                  icon: Icons.tune_rounded,
                  children: [
                    TextFormField(
                      key: const ValueKey<String>('track-version-label-field'),
                      controller: _versionLabelController,
                      decoration: const InputDecoration(
                        labelText: 'Version label',
                        hintText: 'Live, Remix, 2024 Remaster...',
                      ),
                    ),
                    const SizedBox(height: 12),

                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final characteristic
                            in SongVersionCharacteristic.values)
                          FilterChip(
                            key: ValueKey<String>(
                              'track-version-${characteristic.name}',
                            ),
                            label: Text(
                              songVersionCharacteristicLabel(characteristic),
                            ),
                            selected: _versionCharacteristics.contains(
                              characteristic,
                            ),
                            onSelected: (selected) {
                              setState(() {
                                if (selected) {
                                  _versionCharacteristics.add(characteristic);
                                } else {
                                  _versionCharacteristics.remove(
                                    characteristic,
                                  );
                                }
                              });
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    DropdownButtonFormField<SongReleaseStatus>(
                      key: const ValueKey<String>('track-release-status-field'),
                      isExpanded: true,
                      initialValue: _releaseStatus,
                      decoration: const InputDecoration(
                        labelText: 'Release status',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: SongReleaseStatus.released,
                          child: Text('Released'),
                        ),
                        DropdownMenuItem(
                          value: SongReleaseStatus.unreleased,
                          child: Text('Unreleased'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }

                        setState(() {
                          _releaseStatus = value;
                        });
                      },
                    ),

                    SwitchListTile(
                      key: const ValueKey<String>('track-leak-toggle'),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Leak'),
                      subtitle: const Text(
                        'Mark this track as leaked material.',
                      ),
                      value: _isLeak,
                      onChanged: (value) {
                        setState(() {
                          _isLeak = value;
                        });
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                SonusFormSection(
                  title: 'Credits',
                  icon: Icons.people_alt_outlined,
                  children: [
                    AbsorbPointer(
                      absorbing: _isSavingCredits,
                      child: TrackCreditList(
                        credits: _additionalCredits,
                        artists: _artists,
                        primaryArtistId: _artistId,
                        primaryArtistName: _primaryArtistName,
                        onChanged: (credits) {
                          unawaited(_onCreditsChanged(credits));
                        },
                      ),
                    ),
                    SwitchListTile(
                      key: const ValueKey<String>('track-single-toggle'),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Single'),
                      value: _isSingle,
                      onChanged: (value) {
                        setState(() {
                          _isSingle = value;
                        });
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _searchMusicBrainz() async {
    final provider = widget.metadataProvider;
    final applicationService = widget.externalMetadataApplicationService;
    final proposalService = widget.externalMetadataProposalService;
    final onApplied = widget.onMetadataApplied;

    if (!widget.canEditDetails ||
        provider == null ||
        applicationService == null ||
        proposalService == null ||
        onApplied == null ||
        _isApplyingMusicBrainz) {
      return;
    }

    final shouldProceed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Search MusicBrainz?'),
          content: const Text(
            'If metadata is applied, Track Studio will close and '
            'any unsaved form edits will be discarded.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const ValueKey<String>('track-studio-musicbrainz-continue'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Continue'),
            ),
          ],
        );
      },
    );

    if (!mounted || shouldProceed != true) {
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
              entityKind: ExternalMetadataEntityKind.track,
              title: widget.track.title,
              artistName: widget.track.artistName,
              albumTitle: widget.track.albumTitle,
              durationSeconds: widget.track.durationSeconds,
            ),
            previewer: (candidate) {
              return proposalService.previewTrack(
                songId: widget.track.songId,
                candidate: candidate,
              );
            },
            applier: (candidate) {
              return applicationService.applyTrackCandidate(
                userId: widget.userId,
                songId: widget.track.songId,
                candidate: candidate,
              );
            },
            reviewedApplier: (candidate, confirmedFields) {
              return applicationService.confirmReviewedTrackCandidate(
                userId: widget.userId,
                songId: widget.track.songId,
                candidate: candidate,
                confirmedFields: confirmedFields,
              );
            },
          );
        },
      );

      if (!mounted || selection == null) {
        return;
      }

      var refreshFailed = false;

      try {
        await onApplied();
      } catch (_) {
        refreshFailed = true;
      }

      if (!mounted) {
        return;
      }

      final result = selection.result;

      final message = refreshFailed
          ? 'MusicBrainz metadata was applied, but the library could not refresh.'
          : result.requiresReview
          ? 'MusicBrainz match selected. Some fields require review.'
          : result.hasProtectedFields
          ? 'MusicBrainz match selected. Protected fields were preserved.'
          : result.entityChanged
          ? 'MusicBrainz track metadata applied.'
          : 'MusicBrainz metadata already matched this track.';

      final messenger = ScaffoldMessenger.of(context);

      // Close without returning an edit draft or saving stale form values.
      Navigator.of(context).pop();

      // The messenger belongs to the app, not the closing Studio route.
      messenger.showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not complete the MusicBrainz operation.'),
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

  Future<void> _createArtist() async {
    final onCreateArtist = widget.onCreateArtist;

    if (onCreateArtist == null) {
      return;
    }

    final nameController = TextEditingController();

    try {
      final name = await showDialog<String>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Add new artist'),
            content: TextField(
              key: const ValueKey<String>('track-new-artist-name-field'),
              controller: nameController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Artist name'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                key: const ValueKey<String>('track-new-artist-save-button'),
                onPressed: () {
                  final value = nameController.text.trim();

                  if (value.isEmpty) {
                    return;
                  }

                  Navigator.of(dialogContext).pop(value);
                },
                child: const Text('Add artist'),
              ),
            ],
          );
        },
      );

      if (!mounted || name == null) {
        return;
      }

      final artist = await onCreateArtist(name);

      if (!mounted || artist == null) {
        return;
      }

      setState(() {
        final existingIndex = _artists.indexWhere(
          (existing) => existing.artistId == artist.artistId,
        );

        if (existingIndex >= 0) {
          _artists[existingIndex] = artist;
        } else {
          _artists.add(artist);
        }

        _artistId = artist.artistId;
      });
    } finally {
      nameController.dispose();
    }
  }

  /// Saves edited credits at once when the Studio can (E1), against the
  /// song's stored primary artist; otherwise keeps them as a draft.
  Future<void> _onCreditsChanged(List<TrackProfileCreditDraft> credits) async {
    final save = widget.onSaveCredits;

    if (save == null || !widget.canEditDetails) {
      setState(() => _additionalCredits = credits);
      return;
    }

    final messenger = ScaffoldMessenger.of(context);

    // An unsaved primary artist change: the credits would be checked
    // against an artist that is not stored, so they wait for Save.
    if (_artistId != widget.track.artistId) {
      setState(() => _additionalCredits = credits);
      messenger.showSnackBar(
        const SnackBar(
          key: ValueKey<String>('track-studio-credits-wait-message'),
          content: Text(
            'The new primary artist is not saved yet, so these credits will '
            'be saved with your other changes.',
          ),
        ),
      );
      return;
    }

    final redundantNames = TrackProfileEditingService.redundantCreditNames(
      credits.map((credit) => credit.toInput()),
      primaryArtistId: widget.track.artistId,
      primaryCanonicalName: TextNormalizer.canonicalize(
        widget.track.artistName,
      ),
    );

    if (redundantNames.isNotEmpty) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${redundantNames.first} is already credited as the primary '
            'artist or in another credit, so the credits were not saved.',
          ),
        ),
      );
      return;
    }

    final previous = _additionalCredits;
    setState(() {
      _additionalCredits = credits;
      _isSavingCredits = true;
    });

    try {
      final saved = await save(credits);

      if (!mounted) {
        return;
      }

      if (saved == null) {
        // Nothing could be saved here: the credits stay a draft for Save.
        return;
      }

      setState(() {
        _additionalCredits = List<TrackProfileCreditDraft>.of(saved);
        _savedCredits = List<TrackProfileCreditDraft>.unmodifiable(saved);
      });
      messenger.showSnackBar(
        const SnackBar(
          key: ValueKey<String>('track-studio-credits-saved-message'),
          content: Text('Credits saved.'),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() => _additionalCredits = previous);
      messenger.showSnackBar(
        SnackBar(
          key: const ValueKey<String>('track-studio-credits-failed-message'),
          content: Text(
            error is TrackCreditPrimaryArtistChangedException
                ? 'This song\'s primary artist changed, so the credits were '
                      'not saved.'
                : 'Could not save the credits.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSavingCredits = false);
      }
    }
  }

  void _onTextEdited() {
    if (_hasUnsavedChanges != _guardsBack) {
      setState(() {});
    }
  }

  /// Whether leaving would lose an edit: credits differ from what is stored
  /// or another field differs from the song.
  bool get _hasUnsavedChanges {
    final track = widget.track;

    return _titleController.text.trim() != track.title.trim() ||
        _trackNumberController.text.trim() != track.trackNumber.toString() ||
        _discNumberController.text.trim() != track.discNumber.toString() ||
        _versionLabelController.text.trim() !=
            (track.versionLabel ?? '').trim() ||
        _artistId != track.artistId ||
        _albumId != track.albumId ||
        _isSingle != track.isSingle ||
        _releaseStatus != track.releaseStatus ||
        _isLeak != track.isLeak ||
        !_sameCharacteristics(
          _versionCharacteristics,
          track.versionCharacteristics,
        ) ||
        !_sameCredits(_additionalCredits, _savedCredits);
  }

  static bool _sameCharacteristics(
    Set<SongVersionCharacteristic> edited,
    List<SongVersionCharacteristic> stored,
  ) => edited.length == stored.toSet().length && edited.containsAll(stored);

  static bool _sameCredits(
    List<TrackProfileCreditDraft> first,
    List<TrackProfileCreditDraft> second,
  ) {
    if (first.length != second.length) {
      return false;
    }

    for (var index = 0; index < first.length; index++) {
      final a = first[index];
      final b = second[index];

      if (a.creditedName != b.creditedName ||
          a.role != b.role ||
          a.artistId != b.artistId) {
        return false;
      }
    }

    return true;
  }

  Future<void> _confirmDiscard() async {
    final navigator = Navigator.of(context);
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          key: const ValueKey<String>('track-studio-discard-dialog'),
          title: const Text('Discard unsaved changes?'),
          content: Text(
            widget.onSaveCredits == null
                ? 'Your changes to this song will be lost.'
                : 'Your other changes to this song will be lost. Credits '
                      'you already saved stay saved.',
          ),
          actions: [
            TextButton(
              key: const ValueKey<String>('track-studio-keep-editing'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Keep editing'),
            ),
            FilledButton(
              key: const ValueKey<String>('track-studio-discard'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Discard'),
            ),
          ],
        );
      },
    );

    if (!mounted || discard != true) {
      return;
    }

    // Leaves without a draft, so nothing else is saved.
    navigator.pop();
  }

  String get _primaryArtistName {
    for (final artist in _artists) {
      if (artist.artistId == _artistId) {
        return artist.name;
      }
    }

    return widget.track.artistName;
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // Changing the primary artist can make a credit repeat them; saving
    // would drop it, so say so instead of reporting a full save.
    final redundantNames = TrackProfileEditingService.redundantCreditNames(
      _additionalCredits.map((credit) => credit.toInput()),
      primaryArtistId: _artistId,
      primaryCanonicalName: TextNormalizer.canonicalize(_primaryArtistName),
    );

    if (redundantNames.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${redundantNames.first} is already credited as the primary '
            'artist or in another credit. Edit or remove that credit to save.',
          ),
        ),
      );
      return;
    }

    final moveToEditionId = _moveToEditionId();

    final featuredArtists = _additionalCredits
        .where((credit) => credit.role == SongArtistCreditRole.featured)
        .map((credit) => credit.creditedName)
        .toList(growable: false);
    Navigator.of(context).pop(
      TrackProfileEditDraft(
        title: _titleController.text.trim(),
        trackNumber: int.parse(_trackNumberController.text.trim()),
        discNumber: int.parse(_discNumberController.text.trim()),
        featuredArtists: featuredArtists,
        additionalCredits: List<TrackProfileCreditDraft>.unmodifiable(
          _additionalCredits,
        ),
        isSingle: _isSingle,
        versionLabel: _versionLabelController.text.trim().isEmpty
            ? null
            : _versionLabelController.text.trim(),
        versionCharacteristics: List<SongVersionCharacteristic>.unmodifiable(
          SongVersionCharacteristic.values.where(
            _versionCharacteristics.contains,
          ),
        ),
        releaseStatus: _releaseStatus,
        isLeak: _isLeak,
        artistId: _artistId,
        albumId: _albumId,
        moveToEditionId: moveToEditionId,
        placementEditionId: widget.track.albumEditionId,
      ),
    );
  }

  /// The edition to move into, only when the user picked another album:
  /// that album's primary edition. Saving within the same album never
  /// changes edition memberships.
  String? _moveToEditionId() {
    if (_albumId == widget.track.albumId) {
      return null;
    }

    for (final album in widget.albums) {
      if (album.albumId != _albumId) {
        continue;
      }

      final primaryEditionId = album.primaryEditionId?.trim();

      return primaryEditionId == null || primaryEditionId.isEmpty
          ? null
          : primaryEditionId;
    }

    return null;
  }
}

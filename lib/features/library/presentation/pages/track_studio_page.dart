import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../application/models/external_metadata_search_query.dart';
import '../../application/models/library_album.dart';
import '../../application/models/library_artist.dart';
import '../../application/models/library_track.dart';
import '../../application/services/external_metadata_application_service.dart';
import '../../application/services/external_metadata_proposal_service.dart';
import '../../application/services/metadata_provider.dart';
import '../../domain/entities/song.dart';
import '../../domain/entities/song_artist_credit.dart';
import '../models/track_profile_edit_draft.dart';
import '../widgets/musicbrainz_search_dialog.dart';

class TrackStudioPage extends StatefulWidget {
  const TrackStudioPage({
    super.key,
    required this.track,
    this.artists = const [],
    this.albums = const [],
    this.initialAdditionalCredits = const [],
    this.onCreateArtist,
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

class _TrackStudioPageState extends State<TrackStudioPage> {
  final _formKey = GlobalKey<FormState>();
  bool _isApplyingMusicBrainz = false;

  late final TextEditingController _titleController;
  late final TextEditingController _trackNumberController;
  late final TextEditingController _discNumberController;
  late final TextEditingController _versionLabelController;

  late List<TrackProfileCreditDraft> _additionalCredits;
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
    _additionalCredits = List<TrackProfileCreditDraft>.from(
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

    return Scaffold(
      key: const ValueKey<String>('track-studio-page'),
      appBar: AppBar(
        title: const Text('Track Studio'),
        actions: [
          TextButton(
            key: const ValueKey<String>('track-studio-save-button'),
            onPressed: widget.canEditDetails ? _submit : null,
            child: const Text('Save'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              Text(
                widget.track.title,
                key: const ValueKey<String>('track-studio-heading'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 20),

              Card(
                child: ListTile(
                  key: const ValueKey<String>(
                    'track-studio-search-musicbrainz',
                  ),
                  leading: const Icon(Icons.travel_explore_rounded),
                  title: const Text('Search MusicBrainz'),
                  subtitle: const Text(
                    'Match this recording and apply allowed metadata.',
                  ),
                  enabled:
                      widget.canEditDetails &&
                      widget.metadataProvider != null &&
                      widget.externalMetadataApplicationService != null &&
                      widget.externalMetadataProposalService != null &&
                      widget.onMetadataApplied != null &&
                      !_isApplyingMusicBrainz,
                  onTap:
                      widget.canEditDetails &&
                          widget.metadataProvider != null &&
                          widget.externalMetadataApplicationService != null &&
                          widget.externalMetadataProposalService != null &&
                          widget.onMetadataApplied != null &&
                          !_isApplyingMusicBrainz
                      ? () => unawaited(_searchMusicBrainz())
                      : null,
                ),
              ),
              const SizedBox(height: 20),

              Text('Details', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),

              TextFormField(
                key: const ValueKey<String>('track-title-field'),
                controller: _titleController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Song title'),
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
                  key: const ValueKey<String>('track-primary-artist-field'),
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
                const SizedBox(height: 12),
              ],

              if (widget.onCreateArtist != null) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const ValueKey<String>(
                      'track-add-primary-artist-button',
                    ),
                    onPressed: _createArtist,
                    icon: const Icon(Icons.person_add_alt_1_rounded),
                    label: const Text('Add new artist...'),
                  ),
                ),
                const SizedBox(height: 12),
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
                          '${album.title} — ${album.artistName}',
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

              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      key: const ValueKey<String>('track-number-field'),
                      controller: _trackNumberController,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.next,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'Track number',
                      ),
                      validator: (value) {
                        final number = int.tryParse(value?.trim() ?? '');

                        if (number == null || number < 0) {
                          return 'Enter a valid track number.';
                        }

                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      key: const ValueKey<String>('track-disc-number-field'),
                      controller: _discNumberController,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.next,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'Disc number',
                      ),
                      validator: (value) {
                        final number = int.tryParse(value?.trim() ?? '');

                        if (number == null || number < 0) {
                          return 'Enter a valid disc number.';
                        }

                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              Text('Version', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),

              TextFormField(
                key: const ValueKey<String>('track-version-label-field'),
                controller: _versionLabelController,
                decoration: const InputDecoration(
                  labelText: 'Version label',
                  hintText: 'Live, Remix, 2024 Remaster...',
                ),
              ),
              const SizedBox(height: 12),

              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
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
                          _versionCharacteristicLabel(characteristic),
                        ),
                        selected: _versionCharacteristics.contains(
                          characteristic,
                        ),
                        onSelected: (selected) {
                          setState(() {
                            if (selected) {
                              _versionCharacteristics.add(characteristic);
                            } else {
                              _versionCharacteristics.remove(characteristic);
                            }
                          });
                        },
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              DropdownButtonFormField<SongReleaseStatus>(
                key: const ValueKey<String>('track-release-status-field'),
                initialValue: _releaseStatus,
                decoration: const InputDecoration(labelText: 'Release status'),
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
                subtitle: const Text('Mark this track as leaked material.'),
                value: _isLeak,
                onChanged: (value) {
                  setState(() {
                    _isLeak = value;
                  });
                },
              ),

              const SizedBox(height: 24),

              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Credits',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  TextButton.icon(
                    key: const ValueKey<String>('track-add-credit-button'),
                    onPressed: _addCredit,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add credit'),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              if (_additionalCredits.isEmpty)
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('No additional artist credits.'),
                )
              else
                for (var index = 0; index < _additionalCredits.length; index++)
                  Card(
                    key: ValueKey<String>('track-credit-row-$index'),
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(_additionalCredits[index].creditedName),
                      subtitle: Text(
                        _creditRoleLabel(_additionalCredits[index].role),
                      ),
                      trailing: Wrap(
                        spacing: 4,
                        children: [
                          IconButton(
                            key: ValueKey<String>('track-edit-credit-$index'),
                            tooltip: 'Edit credit',
                            onPressed: () => _editCredit(index),
                            icon: const Icon(Icons.edit_rounded),
                          ),
                          IconButton(
                            key: ValueKey<String>('track-remove-credit-$index'),
                            tooltip: 'Remove credit',
                            onPressed: () => _removeCredit(index),
                            icon: const Icon(Icons.delete_outline_rounded),
                          ),
                        ],
                      ),
                    ),
                  ),

              const SizedBox(height: 8),

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

              const SizedBox(height: 24),
              Text('Artwork', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),

              Card(
                margin: EdgeInsets.zero,
                child: Column(
                  children: [
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
                    const Divider(height: 1),
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
              ),
            ],
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

  String _versionCharacteristicLabel(SongVersionCharacteristic characteristic) {
    switch (characteristic) {
      case SongVersionCharacteristic.remix:
        return 'Remix';
      case SongVersionCharacteristic.live:
        return 'Live';
      case SongVersionCharacteristic.acoustic:
        return 'Acoustic';
      case SongVersionCharacteristic.demo:
        return 'Demo';
      case SongVersionCharacteristic.instrumental:
        return 'Instrumental';
      case SongVersionCharacteristic.edit:
        return 'Edit';
      case SongVersionCharacteristic.radioEdit:
        return 'Radio Edit';
      case SongVersionCharacteristic.extended:
        return 'Extended';
      case SongVersionCharacteristic.remaster:
        return 'Remaster';
      case SongVersionCharacteristic.alternate:
        return 'Alternate';
    }
  }

  String _creditRoleLabel(SongArtistCreditRole role) {
    switch (role) {
      case SongArtistCreditRole.coPrimary:
        return 'Co-primary';
      case SongArtistCreditRole.featured:
        return 'Featured';
      case SongArtistCreditRole.guest:
        return 'Guest';
      case SongArtistCreditRole.primary:
        return 'Primary';
    }
  }

  Future<void> _addCredit() async {
    final credit = await _showCreditEditor();

    if (!mounted || credit == null) {
      return;
    }

    setState(() {
      _additionalCredits.add(credit);
    });
  }

  Future<void> _editCredit(int index) async {
    final original = _additionalCredits[index];
    final updated = await _showCreditEditor(initialCredit: original);

    if (!mounted || updated == null) {
      return;
    }

    setState(() {
      _additionalCredits[index] = updated;
    });
  }

  void _removeCredit(int index) {
    setState(() {
      _additionalCredits.removeAt(index);
    });
  }

  Future<TrackProfileCreditDraft?> _showCreditEditor({
    TrackProfileCreditDraft? initialCredit,
  }) async {
    var creditedName = initialCredit?.creditedName ?? '';
    var role = initialCredit?.role ?? SongArtistCreditRole.featured;

    return showDialog<TrackProfileCreditDraft>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(initialCredit == null ? 'Add credit' : 'Edit credit'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    key: const ValueKey<String>('track-credit-name-field'),
                    initialValue: creditedName,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: 'Artist name'),
                    onChanged: (value) {
                      creditedName = value;
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<SongArtistCreditRole>(
                    key: const ValueKey<String>('track-credit-role-field'),
                    initialValue: role,
                    decoration: const InputDecoration(labelText: 'Role'),
                    items: const [
                      DropdownMenuItem(
                        value: SongArtistCreditRole.coPrimary,
                        child: Text('Co-primary'),
                      ),
                      DropdownMenuItem(
                        value: SongArtistCreditRole.featured,
                        child: Text('Featured'),
                      ),
                      DropdownMenuItem(
                        value: SongArtistCreditRole.guest,
                        child: Text('Guest'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }

                      setDialogState(() {
                        role = value;
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  key: const ValueKey<String>('track-credit-save-button'),
                  onPressed: () {
                    final name = creditedName.trim();

                    if (name.isEmpty) {
                      return;
                    }

                    final originalName = initialCredit?.creditedName
                        .trim()
                        .toLowerCase();
                    final preservesIdentity =
                        originalName != null &&
                        originalName == name.toLowerCase();

                    Navigator.of(dialogContext).pop(
                      TrackProfileCreditDraft(
                        creditedName: name,
                        role: role,
                        artistId: preservesIdentity
                            ? initialCredit!.artistId
                            : null,
                      ),
                    );
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    var albumEditionId = widget.track.albumEditionId;

    for (final album in widget.albums) {
      if (album.albumId != _albumId) {
        continue;
      }

      final primaryEditionId = album.primaryEditionId?.trim();

      if (primaryEditionId != null && primaryEditionId.isNotEmpty) {
        albumEditionId = primaryEditionId;
      }

      break;
    }

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
        albumEditionId: albumEditionId,
      ),
    );
  }
}

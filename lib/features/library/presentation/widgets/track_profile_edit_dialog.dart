import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../application/models/library_album.dart';
import '../../application/models/library_artist.dart';
import '../../application/models/library_track.dart';
import '../models/track_profile_edit_draft.dart';

class TrackProfileEditDialog extends StatefulWidget {
  const TrackProfileEditDialog({
    super.key,
    required this.track,
    this.artists = const [],
    this.albums = const [],
    this.onCreateArtist,
  });

  final LibraryTrack track;
  final List<LibraryArtist> artists;
  final List<LibraryAlbum> albums;
  final TrackArtistCreationCallback? onCreateArtist;

  @override
  State<TrackProfileEditDialog> createState() => _TrackProfileEditDialogState();
}

class _TrackProfileEditDialogState extends State<TrackProfileEditDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _titleController;
  late final TextEditingController _trackNumberController;
  late final TextEditingController _discNumberController;
  late final TextEditingController _featuredArtistsController;

  late List<LibraryArtist> _artists;
  late String _artistId;
  late String _albumId;
  late bool _isSingle;

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

    _featuredArtistsController = TextEditingController(
      text: widget.track.featuredArtists.join(', '),
    );

    _artists = List<LibraryArtist>.from(widget.artists);
    _artistId = widget.track.artistId;
    _albumId = widget.track.albumId;
    _isSingle = widget.track.isSingle;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _trackNumberController.dispose();
    _discNumberController.dispose();
    _featuredArtistsController.dispose();
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

    return AlertDialog(
      title: const Text('Edit song details'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const ValueKey<String>('track-title-field'),
                controller: _titleController,
                autofocus: true,
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
                          '${album.title} \u2014 ${album.artistName}',
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
              TextFormField(
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
              ),
              const SizedBox(height: 12),
              TextFormField(
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
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey<String>('track-featured-artists-field'),
                controller: _featuredArtistsController,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'Featured artists',
                  helperText: 'Separate multiple artists with commas.',
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
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey<String>('track-edit-save-button'),
          onPressed: _submit,
          child: const Text('Save'),
        ),
      ],
    );
  }

  Future<void> _createArtist() async {
    final onCreateArtist = widget.onCreateArtist;

    if (onCreateArtist == null) {
      return;
    }

    final artist = await showDialog<LibraryArtist>(
      context: context,
      builder: (_) => _NewTrackArtistDialog(onCreateArtist: onCreateArtist),
    );

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
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    String albumEditionId = widget.track.albumEditionId;

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

    final featuredArtists = _featuredArtistsController.text
        .split(',')
        .map((artist) => artist.trim())
        .where((artist) => artist.isNotEmpty)
        .toList(growable: false);

    Navigator.of(context).pop(
      TrackProfileEditDraft(
        title: _titleController.text.trim(),
        trackNumber: int.parse(_trackNumberController.text.trim()),
        discNumber: int.parse(_discNumberController.text.trim()),
        featuredArtists: featuredArtists,
        isSingle: _isSingle,
        artistId: _artistId,
        albumId: _albumId,
        albumEditionId: albumEditionId,
      ),
    );
  }
}

class _NewTrackArtistDialog extends StatefulWidget {
  const _NewTrackArtistDialog({required this.onCreateArtist});

  final TrackArtistCreationCallback onCreateArtist;

  @override
  State<_NewTrackArtistDialog> createState() => _NewTrackArtistDialogState();
}

class _NewTrackArtistDialogState extends State<_NewTrackArtistDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();

  bool _isSaving = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add new artist'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              key: const ValueKey<String>('track-new-artist-name-field'),
              controller: _nameController,
              autofocus: true,
              enabled: !_isSaving,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(labelText: 'Artist name'),
              onFieldSubmitted: (_) {
                if (!_isSaving) {
                  _submit();
                }
              },
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Artist name cannot be blank.';
                }

                return null;
              },
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                key: const ValueKey<String>('track-new-artist-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving
              ? null
              : () {
                  Navigator.of(context).pop();
                },
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey<String>('track-new-artist-save-button'),
          onPressed: _isSaving ? null : _submit,
          child: _isSaving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Add artist'),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final artist = await widget.onCreateArtist(_nameController.text.trim());

      if (!mounted) {
        return;
      }

      if (artist == null) {
        setState(() {
          _isSaving = false;
          _errorMessage = 'Could not add artist.';
        });
        return;
      }

      Navigator.of(context).pop(artist);
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isSaving = false;
        _errorMessage = 'Could not add artist.';
      });
    }
  }
}

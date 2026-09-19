import 'package:flutter/material.dart';

import '../../application/models/library_album.dart';
import '../../application/models/library_artist.dart';
import '../../domain/entities/album_edition.dart';

class AlbumProfileEditDraft {
  const AlbumProfileEditDraft({
    required this.title,
    required this.artistId,
    required this.editionTitle,
    required this.editionType,
    required this.releaseDate,
    required this.genre,
  });

  final String title;
  final String artistId;
  final String editionTitle;
  final AlbumEditionType editionType;
  final DateTime? releaseDate;
  final String? genre;
}

class AlbumProfileEditDialog extends StatefulWidget {
  const AlbumProfileEditDialog({
    super.key,
    required this.album,
    this.artists = const [],
  });

  final LibraryAlbum album;
  final List<LibraryArtist> artists;

  @override
  State<AlbumProfileEditDialog> createState() => _AlbumProfileEditDialogState();
}

class _AlbumProfileEditDialogState extends State<AlbumProfileEditDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _titleController;
  late final TextEditingController _editionTitleController;
  late final TextEditingController _releaseDateController;
  late final TextEditingController _genreController;

  late String _artistId;
  late AlbumEditionType _editionType;

  @override
  void initState() {
    super.initState();

    final editionTitle = widget.album.primaryEditionTitle?.trim();

    _titleController = TextEditingController(text: widget.album.title);

    _editionTitleController = TextEditingController(
      text: editionTitle == null || editionTitle.isEmpty
          ? 'Standard'
          : editionTitle,
    );

    _releaseDateController = TextEditingController(
      text: _formatInputDate(widget.album.releaseDate),
    );

    _genreController = TextEditingController(text: widget.album.genre ?? '');

    _artistId = widget.album.artistId;

    _editionType = widget.album.primaryEditionType ?? AlbumEditionType.standard;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _editionTitleController.dispose();
    _releaseDateController.dispose();
    _genreController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canSelectArtist = widget.artists.any(
      (artist) => artist.artistId == _artistId,
    );

    return AlertDialog(
      title: const Text('Edit album details'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const ValueKey<String>('album-title-field'),
                controller: _titleController,
                autofocus: true,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Album title'),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Album title cannot be blank.';
                  }

                  return null;
                },
              ),
              const SizedBox(height: 12),
              if (canSelectArtist) ...[
                DropdownButtonFormField<String>(
                  key: const ValueKey<String>('album-artist-field'),
                  initialValue: _artistId,
                  decoration: const InputDecoration(labelText: 'Album artist'),
                  items: [
                    for (final artist in widget.artists)
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
              TextFormField(
                key: const ValueKey<String>('album-edition-title-field'),
                controller: _editionTitleController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Edition title'),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Edition title cannot be blank.';
                  }

                  return null;
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<AlbumEditionType>(
                key: const ValueKey<String>('album-edition-type-field'),
                initialValue: _editionType,
                decoration: const InputDecoration(labelText: 'Edition type'),
                items: [
                  for (final type in AlbumEditionType.values)
                    DropdownMenuItem(
                      value: type,
                      child: Text(_editionTypeLabel(type)),
                    ),
                ],
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }

                  setState(() {
                    _editionType = value;
                  });
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey<String>('album-release-date-field'),
                controller: _releaseDateController,
                keyboardType: TextInputType.datetime,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Release date',
                  hintText: 'YYYY-MM-DD',
                ),
                validator: (value) {
                  final trimmed = value?.trim() ?? '';

                  if (trimmed.isEmpty) {
                    return null;
                  }

                  if (_parseInputDate(trimmed) == null) {
                    return 'Use YYYY-MM-DD.';
                  }

                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey<String>('album-genre-field'),
                controller: _genreController,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(labelText: 'Genre'),
                onFieldSubmitted: (_) => _submit(),
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
          key: const ValueKey<String>('album-edit-save-button'),
          onPressed: _submit,
          child: const Text('Save'),
        ),
      ],
    );
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final genre = _genreController.text.trim();

    Navigator.of(context).pop(
      AlbumProfileEditDraft(
        title: _titleController.text.trim(),
        artistId: _artistId,
        editionTitle: _editionTitleController.text.trim(),
        editionType: _editionType,
        releaseDate: _parseInputDate(_releaseDateController.text),
        genre: genre.isEmpty ? null : genre,
      ),
    );
  }

  String _editionTypeLabel(AlbumEditionType type) {
    return switch (type) {
      AlbumEditionType.standard => 'Standard',
      AlbumEditionType.deluxe => 'Deluxe',
      AlbumEditionType.expanded => 'Expanded',
      AlbumEditionType.anniversary => 'Anniversary',
      AlbumEditionType.remaster => 'Remaster',
      AlbumEditionType.other => 'Other',
    };
  }

  String _formatInputDate(DateTime? date) {
    if (date == null) {
      return '';
    }

    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');

    return '${date.year.toString().padLeft(4, '0')}-$month-$day';
  }

  DateTime? _parseInputDate(String value) {
    final trimmed = value.trim();

    if (trimmed.isEmpty) {
      return null;
    }

    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(trimmed);

    if (match == null) {
      return null;
    }

    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);

    if (month < 1 || month > 12 || day < 1 || day > 31) {
      return null;
    }

    final parsed = DateTime(year, month, day);

    if (parsed.year != year || parsed.month != month || parsed.day != day) {
      return null;
    }

    return parsed;
  }
}

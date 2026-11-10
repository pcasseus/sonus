import 'package:flutter/material.dart';

import '../../application/models/library_album.dart';
import '../../application/models/library_artist.dart';
import '../../application/models/release_display_title.dart';
import '../../domain/entities/album_edition.dart';
import '../../domain/entities/release_date.dart';
import 'album_studio/release_date_editor.dart';

class AlbumProfileEditDraft {
  const AlbumProfileEditDraft({
    required this.title,
    required this.artistId,
    required this.editionTitle,
    required this.editionType,
    required this.releaseDate,
    required this.genre,
    this.releaseDatePrecision,
  });

  final String title;
  final String artistId;
  final String editionTitle;
  final AlbumEditionType editionType;
  final DateTime? releaseDate;

  /// How much of [releaseDate] was entered.
  final ReleaseDatePrecision? releaseDatePrecision;
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
  late ReleaseDate? _releaseDate = widget.album.releaseDateValue;
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

    _genreController = TextEditingController(text: widget.album.genre ?? '');

    _artistId = widget.album.artistId;

    _editionType = widget.album.primaryEditionType ?? AlbumEditionType.standard;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _editionTitleController.dispose();
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
              // BUG-10: the same release date editor as Edit Release.
              _ReleaseDateField(date: _releaseDate, onTap: _editReleaseDate),
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
    final releaseDate = _releaseDate;

    Navigator.of(context).pop(
      AlbumProfileEditDraft(
        title: _titleController.text.trim(),
        artistId: _artistId,
        editionTitle: _editionTitleController.text.trim(),
        editionType: _editionType,
        releaseDate: releaseDate?.instant,
        releaseDatePrecision: releaseDate?.precision,
        genre: genre.isEmpty ? null : genre,
      ),
    );
  }

  String _editionTypeLabel(AlbumEditionType type) => editionTypeLabel(type);

  Future<void> _editReleaseDate() async {
    final edit = await showReleaseDateEditor(context, current: _releaseDate);
    if (edit == null || !mounted) return;
    setState(() {
      _releaseDate = switch (edit) {
        ReleaseDateSet(:final date) => date,
        ReleaseDateCleared() => null,
      };
    });
  }
}

/// The release date as a field that opens the release date editor.
class _ReleaseDateField extends StatelessWidget {
  const _ReleaseDateField({required this.date, required this.onTap});

  final ReleaseDate? date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final date = this.date;
    return Semantics(
      button: true,
      child: InkWell(
        key: const ValueKey<String>('album-release-date-field'),
        onTap: onTap,
        child: InputDecorator(
          decoration: const InputDecoration(
            labelText: 'Release date',
            suffixIcon: Icon(Icons.edit_calendar_rounded),
          ),
          child: Text(date == null ? 'Not set' : date.label),
        ),
      ),
    );
  }
}

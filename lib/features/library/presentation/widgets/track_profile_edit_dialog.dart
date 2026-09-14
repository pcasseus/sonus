import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../application/models/library_track.dart';

class TrackProfileEditDraft {
  const TrackProfileEditDraft({
    required this.title,
    required this.trackNumber,
    required this.featuredArtists,
    required this.isSingle,
  });

  final String title;
  final int trackNumber;
  final List<String> featuredArtists;
  final bool isSingle;
}

class TrackProfileEditDialog extends StatefulWidget {
  const TrackProfileEditDialog({super.key, required this.track});

  final LibraryTrack track;

  @override
  State<TrackProfileEditDialog> createState() => _TrackProfileEditDialogState();
}

class _TrackProfileEditDialogState extends State<TrackProfileEditDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _titleController;
  late final TextEditingController _trackNumberController;
  late final TextEditingController _featuredArtistsController;

  late bool _isSingle;

  @override
  void initState() {
    super.initState();

    _titleController = TextEditingController(text: widget.track.title);
    _trackNumberController = TextEditingController(
      text: widget.track.trackNumber.toString(),
    );
    _featuredArtistsController = TextEditingController(
      text: widget.track.featuredArtists.join(', '),
    );
    _isSingle = widget.track.isSingle;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _trackNumberController.dispose();
    _featuredArtistsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
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
        featuredArtists: featuredArtists,
        isSingle: _isSingle,
      ),
    );
  }
}

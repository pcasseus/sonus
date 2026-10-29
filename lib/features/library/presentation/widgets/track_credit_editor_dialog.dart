import 'package:flutter/material.dart';

import '../../../../core/design/sonus_theme.dart';
import '../../../../core/identity/text_normalizer.dart';
import '../../application/models/library_artist.dart';
import '../../application/services/song_artist_credit_service.dart';
import '../../domain/entities/song_artist_credit.dart';
import '../models/track_profile_edit_draft.dart';

/// Opens the Track Studio credit editor: a search over the library's
/// artists with a free-text fallback (SN-50 C-Q3).
///
/// A credit links to an existing artist only when the person picks that
/// artist from the list; a typed name that matches one is never linked on
/// its own (C-Q2). A credit repeating the primary artist or another credit
/// in [otherCredits] is refused with a message, so nothing is dropped
/// silently on save (C-Q4).
Future<TrackProfileCreditDraft?> showTrackCreditEditor({
  required BuildContext context,
  required List<LibraryArtist> artists,
  required String primaryArtistId,
  required String primaryArtistName,
  required List<TrackProfileCreditDraft> otherCredits,
  TrackProfileCreditDraft? initialCredit,
}) {
  return showDialog<TrackProfileCreditDraft>(
    context: context,
    builder: (_) => _TrackCreditEditorDialog(
      artists: artists,
      primaryArtistId: primaryArtistId,
      primaryArtistName: primaryArtistName,
      otherCredits: otherCredits,
      initialCredit: initialCredit,
    ),
  );
}

const int _maxArtistOptions = 8;

class _TrackCreditEditorDialog extends StatefulWidget {
  const _TrackCreditEditorDialog({
    required this.artists,
    required this.primaryArtistId,
    required this.primaryArtistName,
    required this.otherCredits,
    this.initialCredit,
  });

  final List<LibraryArtist> artists;
  final String primaryArtistId;
  final String primaryArtistName;
  final List<TrackProfileCreditDraft> otherCredits;
  final TrackProfileCreditDraft? initialCredit;

  @override
  State<_TrackCreditEditorDialog> createState() =>
      _TrackCreditEditorDialogState();
}

class _TrackCreditEditorDialogState extends State<_TrackCreditEditorDialog> {
  late final TextEditingController _nameController;
  final FocusNode _nameFocusNode = FocusNode();

  late SongArtistCreditRole _role;
  String? _linkedArtistId;
  String _linkedName = '';
  String? _error;

  @override
  void initState() {
    super.initState();

    final initialCredit = widget.initialCredit;

    _nameController = TextEditingController(
      text: initialCredit?.creditedName ?? '',
    )..addListener(_onNameChanged);
    _role = initialCredit?.role ?? SongArtistCreditRole.featured;
    _linkedArtistId = initialCredit?.artistId;
    _linkedName = initialCredit?.creditedName ?? '';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nameFocusNode.dispose();
    super.dispose();
  }

  /// Editing the name away from the linked artist's unlinks the credit.
  void _onNameChanged() {
    setState(() {
      if (TextNormalizer.canonicalize(_nameController.text) !=
          TextNormalizer.canonicalize(_linkedName)) {
        _linkedArtistId = null;
      }

      _error = null;
    });
  }

  List<LibraryArtist> _artistOptions(String query) {
    final canonicalQuery = TextNormalizer.canonicalize(query);

    if (canonicalQuery.isEmpty) {
      return const [];
    }

    final matches =
        widget.artists
            .where(
              (artist) => TextNormalizer.canonicalize(
                artist.name,
              ).contains(canonicalQuery),
            )
            .toList()
          ..sort((left, right) {
            final leftStarts = TextNormalizer.canonicalize(
              left.name,
            ).startsWith(canonicalQuery);
            final rightStarts = TextNormalizer.canonicalize(
              right.name,
            ).startsWith(canonicalQuery);

            if (leftStarts != rightStarts) {
              return leftStarts ? -1 : 1;
            }

            return left.name.toLowerCase().compareTo(right.name.toLowerCase());
          });

    return matches.take(_maxArtistOptions).toList(growable: false);
  }

  bool get _matchesExistingArtist {
    final canonicalName = TextNormalizer.canonicalize(_nameController.text);

    return canonicalName.isNotEmpty &&
        widget.artists.any(
          (artist) => TextNormalizer.canonicalize(artist.name) == canonicalName,
        );
  }

  void _save() {
    final name = _nameController.text.trim();
    final canonicalName = TextNormalizer.canonicalize(name);

    if (canonicalName.isEmpty) {
      setState(() => _error = 'Enter an artist name.');
      return;
    }

    final artistId = _linkedArtistId;

    if (artistId == null &&
        _role == SongArtistCreditRole.coPrimary &&
        _matchesExistingArtist) {
      setState(
        () => _error =
            'Choose $name from the list to credit that artist as co-primary.',
      );
      return;
    }

    final identities = SongCreditIdentitySet(
      primaryArtistId: widget.primaryArtistId,
      primaryCanonicalName: TextNormalizer.canonicalize(
        widget.primaryArtistName,
      ),
    );

    for (final credit in widget.otherCredits) {
      identities.add(
        canonicalName: TextNormalizer.canonicalize(credit.creditedName),
        artistId: credit.artistId,
      );
    }

    if (!identities.add(canonicalName: canonicalName, artistId: artistId)) {
      final isPrimary =
          artistId == widget.primaryArtistId ||
          (artistId == null &&
              canonicalName ==
                  TextNormalizer.canonicalize(widget.primaryArtistName));

      setState(
        () => _error = isPrimary
            ? '$name is already the primary artist.'
            : '$name is already credited on this song.',
      );
      return;
    }

    Navigator.of(context).pop(
      TrackProfileCreditDraft(
        creditedName: name,
        role: _role,
        artistId: artistId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final theme = Theme.of(context);
    final status = _linkedArtistId != null
        ? (Icons.link_rounded, 'Linked to the existing artist $_linkedName.')
        : _matchesExistingArtist
        ? (
            Icons.info_outline_rounded,
            'An artist with this name exists. Choose it from the list to '
                'link this credit to them.',
          )
        : null;

    return AlertDialog(
      title: Text(widget.initialCredit == null ? 'Add credit' : 'Edit credit'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RawAutocomplete<LibraryArtist>(
              textEditingController: _nameController,
              focusNode: _nameFocusNode,
              displayStringForOption: (artist) => artist.name,
              optionsBuilder: (value) => _artistOptions(value.text),
              onSelected: (artist) {
                setState(() {
                  _linkedArtistId = artist.artistId;
                  _linkedName = artist.name;
                  _error = null;
                });
              },
              fieldViewBuilder:
                  (context, controller, focusNode, onFieldSubmitted) {
                    return TextField(
                      key: const ValueKey<String>('track-credit-name-field'),
                      controller: controller,
                      focusNode: focusNode,
                      autofocus: true,
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                        labelText: 'Artist name',
                        helperText: 'Search your artists or type a new name.',
                        helperMaxLines: 3,
                        errorText: _error,
                        errorMaxLines: 3,
                      ),
                      onSubmitted: (_) => onFieldSubmitted(),
                    );
                  },
              optionsViewBuilder: (context, onSelected, options) {
                final highlighted = AutocompleteHighlightedOption.of(context);

                return Align(
                  alignment: AlignmentDirectional.topStart,
                  child: Material(
                    color: colors.raisedSurface,
                    elevation: 4,
                    borderRadius: BorderRadius.circular(
                      tokens.metrics.controlRadius,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxHeight: 240,
                        maxWidth: 320,
                      ),
                      child: ListView.builder(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        itemCount: options.length,
                        itemBuilder: (context, index) {
                          final artist = options.elementAt(index);

                          return ListTile(
                            key: ValueKey<String>(
                              'track-credit-artist-option-${artist.artistId}',
                            ),
                            selected: index == highlighted,
                            selectedTileColor: colors.selection,
                            leading: const Icon(Icons.person_rounded),
                            title: Text(artist.name),
                            onTap: () => onSelected(artist),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
            if (status != null) ...[
              const SizedBox(height: 8),
              Row(
                key: const ValueKey<String>('track-credit-link-status'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(status.$1, size: 18, color: colors.textSecondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      status.$2,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            DropdownButtonFormField<SongArtistCreditRole>(
              key: const ValueKey<String>('track-credit-role-field'),
              initialValue: _role,
              isExpanded: true,
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

                setState(() {
                  _role = value;
                  _error = null;
                });
              },
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
          key: const ValueKey<String>('track-credit-save-button'),
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

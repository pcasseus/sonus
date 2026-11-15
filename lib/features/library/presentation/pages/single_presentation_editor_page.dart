import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/design/sonus_theme.dart';
import '../../../artwork/application/services/artwork_file_picker.dart';
import '../../application/services/song_single_presentation_service.dart';
import '../../domain/entities/song_single_presentation.dart';
import '../widgets/album_studio/release_date_editor.dart';

/// Edits a song's Single presentation (App Update 1.3, REF-1.3-04): its own
/// release date and its own cover, each saved on its own as soon as it is
/// chosen. The album's artwork and dates are never changed, and switching
/// the song's Single designation off keeps what is set here.
class SinglePresentationEditorPage extends StatefulWidget {
  const SinglePresentationEditorPage({
    super.key,
    required this.songId,
    required this.songTitle,
  });

  final String songId;
  final String songTitle;

  static Future<void> open(
    BuildContext context, {
    required String songId,
    required String songTitle,
  }) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          SinglePresentationEditorPage(songId: songId, songTitle: songTitle),
    ),
  );

  @override
  State<SinglePresentationEditorPage> createState() =>
      _SinglePresentationEditorPageState();
}

class _SinglePresentationEditorPageState
    extends State<SinglePresentationEditorPage> {
  SongSinglePresentation? _presentation;
  bool _loading = true;
  bool _busy = false;

  SongSinglePresentationService? get _service =>
      context.read<SongSinglePresentationService?>();

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final service = _service;
    final loaded = service == null ? null : await service.load(widget.songId);
    if (!mounted) return;
    setState(() {
      _presentation = loaded;
      _loading = false;
    });
  }

  Future<void> _run(
    Future<SongSinglePresentation> Function(SongSinglePresentationService)
    change, {
    required String failure,
  }) async {
    final service = _service;
    if (service == null || _busy) return;
    setState(() => _busy = true);
    try {
      final next = await change(service);
      if (mounted) setState(() => _presentation = next);
    } catch (error, stackTrace) {
      developer.log(
        'Single presentation could not be saved (${error.runtimeType})',
        name: 'sonus.library.single',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(failure)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editDate() async {
    final edit = await showReleaseDateEditor(
      context,
      current: _presentation?.releaseDate,
    );
    if (edit == null || !mounted) return;
    await _run(
      (service) => service.setReleaseDate(widget.songId, switch (edit) {
        ReleaseDateSet(:final date) => date,
        ReleaseDateCleared() => null,
      }),
      failure: 'The release date could not be saved.',
    );
  }

  Future<void> _chooseCover() async {
    final picker = context.read<ArtworkFilePicker?>();
    if (picker == null) return;
    final path = await picker.pickArtworkFile();
    if (path == null || !mounted) return;
    await _run(
      (service) => service.assignArtwork(widget.songId, path),
      failure: 'The cover could not be saved.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;
    final theme = Theme.of(context);
    final presentation = _presentation;
    final date = presentation?.releaseDate;
    final cover = presentation?.coverPath;
    final canPick =
        (_service?.canAssignArtwork ?? false) &&
        context.read<ArtworkFilePicker?>() != null;

    return Scaffold(
      key: const ValueKey<String>('single-presentation-editor'),
      appBar: AppBar(title: const Text('Single cover and date')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  widget.songTitle,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Shown when this song appears as a Single on the '
                  "artist's profile. The album keeps its own cover and date.",
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(height: 20),
                Semantics(
                  header: true,
                  child: Text(
                    'Release date',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                ListTile(
                  key: const ValueKey<String>('single-release-date'),
                  contentPadding: EdgeInsets.zero,
                  minTileHeight: 48,
                  title: Text(date?.label ?? 'Not set'),
                  subtitle: const Text('Year, month or exact day'),
                  trailing: const Icon(Icons.edit_calendar_rounded),
                  enabled: !_busy,
                  onTap: _editDate,
                ),
                const SizedBox(height: 16),
                Semantics(
                  header: true,
                  child: Text('Cover', style: theme.textTheme.titleSmall),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _CoverPreview(path: cover),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FilledButton.tonal(
                            key: const ValueKey<String>('single-cover-choose'),
                            onPressed: canPick && !_busy ? _chooseCover : null,
                            child: Text(
                              cover == null ? 'Choose cover' : 'Change cover',
                            ),
                          ),
                          if (presentation?.artworkId != null)
                            TextButton(
                              key: const ValueKey<String>(
                                'single-cover-remove',
                              ),
                              onPressed: _busy
                                  ? null
                                  : () => _run(
                                      (service) =>
                                          service.clearArtwork(widget.songId),
                                      failure:
                                          'The cover could not be removed.',
                                    ),
                              child: const Text('Remove cover'),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  key: const ValueKey<String>('single-cover-in-charts'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Use this cover in charts and Moments'),
                  subtitle: const Text(
                    'Otherwise charts and Moments keep the usual artwork.',
                  ),
                  value: presentation?.useArtworkInCharts ?? false,
                  onChanged: cover == null || _busy
                      ? null
                      : (value) => _run(
                          (service) => service.setUseArtworkInCharts(
                            widget.songId,
                            value: value,
                          ),
                          failure: 'The setting could not be saved.',
                        ),
                ),
              ],
            ),
    );
  }
}

class _CoverPreview extends StatelessWidget {
  const _CoverPreview({required this.path});

  final String? path;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final path = this.path;
    return ClipRRect(
      borderRadius: BorderRadius.circular(tokens.metrics.artworkRadius),
      child: SizedBox.square(
        dimension: 96,
        child: path == null
            ? ColoredBox(
                key: const ValueKey<String>('single-cover-none'),
                color: tokens.colors.artworkPlaceholder,
                child: Icon(
                  Icons.album_rounded,
                  semanticLabel: 'No Single cover',
                  color: tokens.colors.onArtworkPlaceholder,
                ),
              )
            : Image.file(
                File(path),
                key: const ValueKey<String>('single-cover-image'),
                fit: BoxFit.cover,
                width: 96,
                height: 96,
                cacheWidth: 288,
                semanticLabel: 'Single cover',
                errorBuilder: (_, _, _) =>
                    ColoredBox(color: tokens.colors.artworkPlaceholder),
              ),
      ),
    );
  }
}

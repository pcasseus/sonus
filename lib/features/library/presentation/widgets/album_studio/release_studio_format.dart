import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';

import '../../../../../core/design/sonus_theme.dart';
import '../../../application/services/library_organization_service.dart';
import '../../../domain/entities/library_organization.dart';

/// The release's format: Single, EP or Album (SN-45).
///
/// The user's choice is kept through every later metadata refresh. A
/// MusicBrainz match can suggest a format; with neither, the release is an
/// Album. Nothing is inferred from how many tracks it has. Singles chart
/// through their songs only, never as a release.
class ReleaseStudioFormat extends StatefulWidget {
  const ReleaseStudioFormat({
    super.key,
    required this.albumId,
    required this.service,
  });

  final String albumId;
  final LibraryOrganizationService service;

  @override
  State<ReleaseStudioFormat> createState() => _ReleaseStudioFormatState();
}

class _ReleaseStudioFormatState extends State<ReleaseStudioFormat> {
  AlbumReleaseFormat? _stated;
  bool _loaded = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final organization = await widget.service.load();
      if (!mounted) return;
      setState(() {
        _stated = organization.formats[widget.albumId];
        _loaded = true;
      });
    } catch (error, stackTrace) {
      developer.log(
        'Release format could not be read (${error.runtimeType})',
        name: 'sonus.library.organization',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) setState(() => _loaded = true);
    }
  }

  Future<void> _change(Future<void> Function() action, String message) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      await action();
      await _load();
      messenger.showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('The format could not be saved.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final theme = Theme.of(context);
    final stated = _stated;
    final format = stated?.format ?? ReleaseFormat.album;
    final isManual = stated?.authority == ReleaseClassificationAuthority.manual;

    final source = stated == null
        ? 'Not stated, so it counts as an Album.'
        : isManual
        ? 'Set by you. Metadata lookups never change it.'
        : 'Suggested by MusicBrainz.';

    return Material(
      key: const ValueKey<String>('release-studio-format'),
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.metrics.cardRadius),
        side: BorderSide(color: colors.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                'Format',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 10),
            SegmentedButton<ReleaseFormat>(
              key: const ValueKey<String>('release-studio-format-choice'),
              showSelectedIcon: false,
              segments: [
                for (final option in ReleaseFormat.values)
                  ButtonSegment<ReleaseFormat>(
                    value: option,
                    label: Text(
                      option.label,
                      key: ValueKey<String>(
                        'release-studio-format-${option.name}',
                      ),
                    ),
                  ),
              ],
              selected: {format},
              onSelectionChanged: !_loaded || _busy
                  ? null
                  : (selection) {
                      final chosen = selection.single;
                      if (chosen == format && isManual) return;
                      unawaited(
                        _change(
                          () => widget.service.setReleaseFormat(
                            albumId: widget.albumId,
                            format: chosen,
                          ),
                          'Saved as ${_article(chosen)} ${chosen.label}.',
                        ),
                      );
                    },
            ),
            const SizedBox(height: 8),
            Text(
              source,
              key: const ValueKey<String>('release-studio-format-source'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.textSecondary,
              ),
            ),
            if (format == ReleaseFormat.single)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Singles chart through their songs on the Sonus Hot 100, '
                  'not as a release.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
            if (isManual)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  key: const ValueKey<String>('release-studio-format-reset'),
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: _busy
                      ? null
                      : () => unawaited(
                          _change(
                            () => widget.service.clearReleaseFormat(
                              widget.albumId,
                            ),
                            'Your format choice was removed.',
                          ),
                        ),
                  child: const Text('Remove my choice'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _article(ReleaseFormat format) =>
      format == ReleaseFormat.album ? 'an' : 'a';
}

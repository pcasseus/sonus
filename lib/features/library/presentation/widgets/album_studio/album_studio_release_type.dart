import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';

import '../../../../../core/design/sonus_theme.dart';
import '../../../application/services/library_organization_service.dart';
import '../../../domain/entities/library_organization.dart';

/// What kind of release the album is, beside its format: a soundtrack, a
/// cast recording or a compilation. A soundtrack can be an Album or an EP;
/// who owns it, and who is shown as a standalone artist, never depends on
/// this label.
///
/// The user's choice replaces a MusicBrainz release-group type, and only
/// the user's own choice can be cleared here. Nothing is inferred from
/// titles or credit counts. Kept in backups and the cloud archive.
class AlbumStudioReleaseType extends StatefulWidget {
  const AlbumStudioReleaseType({
    super.key,
    required this.albumId,
    required this.service,
  });

  final String albumId;
  final LibraryOrganizationService service;

  static String labelFor(ReleaseKind? kind) => switch (kind) {
    null => 'Not set',
    ReleaseKind.soundtrack => 'Soundtrack',
    ReleaseKind.castRecording => 'Cast recording',
    ReleaseKind.compilation => 'Compilation',
  };

  @override
  State<AlbumStudioReleaseType> createState() => _AlbumStudioReleaseTypeState();
}

class _AlbumStudioReleaseTypeState extends State<AlbumStudioReleaseType> {
  AlbumReleaseClassification? _current;
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
        _current = organization.classifications[widget.albumId];
        _loaded = true;
      });
    } catch (error, stackTrace) {
      developer.log(
        'Release type could not be read (${error.runtimeType})',
        name: 'sonus.library.organization',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) setState(() => _loaded = true);
    }
  }

  Future<void> _choose(ReleaseKind? kind) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      if (kind == null) {
        await widget.service.clearReleaseClassification(widget.albumId);
      } else {
        await widget.service.classifyRelease(
          albumId: widget.albumId,
          kind: kind,
        );
      }
      await _load();
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('The kind could not be saved.')),
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
    final current = _current;
    final isManual =
        current?.authority == ReleaseClassificationAuthority.manual;

    final source = current == null
        ? 'Shown on the release, such as "Soundtrack".'
        : isManual
        ? 'Set by you.'
        : 'From MusicBrainz.';

    return Material(
      key: const ValueKey<String>('album-studio-release-type'),
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.metrics.cardRadius),
        side: BorderSide(color: colors.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Kind: '
                    '${_loaded ? AlbumStudioReleaseType.labelFor(current?.kind) : '…'}',
                    key: const ValueKey<String>(
                      'album-studio-release-type-value',
                    ),
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    source,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuButton<_ReleaseChoice>(
              key: const ValueKey<String>('album-studio-release-type-menu'),
              tooltip: 'Change kind of release',
              enabled: _loaded && !_busy,
              onSelected: (choice) => unawaited(_choose(choice.kind)),
              itemBuilder: (context) => [
                for (final kind in ReleaseKind.values)
                  CheckedPopupMenuItem<_ReleaseChoice>(
                    value: _ReleaseChoice(kind),
                    checked: current?.kind == kind,
                    child: Text(AlbumStudioReleaseType.labelFor(kind)),
                  ),
                // Only the user's own choice can be cleared here; a
                // MusicBrainz type is evidence and stays.
                if (isManual)
                  const PopupMenuItem<_ReleaseChoice>(
                    value: _ReleaseChoice(null),
                    child: Text('Clear my choice'),
                  ),
              ],
              icon: const Icon(Icons.more_vert_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReleaseChoice {
  const _ReleaseChoice(this.kind);

  final ReleaseKind? kind;
}

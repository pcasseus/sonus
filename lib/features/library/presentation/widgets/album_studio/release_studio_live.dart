import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';

import '../../../../../core/design/sonus_theme.dart';
import '../../../application/services/library_organization_service.dart';
import '../../../domain/entities/library_organization.dart';

/// Whether the release is a live recording (SN-49). Live sits beside the
/// format: a live EP stays an EP and charts as one. It is never inferred;
/// only the user or a MusicBrainz "Live" type sets it, and the user's
/// answer, yes or no, is kept through every later metadata refresh.
class ReleaseStudioLive extends StatefulWidget {
  const ReleaseStudioLive({
    super.key,
    required this.albumId,
    required this.service,
  });

  final String albumId;
  final LibraryOrganizationService service;

  @override
  State<ReleaseStudioLive> createState() => _ReleaseStudioLiveState();
}

class _ReleaseStudioLiveState extends State<ReleaseStudioLive> {
  AlbumLiveClassification? _stated;
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
        _stated = organization.lives[widget.albumId];
        _loaded = true;
      });
    } catch (error, stackTrace) {
      developer.log(
        'Live classification could not be read (${error.runtimeType})',
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
    } catch (error, stackTrace) {
      developer.log(
        'Live classification could not be saved (${error.runtimeType})',
        name: 'sonus.library.organization',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
      messenger.showSnackBar(
        const SnackBar(content: Text('Live could not be saved.')),
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
    final isLive = stated?.isLive ?? false;
    final isManual = stated?.authority == ReleaseClassificationAuthority.manual;

    final source = stated == null
        ? 'Concerts, live sessions and live performances. Shown in the '
              "artist's Live section; charts as its format."
        : isManual
        ? 'Set by you. Metadata lookups never change it.'
        : 'Suggested by MusicBrainz.';

    return Material(
      key: const ValueKey<String>('release-studio-live'),
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.metrics.cardRadius),
        side: BorderSide(color: colors.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile(
              key: const ValueKey<String>('release-studio-live-switch'),
              value: isLive,
              onChanged: !_loaded || _busy
                  ? null
                  : (live) => unawaited(
                      _change(
                        () => widget.service.setReleaseLive(
                          albumId: widget.albumId,
                          live: live,
                        ),
                        live ? 'Saved as live.' : 'Saved as not live.',
                      ),
                    ),
              title: Text(
                'Live recording',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              subtitle: Text(
                source,
                key: const ValueKey<String>('release-studio-live-source'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ),
            if (isManual)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 8),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton(
                    key: const ValueKey<String>('release-studio-live-reset'),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(48, 48),
                    ),
                    onPressed: _busy
                        ? null
                        : () => unawaited(
                            _change(
                              () => widget.service.clearReleaseLive(
                                widget.albumId,
                              ),
                              'Your Live choice was removed.',
                            ),
                          ),
                    child: const Text('Remove my choice'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

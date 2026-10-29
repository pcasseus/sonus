import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';

import '../../../../../core/design/sonus_theme.dart';
import '../../../application/services/library_organization_service.dart';

/// Whether the whole release is leaked (SN-50 A-Q2C). Only the user sets
/// it, and it is independent of the songs' own leak flags: marking songs
/// as leaks never marks the release (A-Q2D). It changes no chart (B-Q13).
class ReleaseStudioLeaked extends StatefulWidget {
  const ReleaseStudioLeaked({
    super.key,
    required this.albumId,
    required this.service,
  });

  final String albumId;
  final LibraryOrganizationService service;

  @override
  State<ReleaseStudioLeaked> createState() => _ReleaseStudioLeakedState();
}

class _ReleaseStudioLeakedState extends State<ReleaseStudioLeaked> {
  bool _leaked = false;
  bool _loaded = false;
  bool _busy = false;
  bool _unreadable = false;

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
        _leaked = organization.isLeaked(widget.albumId);
        _loaded = true;
      });
    } catch (error, stackTrace) {
      developer.log(
        'Leaked classification could not be read (${error.runtimeType})',
        name: 'sonus.library.organization',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) setState(() => _unreadable = true);
    }
  }

  Future<void> _change(bool leaked) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      await (leaked
          ? widget.service.setReleaseLeaked(widget.albumId)
          : widget.service.clearReleaseLeaked(widget.albumId));
      await _load();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            leaked ? 'Marked as leaked.' : 'No longer marked as leaked.',
          ),
        ),
      );
    } catch (error, stackTrace) {
      developer.log(
        'Leaked classification could not be saved (${error.runtimeType})',
        name: 'sonus.library.organization',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
      messenger.showSnackBar(
        const SnackBar(content: Text('Leaked could not be saved.')),
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

    return Material(
      key: const ValueKey<String>('release-studio-leaked'),
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.metrics.cardRadius),
        side: BorderSide(color: colors.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: SwitchListTile(
          key: const ValueKey<String>('release-studio-leaked-switch'),
          value: _leaked,
          onChanged: !_loaded || _busy
              ? null
              : (leaked) => unawaited(_change(leaked)),
          title: Text(
            'Leaked release',
            style: theme.textTheme.titleMedium?.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          subtitle: Text(
            _unreadable
                ? 'Leaked could not be read. Open Release Studio again.'
                : 'Mark the whole release as leaked. Song leak labels are '
                      'set per song.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

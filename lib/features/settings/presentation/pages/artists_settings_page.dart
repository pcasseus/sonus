import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/design/sonus_theme.dart';
import '../../../../core/design/widgets/sonus_state_view.dart';
import '../../../../core/events/library_change_signal.dart';
import '../../../account/application/controllers/account_controller.dart';
import '../../../library/application/services/artist_profile_editing_service.dart';
import '../../../library/application/services/artist_retirement_service.dart';
import '../../../library/domain/repositories/artist_reference_repository.dart';
import '../../../library/presentation/models/artist_removal_message.dart';
import '../../../library/presentation/models/artist_state_wording.dart';
import '../../../library/presentation/pages/artist_profile_page.dart';
import '../widgets/settings/settings_section.dart';

/// Settings › Library & Imports › Artists (A2): every artist by state, with
/// what refers to it.
///
/// Only an artist nothing refers to can be removed, one at a time and only
/// after confirming. Removal goes through the guarded
/// [ArtistProfileEditingService.removeArtist], which checks again inside
/// its transaction and refuses if anything refers to the artist by then.
/// There is no bulk removal.
class ArtistsSettingsPage extends StatefulWidget {
  const ArtistsSettingsPage({super.key, this.changes});

  /// For tests; the app's shared signal otherwise.
  final LibraryChangeSignal? changes;

  @override
  State<ArtistsSettingsPage> createState() => _ArtistsSettingsPageState();
}

class _ArtistsSettingsPageState extends State<ArtistsSettingsPage> {
  ArtistRetirementService? _service;
  List<ArtistReferenceSummary>? _summaries;
  Object? _error;
  bool _loading = false;
  String? _removingId;
  ArtistLibraryState _filter = ArtistLibraryState.active;
  late final LibraryChangeRefresher _refresher;

  @override
  void initState() {
    super.initState();
    _refresher = LibraryChangeRefresher(
      signal: widget.changes ?? LibraryChangeSignal.shared,
      kinds: LibraryChangeKind.values.toSet(),
      onChange: () => unawaited(_load()),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final service = context.watch<ArtistRetirementService?>();
    if (identical(service, _service)) {
      return;
    }
    _service = service;
    unawaited(_load());
  }

  @override
  void dispose() {
    _refresher.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final service = _service;
    if (service == null || !mounted) {
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final summaries = await service.classifyAll();
      if (!mounted || !identical(service, _service)) return;
      setState(() => _summaries = summaries);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _remove(ArtistReferenceSummary artist) async {
    final editing = context.read<ArtistProfileEditingService?>();
    final userId = context.read<AccountController?>()?.user?.id;
    final messenger = ScaffoldMessenger.of(context);

    if (editing == null || _removingId != null) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const ValueKey<String>('artists-remove-dialog'),
        title: Text('Remove ${artist.name}?'),
        content: const Text(
          'Nothing in Sonus refers to this artist. This removes the artist '
          'entry from Sonus. Your music and audio files will not be deleted.',
        ),
        actions: [
          TextButton(
            key: const ValueKey<String>('artists-remove-cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey<String>('artists-remove-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() => _removingId = artist.artistId);
    String message;
    Key messageKey;

    try {
      await editing.removeArtist(userId: userId, artistId: artist.artistId);
      message = '${artist.name} was removed.';
      messageKey = const ValueKey<String>('artists-removed-message');
    } on ArtistStillReferencedException catch (error) {
      // Something started referring to the artist since the list loaded;
      // the guard kept it and nothing changed.
      message = artistRemovalBlockedMessage(error.references);
      messageKey = const ValueKey<String>('artists-remove-referenced-message');
    } catch (_) {
      message = 'Could not remove artist. Nothing was changed.';
      messageKey = const ValueKey<String>('artists-remove-error-message');
    }

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(key: messageKey, content: Text(message)));

    if (!mounted) return;
    setState(() => _removingId = null);
    await _load();
  }

  Future<void> _explainKept(ArtistReferenceSummary artist) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const ValueKey<String>('artists-kept-dialog'),
        title: Text(artist.name),
        content: Text(
          artist.state == ArtistLibraryState.waitingForSync
              ? '${artistKeptMessage(artist.references)} It can be reviewed '
                    'again once sync finishes.'
              : '${artistKeptMessage(artist.references)} Removing it would '
                    'leave those records without their artist, so Sonus does '
                    'not offer it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _openProfile(ArtistReferenceSummary artist) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ArtistProfilePage(
          artistId: artist.artistId,
          initialArtistName: artist.name,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;

    return Scaffold(
      key: const ValueKey<String>('artists-settings-page'),
      backgroundColor: colors.background,
      appBar: AppBar(
        title: const Text('Artists'),
        backgroundColor: colors.background,
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final summaries = _summaries;

    if (_service == null) {
      return const SonusStateView(
        key: ValueKey<String>('artists-unavailable'),
        icon: Icons.hourglass_empty_rounded,
        title: 'Your library is still opening.',
      );
    }

    if (summaries == null) {
      return _error == null
          ? const SonusStateView.loading(
              key: ValueKey<String>('artists-loading'),
              label: 'Checking your artists…',
            )
          : SonusStateView(
              key: const ValueKey<String>('artists-error'),
              icon: Icons.error_outline_rounded,
              isError: true,
              title: "Your artists couldn't be checked.",
              message: 'Nothing was changed. Try again.',
              action: FilledButton.tonalIcon(
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try again'),
              ),
            );
    }

    final byState = {
      for (final state in ArtistLibraryState.values)
        state: [
          for (final summary in summaries)
            if (summary.state == state) summary,
        ],
    };
    final shown = byState[_filter]!;
    final theme = Theme.of(context);
    final colors = SonusTheme.of(context).colors;
    final canRemove = context.watch<ArtistProfileEditingService?>() != null;

    return ListView(
      key: const ValueKey<String>('artists-list'),
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        32 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        if (_loading) ...[
          const LinearProgressIndicator(),
          const SizedBox(height: 12),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final state in ArtistLibraryState.values)
              if (state != ArtistLibraryState.waitingForSync ||
                  byState[state]!.isNotEmpty ||
                  _filter == state)
                ChoiceChip(
                  key: ValueKey<String>('artists-filter-${state.name}'),
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  label: Text(
                    '${artistStateLabel(state)} (${byState[state]!.length})',
                  ),
                  selected: _filter == state,
                  onSelected: (_) => setState(() => _filter = state),
                ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          artistStateExplanation(_filter),
          key: const ValueKey<String>('artists-state-explanation'),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(height: 16),
        SettingsSection(
          title: artistStateLabel(_filter),
          children: [
            if (shown.isEmpty)
              const ListTile(
                key: ValueKey<String>('artists-empty'),
                title: Text('No artists here.'),
              ),
            for (final artist in shown)
              _ArtistRow(
                artist: artist,
                removing: _removingId == artist.artistId,
                onRemove:
                    artist.state == ArtistLibraryState.removable &&
                        canRemove &&
                        _removingId == null
                    ? () => _remove(artist)
                    : null,
                onTap: switch (artist.state) {
                  ArtistLibraryState.active => () => _openProfile(artist),
                  ArtistLibraryState.retired ||
                  ArtistLibraryState.waitingForSync => () => _explainKept(
                    artist,
                  ),
                  ArtistLibraryState.removable => null,
                },
              ),
          ],
        ),
      ],
    );
  }
}

class _ArtistRow extends StatelessWidget {
  const _ArtistRow({
    required this.artist,
    required this.removing,
    required this.onRemove,
    required this.onTap,
  });

  final ArtistReferenceSummary artist;
  final bool removing;
  final VoidCallback? onRemove;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;
    final counts = artistReferenceCounts(artist);
    final state = artist.state;

    return ListTile(
      key: ValueKey<String>('artists-row-${artist.artistId}'),
      minTileHeight: 56,
      title: Text(
        artist.name,
        style: TextStyle(
          color: colors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        counts.isEmpty ? 'Nothing refers to this artist.' : counts,
        key: ValueKey<String>('artists-reason-${artist.artistId}'),
        style: TextStyle(color: colors.textSecondary),
      ),
      onTap: onTap,
      trailing: switch (state) {
        ArtistLibraryState.removable =>
          removing
              ? const SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : TextButton(
                  key: ValueKey<String>('artists-remove-${artist.artistId}'),
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: onRemove,
                  child: Text(
                    'Remove',
                    semanticsLabel: 'Remove ${artist.name}',
                  ),
                ),
        ArtistLibraryState.active => Icon(
          Icons.chevron_right_rounded,
          color: colors.textSecondary,
          semanticLabel: 'Open profile',
        ),
        ArtistLibraryState.retired || ArtistLibraryState.waitingForSync => Icon(
          Icons.info_outline_rounded,
          color: colors.textSecondary,
          semanticLabel: 'Why it is kept',
        ),
      },
    );
  }
}

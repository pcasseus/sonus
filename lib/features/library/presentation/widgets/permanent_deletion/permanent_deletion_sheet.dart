import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../core/database/app_database.dart';
import '../../../../../core/design/sonus_text_scale.dart';
import '../../../../../core/design/sonus_theme.dart';
import '../../../../account/application/controllers/account_controller.dart';
import '../../../../player/application/controllers/playback_coordinator.dart';
import '../../../../sync/application/services/cloud_deletion_readiness.dart';
import '../../../application/services/permanent_deletion_service.dart';
import '../../../domain/deletion/permanent_deletion_impact.dart';

/// App Update 1.2: the permanent-deletion flow for a song, release, edition
/// or artist. Shows exactly what goes and what stays, then asks for the
/// name to be typed before anything is deleted. Resolves to true when the
/// deletion happened.
Future<bool> showPermanentDeletion(
  BuildContext context, {
  required PermanentDeletionTarget target,
  required String name,
  String? artworkPath,
}) async {
  final service = permanentDeletionServiceOf(context);
  final deleted = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => PermanentDeletionSheet(
      target: target,
      name: name,
      artworkPath: artworkPath,
      loadPreview: (options) => service.preview(target, options: options),
      delete: (impact, options) => service.delete(impact, options: options),
    ),
  );
  return deleted ?? false;
}

/// The service, composed from what the app provides above the Library.
PermanentDeletionService permanentDeletionServiceOf(BuildContext context) {
  T? optional<T>() {
    try {
      return context.read<T>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  final rawUserId = optional<AccountController?>()?.user?.id;
  final readiness = optional<CloudDeletionReadiness?>();
  final playback = optional<PlaybackCoordinator?>();
  return PermanentDeletionService(
    appDatabase: context.read<AppDatabase>(),
    userId: rawUserId == null || rawUserId.isEmpty ? null : rawUserId,
    cloudDeletionReady: readiness?.isReady,
    onSongsDeleted: playback == null
        ? null
        : (songIds) => playback.removeSongsFromQueue(songIds),
  );
}

String _kindLabel(PermanentDeletionTargetKind kind) => switch (kind) {
  PermanentDeletionTargetKind.song => 'Song',
  PermanentDeletionTargetKind.album => 'Release',
  PermanentDeletionTargetKind.edition => 'Edition',
  PermanentDeletionTargetKind.artist => 'Artist',
};

String _plural(int n, String one, [String? many]) =>
    '$n ${n == 1 ? one : (many ?? '${one}s')}';

String _duration(int ms) {
  final minutes = (ms / 60000).round();
  if (minutes < 1) return 'less than a minute';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  if (hours == 0) return _plural(minutes, 'minute');
  return rest == 0
      ? _plural(hours, 'hour')
      : '${_plural(hours, 'hour')} ${_plural(rest, 'minute')}';
}

String _weekDate(String iso) {
  final at = DateTime.tryParse(iso)?.toLocal();
  if (at == null) return iso;
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[at.month - 1]} ${at.day}, ${at.year}';
}

class PermanentDeletionSheet extends StatefulWidget {
  const PermanentDeletionSheet({
    super.key,
    required this.target,
    required this.name,
    required this.loadPreview,
    required this.delete,
    this.artworkPath,
  });

  final PermanentDeletionTarget target;
  final String name;
  final String? artworkPath;
  final Future<PermanentDeletionImpact> Function(PermanentDeletionOptions)
  loadPreview;
  final Future<PermanentDeletionImpact> Function(
    PermanentDeletionImpact impact,
    PermanentDeletionOptions options,
  )
  delete;

  @override
  State<PermanentDeletionSheet> createState() => _PermanentDeletionSheetState();
}

class _PermanentDeletionSheetState extends State<PermanentDeletionSheet> {
  PermanentDeletionImpact? _impact;
  Object? _error;
  String? _notice;
  bool _busy = false;
  bool _includeShared = false;

  PermanentDeletionOptions get _options =>
      PermanentDeletionOptions(includeSharedRecordings: _includeShared);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({String? notice}) async {
    setState(() {
      _impact = null;
      _error = null;
      _notice = notice;
    });
    try {
      final impact = await widget.loadPreview(_options);
      if (mounted) setState(() => _impact = impact);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _confirmAndDelete(PermanentDeletionImpact impact) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => PermanentDeletionConfirmDialog(name: widget.name),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await widget.delete(impact, _options);
      if (mounted) Navigator.of(context).pop(true);
    } on StaleDeletionPreview {
      if (!mounted) return;
      setState(() => _busy = false);
      await _load(
        notice:
            'Your library changed since this preview. Nothing was deleted. '
            'Check the updated details.',
      );
    } on DeletionBlocked {
      if (!mounted) return;
      setState(() => _busy = false);
      await _load(notice: 'Nothing was deleted.');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _notice = 'Nothing was deleted. Something went wrong: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final impact = _impact;
    final theme = Theme.of(context);
    final colors = SonusTheme.of(context).colors;

    final Widget body;
    if (_error != null) {
      body = _Notice(
        key: const ValueKey<String>('permanent-deletion-load-error'),
        text: 'The details could not be loaded. Nothing was deleted.',
        error: true,
      );
    } else if (impact == null) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator()),
      );
    } else {
      body = _ImpactDetails(
        impact: impact,
        name: widget.name,
        includeShared: _includeShared,
        onIncludeShared: _busy
            ? null
            : (value) {
                _includeShared = value;
                _load();
              },
      );
    }

    final canContinue = impact != null && impact.canProceed && !_busy;

    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: _largeLayout(context) ? 0.95 : 0.85,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Column(
          key: const ValueKey<String>('permanent-deletion-sheet'),
          children: [
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                children: [
                  Flex(
                    mainAxisSize: MainAxisSize.min,
                    direction: _largeLayout(context)
                        ? Axis.vertical
                        : Axis.horizontal,
                    crossAxisAlignment: _largeLayout(context)
                        ? CrossAxisAlignment.start
                        : CrossAxisAlignment.center,
                    children: [
                      _Artwork(path: widget.artworkPath),
                      const SizedBox(width: 14, height: 12),
                      Flexible(
                        // Stacked: laid out at its own height.
                        flex: _largeLayout(context) ? 0 : 1,
                        fit: _largeLayout(context)
                            ? FlexFit.loose
                            : FlexFit.tight,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Delete permanently',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.name,
                              key: const ValueKey<String>(
                                'permanent-deletion-name',
                              ),
                              style: theme.textTheme.titleMedium,
                            ),
                            Text(
                              '${_kindLabel(widget.target.kind)} · '
                              '${widget.target.id}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_notice != null) ...[
                    _Notice(
                      key: const ValueKey<String>('permanent-deletion-notice'),
                      text: _notice!,
                    ),
                    const SizedBox(height: 12),
                  ],
                  body,
                ],
              ),
            ),
            // Always visible, whatever the text size; stacked full width
            // at large text or on narrow screens.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: _Actions(
                stacked: _largeLayout(context),
                labels: const ['Cancel', 'Continue'],
                cancel: OutlinedButton(
                  key: const ValueKey<String>('permanent-deletion-cancel'),
                  onPressed: _busy
                      ? null
                      : () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                destructive: FilledButton(
                  key: const ValueKey<String>('permanent-deletion-continue'),
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.error,
                    foregroundColor: theme.colorScheme.onError,
                  ),
                  onPressed: canContinue
                      ? () => _confirmAndDelete(impact)
                      : null,
                  child: _busy
                      ? SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: theme.colorScheme.onError,
                          ),
                        )
                      : const Text('Continue'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImpactDetails extends StatelessWidget {
  const _ImpactDetails({
    required this.impact,
    required this.name,
    required this.includeShared,
    required this.onIncludeShared,
  });

  final PermanentDeletionImpact impact;
  final String name;
  final bool includeShared;
  final ValueChanged<bool>? onIncludeShared;

  @override
  Widget build(BuildContext context) {
    final i = impact;
    final kind = i.target.kind;
    final blockers = i.blockers;

    if (blockers.contains(PermanentDeletionBlocker.notFound)) {
      return const _Notice(
        key: ValueKey<String>('permanent-deletion-not-found'),
        text: 'This is no longer in your library.',
        error: true,
      );
    }

    final plays = i.qualifiedPlayIds.length;
    final weeks = i.affectedChartWeeks.length;
    final stories = i.allMomentIds.length;
    final playlistItems = i.playlists.fold<int>(
      0,
      (sum, p) => sum + p.itemsRemoved,
    );

    final deleted = <(String, String)>[
      if (kind == PermanentDeletionTargetKind.artist) ('Artist', name),
      if (i.albumIds.isNotEmpty) ('Releases', '${i.albumIds.length}'),
      if (i.editionIds.isNotEmpty &&
          (kind != PermanentDeletionTargetKind.edition ||
              i.albumIds.isNotEmpty))
        ('Editions', '${i.editionIds.length}'),
      if (kind == PermanentDeletionTargetKind.edition && i.albumIds.isEmpty)
        ('Edition', name),
      ('Songs', '${i.songIds.length}'),
      (
        'Listening',
        plays == 0
            ? 'None'
            : '${_plural(plays, 'stream')} · '
                  '${_plural(i.playbackSessionIds.length, 'listening session')}'
                  ' · ${_duration(i.listenedMs)}',
      ),
      (
        'Charts',
        i.chartEntryIds.isEmpty && weeks == 0
            ? 'None'
            : '${_plural(i.chartEntryIds.length, 'chart entry', 'chart entries')}'
                  ' removed${weeks == 0 ? '' : ' · ${_plural(weeks, 'week')} '
                            'recalculated from ${_weekDate(i.earliestAffectedWeekStartUtc!)}'}',
      ),
      ('Moments', stories == 0 ? 'None' : _plural(stories, 'story', 'stories')),
      (
        'Playlists',
        playlistItems == 0
            ? 'None'
            : '${_plural(playlistItems, 'entry', 'entries')} from '
                  '${i.playlists.map((p) => p.playlistName).join(', ')}',
      ),
      if (i.artworkAssetIds.isNotEmpty)
        ('Artwork', _plural(i.artworkAssetIds.length, 'picture')),
    ];

    final stays = <String>[
      'Your audio files stay on this device. Only Sonus\'s library entries '
          'and listening history are removed.',
      if (i.songsKeptLosingListing.isNotEmpty)
        '${_plural(i.songsKeptLosingListing.length, 'song')} also on another '
            'edition stay there, with their listening.',
      if (i.collaborationSongIdsKept.isNotEmpty)
        '${_plural(i.collaborationSongIdsKept.length, 'song')} by other '
            'artists stay, with $name still credited by name.',
      if (i.otherArtistsLosingProjectGrouping.isNotEmpty)
        '${_plural(i.otherArtistsLosingProjectGrouping.length, 'artist')} '
            'grouped under this release will show on their own.',
      'Other music\'s listening and stories stay. Charts are recalculated '
          'from what remains; nothing new is invented.',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle('What will be deleted'),
        for (final (label, value) in deleted) _Row(label: label, value: value),
        const SizedBox(height: 16),
        _SectionTitle('What stays'),
        for (final line in stays) _Bullet(line),
        if (i.sharedRecordingIds.isNotEmpty) ...[
          const SizedBox(height: 16),
          _Notice(
            key: const ValueKey<String>('permanent-deletion-shared'),
            text: i.sharedRecordingIds.length == 1
                ? 'One recording is shared with another artist: it is on '
                      'this artist\'s release but by someone else, or by '
                      'this artist on someone else\'s release. Choose '
                      'whether it is deleted too.'
                : '${i.sharedRecordingIds.length} recordings are shared '
                      'with other artists: on this artist\'s releases but by '
                      'someone else, or by this artist on someone else\'s '
                      'releases. Choose whether they are deleted too.',
          ),
          CheckboxListTile(
            key: const ValueKey<String>('permanent-deletion-include-shared'),
            contentPadding: EdgeInsets.zero,
            value: includeShared,
            onChanged: onIncludeShared == null
                ? null
                : (value) => onIncludeShared!(value ?? false),
            title: Text(
              i.sharedRecordingIds.length == 1
                  ? 'Also delete this recording'
                  : 'Also delete these '
                        '${i.sharedRecordingIds.length} recordings',
            ),
          ),
        ],
        if (blockers.contains(
          PermanentDeletionBlocker.cloudDeletionUnavailable,
        )) ...[
          const SizedBox(height: 16),
          const _Notice(
            key: ValueKey<String>('permanent-deletion-cloud-unavailable'),
            text:
                'Permanent deletion isn\'t available yet. Sonus can\'t '
                'remove this from your cloud library and your other '
                'devices until cloud support for deletion is ready. '
                'Nothing has been changed.',
            error: true,
          ),
        ],
        if (blockers.contains(PermanentDeletionBlocker.pendingCloudWrite)) ...[
          const SizedBox(height: 16),
          const _Notice(
            key: ValueKey<String>('permanent-deletion-pending-sync'),
            text:
                'Changes to this are still waiting to sync. Try again after '
                'the next sync.',
            error: true,
          ),
        ],
        const SizedBox(height: 16),
        const _Notice(
          key: ValueKey<String>('permanent-deletion-irreversible'),
          text:
              'This can\'t be undone. Your devices linked to your Sonus '
              'account will apply it when they sync.',
        ),
      ],
    );
  }
}

/// Names longer than this are confirmed with an acknowledgement and a
/// separate final step instead of being typed out.
const int permanentDeletionTypedNameLimit = 32;

/// The last step before a permanent deletion.
///
/// - A name up to [permanentDeletionTypedNameLimit] characters: type it
///   exactly to enable "Delete permanently".
/// - A longer name: the full name is shown (selectable, never cut), an
///   "I understand" box must be ticked to continue, and a separate final
///   step holds "Delete permanently". Three deliberate actions; nothing
///   destructive is focused automatically.
///
/// Fits any screen: the content scrolls inside the space left by the
/// keyboard, and the actions stay below it, stacked full width when they
/// do not fit side by side. Text is never shrunk below the user's setting.
class PermanentDeletionConfirmDialog extends StatefulWidget {
  const PermanentDeletionConfirmDialog({super.key, required this.name});

  final String name;

  @override
  State<PermanentDeletionConfirmDialog> createState() =>
      _PermanentDeletionConfirmDialogState();
}

class _PermanentDeletionConfirmDialogState
    extends State<PermanentDeletionConfirmDialog> {
  final _controller = TextEditingController();
  bool _acknowledged = false;
  bool _finalStep = false;

  bool get _long =>
      widget.name.trim().runes.length > permanentDeletionTypedNameLimit;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _matches => _controller.text.trim() == widget.name.trim();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = SonusTheme.of(context).colors;
    final media = MediaQuery.of(context);
    final large = _largeLayout(context);
    final inset = large ? 8.0 : 24.0;
    final side = large ? 12.0 : 24.0;
    // The room the dialog may use: the screen less the keyboard, the
    // system bars and the dialog's own margins.
    final maxHeight =
        media.size.height -
        media.viewInsets.bottom -
        media.padding.vertical -
        inset * 2;

    const explanation = Text(
      'Its library entries, listening history, chart entries and stories '
      'are removed from Sonus. This can\'t be undone. Your audio files are '
      'not deleted.',
    );

    final destructiveStyle = FilledButton.styleFrom(
      backgroundColor: scheme.error,
      foregroundColor: scheme.onError,
      // More room for the label on narrow, large-text screens.
      padding: large ? const EdgeInsets.symmetric(horizontal: 12) : null,
    );

    final cancel = TextButton(
      key: const ValueKey<String>('permanent-deletion-confirm-cancel'),
      onPressed: () => Navigator.of(context).pop(false),
      child: const Text('Cancel'),
    );

    final List<Widget> content;
    final Widget destructive;
    final String destructiveLabel;

    if (!_long) {
      content = [
        Text(
          'Delete ${widget.name} permanently?',
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 16),
        explanation,
        const SizedBox(height: 16),
        Text('Type ${widget.name} to confirm.'),
        const SizedBox(height: 8),
        TextField(
          key: const ValueKey<String>('permanent-deletion-confirm-field'),
          controller: _controller,
          autofocus: true,
          autocorrect: false,
          enableSuggestions: false,
          scrollPadding: const EdgeInsets.all(24),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            hintText: widget.name,
          ),
        ),
      ];
      destructiveLabel = 'Delete permanently';
      destructive = FilledButton(
        key: const ValueKey<String>('permanent-deletion-confirm-delete'),
        style: destructiveStyle,
        onPressed: _matches ? () => Navigator.of(context).pop(true) : null,
        child: Text(destructiveLabel),
      );
    } else {
      final fullName = Container(
        key: const ValueKey<String>('permanent-deletion-confirm-full-name'),
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Semantics(
          label: 'Full name: ${widget.name}',
          excludeSemantics: true,
          child: SelectableText(
            widget.name,
            style: theme.textTheme.titleMedium,
          ),
        ),
      );
      if (!_finalStep) {
        content = [
          Text('Delete permanently?', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 12),
          fullName,
          const SizedBox(height: 16),
          explanation,
          const SizedBox(height: 8),
          CheckboxListTile(
            key: const ValueKey<String>('permanent-deletion-confirm-ack'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _acknowledged,
            onChanged: (value) =>
                setState(() => _acknowledged = value ?? false),
            title: const Text(
              'I understand this permanently deletes it and its listening '
              'history, and that it can\'t be undone.',
            ),
          ),
        ];
        destructiveLabel = 'Continue';
        destructive = FilledButton(
          key: const ValueKey<String>('permanent-deletion-confirm-next'),
          style: destructiveStyle,
          onPressed: _acknowledged
              ? () => setState(() => _finalStep = true)
              : null,
          child: Text(destructiveLabel),
        );
      } else {
        content = [
          Text('Last step', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 12),
          fullName,
          const SizedBox(height: 16),
          const Text(
            'Delete this permanently? This can\'t be undone. Your audio '
            'files are not deleted.',
          ),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: const ValueKey<String>('permanent-deletion-confirm-back'),
              onPressed: () => setState(() => _finalStep = false),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Back'),
            ),
          ),
        ];
        destructiveLabel = 'Delete permanently';
        destructive = FilledButton(
          key: const ValueKey<String>('permanent-deletion-confirm-delete'),
          style: destructiveStyle,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(destructiveLabel),
        );
      }
    }

    return Dialog(
      key: const ValueKey<String>('permanent-deletion-confirm-dialog'),
      insetPadding: EdgeInsets.symmetric(horizontal: inset, vertical: inset),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight, maxWidth: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              child: SingleChildScrollView(
                key: const ValueKey<String>(
                  'permanent-deletion-confirm-scroll',
                ),
                padding: EdgeInsets.fromLTRB(side, 24, side, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: content,
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(side, 8, side, 20),
              child: _Actions(
                stacked: large,
                natural: true,
                labels: ['Cancel', destructiveLabel],
                cancel: cancel,
                destructive: destructive,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Large text, or a screen too narrow for two actions side by side.
bool _largeLayout(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(1) > sonusLargeTextScale ||
    MediaQuery.sizeOf(context).width < 360;

/// Cancel and the destructive action: side by side when both labels fit
/// on one line each, otherwise stacked full width (destructive first,
/// Cancel last and nearest the thumb). Labels are measured with the real
/// text style and the user's text scale, so a label never wraps.
class _Actions extends StatelessWidget {
  const _Actions({
    required this.stacked,
    required this.cancel,
    required this.destructive,
    required this.labels,
    this.natural = false,
  });

  /// Side by side at natural width, aligned to the end (a dialog), instead
  /// of two equal halves (the sheet).
  final bool natural;

  /// Stack whatever the measurement (large text, narrow screen).
  final bool stacked;
  final Widget cancel;
  final Widget destructive;

  /// The two button labels, for the measurement.
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelLarge;
    final scaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 12.0;
        // Button padding and a little slack.
        const chrome = 56.0;
        final half = (constraints.maxWidth - gap) / 2;
        final widths = [
          for (final (index, label) in labels.indexed)
            () {
              final painter = TextPainter(
                text: TextSpan(text: label, style: style),
                textDirection: TextDirection.ltr,
                textScaler: scaler,
                maxLines: 1,
              )..layout();
              final width = painter.width;
              painter.dispose();
              // A dialog's Cancel is a text button with slimmer padding.
              return width + (natural && index == 0 ? 32 : chrome);
            }(),
        ];
        final fits = natural
            ? widths.fold<double>(0, (a, b) => a + b) + gap <=
                  constraints.maxWidth
            : widths.every((width) => width <= half);
        if (stacked || !fits) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [destructive, const SizedBox(height: 8), cancel],
          );
        }
        if (natural) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              cancel,
              const SizedBox(width: gap),
              destructive,
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: cancel),
            const SizedBox(width: gap),
            Expanded(child: destructive),
          ],
        );
      },
    );
  }
}

class _Artwork extends StatelessWidget {
  const _Artwork({required this.path});

  final String? path;

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;
    final file = path == null ? null : File(path!);
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox.square(
        dimension: 64,
        child: file != null && file.existsSync()
            ? Image.file(file, fit: BoxFit.cover)
            : ColoredBox(
                color: colors.artworkPlaceholder,
                child: Icon(
                  Icons.album_outlined,
                  color: colors.onArtworkPlaceholder,
                ),
              ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;
    // Large text: the label above its value, so no word is broken.
    if (MediaQuery.textScalerOf(context).scale(1) > sonusLargeTextScale) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
            ),
            Text(value, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
            ),
          ),
          Expanded(
            child: Text(value, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 2, right: 8),
          child: Icon(Icons.check, size: 16),
        ),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
        ),
      ],
    ),
  );
}

class _Notice extends StatelessWidget {
  const _Notice({super.key, required this.text, this.error = false});

  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = SonusTheme.of(context).colors;
    final decoration = SonusTheme.of(context).decoration;
    final foreground = error ? scheme.error : colors.textPrimary;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: error
            ? scheme.errorContainer.withValues(
                alpha: decoration.highContrast ? 1 : 0.35,
              )
            : colors.raisedSurface,
        border: Border.all(
          color: error ? scheme.error : colors.border,
          width: decoration.highContrast ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            error ? Icons.error_outline : Icons.info_outline,
            color: foreground,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: error && !decoration.highContrast
                    ? colors.textPrimary
                    : foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/design/sonus_count_label.dart';
import '../../../../core/design/sonus_theme.dart';
import '../../../../core/design/widgets/sonus_form_section.dart';
import '../../../../core/design/widgets/sonus_notice_card.dart';
import '../../../../core/design/widgets/sonus_state_view.dart';
import '../../../account/application/controllers/account_controller.dart';
import '../../../sync/data/repositories/sync_mutation_transaction_runner.dart';
import '../../application/models/library_health_report.dart';
import '../../application/services/album_edition_management_service.dart';
import '../../application/services/library_integrity_service.dart';
import '../../data/daos/library_integrity_dao.dart';
import 'album_profile_page.dart';

/// The Import Health Report, and "Verify Library" for an existing library.
///
/// Verification reads the library as stored and never changes it. Safe
/// corrections are offered with an Apply button each, and applied only
/// when the user confirms.
class LibraryHealthPage extends StatefulWidget {
  const LibraryHealthPage({super.key, this.importCounts, this.service});

  /// The import this report follows, if any.
  final ImportHealthCounts? importCounts;

  /// For tests; otherwise built from the app database.
  final LibraryIntegrityService? service;

  @override
  State<LibraryHealthPage> createState() => _LibraryHealthPageState();
}

class _LibraryHealthPageState extends State<LibraryHealthPage> {
  LibraryIntegrityService? _service;
  LibraryHealthReport? _report;
  Object? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _verify();
  }

  Future<LibraryIntegrityService> _resolveService() async {
    final existing = _service ?? widget.service;
    if (existing != null) {
      return _service = existing;
    }

    final appDatabase = context.read<AppDatabase>();
    return _service = LibraryIntegrityService(
      dao: LibraryIntegrityDao(await appDatabase.database),
      editions: AlbumEditionManagementService(
        mutationRunner: SyncMutationTransactionRunner(appDatabase: appDatabase),
      ),
      fileExists: (path) => File(path).exists(),
    );
  }

  Future<void> _verify() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final service = await _resolveService();
      final report = await service.verify(importCounts: widget.importCounts);
      if (mounted) setState(() => _report = report);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apply(HealthFinding finding) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Apply correction?'),
        content: Text(
          '${finding.summary}\n\nSonus will correct '
          '${finding.corrections.length == 1 ? 'this' : 'these ${finding.corrections.length}'} '
          'without changing songs, files or listening history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey<String>('library-health-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Apply'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    final userId = context.read<AccountController?>()?.user?.id;
    setState(() => _busy = true);

    try {
      final service = await _resolveService();
      for (final correction in finding.corrections) {
        await service.applyCorrection(correction, userId: userId);
      }
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }

    await _verify();
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    final tokens = SonusTheme.of(context);
    final gutter = tokens.metrics.pageGutter;

    return Scaffold(
      backgroundColor: tokens.colors.background,
      appBar: AppBar(
        backgroundColor: tokens.colors.background,
        surfaceTintColor: Colors.transparent,
        title: Text(
          widget.importCounts == null
              ? 'Verify Library'
              : 'Import Health Report',
        ),
        actions: [
          IconButton(
            key: const ValueKey<String>('library-health-verify'),
            tooltip: 'Verify again',
            onPressed: _busy ? null : _verify,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: report == null
          ? _error == null
                ? const SonusStateView.loading(
                    key: ValueKey<String>('library-health-checking'),
                    label: 'Checking your library…',
                  )
                : SonusStateView(
                    key: const ValueKey<String>('library-health-failed'),
                    icon: Icons.error_outline_rounded,
                    isError: true,
                    title: 'The library could not be checked.',
                    message: 'Nothing was changed. Try again.',
                    action: FilledButton.tonalIcon(
                      onPressed: _busy ? null : _verify,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Try again'),
                    ),
                  )
          : ListView(
              key: const ValueKey<String>('library-health-report'),
              padding: EdgeInsets.fromLTRB(gutter, 8, gutter, 32),
              children: [
                if (_busy) ...[
                  const LinearProgressIndicator(),
                  const SizedBox(height: 12),
                ],
                _Overview(report: report),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  const SonusNoticeCard(
                    key: ValueKey<String>('library-health-apply-failed'),
                    tone: SonusNoticeTone.error,
                    title: 'A correction could not be applied.',
                    message: 'Nothing was changed.',
                  ),
                ],
                for (final (severity, title, subtitle) in const [
                  (
                    HealthSeverity.needsReview,
                    'Needs your review',
                    'Sonus won\'t change these by itself.',
                  ),
                  (
                    HealthSeverity.safeCorrection,
                    'Safe corrections',
                    'Applied only when you choose Apply.',
                  ),
                  (HealthSeverity.warning, 'Warnings', null),
                  (HealthSeverity.verified, 'Verified', null),
                ])
                  if (report.withSeverity(severity).isNotEmpty) ...[
                    const SizedBox(height: 16),
                    SonusFormSection(
                      title: title,
                      subtitle: subtitle,
                      icon: _iconFor(severity),
                      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                      children: [
                        for (final finding in report.withSeverity(severity))
                          _FindingTile(
                            finding: finding,
                            severity: severity,
                            busy: _busy,
                            onApply: () => _apply(finding),
                            onReviewFormats: () => _reviewFormats(finding),
                          ),
                      ],
                    ),
                  ],
              ],
            ),
    );
  }

  /// Lists the releases that might be Singles; each opens its page, where
  /// Edit Release sets the format. The report is checked again afterwards.
  Future<void> _reviewFormats(HealthFinding finding) async {
    final albumId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _FormatReviewList(releases: finding.formatReviews),
    );
    if (albumId == null || !mounted) return;

    final release = finding.formatReviews.firstWhere(
      (r) => r.albumId == albumId,
    );
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => AlbumProfilePage(
          albumId: release.albumId,
          initialAlbumTitle: release.title,
        ),
      ),
    );
    if (mounted) await _verify();
  }

  static IconData _iconFor(HealthSeverity severity) => switch (severity) {
    HealthSeverity.verified => Icons.check_circle_outline_rounded,
    HealthSeverity.safeCorrection => Icons.build_circle_outlined,
    HealthSeverity.warning => Icons.info_outline_rounded,
    HealthSeverity.needsReview => Icons.rate_review_outlined,
  };
}

class _FindingTile extends StatelessWidget {
  const _FindingTile({
    required this.finding,
    required this.severity,
    required this.busy,
    required this.onApply,
    required this.onReviewFormats,
  });

  final HealthFinding finding;
  final HealthSeverity severity;
  final bool busy;
  final VoidCallback onApply;
  final VoidCallback onReviewFormats;

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;
    final theme = Theme.of(context);
    final color = switch (severity) {
      HealthSeverity.verified => colors.chartUp,
      HealthSeverity.safeCorrection => colors.accentPrimary,
      HealthSeverity.warning => colors.textSecondary,
      HealthSeverity.needsReview => colors.chartDown,
    };

    return ListTile(
      key: ValueKey<String>('library-health-${finding.check.name}'),
      leading: Icon(_LibraryHealthPageState._iconFor(severity), color: color),
      title: Text(
        finding.summary,
        style: theme.textTheme.bodyMedium?.copyWith(color: colors.textPrimary),
      ),
      trailing: finding.folderSplits.isNotEmpty
          ? TextButton(
              key: const ValueKey<String>('library-health-preview-folders'),
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                showDragHandle: true,
                builder: (_) =>
                    _FolderSplitPreview(splits: finding.folderSplits),
              ),
              child: const Text('Preview'),
            )
          : finding.formatReviews.isNotEmpty
          ? TextButton(
              key: const ValueKey<String>('library-health-review-formats'),
              onPressed: busy ? null : onReviewFormats,
              child: const Text('Review'),
            )
          : finding.corrections.isEmpty
          ? null
          : TextButton(
              key: ValueKey<String>(
                'library-health-apply-${finding.check.name}',
              ),
              onPressed: busy ? null : onApply,
              child: const Text('Apply'),
            ),
    );
  }
}

/// SN-45 reconciliation preview: which albums each split folder was filed
/// under. Read-only.
class _FolderSplitPreview extends StatelessWidget {
  const _FolderSplitPreview({required this.splits});

  final List<FolderSplit> splits;

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, controller) => ListView(
        key: const ValueKey<String>('library-health-folder-preview'),
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children: [
          Semantics(
            header: true,
            child: Text(
              'Folders split into several albums',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'New imports keep each folder together as one album. These '
            'folders were imported earlier, when each song was filed by its '
            "own artist tag. They are listed for review only: Sonus doesn't "
            'merge albums by itself, and your songs, streams and playlists '
            'are unchanged.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.textSecondary,
            ),
          ),
          for (final split in splits) ...[
            const SizedBox(height: 20),
            Text(
              split.folderName,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            for (final album in split.albums)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.album_outlined),
                title: Text(album.title),
                subtitle: Text(
                  '${album.owner} · ${sonusCount(album.songCount, 'song')}',
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// SN-45: releases that might be Singles. Choosing one returns its id.
class _FormatReviewList extends StatelessWidget {
  const _FormatReviewList({required this.releases});

  final List<ReleaseFormatReview> releases;

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, controller) => ListView(
        key: const ValueKey<String>('library-health-format-reviews'),
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children: [
          Semantics(
            header: true,
            child: Text(
              'Choose Single, EP or Album',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'These releases have no stated format and only a few songs, so '
            'they might be Singles. Sonus does not guess: open one and set '
            'its format in Edit Release. Until then it stays off the Sonus '
            'Albums & EPs chart; its songs still chart on the Sonus Hot 100, '
            'and nothing about them changes.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          for (final release in releases)
            ListTile(
              key: ValueKey<String>(
                'library-health-format-review-${release.albumId}',
              ),
              contentPadding: EdgeInsets.zero,
              minTileHeight: 56,
              leading: const Icon(Icons.album_outlined),
              title: Text(release.title),
              subtitle: Text(
                '${release.owner} · ${sonusCount(release.songCount, 'song')}',
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(context).pop(release.albumId),
            ),
        ],
      ),
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview({required this.report});

  final LibraryHealthReport report;

  @override
  Widget build(BuildContext context) {
    final counts = report.importCounts;
    final checked =
        '${sonusCount(report.songCount, 'song')}, '
        '${sonusCount(report.albumCount, 'album')} and '
        '${sonusCount(report.artistCount, 'artist')} checked.';

    return SonusNoticeCard(
      key: const ValueKey<String>('library-health-status'),
      tone: report.isHealthy
          ? SonusNoticeTone.success
          : SonusNoticeTone.warning,
      title: report.isHealthy
          ? 'Nothing needs your attention.'
          : 'Some items need your attention.',
      message: [
        checked,
        if (counts != null)
          'This import: ${counts.imported} imported, ${counts.relinked} '
              'relinked, ${counts.skipped} skipped, ${counts.failed} failed.',
        'Checking only reads your library; nothing changes unless you apply '
            'a correction.',
      ].join('\n'),
    );
  }
}

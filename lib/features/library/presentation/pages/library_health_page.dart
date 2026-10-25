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
                          ),
                      ],
                    ),
                  ],
              ],
            ),
    );
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
  });

  final HealthFinding finding;
  final HealthSeverity severity;
  final bool busy;
  final VoidCallback onApply;

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
      trailing: finding.corrections.isEmpty
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

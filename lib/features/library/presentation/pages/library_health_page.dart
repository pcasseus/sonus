import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/database/app_database.dart';
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
/// when the user confirms. Presentation is deliberately plain.
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

    return Scaffold(
      appBar: AppBar(
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
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : const Text('The library could not be checked. Try again.'),
            )
          : ListView(
              key: const ValueKey<String>('library-health-report'),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                if (_busy) const LinearProgressIndicator(),
                if (_error != null)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'A correction could not be applied. Nothing was changed.',
                    ),
                  ),
                _Overview(report: report),
                for (final (severity, title) in const [
                  (HealthSeverity.needsReview, 'Needs your review'),
                  (HealthSeverity.safeCorrection, 'Safe corrections'),
                  (HealthSeverity.warning, 'Warnings'),
                  (HealthSeverity.verified, 'Verified'),
                ])
                  if (report.withSeverity(severity).isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 20, bottom: 4),
                      child: Semantics(
                        header: true,
                        child: Text(
                          title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ),
                    for (final finding in report.withSeverity(severity))
                      ListTile(
                        key: ValueKey<String>(
                          'library-health-${finding.check.name}',
                        ),
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(_iconFor(severity)),
                        title: Text(finding.summary),
                        trailing: finding.corrections.isEmpty
                            ? null
                            : TextButton(
                                key: ValueKey<String>(
                                  'library-health-apply-${finding.check.name}',
                                ),
                                onPressed: _busy ? null : () => _apply(finding),
                                child: const Text('Apply'),
                              ),
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

class _Overview extends StatelessWidget {
  const _Overview({required this.report});

  final LibraryHealthReport report;

  @override
  Widget build(BuildContext context) {
    final counts = report.importCounts;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${report.songCount} songs, ${report.albumCount} albums, '
          '${report.artistCount} artists checked.',
        ),
        if (counts != null)
          Text(
            'This import: ${counts.imported} imported, ${counts.relinked} '
            'relinked, ${counts.skipped} skipped, ${counts.failed} failed.',
          ),
        const SizedBox(height: 4),
        Text(
          report.isHealthy
              ? 'Nothing needs your attention.'
              : 'Some items need your attention.',
          key: const ValueKey<String>('library-health-status'),
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ],
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/design/sonus_theme.dart';
import '../../../../core/design/widgets/sonus_notice_card.dart';
import '../../../../core/design/widgets/sonus_surface_card.dart';
import '../../../account/application/controllers/account_controller.dart';
import '../../../artwork/application/services/artwork_assignment_service.dart';
import '../../../artwork/application/services/artwork_file_picker.dart';
import '../../../library/application/models/library_health_report.dart';
import '../../../library/application/services/album_profile_editing_service.dart';
import '../../../library/presentation/pages/library_health_page.dart';
import '../../application/models/import_execution_summary.dart';
import '../../application/services/device_music_access.dart';
import '../../application/services/import_review_service.dart';
import '../../application/services/import_source_picker.dart';
import '../../application/services/import_workflow_service.dart';
import '../../domain/entities/import_source.dart';
import '../controllers/imports_controller.dart';
import '../widgets/import_error_card.dart';
import '../widgets/import_folder_structure_card.dart';
import '../widgets/import_progress_card.dart';
import '../widgets/import_result_card.dart';
import '../widgets/import_source_card.dart';
import 'device_music_folder_page.dart';
import 'import_review_page.dart';

class ImportsPage extends StatefulWidget {
  const ImportsPage({super.key});

  @override
  State<ImportsPage> createState() => _ImportsPageState();
}

class _ImportsPageState extends State<ImportsPage> {
  ImportWorkflowService? _workflowService;
  ImportReviewService? _reviewService;
  ImportsController? _controller;

  String? _userId;
  int _reviewCount = 0;
  int _reviewLoadVersion = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final workflowService = context.watch<ImportWorkflowService?>();
    final reviewService = context.watch<ImportReviewService?>();
    final accountController = context.watch<AccountController?>();

    final rawUserId = accountController?.user?.id.trim();
    final userId = rawUserId == null || rawUserId.isEmpty ? null : rawUserId;

    if (!identical(workflowService, _workflowService)) {
      _controller?.dispose();
      _workflowService = workflowService;

      if (workflowService == null) {
        _controller = null;
      } else {
        final controller = ImportsController(
          workflowService: workflowService,
          sourcePicker: context.read<ImportSourcePicker>(),
        );

        _controller = controller;
        unawaited(controller.loadSources());
      }
    }

    if (!identical(reviewService, _reviewService)) {
      _reviewService = reviewService;

      if (reviewService == null) {
        _reviewCount = 0;
      } else {
        unawaited(_loadReviewCount());
      }
    }

    _userId = userId;
  }

  /// On Android, Sonus's own music folder browser comes first: some
  /// devices' system picker cannot open folders such as Download/Music.
  Future<bool> _importFolder(ImportsController controller) async {
    final access = context.read<DeviceMusicAccess?>();

    if (access == null) {
      return controller.importStructuredFolder();
    }

    final choice = await DeviceMusicFolderPage.open(context, access);

    return switch (choice) {
      ChosenDeviceMusicFolder(:final path) => controller.importFolderAt(path),
      UseSystemFolderPicker() => controller.importStructuredFolder(),
      null => false,
    };
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;

    return Scaffold(
      key: const ValueKey<String>('imports-page'),
      backgroundColor: colors.background,
      appBar: AppBar(
        title: const Text('Import music'),
        backgroundColor: colors.background,
        surfaceTintColor: Colors.transparent,
      ),
      body: controller == null
          ? const Center(
              child: CircularProgressIndicator(
                key: ValueKey<String>('imports-loading'),
              ),
            )
          : AnimatedBuilder(
              animation: controller,
              builder: (context, _) {
                return ListView(
                  padding: EdgeInsets.fromLTRB(
                    tokens.metrics.pageGutter,
                    12,
                    tokens.metrics.pageGutter,
                    32 + MediaQuery.paddingOf(context).bottom,
                  ),
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        'Add music to Sonus',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              color: colors.textPrimary,
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Import one MP3 from anywhere on your device or import '
                      'an organized music folder.',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (controller.status == ImportsControllerStatus.idle) ...[
                      if (_reviewCount > 0) ...[
                        _NeedsReviewCard(
                          count: _reviewCount,
                          canReview: _reviewService != null,
                          onReview: _openReviewPage,
                        ),
                        const SizedBox(height: 14),
                      ],
                      ImportSourceCard(
                        key: const ValueKey<String>('import-single-song-card'),
                        icon: Icons.audio_file_rounded,
                        title: 'Import one song',
                        description:
                            'Choose a single MP3 file. Sonus will read its '
                            'embedded metadata when available.',
                        buttonLabel: 'Choose MP3',
                        enabled: !controller.isBusy,
                        onPressed: () {
                          unawaited(
                            _runAndRefreshReviewCount(
                              controller.importSingleSong,
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 14),
                      ImportSourceCard(
                        key: const ValueKey<String>('import-folder-card'),
                        icon: Icons.folder_copy_outlined,
                        title: 'Import a music folder',
                        description:
                            'Import multiple artists and albums using the '
                            'Sonus folder structure.',
                        buttonLabel: 'Choose folder',
                        enabled: !controller.isBusy,
                        onPressed: () {
                          unawaited(
                            _runAndRefreshReviewCount(
                              () => _importFolder(controller),
                            ),
                          );
                        },
                      ),
                      if (controller.isLoadingSources) ...[
                        const SizedBox(height: 20),
                        const Center(
                          child: CircularProgressIndicator(
                            key: ValueKey<String>('import-sources-loading'),
                          ),
                        ),
                      ],
                      if (controller.hasSources) ...[
                        const SizedBox(height: 24),
                        Semantics(
                          header: true,
                          child: Text(
                            'Saved music folders',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  color: colors.textPrimary,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Scan these folders again to add new music and '
                          'detect files that are no longer available.',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: colors.textSecondary),
                        ),
                        const SizedBox(height: 12),
                        ...controller.sources.map(
                          (source) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _SavedImportSourceCard(
                              source: source,
                              onRescan: () {
                                unawaited(
                                  _runAndRefreshReviewCount(
                                    () => controller.rescanSource(source),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      const ImportFolderStructureCard(),
                    ],
                    if (controller.isBusy)
                      ImportProgressCard(controller: controller),
                    if (controller.hasCompleted && controller.summary != null)
                      ImportResultCard(
                        summary: controller.summary!,
                        reviewCount: _reviewCount,
                        onReview: _reviewService != null
                            ? _openReviewPage
                            : null,
                        onReset: controller.reset,
                        onCheckHealth: () =>
                            _openHealthReport(controller.summary!),
                      ),
                    if (controller.hasError)
                      ImportErrorCard(
                        message:
                            controller.errorMessage ??
                            'Could not complete the import.',
                        onReset: controller.reset,
                      ),
                  ],
                );
              },
            ),
    );
  }

  Future<void> _runAndRefreshReviewCount(
    Future<bool> Function() operation,
  ) async {
    final completed = await operation();

    if (completed) {
      await _loadReviewCount();
    }
  }

  Future<void> _loadReviewCount() async {
    final service = _reviewService;
    final version = ++_reviewLoadVersion;

    if (service == null) {
      return;
    }

    try {
      final count = await service.countUnresolved();

      if (!mounted ||
          version != _reviewLoadVersion ||
          !identical(service, _reviewService)) {
        return;
      }

      setState(() {
        _reviewCount = count;
      });
    } catch (_) {
      // Importing remains usable even if the review count cannot be loaded.
    }
  }

  Future<void> _openHealthReport(ImportExecutionSummary summary) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => LibraryHealthPage(
          importCounts: ImportHealthCounts(
            imported: summary.importedCount,
            relinked: summary.relinkedCount,
            skipped: summary.skippedCount,
            failed: summary.failedCount,
          ),
        ),
      ),
    );
  }

  Future<void> _openReviewPage() async {
    final service = _reviewService;
    final userId = _userId;

    if (service == null) {
      return;
    }

    final artworkAssignmentService = context.read<ArtworkAssignmentService?>();
    final artworkFilePicker = context.read<ArtworkFilePicker?>();
    final albumProfileEditingService = context
        .read<AlbumProfileEditingService?>();

    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ImportReviewPage(
          service: service,
          userId: userId,
          artworkAssignmentService: artworkAssignmentService,
          artworkFilePicker: artworkFilePicker,
          albumProfileEditingService: albumProfileEditingService,
        ),
      ),
    );

    await _loadReviewCount();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }
}

class _NeedsReviewCard extends StatelessWidget {
  const _NeedsReviewCard({
    required this.count,
    required this.canReview,
    required this.onReview,
  });

  final int count;
  final bool canReview;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    return SonusNoticeCard(
      key: const ValueKey<String>('import-needs-review-card'),
      tone: SonusNoticeTone.info,
      title: '$count ${count == 1 ? 'song needs' : 'songs need'} review',
      message: canReview
          ? 'Review metadata Sonus could not confidently determine during '
                'import.'
          : 'Review is currently unavailable.',
      actions: [
        if (canReview)
          FilledButton.tonalIcon(
            key: const ValueKey<String>('open-import-review-button'),
            onPressed: onReview,
            icon: const Icon(Icons.edit_note_rounded),
            label: const Text('Review metadata'),
          ),
      ],
    );
  }
}

class _SavedImportSourceCard extends StatelessWidget {
  const _SavedImportSourceCard({required this.source, required this.onRescan});

  final ImportSource source;
  final VoidCallback onRescan;

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;
    final theme = Theme.of(context);
    final lastScannedAt = source.lastScannedAt;

    return SonusSurfaceCard(
      key: ValueKey<String>('import-source-${source.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.folder_outlined, color: colors.textSecondary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Music folder',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            source.rootPath,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textPrimary,
            ),
          ),
          if (lastScannedAt != null) ...[
            const SizedBox(height: 8),
            Text(
              'Last scanned ${formatImportScanTime(lastScannedAt)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.textSecondary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              key: ValueKey<String>('rescan-source-${source.id}'),
              onPressed: onRescan,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Scan for changes'),
            ),
          ),
        ],
      ),
    );
  }
}

/// "October 5, 2026 at 14:07", in local time.
@visibleForTesting
String formatImportScanTime(DateTime value) {
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  final local = value.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${months[local.month - 1]} ${local.day}, ${local.year} at '
      '$hour:$minute';
}

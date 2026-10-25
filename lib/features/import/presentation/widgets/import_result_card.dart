import 'package:flutter/material.dart';

import '../../../../core/design/widgets/sonus_notice_card.dart';

import '../../application/models/import_execution_summary.dart';

class ImportResultCard extends StatelessWidget {
  const ImportResultCard({
    super.key,
    required this.summary,
    required this.onReset,
    this.reviewCount = 0,
    this.onReview,
    this.onCheckHealth,
  });

  final ImportExecutionSummary summary;
  final VoidCallback onReset;
  final int reviewCount;
  final VoidCallback? onReview;

  /// Opens the Import Health Report for this import.
  final VoidCallback? onCheckHealth;

  @override
  Widget build(BuildContext context) {
    return SonusNoticeCard(
      key: const ValueKey<String>('import-result-card'),
      tone: summary.hasFailures
          ? SonusNoticeTone.warning
          : SonusNoticeTone.success,
      title: summary.hasFailures
          ? 'Import completed with issues'
          : 'Import complete',
      actions: [
        if (reviewCount > 0 && onReview != null)
          FilledButton.icon(
            key: const ValueKey<String>('import-review-button'),
            onPressed: onReview,
            icon: const Icon(Icons.fact_check_outlined),
            label: const Text('Review metadata'),
          ),
        if (onCheckHealth != null)
          OutlinedButton.icon(
            key: const ValueKey<String>('import-health-button'),
            onPressed: onCheckHealth,
            icon: const Icon(Icons.health_and_safety_outlined),
            label: const Text('Check library health'),
          ),
        FilledButton.tonal(
          key: const ValueKey<String>('import-reset-button'),
          onPressed: onReset,
          child: const Text('Import more music'),
        ),
      ],
      children: [
        const SizedBox(height: 12),
        _ResultRow(label: 'Processed', value: summary.processedCount),
        _ResultRow(label: 'Imported', value: summary.importedCount),
        _ResultRow(label: 'Relinked', value: summary.relinkedCount),
        _ResultRow(label: 'Skipped', value: summary.skippedCount),
        _ResultRow(label: 'Failed', value: summary.failedCount),
        if (reviewCount > 0)
          _ResultRow(label: 'Needs review', value: reviewCount),
      ],
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            '$value',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

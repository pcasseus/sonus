import 'package:flutter/material.dart';

import '../../application/models/import_execution_summary.dart';

class ImportResultCard extends StatelessWidget {
  const ImportResultCard({
    super.key,
    required this.summary,
    required this.onReset,
    this.reviewCount = 0,
    this.onReview,
  });

  final ImportExecutionSummary summary;
  final VoidCallback onReset;
  final int reviewCount;
  final VoidCallback? onReview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      key: const ValueKey<String>('import-result-card'),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  summary.hasFailures
                      ? Icons.warning_amber_rounded
                      : Icons.check_circle_outline_rounded,
                  color: summary.hasFailures
                      ? theme.colorScheme.error
                      : theme.colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Text(
                  summary.hasFailures
                      ? 'Import completed with issues'
                      : 'Import complete',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _ResultRow(label: 'Processed', value: summary.processedCount),
            _ResultRow(label: 'Imported', value: summary.importedCount),
            _ResultRow(label: 'Relinked', value: summary.relinkedCount),
            _ResultRow(label: 'Skipped', value: summary.skippedCount),
            _ResultRow(label: 'Failed', value: summary.failedCount),
            if (reviewCount > 0)
              _ResultRow(label: 'Needs review', value: reviewCount),
            if (reviewCount > 0 && onReview != null) ...[
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const ValueKey<String>('import-review-button'),
                  onPressed: onReview,
                  icon: const Icon(Icons.fact_check_outlined),
                  label: const Text('Review metadata'),
                ),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonal(
                key: const ValueKey<String>('import-reset-button'),
                onPressed: onReset,
                child: const Text('Import more music'),
              ),
            ),
          ],
        ),
      ),
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
          Text('$value', style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

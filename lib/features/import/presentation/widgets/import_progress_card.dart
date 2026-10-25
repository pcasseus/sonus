import 'package:flutter/material.dart';

import '../../../../core/design/widgets/sonus_surface_card.dart';

import '../controllers/imports_controller.dart';

class ImportProgressCard extends StatelessWidget {
  const ImportProgressCard({super.key, required this.controller});

  final ImportsController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final batch = controller.currentBatch;

    final total = batch?.totalCount ?? 0;
    final completed = batch?.completedCount ?? 0;
    final progress = total == 0 ? null : batch!.progress;

    return SonusSurfaceCard(
      key: const ValueKey<String>('import-progress-card'),
      padding: const EdgeInsets.all(20),
      child: Semantics(
        liveRegion: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    controller.isSelectingSource
                        ? 'Choose a source'
                        : 'Importing music',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 10),
            Text(
              total == 0
                  ? 'Preparing import...'
                  : '$completed of $total files processed',
              key: const ValueKey<String>('import-progress-text'),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

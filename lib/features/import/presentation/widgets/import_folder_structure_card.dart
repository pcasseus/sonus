import 'package:flutter/material.dart';

import '../../../../core/design/widgets/sonus_surface_card.dart';

class ImportFolderStructureCard extends StatelessWidget {
  const ImportFolderStructureCard({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SonusSurfaceCard(
      padding: EdgeInsets.zero,
      key: const ValueKey<String>('import-folder-structure-card'),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.account_tree_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Folder structure',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Folder imports must follow this structure:',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Text(
                'Music Folder\n'
                '└── Artist\n'
                '    └── Album\n'
                '        ├── 01 - Song.mp3\n'
                '        └── 02 - Song.mp3',
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Only MP3 files are supported right now. '
              'Artist folders may contain only album folders, and album '
              'folders may contain only MP3 files.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

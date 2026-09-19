import 'package:flutter/material.dart';

class ImportErrorCard extends StatelessWidget {
  const ImportErrorCard({
    super.key,
    required this.message,
    required this.onReset,
  });

  final String message;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      key: const ValueKey<String>('import-error-card'),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(width: 10),
                Text(
                  'Import failed',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(message),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonal(
                key: const ValueKey<String>('import-error-reset-button'),
                onPressed: onReset,
                child: const Text('Try again'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

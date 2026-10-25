import 'package:flutter/material.dart';

import '../../../../core/design/widgets/sonus_notice_card.dart';

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
    return SonusNoticeCard(
      key: const ValueKey<String>('import-error-card'),
      tone: SonusNoticeTone.error,
      title: 'Import failed',
      message: message,
      actions: [
        FilledButton.tonal(
          key: const ValueKey<String>('import-error-reset-button'),
          onPressed: onReset,
          child: const Text('Try again'),
        ),
      ],
    );
  }
}

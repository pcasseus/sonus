import 'package:flutter/material.dart';

import '../../../../core/design/widgets/sonus_surface_card.dart';

import '../../../../core/design/sonus_theme.dart';

class ImportSourceCard extends StatelessWidget {
  const ImportSourceCard({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.buttonLabel,
    required this.onPressed,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String description;
  final String buttonLabel;
  final VoidCallback onPressed;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = SonusTheme.of(context).colors;

    return SonusSurfaceCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 34, color: colors.accentPrimary),
          const SizedBox(height: 16),
          Text(
            title,
            style: theme.textTheme.titleLarge?.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: enabled ? onPressed : null,
              icon: Icon(icon),
              label: Text(buttonLabel),
            ),
          ),
        ],
      ),
    );
  }
}

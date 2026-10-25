import 'package:flutter/material.dart';

import '../../../../core/design/sonus_theme.dart';

/// Marks where the official chart ends and extended standings begin, so
/// positions 101–200 are never read as official entries.
class ChartExtendedDivider extends StatelessWidget {
  const ChartExtendedDivider({super.key});

  static const String label = 'Extended standings · 101–200';

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final line = Expanded(
      child: Divider(color: tokens.colors.border, thickness: 1, height: 1),
    );

    return Padding(
      key: const ValueKey<String>('charts-extended-divider'),
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          line,
          // Loose, so the label wraps instead of overflowing with large text.
          Flexible(
            flex: 8,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Semantics(
                header: true,
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: tokens.colors.textSecondary,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ),
          ),
          line,
        ],
      ),
    );
  }
}

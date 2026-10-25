import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/design/sonus_theme.dart';
import '../../../../core/privacy/online_lookup_consent.dart';

/// The consent in scope, or null when lookups need no consent (tests and
/// screens without one).
OnlineLookupConsent? onlineLookupConsentOf(BuildContext context) {
  try {
    return Provider.of<OnlineLookupConsent?>(context, listen: false);
  } on ProviderNotFoundException {
    return null;
  }
}

/// Shown in place of results until the user accepts online lookups.
class OnlineLookupDisclosure extends StatelessWidget {
  const OnlineLookupDisclosure({super.key, required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;
    final theme = Theme.of(context);

    return SingleChildScrollView(
      key: const ValueKey<String>('online-lookup-disclosure'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.public_rounded, color: colors.accentPrimary),
              const SizedBox(width: 10),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    'Search online?',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            onlineLookupDisclosure,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FilledButton(
              key: const ValueKey<String>('online-lookup-accept'),
              onPressed: onContinue,
              child: const Text('Search online'),
            ),
          ),
        ],
      ),
    );
  }
}

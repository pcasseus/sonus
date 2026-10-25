import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
    return SingleChildScrollView(
      key: const ValueKey<String>('online-lookup-disclosure'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Search online?',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const Text(onlineLookupDisclosure),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
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

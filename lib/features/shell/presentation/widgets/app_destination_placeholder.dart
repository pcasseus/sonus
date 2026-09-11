import 'package:flutter/material.dart';

import '../../domain/models/app_destination.dart';

class AppDestinationPlaceholder extends StatelessWidget {
  const AppDestinationPlaceholder({super.key, required this.destination});

  final AppDestination destination;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: Center(
        child: Text(
          destination.label,
          key: ValueKey<String>('app-destination-${destination.name}'),
          style: Theme.of(context).textTheme.headlineMedium,
        ),
      ),
    );
  }
}

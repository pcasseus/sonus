import 'package:flutter/material.dart';

class ShellPlaybackSlot extends StatelessWidget {
  const ShellPlaybackSlot({super.key, this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const ValueKey<String>('shell-playback-slot'),
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(top: false, child: child ?? const SizedBox.shrink()),
    );
  }
}

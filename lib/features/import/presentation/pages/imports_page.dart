import 'package:flutter/material.dart';

class ImportsPage extends StatelessWidget {
  const ImportsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Imports')),
      body: const Center(
        child: Text('Imports', key: ValueKey<String>('imports-page')),
      ),
    );
  }
}

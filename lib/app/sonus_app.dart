import 'package:flutter/material.dart';

import '../features/player/presentation/scopes/playback_scope.dart';

class SonusApp extends StatelessWidget {
  const SonusApp({super.key, this.playbackEngineFactory});

  final PlaybackEngineFactory? playbackEngineFactory;

  @override
  Widget build(BuildContext context) {
    return PlaybackScope(
      engineFactory: playbackEngineFactory,
      child: MaterialApp(
        title: 'Sonus',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        ),
        home: const _SonusBootstrapPage(),
      ),
    );
  }
}

class _SonusBootstrapPage extends StatelessWidget {
  const _SonusBootstrapPage();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('Sonus')));
  }
}

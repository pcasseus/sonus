import 'package:flutter/material.dart';

import '../features/player/presentation/scopes/playback_scope.dart';
import '../features/shell/presentation/pages/app_shell_page.dart';

class SonusApp extends StatelessWidget {
  const SonusApp({super.key, this.playbackEngineFactory});

  final PlaybackEngineFactory? playbackEngineFactory;

  @override
  Widget build(BuildContext context) {
    return PlaybackScope(
      engineFactory: playbackEngineFactory,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Sonus',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        ),
        home: const AppShellPage(),
      ),
    );
  }
}

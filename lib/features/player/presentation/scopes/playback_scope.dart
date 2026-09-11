import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../application/controllers/playback_coordinator.dart';
import '../../data/engines/just_audio_playback_engine.dart';
import '../../domain/services/playback_engine.dart';
import '../controllers/playback_state_controller.dart';

typedef PlaybackEngineFactory = PlaybackEngine Function();

class PlaybackScope extends StatefulWidget {
  const PlaybackScope({super.key, required this.child, this.engineFactory});

  final Widget child;
  final PlaybackEngineFactory? engineFactory;

  @override
  State<PlaybackScope> createState() => _PlaybackScopeState();
}

class _PlaybackScopeState extends State<PlaybackScope> {
  late final PlaybackEngine _engine;
  late final PlaybackCoordinator _coordinator;
  late final PlaybackStateController _stateController;

  @override
  void initState() {
    super.initState();

    _engine = widget.engineFactory?.call() ?? JustAudioPlaybackEngine();

    _coordinator = PlaybackCoordinator(engine: _engine);

    _stateController = PlaybackStateController(coordinator: _coordinator);
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<PlaybackCoordinator>.value(value: _coordinator),
        ChangeNotifierProvider<PlaybackStateController>.value(
          value: _stateController,
        ),
      ],
      child: widget.child,
    );
  }

  @override
  void dispose() {
    _stateController.dispose();
    unawaited(_engine.dispose());
    super.dispose();
  }
}

// Device-faithful layout tests: the real Roboto glyphs (Flutter's test font
// draws every character as a square, about 1.7x wider than Roboto, which
// would make wrapping and fitting look worse than on a phone), and a
// playback engine with a song queued, so the real mini-player shows.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/player/domain/models/playback_queue.dart';
import 'package:sonus_next/features/player/domain/models/playback_state.dart';
import 'package:sonus_next/features/player/domain/models/playback_track.dart';
import 'package:sonus_next/features/player/domain/services/playback_engine.dart';

/// The family the real Roboto files are loaded under. The test runner maps
/// "Roboto" itself to its square test font, so another name is used.
const String realRobotoFamily = 'SonusTestRoboto';

bool _robotoLoaded = false;

/// Loads Roboto from the Flutter SDK (the material fonts that ship with
/// it) under [realRobotoFamily]. Call from setUpAll.
Future<void> loadRealRoboto() async {
  if (_robotoLoaded) return;
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) {
    throw StateError('FLUTTER_ROOT is not set; run with `flutter test`.');
  }
  final dir = Directory('$root/bin/cache/artifacts/material_fonts');
  final loader = FontLoader(realRobotoFamily);
  var count = 0;
  for (final file in dir.listSync().whereType<File>()) {
    final name = file.uri.pathSegments.last;
    if (name.startsWith('roboto-') && name.endsWith('.ttf')) {
      final bytes = await file.readAsBytes();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
      count++;
    }
  }
  if (count == 0) throw StateError('No Roboto fonts found in ${dir.path}.');
  await loader.load();
  _robotoLoaded = true;
}

/// [theme] drawing its text in the real Roboto.
ThemeData withRealRoboto(ThemeData theme) => theme.copyWith(
  textTheme: theme.textTheme.apply(fontFamily: realRobotoFamily),
  primaryTextTheme: theme.primaryTextTheme.apply(fontFamily: realRobotoFamily),
);

/// The Galaxy S26 Ultra as measured on the device (2026-11-04): 384 x 832dp
/// at density 450, a 40dp status bar and a 48dp three-button navigation
/// bar.
const Size s26UltraSize = Size(384, 832);
const double s26UltraRatio = 2.8125;

void setDevice(
  WidgetTester tester, {
  Size size = s26UltraSize,
  double ratio = s26UltraRatio,
  double statusBar = 40,
  double navigationBar = 48,
}) {
  tester.view.devicePixelRatio = ratio;
  tester.view.physicalSize = size * ratio;
  tester.view.padding = FakeViewPadding(
    top: statusBar * ratio,
    bottom: navigationBar * ratio,
  );
  addTearDown(tester.view.reset);
}

/// A playback engine with one song queued and nothing else.
class QueuedSongEngine implements PlaybackEngine {
  final StreamController<PlaybackState> _states =
      StreamController<PlaybackState>.broadcast();

  @override
  Stream<PlaybackState> get states => _states.stream;

  @override
  PlaybackState get currentState => const PlaybackState(
    queue: PlaybackQueue(
      tracks: [
        PlaybackTrack(
          songId: 'song-1',
          title: 'Song',
          artistId: 'artist',
          artistName: 'Artist',
          albumId: 'album',
          albumTitle: 'Album',
          filePath: '/music/song.mp3',
          duration: Duration(minutes: 3),
        ),
      ],
      currentIndex: 0,
    ),
  );

  @override
  Future<void> dispose() async {
    if (!_states.isClosed) await _states.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

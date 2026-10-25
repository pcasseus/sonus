import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/player/application/controllers/playback_coordinator.dart';
import 'package:sonus_next/features/player/application/services/media_session/media_session_bootstrap.dart';
import 'package:sonus_next/features/player/application/services/media_session/media_session_state_mapper.dart';
import 'package:sonus_next/features/player/application/services/media_session/sonus_audio_handler.dart';
import 'package:sonus_next/features/player/domain/models/playback_state.dart';

import 'media_session_test_support.dart';

void main() {
  test('release builds keep every icon audio_service loads by name', () {
    // Resource shrinking cannot see names resolved at runtime; a missing
    // control icon makes every state update throw in release builds.
    final keep = File(
      'android/app/src/main/res/raw/keep.xml',
    ).readAsStringSync();
    final kept = RegExp(r'tools:keep="([^"]*)"')
        .firstMatch(keep)!
        .group(1)!
        .split(',')
        .map((entry) => entry.trim().replaceFirst('@drawable/', ''))
        .toList();
    bool isKept(String name) => kept.any(
      (pattern) => pattern.endsWith('*')
          ? name.startsWith(pattern.substring(0, pattern.length - 1))
          : name == pattern,
    );

    final icons = {
      MediaSessionBootstrap.config.androidNotificationIcon,
      for (final playing in [true, false])
        for (final control in MediaSessionStateMapper.controlsFor(
          playing: playing,
        ))
          control.androidIcon,
    }.map((icon) => icon.replaceFirst('drawable/', ''));

    for (final icon in icons) {
      expect(isKept(icon), isTrue, reason: '$icon is not in keep.xml');
    }
  });

  test('the vendored plugin keeps the explicit PLAY/PAUSE key patch', () {
    // Guards against an upgrade or a return to the hosted package silently
    // dropping the patch (third_party/audio_service/PATCHES.md).
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('path: third_party/audio_service'));

    final source = File(
      'third_party/audio_service/android/src/main/java/com/ryanheise/'
      'audioservice/AudioService.java',
    ).readAsStringSync();
    final callback = source.substring(
      source.indexOf('public boolean onMediaButtonEvent'),
      source.indexOf('private MediaButton eventToButton'),
    );
    String routeOf(String key) {
      final at = callback.indexOf('case KeyEvent.$key:');
      expect(at, isNot(-1), reason: '$key is not handled');
      return RegExp(
        r'(onPlay|onPause|listener\.onClick)\(',
      ).firstMatch(callback.substring(at))!.group(1)!;
    }

    expect(routeOf('KEYCODE_MEDIA_PLAY'), 'onPlay');
    expect(routeOf('KEYCODE_MEDIA_PAUSE'), 'onPause');
    expect(routeOf('KEYCODE_MEDIA_PLAY_PAUSE'), 'listener.onClick');
    expect(routeOf('KEYCODE_HEADSETHOOK'), 'listener.onClick');
  });

  group('bootstrap', () {
    test('keeps the service alive while paused and uses the Sonus icon', () {
      const config = MediaSessionBootstrap.config;

      expect(config.androidStopForegroundOnPause, isFalse);
      expect(config.androidNotificationIcon, 'drawable/ic_stat_sonus');
      expect(
        config.androidNotificationChannelId,
        'com.sonus.sonus_next.playback',
      );
    });

    test('returns the handler Android bound to', () async {
      SonusAudioHandler? built;

      final handler = await MediaSessionBootstrap.start(
        initialize: (builder, config) async => built = builder(),
      );

      expect(handler, same(built));
    });

    test('playback still starts when the media session cannot', () async {
      final handler = await MediaSessionBootstrap.start(
        initialize: (builder, config) async =>
            throw StateError('no media session on this platform'),
      );

      expect(handler, isNull);
    });
  });

  group('releasing the notification on Android', () {
    late List<String> calls;

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      calls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MediaSessionBootstrap.channel, (
            call,
          ) async {
            calls.add(call.method);
            return true;
          });
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
    });

    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MediaSessionBootstrap.channel, null);
    });

    test('the started handler releases it when the session ends', () async {
      final handler = await MediaSessionBootstrap.start(
        initialize: (builder, config) async => builder(),
      );
      final engine = RecordingEngine()..emit(queuedState());
      addTearDown(engine.dispose);
      handler!.attach(PlaybackCoordinator(engine: engine));

      engine.emit(queuedState(status: PlaybackStatus.paused));
      await pumpEventQueue();
      expect(calls, isEmpty);

      engine.emit(const PlaybackState());
      await pumpEventQueue();
      expect(calls, ['releaseForeground']);
    });

    test('other platforms have nothing to release', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;

      await MediaSessionBootstrap.releaseForeground();

      expect(calls, isEmpty);
    });
  });
}

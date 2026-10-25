import 'dart:developer' as developer;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'sonus_audio_handler.dart';

typedef MediaSessionInitializer =
    Future<SonusAudioHandler> Function(
      SonusAudioHandler Function() builder,
      AudioServiceConfig config,
    );

/// Starts Android's media session once per process.
///
/// If the platform has no media session support (desktop builds, tests) or
/// initialization fails, Sonus keeps playing without system controls; the
/// failure is logged rather than blocking launch.
abstract final class MediaSessionBootstrap {
  static const AudioServiceConfig config = AudioServiceConfig(
    androidNotificationChannelId: 'com.sonus.sonus_next.playback',
    androidNotificationChannelName: 'Playback',
    androidNotificationChannelDescription: 'Playback controls for Sonus',
    androidNotificationIcon: 'drawable/ic_stat_sonus',
    // Keep the service in the foreground while paused, so resuming from
    // the lock screen or a Bluetooth device works on Android 12+. Stop,
    // the end of the queue and clearing the queue still end the session.
    androidStopForegroundOnPause: false,
    // Bounds the memory used for notification artwork.
    artDownscaleWidth: 512,
    artDownscaleHeight: 512,
  );

  /// Implemented by MainActivity and SonusForegroundRelease.kt.
  static const MethodChannel channel = MethodChannel(
    'com.sonus.sonus_next/media_session',
  );

  static Future<SonusAudioHandler?> start({
    MediaSessionInitializer? initialize,
  }) async {
    try {
      return await (initialize ?? _audioServiceInit)(
        () => SonusAudioHandler(releaseForeground: releaseForeground),
        config,
      );
    } catch (error, stackTrace) {
      developer.log(
        'Media session unavailable; playing without system controls. '
        'error=${error.runtimeType}',
        name: 'sonus.media_session',
        level: 1000,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  /// Removes the playback notification once a session has ended. Only
  /// Android implements it; elsewhere there is no notification to remove.
  static Future<void> releaseForeground() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    await channel.invokeMethod<bool>('releaseForeground');
  }

  static Future<SonusAudioHandler> _audioServiceInit(
    SonusAudioHandler Function() builder,
    AudioServiceConfig config,
  ) {
    return AudioService.init(builder: builder, config: config);
  }
}

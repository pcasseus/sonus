import 'dart:developer' as developer;
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'artwork_content_uris.dart';
import 'media_session_state_mapper.dart';
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
    // SN-45 Android Auto: Sonus answers searches, and lists are shown as
    // lists unless an item asks for a grid (Albums).
    androidBrowsableRootExtras: browsableRootExtras,
  );

  /// MediaConstants.BROWSER_SERVICE_EXTRAS_KEY_SEARCH_SUPPORTED.
  static const String searchSupportedKey =
      'android.media.browse.SEARCH_SUPPORTED';

  static const Map<String, dynamic> browsableRootExtras = {
    searchSupportedKey: true,
    AndroidContentStyle.supportedKey: true,
    AndroidContentStyle.browsableHintKey: AndroidContentStyle.listItemHintValue,
    AndroidContentStyle.playableHintKey: AndroidContentStyle.listItemHintValue,
  };

  /// Implemented by MainActivity and SonusForegroundRelease.kt.
  static const MethodChannel channel = MethodChannel(
    'com.sonus.sonus_next/media_session',
  );

  static Future<SonusAudioHandler?> start({
    MediaSessionInitializer? initialize,
    Future<Directory> Function()? supportDirectory,
  }) async {
    try {
      final carArtworkUri = await _carArtworkUris(
        supportDirectory ?? getApplicationSupportDirectory,
      );
      return await (initialize ?? _audioServiceInit)(
        () => SonusAudioHandler(
          releaseForeground: releaseForeground,
          carArtworkUri: carArtworkUri,
          wakeApp: wakeApp,
        ),
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

  /// Requests a frame even when Flutter has paused them, as it does while
  /// Sonus has no activity (Android Auto started it). The app's scopes
  /// finish loading through rebuilds, which need frames.
  static void wakeApp() {
    SchedulerBinding.instance.scheduleForcedFrame();
  }

  /// Removes the playback notification once a session has ended. Only
  /// Android implements it; elsewhere there is no notification to remove.
  static Future<void> releaseForeground() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    await channel.invokeMethod<bool>('releaseForeground');
  }

  /// Car-readable artwork URIs, on Android only (SonusArtworkProvider).
  ///
  /// Optional: if the folder cannot be found, the car shows no artwork and
  /// the media session still starts.
  static Future<CarArtworkUri?> _carArtworkUris(
    Future<Directory> Function() supportDirectory,
  ) async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return null;
    }

    try {
      final support = await supportDirectory();
      return ArtworkContentUris(
        artworkDirectory: p.join(support.path, 'sonus', 'artwork'),
      ).resolve;
    } catch (error, stackTrace) {
      developer.log(
        'Car artwork unavailable. error=${error.runtimeType}',
        name: 'sonus.media_session',
        level: 900,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  static Future<SonusAudioHandler> _audioServiceInit(
    SonusAudioHandler Function() builder,
    AudioServiceConfig config,
  ) {
    return AudioService.init(builder: builder, config: config);
  }
}

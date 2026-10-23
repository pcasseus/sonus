import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The installed app's version, as reported by the platform.
@immutable
class SonusAppInfo {
  const SonusAppInfo({required this.versionName, required this.buildNumber});

  final String versionName;
  final String buildNumber;

  /// "1.0.0 (build 1)", or just the part that is known.
  String get displayVersion {
    if (versionName.isEmpty) return 'Build $buildNumber';
    if (buildNumber.isEmpty) return versionName;
    return '$versionName (build $buildNumber)';
  }
}

/// Reads the app version through Sonus's `app_info` platform channel.
///
/// Returns null where the platform does not provide it (tests, desktop),
/// so the About page can say "Unavailable" instead of guessing.
class AppInfoService {
  const AppInfoService({this.channel = const MethodChannel(channelName)});

  static const String channelName = 'com.sonus.sonus_next/app_info';

  final MethodChannel channel;

  Future<SonusAppInfo?> load() async {
    try {
      final info = await channel.invokeMapMethod<String, Object?>('getAppInfo');
      final versionName = info?['versionName'];
      final buildNumber = info?['buildNumber'];

      if (versionName is! String || buildNumber is! String) {
        developer.log(
          'App info channel returned an unexpected payload.',
          name: 'sonus.settings',
          level: 900,
        );
        return null;
      }

      return SonusAppInfo(versionName: versionName, buildNumber: buildNumber);
    } on MissingPluginException {
      developer.log(
        'App info is not available on this platform.',
        name: 'sonus.settings',
      );
      return null;
    } on PlatformException catch (error) {
      developer.log(
        'App info could not be read. code=${error.code}',
        name: 'sonus.settings',
        level: 900,
      );
      return null;
    }
  }
}

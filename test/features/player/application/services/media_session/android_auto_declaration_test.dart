import 'dart:io';

import 'package:audio_service/audio_service.dart' as media;
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/player/application/services/media_session/artwork_content_uris.dart';
import 'package:sonus_next/features/player/application/services/media_session/media_session_bootstrap.dart';

/// A source file with Windows line endings normalized.
String readSource(String path) =>
    File(path).readAsStringSync().replaceAll(RegExp(r'\r\n?'), '\n');

/// SN-45: what Android Auto needs to discover Sonus as a media app. These
/// read the shipped Android sources, so a refactor cannot silently drop a
/// declaration that only a car would notice.
void main() {
  final manifest = readSource('android/app/src/main/AndroidManifest.xml');

  test('the manifest points Android Auto at the media descriptor', () {
    expect(
      manifest,
      contains(
        'android:name="com.google.android.gms.car.application"\n'
        '            android:resource="@xml/automotive_app_desc"',
      ),
    );

    final descriptor = readSource(
      'android/app/src/main/res/xml/automotive_app_desc.xml',
    );
    expect(descriptor, contains('<automotiveApp>'));
    expect(descriptor, contains('<uses name="media" />'));
  });

  test('the media browser service is exported and discoverable', () {
    final service = RegExp(
      r'<service android:name="com\.ryanheise\.audioservice\.AudioService"'
      r'[\s\S]*?</service>',
    ).firstMatch(manifest)!.group(0)!;

    expect(service, contains('android:exported="true"'));
    expect(service, contains('android:foregroundServiceType="mediaPlayback"'));
    expect(service, contains('android.media.browse.MediaBrowserService'));
  });

  test('a monochrome attribution icon is declared', () {
    expect(manifest, contains('androidx.car.app.TintableAttributionIcon'));
    expect(
      File('android/app/src/main/res/drawable/ic_stat_sonus.xml').existsSync(),
      isTrue,
    );
  });

  test('the root says Sonus answers searches and styles its lists', () {
    final extras = MediaSessionBootstrap.config.androidBrowsableRootExtras!;

    expect(extras['android.media.browse.SEARCH_SUPPORTED'], isTrue);
    expect(extras[media.AndroidContentStyle.supportedKey], isTrue);
  });

  group('the artwork provider and the Dart URIs agree', () {
    final provider = readSource(
      'android/app/src/main/kotlin/com/sonus/sonus_next/'
      'SonusArtworkProvider.kt',
    );

    test('authority', () {
      expect(
        manifest,
        contains('android:authorities="${ArtworkContentUris.authority}"'),
      );
    });

    test('file-name rule', () {
      final kotlinPattern = RegExp(
        r'Regex\("(.*)"\)',
      ).firstMatch(provider)!.group(1)!.replaceAll(r'\\', r'\');

      expect(kotlinPattern, ArtworkContentUris.fileNamePattern.pattern);
    });

    test('the provider is read-only and checks its caller', () {
      expect(provider, contains('if (mode != "r")'));
      expect(provider, contains('isTrustedCaller('));
      expect(provider, contains('MODE_READ_ONLY'));
      expect(provider, contains('com.google.android.projection.gearhead'));
      // The test client is accepted only by debuggable builds.
      expect(provider, contains('FLAG_DEBUGGABLE'));
    });
  });
}

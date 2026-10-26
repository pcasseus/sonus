import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/import/application/services/device_music_access.dart';
import 'package:sonus_next/features/import/data/services/method_channel_device_music_access.dart';
import 'package:sonus_next/features/import/presentation/pages/device_music_folder_page.dart';

class _Access implements DeviceMusicAccess {
  _Access({
    this.permission = DeviceMusicPermission.denied,
    this.onRequest = DeviceMusicPermission.granted,
    this.folders = const [],
  });

  DeviceMusicPermission permission;
  DeviceMusicPermission onRequest;
  List<DeviceAudioFolder> folders;
  int requests = 0;
  int settingsOpened = 0;
  int listings = 0;

  @override
  Future<DeviceMusicPermission> status() async => permission;

  @override
  Future<DeviceMusicPermission> request() async {
    requests++;
    return permission = onRequest;
  }

  @override
  Future<void> openSettings() async => settingsOpened++;

  @override
  Future<List<DeviceAudioFolder>> audioFolders() async {
    listings++;
    if (permission != DeviceMusicPermission.granted) {
      throw StateError('read without permission');
    }
    return folders;
  }
}

const _music = [
  DeviceAudioFolder(
    path: '/storage/emulated/0/Download/Music/FLO/Access All Areas',
    audioCount: 6,
  ),
  DeviceAudioFolder(
    path: '/storage/emulated/0/Download/Music/Victorious',
    audioCount: 18,
  ),
];

void main() {
  late DeviceMusicFolderChoice? result;
  late bool closed;

  Future<void> open(WidgetTester tester, DeviceMusicAccess access) async {
    result = null;
    closed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  result = await DeviceMusicFolderPage.open(context, access);
                  closed = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('nothing is read before the person allows music access', (
    tester,
  ) async {
    final access = _Access(folders: _music);
    await open(tester, access);

    expect(
      find.byKey(const ValueKey<String>('device-music-permission')),
      findsOneWidget,
    );
    expect(access.listings, 0);
    expect(access.requests, 0, reason: 'asked only when the person taps');

    await tester.tap(find.byKey(const ValueKey<String>('device-music-allow')));
    await tester.pumpAndSettle();

    expect(access.requests, 1);
    expect(find.text('Download'), findsOneWidget);
  });

  testWidgets('a refusal can be retried; "don\'t ask again" offers settings', (
    tester,
  ) async {
    final access = _Access(onRequest: DeviceMusicPermission.denied);
    await open(tester, access);

    await tester.tap(find.byKey(const ValueKey<String>('device-music-allow')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('device-music-permission')),
      findsOneWidget,
    );

    access.onRequest = DeviceMusicPermission.blocked;
    await tester.tap(find.byKey(const ValueKey<String>('device-music-allow')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('device-music-blocked')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('device-music-settings')),
    );
    expect(access.settingsOpened, 1);

    access
      ..permission = DeviceMusicPermission.granted
      ..folders = _music;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.text('Download'), findsOneWidget);
  });

  testWidgets('browses into folders, goes back up, and returns the choice', (
    tester,
  ) async {
    await open(
      tester,
      _Access(permission: DeviceMusicPermission.granted, folders: _music),
    );

    expect(
      find.byKey(const ValueKey<String>('device-music-import')),
      findsNothing,
      reason: 'the whole phone is never imported',
    );
    expect(find.text('Open the folder that holds your music.'), findsOneWidget);

    await tester.tap(find.text('Download'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Music'));
    await tester.pumpAndSettle();
    expect(find.text('FLO'), findsOneWidget);
    expect(find.text('Victorious'), findsOneWidget);
    expect(find.text('24 songs'), findsNothing);
    expect(find.text('Import "Music" · 24 songs'), findsOneWidget);

    await tester.tap(find.text('FLO'));
    await tester.pumpAndSettle();
    expect(find.text('Access All Areas'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Victorious'), findsOneWidget, reason: 'back goes up');
    expect(closed, isFalse);

    await tester.tap(find.text('Victorious'));
    await tester.pumpAndSettle();
    expect(find.text('18 songs directly in this folder'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('device-music-import')));
    await tester.pumpAndSettle();

    expect(closed, isTrue);
    expect(
      (result! as ChosenDeviceMusicFolder).path,
      '/storage/emulated/0/Download/Music/Victorious',
    );
  });

  testWidgets('Android\'s own picker can be chosen instead', (tester) async {
    await open(
      tester,
      _Access(permission: DeviceMusicPermission.granted, folders: _music),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('device-music-system-picker')),
    );
    await tester.pumpAndSettle();

    expect(result, isA<UseSystemFolderPicker>());
  });

  testWidgets('a device without music says so and keeps the system picker', (
    tester,
  ) async {
    await open(tester, _Access(permission: DeviceMusicPermission.granted));

    expect(
      find.byKey(const ValueKey<String>('device-music-empty')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('device-music-system-picker')),
      findsOneWidget,
    );
  });

  testWidgets('works at 320 dp with large text', (tester) async {
    tester.view
      ..physicalSize = const Size(320, 640)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await open(
      tester,
      _Access(permission: DeviceMusicPermission.granted, folders: _music),
    );
    for (final name in ['Download', 'Music']) {
      await tester.scrollUntilVisible(
        find.text(name),
        80,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text(name));
      await tester.pumpAndSettle();
    }

    expect(tester.takeException(), isNull);
    final import = tester.getSize(
      find.byKey(const ValueKey<String>('device-music-import')),
    );
    expect(import.height, greaterThanOrEqualTo(44));
  });

  group('the Android channel', () {
    const channel = MethodChannel('com.sonus.sonus_next/audio_library');
    final calls = <String>[];

    setUp(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            return switch (call.method) {
              'status' => 'denied',
              'request' => 'blocked',
              'audioFolders' => [
                {'path': '/storage/emulated/0/Music/A', 'audioCount': 3},
                {'path': null, 'audioCount': 1},
              ],
              _ => null,
            };
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('maps permission states and folder rows', () async {
      const access = MethodChannelDeviceMusicAccess();

      expect(await access.status(), DeviceMusicPermission.denied);
      expect(await access.request(), DeviceMusicPermission.blocked);
      final folders = await access.audioFolders();
      expect(folders.single.path, '/storage/emulated/0/Music/A');
      expect(folders.single.audioCount, 3);
      await access.openSettings();
      expect(calls, ['status', 'request', 'audioFolders', 'openSettings']);
    });
  });
}

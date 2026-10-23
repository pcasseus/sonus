import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/player/data/services/playback_preferences_store.dart';
import 'package:sonus_next/features/player/domain/models/playback_preferences.dart';
import 'package:sonus_next/features/player/domain/models/playback_repeat_mode.dart';

void main() {
  late Map<String, String> storage;
  late PlaybackPreferencesStore store;

  setUp(() {
    storage = {};
    store = PlaybackPreferencesStore.forTesting(
      getString: (key) async => storage[key],
      setString: (key, value) async => storage[key] = value,
    );
  });

  test('a fresh device loads defaults without issues', () async {
    final snapshot = await store.load();

    expect(snapshot.preferences, const PlaybackPreferences());
    expect(snapshot.issues, isEmpty);
  });

  test('saved preferences load back unchanged', () async {
    const preferences = PlaybackPreferences(
      rememberShuffleAndRepeat: true,
      shuffleEnabled: true,
      repeatMode: PlaybackRepeatMode.one,
    );

    await store.save(preferences);
    final snapshot = await store.load();

    expect(snapshot.preferences, preferences);
    expect(snapshot.issues, isEmpty);
    expect(storage.keys, [PlaybackPreferencesStore.preferencesKey]);
  });

  test('corrupt content falls back to defaults and is reported', () async {
    storage[PlaybackPreferencesStore.preferencesKey] = '{oops';

    final snapshot = await store.load();

    expect(snapshot.preferences, const PlaybackPreferences());
    expect(snapshot.issues, ['unreadable']);
  });

  test('a document from a newer Sonus is not reinterpreted', () async {
    storage[PlaybackPreferencesStore.preferencesKey] = jsonEncode({
      'version': 2,
      'rememberShuffleAndRepeat': true,
    });

    final snapshot = await store.load();

    expect(snapshot.preferences, const PlaybackPreferences());
    expect(snapshot.issues, ['version']);
  });

  test('invalid fields fall back individually', () async {
    storage[PlaybackPreferencesStore.preferencesKey] = jsonEncode({
      'version': 1,
      'rememberShuffleAndRepeat': true,
      'shuffleEnabled': 'yes',
      'repeatMode': 'forever',
    });

    final snapshot = await store.load();

    expect(snapshot.preferences.rememberShuffleAndRepeat, isTrue);
    expect(snapshot.preferences.shuffleEnabled, isFalse);
    expect(snapshot.preferences.repeatMode, PlaybackRepeatMode.off);
    expect(snapshot.issues, ['shuffleEnabled', 'repeatMode']);
  });

  test('repeat modes have stable storage names', () {
    expect(PlaybackPreferences.repeatModeKeys, {
      PlaybackRepeatMode.off: 'off',
      PlaybackRepeatMode.one: 'one',
      PlaybackRepeatMode.all: 'all',
    });
  });

  test('storage failures reach the caller', () async {
    final failing = PlaybackPreferencesStore.forTesting(
      getString: (key) async => throw StateError('locked'),
      setString: (key, value) async => throw StateError('full'),
    );

    await expectLater(failing.load(), throwsStateError);
    await expectLater(
      failing.save(const PlaybackPreferences()),
      throwsStateError,
    );
  });
}

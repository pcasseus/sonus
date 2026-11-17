# Sonus patches to audio_service

This directory is **audio_service 0.18.18** from pub.dev
(https://pub.dev/packages/audio_service/versions/0.18.18), copied unchanged
except for the patches below. `example/` and `test/` were omitted. The
upstream MIT license is kept in `LICENSE`.

Sonus depends on it through `pubspec.yaml`
(`audio_service: path: third_party/audio_service`).

## Why it is vendored

A media key's exact keycode is only known inside
`AudioService.MediaSessionCallback.onMediaButtonEvent`. Upstream turns
KEYCODE_MEDIA_PLAY, KEYCODE_MEDIA_PAUSE, KEYCODE_MEDIA_PLAY_PAUSE and
KEYCODE_HEADSETHOOK all into `onClick(MediaButton.media)`, which the Dart
handler can only treat as a toggle. The plugin offers no hook for this,
so it cannot be fixed from Sonus's own code (SN-44).

Upstream also keeps `AudioHandler.queueTitle` on the Dart side only: no
platform request carries it, so Android Auto never sees a queue title
(App Update 1.3). See Patch 2.

## Patch 1 — explicit PLAY and PAUSE keys (SN-44)

`android/src/main/java/com/ryanheise/audioservice/AudioService.java`,
`MediaSessionCallback.onMediaButtonEvent`:

- `KEYCODE_MEDIA_PLAY` calls `onPlay()` and `KEYCODE_MEDIA_PAUSE` calls
  `onPause()`, instead of `onClick(MediaButton.media)`.
- `KEYCODE_MEDIA_PLAY_PAUSE` and `KEYCODE_HEADSETHOOK` still go to `onClick`
  and toggle.

This matches AndroidX Media3, and stops a car or Bluetooth device that sends
PLAY while Sonus is already playing from pausing it. Notification and
lock-screen buttons are unaffected: they already use the bypass keycodes.

## Patch 2 — queue title (App Update 1.3)

`lib/audio_service.dart`, `AudioService.init`:

- `_observeQueueTitle()` forwards every distinct `queueTitle` value, on
  Android only, as `setQueueTitle` (`{"queueTitle": <String or null>}`; an
  empty title is sent as null, which clears it) on the plugin's own handler
  channel `com.ryanheise.audio_service.handler.methods`. The hosted
  `audio_service_platform_interface` 0.1.3 has no request for it, so the
  call does not go through `_platform`.

`android/src/main/java/com/ryanheise/audioservice/AudioServicePlugin.java`,
`AudioHandlerInterface.onMethodCall`:

- a `setQueueTitle` case calls `AudioService.instance.setQueueTitle`.

`android/src/main/java/com/ryanheise/audioservice/AudioService.java`:

- `setQueueTitle(String)` stores the title in a static field, like `queue`,
  and calls `MediaSessionCompat.setQueueTitle`; `onCreate` restores it
  after `setQueue`, so a recreated session keeps it.

Nothing else changes: queue items, their IDs and metadata are sent exactly
as before.

## Upgrading

1. Diff the new upstream `onMediaButtonEvent` against this copy.
2. If upstream now routes PLAY/PAUSE to `onPlay`/`onPause`, return to the
   hosted package and delete this directory.
3. Otherwise copy the new version here, re-apply Patch 1, update the
   version above, and run
   `test/features/player/application/services/media_session/media_session_wiring_test.dart`.
4. If upstream now sends `queueTitle` to the platform, drop Patch 2;
   otherwise re-apply it (the same wiring test checks it).
5. Re-run the SN-44 media-key, Stop and end-of-queue device checks, and
   check the queue title in Android Auto's queue view.

See also `android/app/src/main/java/com/ryanheise/audioservice/SonusForegroundRelease.java`,
which relies on this version's package-private `AudioService.instance`.

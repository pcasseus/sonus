# Sonus patches to audio_service

This directory is **audio_service 0.18.18** from pub.dev
(https://pub.dev/packages/audio_service/versions/0.18.18), copied unchanged
except for the patch below. `example/` and `test/` were omitted. The
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

## Upgrading

1. Diff the new upstream `onMediaButtonEvent` against this copy.
2. If upstream now routes PLAY/PAUSE to `onPlay`/`onPause`, return to the
   hosted package and delete this directory.
3. Otherwise copy the new version here, re-apply Patch 1, update the
   version above, and run
   `test/features/player/application/services/media_session/media_session_wiring_test.dart`.
4. Re-run the SN-44 media-key, Stop and end-of-queue device checks.

See also `android/app/src/main/java/com/ryanheise/audioservice/SonusForegroundRelease.java`,
which relies on this version's package-private `AudioService.instance`.

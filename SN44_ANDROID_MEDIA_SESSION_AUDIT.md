# SN-44 — Android Media Session Audit & Plan

- **Branch:** `sn-44-android-media-session`
- **Base:** `5a7a433`, equal to `main` and `origin/main` (PR #46, SN-43)
- **Status:** implemented (D1–D5 approved), plus fixes for QA findings Q1–Q9 and the lyrics gaps (§8–§9b). **SN-44 remains open:** emulator and automated verification are complete, but **no physical-device check has been performed** (§10).

### Verification status at a glance

| Evidence | Covers | Status |
|---|---|---|
| Automated tests | Mapper, handler, engine, restoration, analytics, lyrics, player UI, release keep rules, vendored-patch guard | **Passed** — 3,289 tests, `flutter analyze` clean |
| Emulator, API 34 (debug and release builds) | Notification, lock screen (with a PIN), media keys, Stop/end-of-queue cleanup, background and Doze, simulated call, Back/Recents, restart restoration, unreadable song, shuffle/repeat, lyrics | **Verified on the emulator only** (§9–§9b) |
| Physical Android device | Everything in §10, including Bluetooth, wired headset, real calls and audio focus, OEM battery limits, audible long sessions, TalkBack, on-device analytics | **UNTESTED** |

## 1. Summary

Sonus has **no Android media integration**. The notification controls are not broken; they do not exist. The app has:

- no media session and no `MediaBrowserService`;
- no foreground service, and no notification of any kind;
- no media-button receiver;
- no `WAKE_LOCK` or `FOREGROUND_SERVICE` permissions;
- no media-session dependency (`audio_service` or `just_audio_background`).

Playback works only because `just_audio` plays from the Flutter isolate while the activity's process happens to stay alive. Without a foreground service, Android may stop the process once Sonus is in the background. There are also no lock-screen or Bluetooth controls, and nothing that Android Auto (SN-45) could attach to.

The existing playback layers are sound and form a single authority, which an integration can build on:

```
UI / (future) media session
        │ commands
        ▼
PlaybackCoordinator  ──►  PlaybackEngine (JustAudioPlaybackEngine)  ──►  just_audio AudioPlayer
        ▲                         │ states (PlaybackState stream)
        └──── analytics, UI ◄─────┘
```

## 2. Findings

| # | Area | Finding | Status |
|---|---|---|---|
| F1 | Dependencies | Only `just_audio` 0.10.6 and `audio_session` 0.2.4. No `audio_service`. `audio_service` 0.18.18 is in the local package cache and accepts `audio_session >=0.1.25 <0.3.0`, so it is compatible with the pinned versions. | Missing |
| F2 | AndroidManifest | No permissions, no `<service>`, no `<receiver>`, no `tools` namespace. The label is still `sonus_next` (SN-48L). | Missing |
| F3 | Activity | `MainActivity : FlutterActivity` registers the backup, storage and app-info channels in `configureFlutterEngine`. A media service needs the Flutter engine to outlive the activity (`AudioServiceActivity` or `provideFlutterEngine`). | Must change |
| F4 | Notification | None exists. | Missing |
| F5 | Lock screen and Bluetooth | No media session, so there are no lock-screen controls and Bluetooth/headset buttons are not routed to Sonus. | Missing |
| F6 | Audio focus and interruptions | `AudioSession.configure(music())` runs on each `loadQueue`. just_audio's default `handleInterruptions: true` does three things: (a) pauses when headphones are unplugged ("becoming noisy"); (b) pauses on a transient focus loss such as a call and resumes afterwards; (c) leaves ducking to Android, which ducks automatically on API 26+. These actions run inside the same `AudioPlayer`, so they reach Sonus through `playerStateStream` and **keep a single authority**. None of this is configurable. | Works implicitly; unverified on device |
| F7 | Engine lifecycle | `PlaybackScope` creates the engine and **lives inside `AppRestartScope`**. After a backup restore, the engine and coordinator are disposed and recreated. A media-session handler is a process-wide singleton (`AudioService.init` runs once), so it must **re-bind to the new coordinator**. If it does not, notification buttons stop working after a restore. | Design constraint |
| F8 | State stream | The engine emits a `PlaybackState` on **every position tick** (about 200 ms). Forwarding each tick to the media session would flood notification updates; this is a classic cause of flickering or stale buttons. Position must be reported as an anchor plus speed, and pushed only on meaningful changes. | Design constraint |
| F9 | Analytics | `PlaybackAnalyticsController` derives sessions and qualified plays **only** from `coordinator.states` (track change, status, `transitionCause`). Commands that go through the coordinator therefore produce identical analytics to in-app taps. **Risk:** a second player, a separate queue, or handler-side event writes would duplicate or fabricate plays. | Must preserve |
| F10 | Queue semantics | Shuffle is just_audio's shuffle order; `currentIndex` refers to the original queue order. Repeat maps to `LoopMode`. Unavailable or blocked tracks never enter the queue (the coordinator filters them; the engine refuses them). Previous restarts the track after 3 s. Next at the end of the queue is a no-op. | Preserve |
| F11 | Playback restoration | **None.** The queue, position and modes are held in memory. SN-43 persisted only shuffle and repeat, and deferred "resume the last queue at launch" to SN-44. After a process is killed, Sonus starts with nothing queued. | Missing (decision D3) |
| F12 | Artwork | `PlaybackTrack.artworkPath` is an absolute managed-storage path, which can be missing or unreadable. The media session needs a `file://` URI and a safe fallback. | Needs mapping |
| F13 | Notification icon | Without a configured monochrome status-bar icon, `audio_service` uses `mipmap/ic_launcher`, which renders as a white square. | Needs resource (D4) |
| F14 | Tests | Player tests cover the coordinator (20), engine (9) and models. There is no media-session coverage. | Missing |
| F15 | History | This repository has never contained `audio_service` or any media-session code, so the earlier unreliable implementation was elsewhere. The plan designs against its typical failure causes (§4). | Info |

## 3. Proposed architecture

```
main.dart ── AudioService.init(SonusAudioHandler)  (once per process; failure is logged and Sonus runs without it)
                      │
                      ▼
SonusAudioHandler (BaseAudioHandler + SeekHandler)  ── no player, no queue, no event writes
   attach(PlaybackCoordinator)   ◄── PlaybackScope.initState
   detach()                      ◄── PlaybackScope.dispose (restore reload, app teardown)
   commands  ──►  coordinator.play/pause/skipNext/skipPrevious/seek/skipToIndex/
                  setShuffleEnabled/setRepeatMode/stop
   coordinator.states ──► MediaSessionStateMapper ──► playbackState / mediaItem / queue
```

- **One authority.** The handler holds no player, queue or analytics. Every external command calls the existing `PlaybackCoordinator`, so analytics sees exactly the state transitions an in-app tap produces (F9).
- **A pure mapper.** `MediaSessionStateMapper` converts a Sonus `PlaybackState` into `audio_service` `PlaybackState`, `MediaItem` and the queue. It is unit-tested without a platform.
- **Controls that never change shape.** Previous, Play/Pause and Next are always present, in that order, with compact indices `[0, 1, 2]`. Only the Play/Pause glyph changes. System actions add seek, shuffle and repeat for Bluetooth, the lock screen and SN-45.
- **Throttled updates.** The handler pushes to the session only when the status, track, queue, modes or error change, or when the position jumps by more than about 1.5 s against the extrapolated anchor (a seek). Normal progress is carried by `updatePosition` plus `speed`, so Android animates it without per-tick updates.
- **Status mapping:**
  - loading → buffering
  - ready or paused → ready, not playing
  - playing → ready, playing
  - completed → completed
  - idle → idle (the notification is removed)
  - failed → error, carrying the message
- **Re-binding.** `attach` replaces the subscription. `detach` pushes an idle state, so no stale notification survives a restore reload.
- **Artwork.** `Uri.file(artworkPath)` only when the file exists; otherwise no art. `MediaItem` carries title, artist, album and duration.
- **Activity.** `MainActivity` keeps its channels but provides the `audio_service` cached engine (extends `AudioServiceActivity`), so the Flutter engine, coordinator and analytics survive the activity being destroyed during background playback.

## 4. Designed against the previous implementation's failures

| Typical cause | Prevention |
|---|---|
| Buttons disappear or reorder between states | Controls are a fixed list on every update; tests assert them for every status. |
| Stale buttons or metadata after a track change | `MediaItem` is pushed on every track or queue change; tested. |
| Flicker or battery drain from per-tick updates | Position anchor plus speed, with throttling; tested. |
| Two notifications | One handler and one service; `just_audio_background` is never added. |
| Controls dead after a reload or restore | attach/detach re-binding; tested. |
| `ForegroundServiceStartNotAllowedException` when resuming from Bluetooth in the background (Android 12+) | Decision D2. |
| White-square status icon | A dedicated monochrome drawable (D4). |

## 5. Decisions needing your approval

- **D1 — Add `audio_service: ^0.18.18`.** This is the standard, maintained media-session and `MediaBrowserService` plugin. It also gives SN-45 its Android Auto browse tree. Transitive additions: `flutter_cache_manager`, `rxdart`, `audio_service_platform_interface`, `audio_service_web`. *Alternative:* `just_audio_background` is simpler, but it takes over the player's sources and is a weak foundation for Android Auto. **Recommended: `audio_service`.**
- **D2 — Pause behaviour of the foreground service.**
  - **(a) Keep the service in the foreground while paused** (`androidStopForegroundOnPause: false`): the most reliable resume from Bluetooth or the lock screen. The paused notification stays until Stop or the end of the queue. A Stop action is offered, and the session goes idle when the queue ends.
  - **(b) Default `true`:** the notification can be swiped away when paused, but resuming in the background can fail on Android 12+.
  - **Recommended: (a)**, because reliability is the explicit goal.
- **D3 — Playback restoration after the process is killed** (F11). This is a new feature: persist the queue song IDs, index, position and modes; on launch, restore **paused**, re-checking playability. Analytics only records once playback actually starts.
  - **(a) Include it in SN-44** as Phase 2b.
  - **(b) Defer it** and document "no restoration" in the device checklist.
  - **Recommended: (a)**, but only after Phase 2 is verified.
- **D4 — Add a monochrome notification icon** (`res/drawable/ic_stat_sonus.xml`, a Waveform S vector). This is an Android resource, not the launcher icon, so the SN-48L launcher work stays untouched.
- **D5 — Manifest and activity changes** (required for D1):
  - add the `WAKE_LOCK`, `FOREGROUND_SERVICE` and `FOREGROUND_SERVICE_MEDIA_PLAYBACK` permissions;
  - add the `AudioService` `<service android:foregroundServiceType="mediaPlayback">` and the `MediaButtonReceiver`;
  - change `MainActivity` to extend `AudioServiceActivity`.

  The application ID, signing and label are unchanged. `POST_NOTIFICATIONS` is not needed, because media-session notifications are exempt on Android 13+.

## 6. Implementation plan (after approval)

- **Phase 2:**
  1. Add the dependency (D1); update the manifest and activity (D5); add the icon (D4).
  2. `lib/features/player/application/services/media_session/`:
     - `media_session_state_mapper.dart` (pure);
     - `sonus_audio_handler.dart` (attach/detach, commands to the coordinator, throttled publishing);
     - `media_session_bootstrap.dart` (`AudioService.init` with a logged, fail-safe fallback).
  3. `PlaybackScope`: an optional handler; attach in `initState`, detach in `dispose`. `SonusApp` and `main.dart` pass the handler through. Tests inject a fake.
  4. Keep just_audio's interruption handling as the single focus/noisy authority (F6), and add tests that interruption-driven state changes reach the session.
- **Phase 2b (D3):** queue restoration through `PlaybackPreferencesStore`-style device-local storage.
- **Phase 3:** tests for:
  - **Mapper:** every status, fixed controls, metadata, artwork fallback, queue, modes.
  - **Handler:** command routing, throttling, attach/detach and re-attach, idle on detach, errors.
  - **Analytics integration:** commands through a real `PlaybackAnalyticsController` with a fake engine produce exactly one qualified play, with no duplicate on repeated play/pause.
  - **Bootstrap:** failure falls back cleanly.
- **Phase 4:** a physical-device checklist covering the ten required areas, with per-step expected results. Emulator results will be labelled as emulator results, and device verification as **UNVERIFIED** until performed.

## 7. Risks

- **Engine lifetime.** With a cached engine, the Dart side outlives the activity: correct for background playback, but it changes when `PlaybackScope` is disposed. Covered by attach/detach and device checks.
- **Custom channels.** `configureFlutterEngine` runs again when a new activity attaches to the cached engine; the existing channel registrations are idempotent, and the handlers reference the current activity.
- **OEM differences.** Background restrictions (battery optimization) vary by manufacturer and can only be checked on real devices.
- **Out of scope for SN-44:** Android Auto browse/search (SN-45), and any UI redesign.

## 8. Emulator QA findings and fixes

Two genuine defects were found during emulator QA, each reproducible every time. Findings that came from the QA tooling were confirmed and discarded: `uiautomator` cannot see the notification shade, and stray Menu/keyguard key events had sent an earlier "Stop" tap to the home screen.

### Q1 — Status stuck at `ready` while audio plays (bug from before SN-44, in the engine)

- **Symptom:** loading a queue while one is playing, or after a queue has finished, leaves Sonus at `ready` while audio is audible. Android shows PAUSED with an advancing position, pause does nothing (in the app, on the notification or from a headset), and analytics stops counting listening time. Reproduced 3/3.
- **Cause:** just_audio keeps `playing` set across source changes and completion. `loadQueue` overwrote the real `playing` state with a fixed `ready`, and the following `play()` emitted nothing. The same carried-over flag also made a load *without* autoplay start audio.
- **Fix (`just_audio_playback_engine.dart`, `playback_audio_player.dart`):**
  - The player seam now exposes `playing`.
  - A load without autoplay pauses a still-playing player first.
  - After loading, the status reflects the player (`playing` or `ready`).
  - There is still one engine, one queue and one analytics path.
- **Tests:** `simulated_just_audio_player.dart` follows just_audio's state rules. Six new tests failed before the fix and pass after it:
  - engine status;
  - silent load without autoplay;
  - analytics records a qualified play for the second song, with no duplicates.

  The regression tests (play, pause, resume, skipping, loading from idle) pass both before and after.

### Q2 — Stop or the end of the queue left a foreground notification

- **Symptom:** after Stop or a finished queue, the session reported NONE, but the notification and the foreground service stayed until the activity was destroyed.
- **Cause:** on idle, audio_service 0.18.18 calls `stopSelf()` and `cancel()`. The plugin's own `MediaBrowser` stays bound while an activity exists, so the service is never destroyed. Only `onDestroy()` leaves the foreground, and Android will not cancel a foreground service's notification.
- **Supported options ruled out:**
  - the plugin has no public API for this;
  - `AudioService.instance` is package-private;
  - a manifest-declared subclass breaks the plugin's binding by class name;
  - `androidStopForegroundOnPause: true` (Option B) changes D2 and was not approved.
- **Fix (Option A):**
  - `android/app/src/main/java/com/ryanheise/audioservice/SonusForegroundRelease.java` is Sonus's own source file, declared in the plugin's package. It calls the framework `Service.stopForeground(STOP_FOREGROUND_REMOVE)`. The library itself is not modified, forked or patched.
  - It is written in Java because the plugin's androidx.media superclass is not on the app's compile classpath. No dependency was added.
  - MainActivity registers `com.sonus.sonus_next/media_session` → `releaseForeground`. The channel is deliberately left registered when the activity is cleaned up, because it uses no activity.
  - `SonusAudioHandler` calls it once when the published state changes from non-idle to idle: Stop, completion, clearing the queue, detaching, or a restore reload that replaces playback. It is never called on pause, buffering or error. Failures are logged at level 900 and never thrown.
- **Upgrade policy:**
  - `pubspec.yaml` pins `audio_service: 0.18.18` exactly.
  - If `instance` changes, the Android build fails rather than misbehaving.
  - After any upgrade, re-run the Stop and end-of-queue checks, and delete the shim if the plugin starts leaving the foreground itself.
- **Tests:** release on completion, Stop, detach and restore reload; none on pause, buffering, error or a reload onto restored playback; failures logged; the bootstrap wiring reaches the channel, and other platforms are a no-op.

## 9. Verification results

- **Automated:**
  - `flutter test`: **3,273 passed, 0 failed** after the final round (3,254 after Q1/Q2; baseline before SN-44: 3,179).
  - `flutter analyze`: no issues.
  - `dart format` on the 21 changed Dart files: clean.
- **Emulator** (API 34, `sonus_sn42_disposable`; logs and screenshots in `C:\dev\sonus\sn44_media_session_review\`):

| Scenario | Result |
|---|---|
| Play, pause, resume in the foreground | Session, audio and Sonus agree; the paused position stays fixed (`verify_*.log` D1–D4) |
| New queue while playing, then pause (Q1) | `playing` → pause works (D2–D3) |
| Notification Stop (Q2) | Notification removed, service leaves the foreground (A2–A3) |
| Play after Stop | Notification and foreground return; playback starts (B1, G2) |
| Queue completion (Q2) | Notification removed (C1) |
| Background playback, media pause/play/next/previous | Correct; the notification and foreground are kept while paused (E1–E6) |
| Screen off, then keyguard with a PIN | Playback continues; the keyguard shows the Sonus card; media keys work; Stop clears it (`lock_*.log`, `v06`–`v08`) |
| Real app: force-stop while paused, relaunch | Restored **paused**, silent, same song at 13.97 s (paused at 13.87 s); Play resumes (`restart_*.log` R1–R5) |
| Real app: process killed while playing in the background, relaunch | Restored paused at the last checkpoint (29.6 s), no autoplay (R6–R8) |
| Real app: About (existing native channel) | Works with AudioServiceActivity |

- **Expected behaviour:**
  - While a restored queue sits paused, there is no notification until playback starts. The session is still available to media buttons.
  - Stop keeps the queue, and Play resumes from the stopped position, the same as the in-app Stop.

## 9a. Final validation round (release build, reliability, player state, lyrics)

### Q3 — Release builds published no media session (fixed)
- **Symptom:** the minified release APK played audio, but the session stayed NONE and no notification ever appeared. Every `setState` threw `IllegalArgumentException: You must specify an icon resource id to build a CustomAction`.
- **Cause:** release resource shrinking removed audio_service's control icons (`drawable/audio_service_*`). The plugin resolves them by name at runtime and has no keep rule of its own. Debug builds don't shrink, which is why this was never seen before.
- **Fix:** `res/raw/keep.xml` keeps `@drawable/audio_service_*` alongside `ic_stat_sonus`. `aapt2` confirms all 8 icons are now in the release APK.
- **Test:** a wiring test checks that every icon used by the mapper's controls and the config is in `keep.xml`. It failed without the rule.
- **Release run** (`release_*.log` S0–S9): notification, Stop removal, a repeated Stop while idle, stop/play cycles, activity destruction after a release (no leaked service), and a clean restart. The R8-renamed `SonusForegroundRelease` and its channel strings are present in the dex.

### Q4 — An unreadable song ended playback silently (fixed)
- **Repro:** the next song's file was moved away while the queue played, then Next was pressed. ExoPlayer raised "Source error"; the session went NONE, the notification disappeared and the app showed no message.
- **Cause:** the engine recorded `failed`, then just_audio's trailing `idle` (from the same event, through a second stream) was mapped to `idle` with the error cleared.
- **Fix (`just_audio_playback_engine.dart`):** an `idle` that follows a failure keeps the failure; Stop and loading a queue still replace it. Failures are logged (`sonus.playback`, level 900) with the song ID and error type only, never paths.
- **Tests:** both stream orders, Stop after a failure, a new queue after a failure, and analytics ending the session as `failed`. Analytics was already correct, so that test is a guard, not a regression proof.
- **Emulator after the fix:** ERROR "This song could not be played."; the notification is kept; Next recovers.
- **Not changed (needs a decision):** no in-app error message, no automatic skip of unreadable songs, and Play after a failure does not retry.

### Q5 — In-app Next/Previous ignored shuffle and repeat all (fixed)
- **Repro:** with shuffle on, Next was disabled whenever the current song was last in list order, even with unplayed songs left (3 of 5 shuffled runs started on that song). With repeat all, Next was disabled on the last song.
- **Fix:** `PlaybackState.nextAvailable`/`previousAvailable` are filled by the engine from just_audio's own `hasNext`/`hasPrevious`, which know the shuffle order and repeat. `canSkipNext`/`canSkipPrevious` fall back to list order when unset. The mini-player and Now Playing use them.
- **Tests:** an engine test (repeat all), and a widget test that failed with the old list-order checks.
- **Emulator:** with repeat all on the last song, Next is enabled and wraps to the first song; with repeat off it is disabled.

### Q6 — Synced lyrics lost the active line on long or wrapped lyrics (fixed)
- **Cause:** auto-scroll assumed a fixed 76 px per line. Wrapped lines are taller, so the error accumulated, and on a 320 px screen line 12 was never even built. The scroll also animated regardless of Reduce motion.
- **Fix (`lyrics_page.dart`):** the active line carries a key and is centred with `Scrollable.ensureVisible`, using its real layout. Reduce motion (the app setting or the system one) jumps instead of animating, and the highlight animation respects it too.
- **Tests:** two widget tests (narrow wrapping lyrics; reduced motion) failed before the fix.

### Q7 — LRC `[offset:]` ignored and same-timestamp lines reordered (fixed)
- **Fix (`lrc_parser.dart`):** `[offset:±ms]` is applied (a positive value shows lines earlier, never before 0). Lines that share a timestamp keep their file order, because Dart's `List.sort` is unstable.
- **Tests:** 5 new tests; the offset and ordering tests failed before the fix.

### Audited and found correct (no change)
- **Single authority:** player state flows engine → coordinator → `PlaybackStateController` (a `ChangeNotifier`). `PlaybackState` has no custom `==`, so no update is ever dropped. The mini-player, Now Playing, Queue and Lyrics all `watch` it, and no screen copies state in `initState`. New tests cover position-only updates on the mini-player and Now Playing.
- **Lyrics timing:** lyrics use only `PlaybackState.position`; there is no second clock. New tests: pausing freezes the highlight, seeking selects the right line at once, and skipping never shows the previous song's lyrics.
- **Emulator reliability** (`long_*.log`, `lifecycle_*.log`):
  - 6 minutes locked with forced Doze: continuous play, 2 automatic transitions, a clean stop at the end of the queue;
  - an incoming call pauses, and playback resumes after it;
  - Back (activity destroyed) and removal from Recents: playback continues; pause, resume and Stop with no activity all work.

### Known risks (not changed)
- ~~Hardware PLAY keys toggled.~~ **Resolved in §9b (Q8).** Still to be confirmed on a device with a car or Bluetooth headset (§10 item 16).
- ~~Repeat label stuck at "Repeat all".~~ **Not a defect (§9b):** it was a stale QA dump. Still to be confirmed with TalkBack on a device (§10 item 17).
- Dragging the Now Playing seek bar seeks on every frame, with no local drag value. This predates SN-44.
- `PlaybackTrack.artworkPath` is copied when a track is queued, so artwork fetched later appears only after the queue is reloaded. Fixing it needs library-to-queue change propagation, which is a metadata architecture change.
- Lyrics:
  - lyrics imported or changed for the song that is playing appear only after a track change;
  - a failed lyrics load is not retried for the same song;
  - removing a `.lrc` sidecar does not delete the stored lyrics;
  - untimed text in a timed LRC file is dropped.

## 9b. Final integration pass

### Q8 — A hardware PLAY key paused playback (fixed; vendored plugin)
- **Cause:** audio_service sends KEYCODE_MEDIA_PLAY/PAUSE, like PLAY_PAUSE and HEADSETHOOK, to `onClick(media)`, which toggles. Dart receives no keycode, and the plugin has no hook.
- **Fix:** audio_service 0.18.18 is vendored at `third_party/audio_service/` with one documented patch (`PATCHES.md`): PLAY → `onPlay()`, PAUSE → `onPause()`. PLAY_PAUSE and HEADSETHOOK still toggle. This matches AndroidX Media3.
- **Setup:** `pubspec.yaml` uses the path dependency; `analysis_options.yaml` excludes `third_party/**`.
- **Tests:** a guard test reads the vendored Java and fails against unpatched upstream; there are handler and engine idempotence tests.
- **Release build on the emulator:** PLAY while playing stays playing (before: paused); PAUSE while paused stays paused; the toggle keys toggle.

### Repeat accessibility label — no defect
The Flutter semantics tree announces "Repeat off", "Repeat all" and "Repeat one" correctly (new regression test), and the device's accessibility tree shows the same. The earlier constant "Repeat all" came from the QA harness re-reading a stale `uiautomator` dump file; the harness now deletes the old dump and retries.

### Q9 — Unreadable song had no in-app message; the existing panel exposed raw errors (fixed)
- **Changes:**
  - A new `PlaybackErrorNotice` (icon plus text, live region).
  - The mini-player shows "Song unavailable".
  - Now Playing shows "This song couldn't be played. It may have been moved or deleted. Skip to another song to continue." directly under the song details.
  - The existing Now Playing error panel used to print `errorMessage`, raw ExoPlayer text that can contain file paths; it now shows only the plain wording.
- **Unchanged:** Next/Previous stay usable, and nothing auto-skips.
- **Tests:** a widget test; confirmed on the release build.

### Lyrics gaps
- **Changed while the song is active — fixed.** `LyricsController.reload()` re-reads the current song, keeping lyrics on screen until the result arrives; a track change discards it. The Lyrics page reloads when opened (not while a read is already under way).
- **Failed reads not retried — fixed.** The failed state has a "Try again" button that calls `reload()`.
- **Removed `.lrc` file — intentionally unchanged.** Ingestion never deletes stored lyrics. Lyrics restored from a backup have no sidecar on the new device, and a briefly unreadable SAF folder also looks like "no sidecar", so auto-deletion would destroy valid lyrics (fail-closed). Follow-up: an explicit "Remove lyrics" action.
- **Untimed text in timed LRC — fixed.** Untimed lines continue the timed line above. Tags, bracketed text, a blank line, or text before the first timestamp end or skip that continuation.
- **Existing test changed:** in `lyrics_page_test.dart`, "position changes do not reload lyrics" now counts reads after the page has opened, because opening deliberately reads again. The property it checks (position ticks cause no reads) is unchanged.
- **Release build on the emulator:** a re-import while playing stored the sidecar. The lyrics showed the joined continuation line, wrapped lines, the `[offset:+1000]` timing, and the active line centred as playback advanced.

### Artwork after queueing — feasible, not implemented
- **What already works:** the media-session handler republishes when `artUri` changes for the same song (tested).
- **What is missing:** `PlaybackTrack.artworkPath` is copied when a track is queued, and nothing tells playback when artwork changes.
- **Plan:**
  1. Add an engine method that replaces the matching `PlaybackTrack`s by song ID without touching the audio sources, so the queue and playback continue undisturbed.
  2. Have Album Studio, cover-art import and Metadata Intelligence call it after an assignment.
- **Why not now:** the second step is a cross-feature change to the metadata flows.

### Seek bar — documented follow-up
Dragging seeks on every frame with no local drag value. No functional defect was observed: seeking lands correctly. Follow-up: seek on `onChangeEnd` with a local drag value.

### Verification
- `flutter test`: **3,289 passed, 0 failed**.
- `flutter analyze`: clean.
- `dart format` on the 32 changed Dart files (the vendored package excluded): clean.
- The release APK builds with the vendored plugin and was verified on the emulator.

## 10. Physical-device checklist (all UNVERIFIED until performed)

1. **Foreground:** play, pause, next and previous from the app and the notification; the icon, title, artist and artwork are correct.
2. **Background:** with Home pressed, playback continues for 10+ minutes; the notification stays while paused; resuming from the notification works after 10+ minutes paused.
3. **Lock screen:** with a secure lock, the card shows correct metadata and seek bar; play/pause, next, previous, seek and Stop all work; after Stop the card disappears.
4. **Bluetooth/headset:** wired and Bluetooth buttons (single press, double press = next, triple press = previous); car/headset metadata.
5. **Track and artwork sync:** auto-advance, skip and queue jump update every surface; a song without artwork falls back cleanly.
6. **Pause/resume and seek:** the notification seek bar and an in-app seek agree; there is no drift after long pauses.
7. **Interruptions:** an incoming call pauses and resumes; navigation prompts duck; unplugging headphones or disconnecting Bluetooth pauses without auto-resume.
8. **Queue, shuffle, repeat and completion:** repeat one/all and shuffle from the app; the end of the queue removes the notification; picking a new song while playing keeps the controls working (Q1).
9. **Process lifecycle:** swipe away from recents while playing and while paused; enable battery optimisation (OEM-specific); after a reboot, relaunch restores paused; after an SN-42 backup restore, the notification follows the new session.
10. **Analytics accuracy:** listens of 30 s+ via notification, headset and lock screen each record exactly one qualified play; a restored-paused relaunch records nothing until playback starts.
11. **Release build:** install the release APK; the notification appears on first play.
12. **Long session:** an hour or more of audible music, locked, across 15+ songs, with no unexplained stop.
13. **Unreadable song:** delete or move a queued file; the lock screen shows "This song could not be played"; Next recovers.
14. **Shuffle/repeat controls:** with shuffle on, in-app Next stays enabled until the shuffle order is used up; with repeat all, it wraps from the last song.
15. **Lyrics:** an album with `.lrc` sidecars, including long wrapping lines and an `[offset:]` tag. The highlight follows the audio, freezes on pause, jumps on seek, changes on skip, and works with Reduce motion on.
16. **Car/Bluetooth PLAY key:** connect while already playing; playback must keep playing (Q8). Headset single, double and triple presses still toggle and skip.
17. **TalkBack:** the repeat button announces the current mode; "Song unavailable" and the Now Playing notice are announced.
18. **Lyrics refresh:** import a `.lrc` for the song that is playing, then open Lyrics; with storage made unreadable, "Try again" recovers.

## 11. Physical-device session — setup, import verification and issue backlog (2026-10-23/24)

**Device:** Samsung Galaxy S26 Ultra (SM-S948U), Android 17. **Build:** release APK from `f4de457` (sha256 `926666fa…b209`), signed with the Android Debug certificate.

### Setup
- The old install (debug build, schema 26, with duplication problems) was uninstalled **at the user's request**. Only `com.sonus.sonus_next` was removed.
- The fresh install started with an empty library at schema 33. Account & Cloud shows "Sign-in is not configured for this build", so no cloud sync is possible. Android Backup Manager is disabled.
- **Music:** `/sdcard/Download/Music`: 874 MP3s, 6,426,077,249 bytes, 37 top-level folders. A per-file MD5 baseline was taken before uninstalling (fingerprint `6e0546b2…`). After the import, all 874 files have identical paths, sizes, modification times and MD5s.
- **Import:** done through Sonus's folder import. The user approved Android's folder-access prompt. Result: **874 processed, 871 imported, 0 relinked, 3 skipped, 0 failed, 148 need review.**
- Two listening events ("angel wings" and "healthy habit", Madison Beer) were played by the user during the session. They are legitimate and part of the baseline.

### Library verification so far
- **Totals:** 78 Library artist pages covering 871 songs, and 97 albums.
- **Loose album folders, checked in the app:**
  - *Zendaya*: 11 tracks, matches the 11 files.
  - *Starstruck*: 8 tracks, matches the 8 files.
  - *Rags* and *Victorious*: not checked. The scan stopped here at the user's request to move on to playback testing.
- **Not verified:** the in-app review list (148), the untagged-song samples, and *locket* in Album Studio.
- **The 3 skipped files** are the Cardi B "ErrTime" group (see Import-1).

### Issue backlog (out of SN-44 scope; to be assigned to separate tickets)
Status key: **CONFIRMED** = reproduced on the device or confirmed in code; **TO VERIFY** = hypothesis or not yet reproduced.

| ID | Priority | Status | Summary | Evidence / root cause |
|---|---|---|---|---|
| Import-1 | **P0, data integrity** | CONFIRMED | Distinct recordings are silently dropped at import | Identity = primary artist + title + version label + primary edition, with featured artists ignored. Four "ErrTime" files: two ~2:26 and two ~3:16 recordings. Three were "skipped" with **no binding, no credits and no review row**. `atomic_library_importer.dart:657-662`, `library_identity_resolver.dart:154-165` |
| Import-2 | P0 | CONFIRMED (code) | A skipped file still ingests its `.lrc` onto the kept song (can overwrite lyrics) | `library_import_service.dart:112-130` only checks `result.failed`. No impact on this library (no `.lrc` files) |
| Edition-1 | **P0, data integrity** | CONFIRMED (code) | Saving in Track Studio re-points a song to the album's primary edition; when the album is unchanged, the old edition membership is also kept | `track_studio_page.dart:901-915`, `track_profile_editing_service.dart:476-483` |
| Artist-1 | P1 | CONFIRMED (device) | Collaboration and feature credits become standalone artist pages | 10 pages with unparsed "[Ft.]" / "Ft." credits (e.g. "Max Schneider [Ft. Keke Palmer]") and 14 "&" collaboration pages. Features are parsed only in the artist/album folder layout when the tagged artist equals the folder artist (`import_identity_metadata_normalizer.dart`). `media_metadata_reader.dart:73` never reads features from tags |
| Artist-3 | P1 | CONFIRMED (device, 3/3) | Album-owner-only artists open to "Artist not found" | Rags Cast, Cheetah Girls and Descendants are listed in Library (they own albums with available tracks), but the profile requires a primary or coPrimary song credit (`library_query_dao.dart:683`, `findProfileEligibleArtists`). Their 7 albums can't be reached from the owner's page |
| Artist-2 | P1 | CONFIRMED (device) | Group and soundtrack identity is split between album owner and performers | "Cheetah Girls" owns 3 albums / 0 songs while "The Cheetah Girls" has 17 songs / 0 albums. Same for Descendants vs Descendants Cast; Rags Cast owns *Rags* with 0 songs. 43 pages have songs but no albums (98 songs). The folder artist overrides TPE2 in the artist/album layout |
| Player-1 | P1 | CONFIRMED (code) | Mini-player hidden on most pushed pages | The slot is only the shell's `bottomNavigationBar` (`app_shell_page.dart:178`). Only Search and Playlist detail add it themselves |
| Data-1 | P1 | CONFIRMED (code) | Screens need a manual refresh after imports, edits or playback | No app-wide change signal. Home, Charts and Insights are long-lived singletons refreshed only by pull-to-refresh; Studio edits refresh only the screen that opened them |
| Studio-1 | P1 | CONFIRMED (code) | Album Studio and Album Profile list tracks in import-arrival order | `ORDER BY aet.sort_position` first (`library_query_dao.dart:558-563`); import appends max+1; editing numbers doesn't move the track |
| Charts-1 | P2 | CONFIRMED (code) | No live Moments; finalization errors appear as "No Moments yet" | `LiveChartMomentService` is unused in `lib/`. The error banner is only shown in the Charts view (`charts_page.dart:81`). A fresh install legitimately shows an empty feed until a completed week has plays |
| Build-1 | P1 (before any distribution) | CONFIRMED | Sign-in configuration is silently omitted from builds | Compile-time defines; only `tool/run-dev.ps1` and VS Code pass `config/sonus.dev.json`; no release or device-test path; no build-time guard; README undocumented |
| Edition-2 | P2, feature | CONFIRMED (code) | No way to create or assign deluxe or other editions | Import creates only one standard primary edition; no UI to move a track between editions; MusicBrainz proposes no edition or release membership |
| Insights-1 | P2 | TO VERIFY | Monthly Insights artwork disappears while swiping | Suspected unbounded full-resolution `Image.file` decodes plus page disposal (same pattern on about 14 screens); needs reproduction |
| Studio-2 | P2 (SN-48) | CONFIRMED (code) | Album Studio layout leaves about 3 visible rows; overflow risk with large text | Non-scrolling `Column` with a fixed management card above the list (`album_studio_page.dart:69-121`) |

**Suggested order:**
1. Import-1, Import-2 and Edition-1 (data integrity).
2. Player-1, Data-1, Studio-1 and Build-1.
3. Artist-1 and Artist-2 (these need a design decision on group and soundtrack attribution).
4. Charts-1, Edition-2, Insights-1 and Studio-2.

**Regression tests needed:**
- the ErrTime collapse (flagged, not dropped) and the lyrics overwrite;
- Track Studio edition preservation;
- disc/track order after import and after edits;
- live Moments, and finalization errors in Moments mode;
- the artwork cache-eviction case;
- a mini-player presence test on pushed routes;
- refresh after edits and imports.

## 12. Physical-device playback results (Samsung SM-S948U, Android 17, release build)

Evidence: `C:\dev\sonus\sn44_device_review\` (`playback_checklist.log` with timestamped system-state samples, `*_logcat.txt`, screenshots `fix01*`/`fix02*`). The recorder reads system services only. ADB loss is now logged explicitly as "ADB UNAVAILABLE", so it can't be mistaken for a playback failure.

### Q10: Stop reset position and duration (found on device; fixed, uncommitted)
- **Symptom (device):**
  - After notification Stop → Play, audio resumed from the stopped position, but Sonus showed **0:00** with no progress.
  - Closing and reopening after Stop restored the song at **0:00**.
  - The logs showed the media session at the right position (for example 1:14), while Sonus's own state said 0.
- **Cause:** `JustAudioPlaybackEngine.stop()` emitted a new idle state with the default position and duration (0). just_audio keeps both through `stop()`, and because the duration doesn't change it never announces it again. So the duration stayed 0, Now Playing capped the elapsed time at 0:00, the progress bar showed 0, and **the seek bar was disabled** (it is disabled when duration ≤ 0). The restoration recorder then saved 0:00.
- **Fix:** `stop()` keeps the state's position and duration in the idle state (`just_audio_playback_engine.dart`). Nothing else changed; the media-session mapper still maps idle → idle, so the notification is still released.
- **Tests:** `test/features/player/stop_resume_regression_test.dart` runs the real engine and coordinator on the simulated player. The simulator now models just_audio keeping its position through `stop()` and re-preparing on `play()`. **4 tests failed before the fix:** the idle state keeps position and duration; Play after Stop resumes with position, duration and progress; Now Playing shows `1:14` with the seek bar enabled (it showed `0:00` before); a restart after Stop restores 1:14, paused. **2 guards passed before and after:** Stop never starts audio; Stop still releases the notification and the session. **An analytics guard** (`playback_analytics_controller_test.dart`): Stop → Play adds no extra qualified play.
- **Verification:**
  - `flutter test`: **3,296 passed, 0 failed**. One run hit the known timing flake in `supabase_cloud_artwork_download_test.dart`, which passed 5/5 in isolation and in the full re-run.
  - `flutter analyze`: clean; changed files formatted.
  - Release APK sha256 `45e3059f…c9a9`, installed **in place** (same signing certificate `92dd91c7…`, same user ID 10666; no uninstall, data kept).
  - **Device:** Stop removed the notification and released the foreground service. Play resumed at the stopped position. Now Playing showed **1:08 → 1:14 / 2:37** with a moving progress bar. Close-and-reopen restored **"free" paused at 0:16** with no autoplay (user confirmed; system state recorded at 13:42:01).

### Q11: The seek bar seeked on every frame of a drag (fixed)
- **Was:** dragging the Now Playing seek bar called `seek` for every drag update, with no local drag value (listed under §9 Known risks and §9b).
- **Fix:** the seek bar keeps a local drag value. The bar and elapsed time follow the finger, and playback seeks once, when the drag or tap ends (`now_playing_page.dart`, `_SeekSection`).
- **Tests** (`shell_playback_slot_test.dart`):
  - Regressions, which failed before the fix:
    - a completed drag seeks exactly once, to where it ended;
    - the bar and time follow the drag while playback keeps reporting progress.
  - Guards, passing before and after:
    - a tap seeks once;
    - a screen-reader increase seeks once.
- **Device:** not yet verified (seek is checklist item 6).

### Device checklist status
| # | Area | Result | Evidence |
|---|---|---|---|
| 1 | Foreground: notification card, artwork, S icon, controls, audible | **PASS** | User; system state |
| 2 | Background and screen-off | **PASS** | 60 s screen-off with automatic advance; about 2½ min with other apps in front; no gaps heard; no audio-focus loss or kills in the log |
| 3 | Lock screen: play/pause/next/previous, card | **PASS** | Next and Previous recorded at 12:50:56 and 12:51:02 |
| 4 | Bluetooth headphones | **PASS** (supported features) | Explicit PLAY/PAUSE from the headset handled; disconnect pauses with no speaker playback; reconnect stays paused. Double/triple press: not supported by the user's headphones (N/A) |
| 5 | Track and artwork sync | **PASS** (observed) | Metadata and artwork followed every automatic advance, Next and Previous |
| 6 | Pause, resume, seek | **PASS** for pause/resume. In-app and notification seek: not explicitly tested | Q10 fix restores seeking after Stop |
| 7 | Calls, ducking, unplug | **UNTESTED** | No call available; wired unplug impossible (USB-C port used for ADB) |
| 8 | Stop and end of queue | **PASS** for Stop (after the Q10 fix). End of queue: emulator only | |
| 9 | Process lifecycle | **PASS** | Removed from Recents while playing (kept playing) and while paused/stopped (process killed by Android); reopening restored paused, no autoplay. Reboot: untested |
| 10 | Analytics accuracy | **NOT YET TESTED** | |
| 11 | Release build | **PASS** | Q3 keep rules: notification present in release |
| 12 | Long session (1 h+) | **UNTESTED** | |
| 13 | Unreadable song | **UNTESTED on device** | Would require moving a music file; verified on the emulator |
| 14 | Shuffle/repeat controls | **NOT YET TESTED on device** | Verified on the emulator |
| 15, 18 | Lyrics | **UNTESTED on device** (user decision: post-release) | No `.lrc` files in the library |
| 16 | Car/Bluetooth PLAY key | **PARTIAL PASS** | Headset sends explicit PLAY/PAUSE and both behave as commands; a car head unit is untested |
| 17 | TalkBack | **UNTESTED** | Semantics verified by widget test |

### Additional observation (low severity)
- **SystemUI tries to read notification artwork from Sonus's private storage** (`file://…/files/sonus/artwork/…`) and logs `FileNotFoundException`. The card still shows the artwork (audio_service supplies the bitmap). Serving the artwork through a `FileProvider` `content://` URI would silence it. Backlog, not SN-44.

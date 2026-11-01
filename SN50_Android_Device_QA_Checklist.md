# SN-50 Android Device QA Checklist

Prepared 2026-10-31 (round 14) for code HEAD on `sn-50-final-refinement`. *Earlier text: "**Nothing here has been run.**" The first device pass is recorded below.* Installing a build on a phone, ADB, an emulator or the Android Auto DHU each needs your separate permission.

## Results: first device pass (2026-10-31)

Galaxy S26 Ultra (SM-S948U), Android 17 (`CP2A.260605.016.S948USQS4BZIG`). APK from `f00a89d`, SHA-256 `07ab0347…dc5a7`, installed with `adb install -r` at 19:26:12. The phone was offline throughout (Airplane mode on, Wi-Fi off). The automated pass used read-only ADB and navigation-only UI taps (accessibility tree). Nothing played, and no setting, import or record was changed.

| Result | Item |
|---|---|
| ~~FAIL (build)~~ **Fixed 20:06** | §0: the first APK (`07ab0347…`) was built with plain `flutter build apk --release`, so sign-in was off. It was rebuilt at `32dfc5f` (code identical to `f00a89d`) with `tool/build-release.ps1 -Config <sonus_next_sn49>\config\sonus.dev.json`. That config is the same file the previous sn49 build used, and it was not copied into this worktree. New APK SHA-256: `cfe5504f1f5ff28add83813c9821ba15e6c17375a6b56f1349cd25ee4b6c369b`, same package and certificate; `adb install -r` succeeded, with the original install date kept. |
| PASS (device) | After the reinstall: cold launch in 146 ms; "Schema version 41"; 881 songs, 97 albums and 74 artists; 177 October streams; Chart Filler with 228 songs. Settings shows "Patrick Casseus · Not synced yet", so the account session was kept. Sync shows Offline, last synced Never, 1,158 pending; nothing was tapped. No Sonus errors or crashes. The queue is restored paused (position 19.514 s became 19.667 s). |
| Observation (wording) | Offline, Account & Cloud shows "Account action failed. Please try again." with no action taken. It comes from the auth-state stream's error, most likely the offline session refresh. This code predates SN-50, the account stays signed in, and it is a candidate for wording approval. |
| PASS (device) | §0: backup `sonus-backup-20261031230436.sonusbackup` (DB v40, SHA-256 `0cdc0123…dc25`) has matching copies on the phone (`Download/Sonus Backup/`) and the PC (`phone_backups\…-before-sn50-v41\`). The flag is not set. |
| PASS (device) | §1: the app opens without an error screen. About shows "Schema version 41". The library shows 881 songs, 97 albums and 74 artists, the same as the v40 backup. Insights shows 177 October streams, the same as the backup's qualified plays. The playlist "Chart Filler" has 228 songs, also the same. |
| PASS (device) | §1: Charts open. Only one week, "in progress, final after Oct 31", is expected after the 2026-10-26 reset. Moments open with text and covers under the legacy rules. |
| PASS (device) | §1: Release Studio shows the "Leaked release" switch, off (PRIMA). It was **not** toggled. |
| PASS (user, manual) | §2–§5 basics: playback, skipping, Repeat One with manual Next, shuffle, queue restore after force-stop, and Clear queue keeping the playing song. |
| PASS (device) | Navigation: Home, Hot 100 (Charts and Moments), Insights (Monthly and Year), Library to artist to album to Edit Release, Playlists to the playlist, Settings (Playback, Library & Imports, Unavailable songs, Review metadata, About, Account & Cloud). No crashes, ANRs or Sonus exceptions in logcat, and the crash buffer is empty. |
| PASS (device) | Preferences kept: theme "Concrete & Spray · Street Bold" and High contrast on. "Remember shuffle and repeat" is **off** (your setting), so §4's persistence check needs it on. |
| PASS (device) | The media session is active with Previous, Play and Next plus Shuffle and Repeat custom actions. The notification is a foreground transport notification with 3 actions. |
| Observation | Android notifications for Sonus are **Blocked** (App info; appop `POST_NOTIFICATION: ignore`). The media notification still posts, but One UI placement and the lock screen need a manual look. |
| Observation | 4 unavailable songs (Cardi B, *Am I The Drama?*): the files were moved or deleted before SN-50. |
| AUTOMATED TEST ONLY | §2–§5 details, §6 Import Review states, §9 sync-paused wording and the signed-out guard. Targeted suites: player 378, database 153, recovery 376, import 461, sync 745, account 42, settings 175, charts 665 and playlists 67, all passed. |
| MANUAL REQUIRED | §2 duplicate-queue and end-of-queue checks; §3–§4 notification, lock-screen and restored shuffle order (needs "Remember" on); §5 Cancel in the dialog; §7 swipe, Recents, End Session and Deluxe edition name; Bluetooth. These all play music and so add listening history. |
| BLOCKED | §6 SAF import and grant revocation (no imports or revokes allowed); §8 Android Auto (no DHU or car); §9 sync and the signed-in delete guard (offline, and sign-in is off in this build); §1 Leaked toggle and new-backup check (data writes not authorized in this pass). |

Media-session detail (notification placement, swipe, Bluetooth after kill, wake lock) is already specified per decision in `SN50_Destructive_Workflows_Design.md` §4.2. This list adds the SN-50 checks and the order to run them in. Record pass/fail, device, Android version and build SHA for each line.

## 0. Before installing (data safety)

- [ ] Build only with `tool/build-release.ps1` (SN-49 rule). Confirm `SONUS_MOMENTS_REFINED_APPROVED` is **not** set (flag off, #21).
- [ ] On the phone's current build: Backup & Restore → Create and save backup (a `.sonusbackup`), and copy it off the phone (e.g. to `C:\dev\sonus\phone_backups`). Note its size and song count.
- [ ] Note the current library counts (songs, releases, Moments in the feed, newest finalized chart week) so they can be compared after the upgrade.
- [ ] Prefer disposable test music for playback checks; never delete or move audio files during QA.

## 1. DB v41 upgrade (first launch of the new build)

- [ ] App opens without an error screen; the library shows the same song and release counts as before.
- [ ] Charts: the newest finalized week and its positions are unchanged; older weeks open.
- [ ] Moments: published stories keep their text and covers (compare 3–5 known stories against screenshots taken before).
- [ ] Release Studio: the "Leaked release" switch appears, off for every release; turn it on and off on one release.
- [ ] A new backup from the new build completes. (Restoring it is optional and only onto this same phone.)
- [ ] Rollback plan if anything is wrong: reinstall the previous build and restore the step-0 backup. There is no down-migration.

## 2. Playback basics

- [ ] Play an album from the start, and from its third song (starts at the tapped song).
- [ ] Queue a song twice; the queue shows two rows; reorder and remove one copy.
- [ ] Pause in the last second of the last song, then Play: resumes there. Let the queue finish: paused on the final song, notification stays; Play replays it from 0:00.
- [ ] Credit edit in Track Studio while the song plays: Now Playing and the notification update without a skip or restart.

## 3. Repeat One

- [ ] Repeat One on: the song loops at its end.
- [ ] Next and Previous from Now Playing move to the next or previous song, and Repeat One stays on for it.
- [ ] Same from the notification, the lock screen and (if available) a Bluetooth headset.
- [ ] Repeat cycles Off → All → One → Off from both Now Playing and the notification.

## 4. Exact shuffle order

- [ ] Settings → Playback → "Remember shuffle and repeat" on. Shuffle a 15+ song queue; write down the first 8 songs of the shuffled order.
- [ ] Force-stop Sonus (Settings → Apps → Force stop), reopen: same song, same position, same shuffled order (Up Next matches the list).
- [ ] Next from the notification after the restart follows that order.
- [ ] With "Remember" off, after a restart shuffle and repeat are off (expected).
- [ ] Queue containing the same song twice, playing the second copy: after a restart the second copy resumes.

## 5. Clear Queue

- [ ] Queue screen → Clear queue → confirm: the playing song keeps playing; every other row is gone; the notification queue (and Auto) shows one item.
- [ ] Cancel in the dialog leaves the queue unchanged.
- [ ] Restart after clearing: only the playing song is restored.

## 6. SAF imports and Import Review

- [ ] Import a folder through the system picker; counts in the import result match the folder.
- [ ] A same-title file at another track position appears under "Possible different recordings" in Import Review with Import separately, Same recording and Not now.
- [ ] Not now keeps it listed after a restart.
- [ ] Revoke the folder grant (Settings → Apps → Sonus → storage, or remove the folder in the picker), reopen Import Review: the entry stays with the "can't read the folder" message rather than disappearing. **Record whether Android raised a permission error or "not found"** (M-6; tests only cover a fake).
- [ ] Delete nothing from the phone during this check; restore the grant afterwards.

## 7. Media notification and lock screen

Run §4.2 of the design doc for D-Q1/2, D-Q3/15, D-Q5/6, D-Q7, D-Q8, D-Q10 and D-Q16. In short:

- [ ] Controls: Previous, Play/Pause, Next, plus Shuffle and Repeat (record where One UI puts them). No Stop button.
- [ ] End Session from Now Playing overflow and the mini-player menu: notification goes, queue and position kept.
- [ ] Swipe the notification while paused and while playing; record what One UI allows.
- [ ] Swipe Sonus out of Recents while playing (keeps playing) and paused (stays paused).
- [ ] Bluetooth Play after End Session, with the process alive and after it was killed: same queue and position.
- [ ] Album art and the edition name (not the base title) show for a Deluxe edition song.

## 8. Android Auto (needs a car or the DHU, separately approved)

- [ ] Browse: song rows name the edition the song is on.
- [ ] Queue in the car matches the phone, including after Clear queue and in shuffled order.
- [ ] Skip to a queue item; Next/Previous under Repeat One behave as in §3.
- [ ] Shuffle and Repeat appear (perhaps in overflow) and toggle.

## 9. Library edits worth a quick look

- [ ] Release Studio → edition → Fix numbering on a gapped edition: preview shows old → new, nothing changes on Cancel, hand-set numbers are asked about separately.
- [ ] Signed out, try to delete a primary edition that was synced before: refused with "This edition is in your cloud library…" (round 14). Signed in, same result as before.
- [ ] Sync with a reachable server only if you choose to; a cloud missing a required table shows "Sync paused" with Retry. Do not test against production data.

## 10. Not on this list (still gated)

- Refined Moments activation and a flag-on build (#21), including the write-once start keys after a restart.
- Android 12 and lower custom actions and the wake lock (vendor patches M-4/M-5).
- Trash, Delete from Phone, ringtones, cloud archive (Leaked/Live), Supabase migrations, release signing and `versionCode`.

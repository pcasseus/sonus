# SN-50 Android Device QA Checklist

Prepared 2026-10-31 (round 14) for code HEAD on `sn-50-final-refinement`. **Nothing here has been run.** Installing a build on a phone, ADB, an emulator or the Android Auto DHU each needs your separate permission.

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

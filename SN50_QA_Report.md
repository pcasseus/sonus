# SN-50 QA Report

Branch `sn-50-final-refinement`, worktree `C:\dev\sonus\sonus_next_sn50`. Base `36d4d5d`. Round 1 ended at `14b592f`; refreshed 2026-10-30 at code HEAD `11f30a7` (round 9, Batches A–E up to `cc680e8`; none pushed).

## 1. Analyzer and test suite

| Point | `flutter analyze` | `flutter test` (full suite) |
|---|---|---|
| Baseline `36d4d5d` (SN-50 worktree, before edits) | No issues | **4,462 passed, 0 failed** |
| `14b592f` (end of round 1) | No issues | **4,798 passed, 0 failed** |
| `2e485ae` (BUG-04, round 3) | No issues | 4,941 passed, 0 failed |
| `83a7d96` (round 4) | No issues | 4,954 passed, 0 failed |
| `420d5d5` (round 5: audit F1/F2) | No issues | 4,967 passed, 0 failed |
| `8c8bffc` (round 6 A: display names, regression tests) | No issues | 4,981 passed, 1 skipped, 0 failed |
| `a4085a5` (round 6 B: playback races F3–F5) | No issues | 4,988 passed, 1 skipped, 0 failed |
| `11f30a7` (round 6 C: sync run queue) | No issues | 4,997 passed, 1 skipped, 0 failed |
| `ec59045` (round 7: #22 duplicate-song restore) | No issues | 5,008 passed, 0 skipped, 0 failed |
| `9ef4717` (round 8: F6 atomic finalization) | No issues | 5,022 passed, 0 failed |
| `48c2714` (round 8: #23 sync cancellation) | No issues | 5,036 passed, 0 failed |
| `e3dd5f5` (round 9 A: Repeat One, Clear queue) | No issues | 5,049 passed, 0 failed |
| `207e65d` (round 9 B: shuffle order) | No issues | 5,058 passed, 0 failed |
| `5c0071b` (round 9 C: paused sync) | No issues | 5,067 passed, 0 failed |
| `2af3a8b` + `cc680e8` (round 9 D and E, latest code; one run) | No issues | **5,098 passed, 0 failed** |

The round 6 skip pinned the duplicate-restore gap; `ec59045` fixes it and the test runs again, so nothing is skipped.

The suite has **336 more tests**. Nothing was dropped silently: a few tests that encoded replaced semantics were swapped for tests of the new rule. For example, Phase 1 replaced the two "replace finalized Moments" repository tests with publish-once tests.

- Tests that pinned old behaviour, which the spec explicitly replaces, were rewritten under names that state the new rule. Examples:
  - the all-edition track count;
  - the self-healing finalized weeks;
  - the four media controls;
  - the "unsynced non-home placement" assertion.
- After every batch, I re-ran the full suite myself rather than relying on the implementing agent's run.
- Formatting:
  - Each commit was checked with `dart format --output=none --set-exit-if-changed` on its changed Dart files.
  - One batch (Phase 7) had a single unformatted file; it was formatted and re-tested before commit.
  - The 22 pre-existing unformatted files from the audit were left untouched, as instructed.
- No failures were seen at any point, so there are no pre-existing failures to separate out. The known flaky `supabase_cloud_artwork_download_test` did not fail in any run.

## 2. Per-phase results

| Commit | Phase | Suite after |
|---|---|---|
| `8956e3a` | 1: freeze finalized weeks and Moments | 4,464 |
| `1a017eb` | 2a: counts, numbering, dates, new editions | 4,488 |
| `e4027e7` | 2b: display title, artwork, discs, genre, sync queue | 4,510 |
| `2a10990` | 2c: Leaked (DB v41), deletion safeguards | 4,545 |
| `1bce919` | 3: credits, credit line, version suffix | 4,597 |
| `70fdf64` | 4: Artist Profile | 4,626 |
| `3dbaaa0` | 5a: chart presentation, "All Time" retired, Deluxe-first | 4,665 |
| `78750b3` | 5b: This Week, prospective engine fixes | 4,693 |
| `ba2d575` | 6a: Moments events | 4,705 |
| `9aee76d` | 6b: Moments feed, dot, covers, publisher | 4,731 |
| `081d4ab` | 7: bulk actions | 4,761 |
| `9547ef0` | 8: media session (Dart side) | 4,783 |
| `14b592f` | final: Release Studio layout, Import Review credits, menus | 4,798 |
| `430700d` | R1 missing vs blocked; R5, E-Q8 tests | 4,816 |
| `8d2cbfe` | R2 approval-based activation; R6 dot baseline | 4,840 (+1 sleep-timeout flake, passes alone) |
| `9a5cdbb` | R3 entry kept on a jump to #1 | 4,845 |
| `db79c4e` | R4 Play after a finished queue | 4,855 |
| `d27aa50` | partials (A-Q13, A-Q26, B-Q30, F-Q7, D-Q18, A-Q7D) | 4,889 |
| `7dac818` | BUG-01 / BUG-05 | 4,907 |
| `4b6abbf` | BUG-02 | 4,916 |
| `0f4bb30` | BUG-03 | 4,930 |
| `2e485ae` | BUG-04, Import-1 and legacy-featured tests | 4,941 |
| `59a33bd` | Round 4 A + C: BU rises 20+, falls 30+ and exits detected, 1,000-stream milestone pinned | 4,949 |
| `83a7d96` | Round 4 B: possible different recordings reported | 4,954 |

Rounds 2–3 ran the full suite once per batch with `flutter test --concurrency=1` (memory-constrained machine), after targeted tests, and before committing. The `83a7d96` run is the final regression: later commits are docs only.

## 3. Data safety and history

- **Finalized history is frozen.** All of these run against SQLite on disposable temporary databases:
  - late plays, renamed identities and 25 repeated passes leave `chart_snapshots`, `chart_entries` and `chart_moment_events` row-identical;
  - an old-engine week (a C-4 row, a later-blocked song, a C-24 album) stays byte-identical after the 5b engine changes;
  - an interrupted first finalization recovers without duplicating Moments;
  - restore races are covered (`1b`, `2a`, `2b`, `3`, `6`).
- **Proof the tests bite:** with the freeze disabled, 7 tests fail.
- **Moments:**
  - Published Moments are append-only (`publishFinalizedForWeek`).
  - New rules apply only in a build compiled with `SONUS_MOMENTS_REFINED_APPROVED=true`, from a write-once per-install activation instant (`8d2cbfe`). Earlier items keep their families, ids, cap and text, pinned by the reachability harness. *Superseded: the fixed 2026-11-01 `refinedFromUtc` gate of round 1.*
  - Existing copy: 0 removed lines in `moment_headlines.dart`, and a test pins 384 variants (192 per publisher).
- **History recording untouched.** Playback sessions, chart snapshots and Moments still record the plain base title and artist (`playback_analytics_controller.dart:252-253`). New display fields (`displayTitle`, `albumDisplayTitle`, `displayArtist`, `creditLine`) are read-time only.
- **No bulk writes.** Nothing backfills or rewrites stored library data:
  - legacy featured names convert only when that song is saved;
  - renumbering happens only on the next membership edit, and changes only inferred numbers.

## 4. Local migration (disposable databases only)

- **DB v41** (`album_release_classifications.leaked`): the table is rebuilt through a staging copy of all 12 v40 columns, as v40 did for Live.
  - The v40→v41 upgrade is tested against the literal v40 table shape. Every row and column survives, `leaked` comes out NULL, and there are no foreign-key problems. An empty table is covered.
  - Fresh install at v41 is compared against the v31→v41 migrated schema.
  - Backup restore is tested for **every version from v31 through v40**, through preflight and the restore executor. Classifications are kept and `leaked` is unset.
  - Versions 34–40 fail if `leaked` is removed from `columnsAddedLater`. A v41 backup round-trips the flag.
  - Rollback means restoring the pre-upgrade backup; the codebase has no down-migration pattern.
- **Not run against any real database.** The migration runs on a real device only when a build containing `2a10990` is installed, which is a separate approval.

## 5. Accessibility, theme and responsiveness

New UI is covered by widget tests at **320dp width and 2× text**, across **all nine themes** where the existing matrix pattern applies:
- Release Studio (all sections open, both edition tabs);
- Artist Profile sections;
- charts (standings and weekly, tiers and longevity, This Week);
- the Moments dot;
- the Search selection bar.

- Indicators always use text or icons, never colour alone: format review, Unavailable, Leak, NEW / RE-ENTRY (new `chartReentry` token, 3:1 contrast tested in every theme), IN PROGRESS.
- Keyboard: Release Studio sections and tabs are focusable, and Tab then Enter toggles them (tested). Selection mode exits with Escape. Standings cards have a 3dp focus outline.
- Semantics: chart cards say what movement is measured against and read out the longevity facts. Selected rows announce their checked state. The Moments segment says "new stories". The mini-player has an End session action.
- Decoration Off, High Contrast and Low Effects: the Artist hero gets a flat backdrop without a banner, and chart tiers keep surface differences with no stripes.

## 6. Performance

- Charts no longer rebuild every past week on load (C-20, finalization part).
- Longevity is derived once per load.
- This Week is built once per load.
- The Moments feed reads bounded pages of 200 events using the existing `occurred_at DESC, id DESC` index (query plan tested).
- New DAO queries are parameterized with no N+1. Credits use `group_concat` subqueries, and project credits use the `song_id` index.
- No device profiling was done. LCP/INP-style measurements need a device build, which is a separate approval.

## 7. Regressions and behaviour changes to know about

These are spec-driven, not bugs, but the user will notice them:
- An unformatted release with ≤3 primary-edition tracks and more songs on other editions now enters format review and leaves the **current** release chart (A-Q14B). Finalized weeks are unaffected.
- Track Studio no longer links a typed credit name to an artist on its own; the user picks the artist.
- Weekly history rows are now tappable (E-Q8).
- The standings badge reads CURRENT; "Career standings" and "Career peak" replace "All Time".
- Play after a finished queue replays the last song from 0:00 (`db79c4e`, R4).
- Featured performers read "Ft." everywhere (BUG-05); queued songs update in place after a credit edit (BUG-01).
- Now Playing and the media session show the playing edition's name instead of the base album title (BUG-03).
- Under the refined Moments rules only:
  - a Bubbling Under → Hot 100 move is never the biggest gainer;
  - a Hot 100 return from Bubbling Under gets a re-entry story (BUG-04);
  - every Bubbling Under climb of 20+ places is a story (round 4).
- The import result shows "Possible different recordings (not imported)" for same-title files at another track position. They were previously counted as plain duplicates (round 4).
- Since round 5 (F1), a song whose own file is missing or absent is no longer relinked or bound to a file at another **known** track position on its edition. It is reported the same way. A file at the same position, or for a song listed with no known position (restored libraries), still relinks.
- The queue shows a song queued twice as two independent rows (round 5, F2). Previously that gave the reorderable list duplicate keys.
- Android Auto song rows name the edition the song is listed on; Blacklisted and the Library Health split-folder report name the release by its primary edition (round 6 A).
- A quick double tap on the system Shuffle or Repeat button now toggles twice; Play after a pause in the last second of the last song resumes there (a restored or finished queue still replays from 0:00); a credit edit during a queue edit is kept (round 6 B).
- Under Repeat One, Next and Previous move to the next or previous song; Repeat One stays on and applies to it (round 9 A1).
- The Queue screen has Clear queue: it keeps the song playing and removes the rest after a confirmation (round 9 A2).
- With Remember shuffle and repeat on, a restart keeps the exact shuffled order (round 9 B).
- A cloud missing what this version needs pauses sync with Retry, instead of retrying forever (round 9 C).
- Possible different recordings appear in Import Review with Import separately, Same recording and Not now (round 9 D).
- A finalized chart week and its Moments are now stored together or not at all; a finalized week can never be rewritten (round 8, F6).
- A timed-out, signed-out or switched sync run stops at its next safe point, so the next sync no longer waits for it to finish (round 8, #23).
- Restoring a queue that holds a song twice resumes the copy that was playing, not the first copy (round 7, #22).
- A sync run longer than 10 minutes is reported as timed out (changes kept, retry pending); no second run starts until it has ended; a sync queued for a signed-out or switched account no longer signs it back in (round 6 C).

## 8. Environment left untouched

- No push, merge, PR, rebase, reset, stash or branch deletion. `main`, the remotes and the other 12 worktrees are unchanged.
- No phone or ADB access, no emulator use, no Supabase or cloud contact, no sign-in, no real database writes, no MP3 operations, no ringtone changes.
- No secrets printed or committed. `config/sonus.dev.json` was not copied into the SN-50 worktree.
- The seven generated registrant files (line-ending churn from `pub get`) were never committed.
- **Two contained incidents in `sonus_next_sn49`, both caused by subagent relative-path writes, both reverted:**
  1. During Phase 2c, `lib/core/database/app_database.dart` was briefly changed (40→41). It was reverted immediately; I verified it is identical to HEAD.
  2. During the final batch, an **empty** untracked `lib/features/library/presentation/widgets/track_credit_editor_dialog.dart` appeared. I confirmed it was 0 bytes, created in this session and referenced nowhere, then removed it.
  - After both, `sonus_next_sn49` shows only its seven registrant files at `36d4d5d`, exactly as at the start.

## 9. Not verified (needs separate approval)

- **Real-device behaviour:**
  - One UI placement of Shuffle and Repeat;
  - notification swipe callbacks;
  - Bluetooth resume after the process is killed;
  - Android Auto;
  - lock screen;
  - rendering of the new icons.
- **Plugin patches:** Android ≤12 custom actions (D-Q14), wake lock (D-Q11).
- **Cloud:** Leaked and Live in the archive (B-Q19), sync of release-date precision, cross-device edition deletes.
- **Destructive workflows:** Trash, Delete from Phone and ringtones are design only (`SN50_Destructive_Workflows_Design.md`).
- **Copy:** editorial line-by-line approval of the existing copy, the 27 new draft lines and the BUG-04 drafts (Editorial §7).
- **BUG-03 and BUG-04 on a device:** verified by widget and pipeline tests only.
- **Audit hardening F3–F6** (round 5): confirmed by code reading only. Not implemented, by instruction. See Progress Round 5.
- **Refined Moments in a release build:** activation is verified by unit tests (F8). No committed config sets `SONUS_MOMENTS_REFINED_APPROVED`.
- **Device only (round 9):** Repeat One Next/Previous and the restored shuffle order from the notification, lock screen and Android Auto; the Clear queue dialog on a phone.
- **Chart jumps (round 9 E):** detected and held; copy and thresholds await approval.
- **Sync against a real server:** the round 6 run queue and the round 8 cancellation are tested with fakes and disposable SQLite only; no Supabase contact.
- **Shuffle order persistence** (BLOCKED #24): known, not changed. The duplicate-song restore start (#22) is fixed in `ec59045`.

**Production is not complete:** release signing, `versionCode`, Supabase migrations and device QA are still release blockers, as in the audit (Part I §9).

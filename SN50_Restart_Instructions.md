# SN-50 Restart Instructions (for a fresh Claude Code session)

## State at handoff (2026-10-30, after round 10)

- **Worktree:** `C:\dev\sonus\sonus_next_sn50`. **Branch:** `sn-50-final-refinement` (local only, never pushed).
- **Last code commit:** `b0f17c4` (round 11 Batch 1). Round 11: `f8088b8` (Batch 0), `b0f17c4` (Batch 1). Round 10: `ae0fd05` (Batch 1), `49c6188` (Batch 2). Round 9: `e3dd5f5` (A), `207e65d` (B), `5c0071b` (C), `2af3a8b` (D), `cc680e8` (E). Before them, `48c2714` (round 8 #23), `9ef4717` (round 8 F6). Before them, `ec59045` (round 7: #22). Before it, round 6 C `11f30a7` (sync run queue). Round 6 code commits: `8c8bffc` (A), `a4085a5` (B), `11f30a7` (C). A docs-only commit with the refreshed reports sits on top; check with `git log --oneline -5`. `a4085a5`'s subject starts with an invisible byte-order mark (PowerShell 5.1 wrote the message file); cosmetic, left as is because amending would rewrite a commit.
- **Last full suite:** at `b0f17c4`: **5,152 passed, 1 failed** (exit code 1). The failure was the sync-resilience sleep flake during Windows standby; that file passed 4/4 when rerun alone. This is not a clean full run. At `f8088b8`: 5,147 passed, 0 failed, 0 skipped (exit code not captured). Earlier: 5,134 at `49c6188`. `flutter analyze`: no issues. Formatting clean on all changed files.
- **Uncommitted changes:** the seven LF-churn registrant files (never committed) and two untracked documents kept uncommitted on purpose: `SN50_Decision_and_Release_Checklist.md` and `SN50_Round9_Editorial_and_Release_Safety_Review.md`. Preserve all of them. Write commit message files from bash or with BOM-free UTF-8, never PowerShell 5.1 `Set-Content -Encoding utf8`.
- **SN-49:** `C:\dev\sonus\sonus_next_sn49` @ `36d4d5d`, showing only its seven registrant files, unchanged.
- **Other worktrees:** unchanged from the baseline snapshot.
- `C:\dev\sonus\SN50_Additional_Bug_Tweaks_Addendum_v2.md` does **not** exist; v1 was used.

### All SN-50 commits (base `36d4d5d`)

| Round | Commits |
|---|---|
| Round 1 | `8956e3a` `1a017eb` `e4027e7` `2a10990` `1bce919` `70fdf64` `3dbaaa0` `78750b3` `ba2d575` `9aee76d` `081d4ab` `9547ef0` `14b592f` `91e5ab0` (docs) |
| Round 2 | `430700d` (R1) `8d2cbfe` (R2/R6) `9a5cdbb` (R3) `db79c4e` (R4) `d27aa50` (partials) `7dac818` (BUG-01/05) `4b6abbf` (BUG-02) `3080338` (docs) |
| Round 3 | `0f4bb30` (BUG-03) `2e485ae` (BUG-04 + Import-1 / legacy-featured tests) `91f60c1` (docs) |
| Round 4 | `59a33bd` (BU rules, milestone tests) `83a7d96` (possible different recordings) `ce51bd2` (docs/approval sheet) |
| Round 5 | Read-only code-integrity audit at `ce51bd2`: no web-instruction contamination, no rollback. `420d5d5` (F1 + F2) + docs (F3–F6 documented, F7 reconciled, F8 verified) |
| Round 6 | Notes reconciliation (`SN50_Original_Notes_Reconciliation.md`, 35 requirements). `8c8bffc` (A: edition names in Auto, Blacklisted, Library Health; regression tests) `a4085a5` (B: F3–F5) `11f30a7` (C: sync run queue) + docs (D) |
| Round 7 | `ec59045` (#22 duplicate-song restore) + docs (design proposals for #23 sync cancellation and F6 atomic finalization, Progress Round 7) |
| Round 8 | `9ef4717` (F6 atomic chart finalization) `48c2714` (#23 cooperative sync cancellation) + docs |
| Round 9 | `e3dd5f5` (Repeat One, Clear queue) `207e65d` (shuffle order) `5c0071b` (paused sync) `2af3a8b` (Import Review list) `cc680e8` (chart jumps, held) + docs `6f5214c`. `SN50_Decision_and_Release_Checklist.md` stays uncommitted. |
| Round 10 | `ae0fd05` (approved chart jumps; approved-family guard) `49c6188` (Import Review file states, `content://`) + docs |
| Round 11 | `f8088b8` (Batch 0: legacy/refined headline isolation, goldens) `b0f17c4` (Batch 1: P-003 to P-009, refined only) + docs. Editorial packages, contract and A-0 reports stay uncommitted. |

## Next steps

**[Round 10]** All approved safe work is done: implementation is complete for rounds 1–10, and device QA is pending. What remains needs the user's decisions (`SN50_Progress.md` → BLOCKED_NEEDS_APPROVAL 1–27; resolved items are struck through there; `SN50_Original_Notes_Reconciliation.md` §4). *Earlier text: "BLOCKED_NEEDS_APPROVAL 1–24, #22 now fixed; #23 and F6 have design proposals"; #22, #23 and F6 are all implemented since.* Do not repeat the round 5 audit or the round 6 reconciliation, or reopen settled decisions.

The user's next priorities, in order:

1. **`SN50_BUG04_Editorial_Approval_Sheet.md`** (BU-001 to BU-071). Once lines are approved:
   - wire sections D and E from `MomentStoryPlanner.copyGated` (ids `#bu-fall` and `#hot-100-exit`) as new families;
   - apply the B rewrites prospectively;
   - add the C variants to F05.
   - A family needs 6 SD + 6 PP approved lines to ship.
2. ~~**Import Review persistence** for possible different recordings (BLOCKED #19). It needs schema approval.~~ *Done without a schema change (`2af3a8b`, `49c6188`). Remaining: the other Import Review wording and the SAF device check (BLOCKED #27).*
3. **SN-50 final release-readiness review.** Known inputs:
   - ~~F3–F6 hardening, documented in Progress Round 5, needs authorization; F6 is a persistence change;~~ *done: `a4085a5`, `9ef4717`;*
   - the refined-Moments release flag is set in no config and stays disabled (#21); it is blocked by the BUG-04 copy (#17), the nine draft families held by the guard (#12) and the P-items (#7);
   - M-2/M-3 sign-off (#14);
   - device, cloud and destructive gates.
4. A **custom type label for BUG-03** needs schema approval.

## Verification workflow (user-approved)

- **Subagents** run only targeted tests for what they change, plus `dart format <changed files>` and `flutter analyze`. Never the full suite.
- **The main session** reviews the diff, runs the boundary check, analyze, the format check and **one** full suite (`flutter test --concurrency=1 --reporter=compact > file 2>&1`) per batch, then commits only if green.
- **Memory:** the background-shell reaper has twice killed test wrappers. When that happens:
  - Don't restart on your own. Check whether `flutter_tester.exe` / `dart.exe` is still running (`tasklist`) and the output file is still growing. The run often finishes by itself; wait for it.
  - A full suite takes about 7–10 minutes at concurrency 1. Run one at a time, and no parallel agents during verification.
- **Known flake:** `test/features/sync/data/services/supabase_sync_resilience_test.dart` "after a timeout, the next attempt succeeds" times out only if the machine sleeps mid-run. Rerun that file alone.
- **Modern standby (round 10):** a suite that seems stuck may be paused by sleep (the Batch 1 run took 158 min). Check `Get-WinEvent` System Kernel-Power 506/507 before suspecting a hang, and let the existing run finish.

## Tooling

The scripts are in the **old** scratchpad: `C:\Users\patri\AppData\Local\Temp\claude\C--dev-sonus-sonus-next-sn49\4ce5fc24-049c-4db3-a342-c1342ba00ef4\scratchpad\`. A new session may get a different scratchpad, so recreate them if they're missing.

- **`commit\commit.ps1 -MessageFile <f> -PathsFile <f>`:**
  - checks the branch, stages the allowlist and requires an exact staged-set match;
  - runs `git diff --cached --check`, a secret scan, and rejects attribution or trailers;
  - commits as the user's git identity.
- **`wt_snapshot.sh`** prints HEAD and status for every worktree except sn50. Compare against `wt_baseline.txt` after each batch.
- **`verify.sh <label>`** runs the boundary diff, analyze, format check and full suite.

Equivalent by hand:

```powershell
cd C:\dev\sonus\sonus_next_sn50
git status --short; git log --oneline -5
git -C C:\dev\sonus\sonus_next_sn49 status --porcelain --untracked-files=all   # only 7 registrants
flutter analyze
flutter test --concurrency=1 --reporter=compact > $env:TEMP\sn50_full.txt 2>&1
```

## Technical findings (so they aren't rediscovered)

- **Editing pitfalls:**
  - `sed -i` in Git Bash converts CRLF to LF; edit with Python and keep CRLF.
  - Bash heredocs containing `'''` break; write Python scripts to a file first.
  - After any scripted edit, check that the file wasn't truncated (one agent emptied a file once).
- **Chart history is frozen** (`ChartFinalizationService`): stored weeks are never rebuilt. Moments are published once through `publishFinalizedForWeek`, written before the snapshot. Engine fixes affect only new weeks.
- **Refined Moments rules** need the `SONUS_MOMENTS_REFINED_APPROVED=true` build flag plus a write-once SharedPreferences marker (`charts.moments.rules_activated_utc`). Dev and test builds always use the old rules. Tests inject `ChartMomentRules(activatedAtUtc: …)`.
- **Display contracts:**
  - `songDisplayTitle` (version qualifier) and `songCreditLine` ("Primary & Co Ft. A, B with Guest") drive `LibraryTrack.displayTitle` / `creditLine` / `releaseCreditLine`, and `PlaybackTrack.displayTitle` / `displayArtist`.
  - Analytics and history always use the plain `title` / `artistName`.
  - `releaseDisplayTitle` gives the primary edition's title, while the base `albums.title` is never rewritten.
- **Live playback display refresh:** `PlaybackDisplayRefresher` (in `PlaybackScope`) listens for library edits and calls `PlaybackCoordinator.refreshTrackDisplay`. It changes only display fields (`displayTitle`, `displayArtist`, `displayAlbum`), never position, session or the history fields.
- **Edition labels:** `editionTypeLabel` / `editionLabel` in `release_display_title.dart`. An Other edition's label is derived from its title (BUG-03).
- **Bubbling Under ↔ Hot 100 Moments (BUG-04):** in `MomentStoryPlanner` (entry and `hot-100` stories, `fromBubblingUnderVariants`) and `MomentEditorialDesk._biggestGainers` (`_crossesIntoHot100`). Refined rules only.
- **Sync run queue (round 6 C):** `SyncController` runs one service run at a time on `_pending`, which ends only when the service run really ends; `_bounded` waits at most `runTimeout` (default 10 min) and reports `SyncRunTimedOut`; a late result is never used; `_sessionEpoch` (sign-out, external `activateUser`) makes queued runs for a stale account skip. Cancellation is not possible today (proposal in Progress Round 6).
- **Repeat One (round 9 A1):** `PlaybackAudioPlayer.adjacentIndex` (play order, ignores Repeat One); the engine uses it for Next/Previous only under Repeat One.
- **Shuffle order (round 9 B):** the optional `ShuffleOrderPlayback` capability (real engine only), `RestoredShuffleOrder`, and the `shuffleOrder` key inside snapshot v1; applied only when shuffle is on at restore.
- **Paused sync (round 9 C):** `SyncFailureKind.isPermanent`, `SyncStatus.paused`, `SyncStatusStore` pause keys; `AutomaticSyncCoordinator.trigger(retry:)`.
- **Possible different recordings (round 9 D):** `PossibleRecordingStore` (SharedPreferences), `PossibleRecordingReviewService`, `AtomicLibraryImporter.import(separateFrom:)`.
- **Chart jumps (round 10, `ae0fd05`):** families `songHot100MajorJump` (PulsePop; capped unless Top 40) and `songHot100ClimbRun` (Sonus Daily; mandatory), planned in `MomentStoryPlanner._addChartJump` with `ChartJumpFacts` (`chart_jump_facts.dart`). *Round 9's `GatedMomentKind.hot100MajorClimb` / `hot100ClimbRun` no longer exist.* Streaming sentence `MomentEditorialDesk._jumpStreamSentence` (CJ-040 revised / CJ-041, floor 10, positive gain).
- **Approved-family guard (round 10, `ae0fd05`):** `MomentHeadlines.approvedFamilies` (fail-closed). `MomentEditorialDesk.compose` skips any other family before facts or headlines, so the neutral fallback can't publish it; it is listed as `GatedMomentKind.unapprovedCopy`. A family joins the set only when its approved lines land.
- **Import file states (round 10, `49c6188`):** `ImportFileMissing` / `ImportFileAccessDenied` / `ImportTagsUnreadable` (`import_file_failure.dart`), `ResolvedMetadata.readFailure`, read-only `ImportFileProbe` / `LocalImportFileProbe`, optional `metadataSource` in the pending-list JSON (approved; device-local only, no SQLite, backup or cloud change).
- **Chart finalization (round 8, F6):** the app passes `weekFinalizer: charts` (`charts_scope.dart`); `SqliteChartRepository.finalizeWeek` writes snapshot, entries and Moments in one transaction and returns an already-finalized week untouched; `replaceSnapshot` throws `FinalizedChartWeekFrozen` for a finalized week.
- **Sync cancellation (round 8, #23):** `SyncCancellation` rides in a zone value set by `SyncController._bounded`; `SyncCancellation.checkpoint()` sits only between units (and first/last inside an inbound record's transaction). Add any new sync loop's check point outside per-item `try` blocks, or rethrow `SyncCancelled` from them.
- **Start index (round 7, #22):** `PlaybackCoordinator.playTracks` starts at the requested entry's own place among the playable entries (count of playable entries before it), never a song-id lookup.
- **End of queue (round 6 B):** `_pausedAtSeekedPosition` arms the one-second R4 end allowance only for a seek made while paused (restore); `play()` clears it. System Shuffle/Repeat go through `_runInTurn` in `SonusAudioHandler`. Queue edits emit `_withCurrentDisplay(updatedQueue)`.
- **Import identity (round 5, F1):** in `AtomicLibraryImporter`, `atKnownOtherPosition` runs **before** any binding check: the song's position on this edition is known and the file's differs. A missing or absent file then never relinks or binds to it. An unknown position (track 0) still relinks, which recovery depends on (`recovery_audio_service_test.dart`).
- **Queue rows (round 5, F2):** `playback_queue_page.dart` keys rows by occurrence (`songId`, then `songId#n`) through `_QueueContent.entryIds`. The queue model has no entry id, and `PlaybackTrack ==` compares `songId`. Engine, persistence and media session are index-based.
- **Claude config:** `.claude/settings.local.json` `claudeMdExcludes` keeps the global web-development `~/.claude/CLAUDE.md` out of SN-50 sessions. It applies only in this worktree.
- **Credits:** Track Studio and Import Review load structured credits plus any older `featured_artists` names not covered. Save writes the mirror from the saved featured credits. Linking only happens through the picker.
- **Charts and missing music (R1):** `play_time_identity.dart` names entities missing from the library from their last playback session. Only blocked songs are excluded, consistently across Career standings, This Week and finalization.
- **DB is v41** (Leaked). No schema changes are authorized; anything needing one goes under BLOCKED.

## Still prohibited without separate explicit approval

- New schemas or migrations.
- Trash, purge or physical deletion; ringtones.
- Changes to finalized chart history or published Moments; backfills.
- Unapproved editorial copy, including P-001 to P-050 and the 27 N-drafts already in code (they ship only after activation and approval; since `ae0fd05` the approved-family guard holds them even after activation).
- Enabling the refined Moments release flag (`SONUS_MOMENTS_REFINED_APPROVED`).
- Vendored plugin patches.
- Phone, ADB, emulator or device QA.
- Supabase, cloud or production data.
- git push, merge, PR or remote publication.

The full list of open user decisions is in `SN50_Progress.md` → `BLOCKED_NEEDS_APPROVAL` (items 1–27; earlier text said 1–16).

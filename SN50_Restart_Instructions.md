# SN-50 Restart Instructions (for a fresh Claude Code session)

## State at handoff (2026-10-30, after round 3)

- **Worktree:** `C:\dev\sonus\sonus_next_sn50`. **Branch:** `sn-50-final-refinement` (local only, never pushed).
- **Last code commit:** `2e485ae` (BUG-04). A docs-only commit with the refreshed reports sits on top of it; check with `git log --oneline -3`.
- **Last full suite:** **4,941 passed, 0 failed** (`flutter test --concurrency=1`, at `2e485ae`). `flutter analyze`: no issues. Formatting clean on all changed files.
- **Uncommitted changes:** none (only the seven LF-churn registrant files, which are never committed).
- **SN-49:** `C:\dev\sonus\sonus_next_sn49` @ `36d4d5d`, showing only its seven registrant files, unchanged.
- **Other worktrees:** unchanged from the baseline snapshot.
- `C:\dev\sonus\SN50_Additional_Bug_Tweaks_Addendum_v2.md` does **not** exist; v1 was used.

### All SN-50 commits (base `36d4d5d`)

| Round | Commits |
|---|---|
| Round 1 | `8956e3a` `1a017eb` `e4027e7` `2a10990` `1bce919` `70fdf64` `3dbaaa0` `78750b3` `ba2d575` `9aee76d` `081d4ab` `9547ef0` `14b592f` `91e5ab0` (docs) |
| Round 2 | `430700d` (R1) `8d2cbfe` (R2/R6) `9a5cdbb` (R3) `db79c4e` (R4) `d27aa50` (partials) `7dac818` (BUG-01/05) `4b6abbf` (BUG-02) `3080338` (docs) |
| Round 3 | `0f4bb30` (BUG-03) `2e485ae` (BUG-04 + Import-1 / legacy-featured tests) + docs refresh |

## Next steps

All safe SN-50 work in the brief and addenda is done. What remains needs the user's decisions, listed in `SN50_Progress.md` → `BLOCKED_NEEDS_APPROVAL` (items 1–18). The most likely next batches once approved:

1. **BUG-04 copy** (Editorial §7, N-8 to N-11): add the approved lines as new families (6 SD + 6 PP each) and wire the approved selection rules in `MomentStoryPlanner`, behind the existing activation gate. Tests go in `test/features/charts/application/services/bubbling_under_moments_test.dart`, which already has the #94 → #121 and #122 → #168 cases asserting "publishes nothing".
2. **Import-1 identity policy** (Progress round 3, rules 1–3): new imports only, never re-evaluate existing songs. Pinned today by `recording_identity_import_test.dart` "SN-44 Import-1" and "SN-50 Import-1".
3. **F-Q7 threshold** (`MomentStoryPlanner.majorStreamMilestone`, 1,000): change only if the user picks another value.
4. **BUG-03 custom type label:** needs a migration, so only with explicit schema approval.

## Verification workflow (user-approved)

- **Subagents** run only targeted tests for what they change, plus `dart format <changed files>` and `flutter analyze`. Never the full suite.
- **The main session** reviews the diff, runs the boundary check, analyze, the format check and **one** full suite (`flutter test --concurrency=1 --reporter=compact > file 2>&1`) per batch, then commits only if green.
- **Memory:** the background-shell reaper has twice killed test wrappers. When that happens:
  - Don't restart on your own. Check whether `flutter_tester.exe` / `dart.exe` is still running (`tasklist`) and the output file is still growing. The run often finishes by itself; wait for it.
  - A full suite takes about 7–10 minutes at concurrency 1. Run one at a time, and no parallel agents during verification.
- **Known flake:** `test/features/sync/data/services/supabase_sync_resilience_test.dart` "after a timeout, the next attempt succeeds" times out only if the machine sleeps mid-run. Rerun that file alone.

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
- **Credits:** Track Studio and Import Review load structured credits plus any older `featured_artists` names not covered. Save writes the mirror from the saved featured credits. Linking only happens through the picker.
- **Charts and missing music (R1):** `play_time_identity.dart` names entities missing from the library from their last playback session. Only blocked songs are excluded, consistently across Career standings, This Week and finalization.
- **DB is v41** (Leaked). No schema changes are authorized; anything needing one goes under BLOCKED.

## Still prohibited without separate explicit approval

- New schemas or migrations.
- Trash, purge or physical deletion; ringtones.
- Changes to finalized chart history or published Moments; backfills.
- Unapproved editorial copy, including P-001 to P-050 and the 27 N-drafts already in code (they ship only after activation and approval).
- Vendored plugin patches.
- Phone, ADB, emulator or device QA.
- Supabase, cloud or production data.
- git push, merge, PR or remote publication.

The full list of open user decisions is in `SN50_Progress.md` → `BLOCKED_NEEDS_APPROVAL` (items 1–16).

# SN-50 QA Report

Branch `sn-50-final-refinement`, worktree `C:\dev\sonus\sonus_next_sn50`. Base `36d4d5d`, HEAD `14b592f` (13 local commits, none pushed). Date: 2026-10-29.

## 1. Analyzer and test suite

| Point | `flutter analyze` | `flutter test` (full suite) |
|---|---|---|
| Baseline `36d4d5d` (SN-50 worktree, before edits) | No issues | **4,462 passed, 0 failed** |
| HEAD `14b592f` | No issues | **4,798 passed, 0 failed** |

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

## 3. Data safety and history

- **Finalized history is frozen.** All of these run against SQLite on disposable temporary databases:
  - late plays, renamed identities and 25 repeated passes leave `chart_snapshots`, `chart_entries` and `chart_moment_events` row-identical;
  - an old-engine week (a C-4 row, a later-blocked song, a C-24 album) stays byte-identical after the 5b engine changes;
  - an interrupted first finalization recovers without duplicating Moments;
  - restore races are covered (`1b`, `2a`, `2b`, `3`, `6`).
- **Proof the tests bite:** with the freeze disabled, 7 tests fail.
- **Moments:**
  - Published Moments are append-only (`publishFinalizedForWeek`).
  - New rules are gated at `ChartMomentRules.refinedFromUtc` (2026-11-01 UTC). Pre-gate items keep their families, ids, cap and text, pinned by the reachability harness.
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
- Play after a finished queue still does nothing, as before. It is pinned for decision M-1.

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
- **Copy:** editorial line-by-line approval of the existing copy and the 27 new draft lines.

**Production is not complete:** release signing, `versionCode`, Supabase migrations and device QA are still release blockers, as in the audit (Part I §9).

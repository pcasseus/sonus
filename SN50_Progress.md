# SN-50 Progress

Branch `sn-50-final-refinement` in worktree `C:\dev\sonus\sonus_next_sn50`, created from `36d4d5d` (SN-49 HEAD, which includes the five unpushed SN-49 commits `3476e87..36d4d5d`).

Authority: `C:\dev\sonus\SN50_Master_Implementation_Spec.md` and `SN50_Claude_Production_Brief.md` (2026-10-29). Local commits on this branch only. No push, merge, PR, phone, cloud or real-data operation.

## Phase 0 — Baseline and freeze inventory (done 2026-10-29)

- `sonus_next_sn49` @ `36d4d5d`: no commits since the audit. The working tree holds only the seven line-ending-only generated registrants (an `--ignore-all-space --ignore-cr-at-eol` diff is empty). It was left untouched.
- `origin/main` = `5c7a838`; `origin/sn-49-release-hardening` = `97045b5`. No `sn-50*` branch existed. Thirteen worktrees are listed; none were modified.
- The SN-50 worktree was created with `git worktree add -b sn-50-final-refinement ..\sonus_next_sn50 36d4d5d`.
- Baseline in the SN-50 worktree: `flutter analyze` reports no issues; `flutter test` reports **4,462 passed, 0 failed** (about 2 min). This matches the audit's count.
- `flutter pub get` regenerates the same seven registrant files with LF endings. They are excluded from every commit by the commit script's allowlist.
- `config/sonus.dev.json` was **not** copied into this worktree. Tests don't need it, and release builds are out of scope.
- Missing sources: none. All four SN-50 documents are present in `C:\dev\sonus`.

## Phase 1 — Non-mutating chart-history guard (done, `8956e3a`)

Implements the spec's immutable-history requirement (§0.1, E-Q8, E-Q19, F3 append-stable) and closes audit issue #1.

- `ChartFinalizationService`: a stored finalized week is returned exactly as stored and never rebuilt. Only a missing week is built. This also removes the O(W²) per-load rebuild (audit C-20, finalization part).
- Its Moments are published **once**, **before** the snapshot write, through the new `ChartMomentRepository.publishFinalizedForWeek`. That call inserts only when the week has no finalized Moments yet. It never deletes or replaces, and it replaces `replaceFinalizedForWeek` (the delete-then-insert path).
- If a pass is interrupted between the two writes, the next pass builds the snapshot and skips the already-published Moments.
- Restore-generation checks still guard both writes.
- Data model: no schema change. Existing stored weeks and Moments are kept as they are, including weeks whose content differs from what today's engine would produce. Those are now frozen rather than self-healed.
- Tests:
  - SQLite-level freeze suite in `chart_finalization_restore_test.dart`: late plays, renamed identities and 25 repeated passes leave `chart_snapshots`, `chart_entries` and `chart_moment_events` row-identical; an interrupted first finalization recovers.
  - Restore races are re-pinned for the new write order: `1b`, `2a`, `2b`.
  - The old self-healing tests are inverted.
  - Repository publish-once tests.
  - Verified: with the freeze disabled, 7 tests fail.
- Result: 4,464 tests pass; analyzer clean.
- Consequence to note: any later engine or identity fix (for example C-4, C-24) now applies only to newly finalized weeks. Repairing stored weeks needs a separately approved repair.

## Phase 2 — Edition and metadata architecture (done)

### 2a (`1a017eb`): counts, numbering, dates, new-edition defaults

- **A-Q14A/B (audit #10).** Card `track_count` is now the primary edition's listings, falling back to all songs when there is no primary. The all-edition count is kept as `songCount`. The possible-Single (≤3) review therefore judges the primary edition.
  - Effect: an unformatted release with ≤3 primary-edition tracks and more songs on other editions now enters review, and leaves the *current* release chart. Finalized weeks are unaffected because of Phase 1.
- **A3, A-Q7A/B/C, A-Q9 (audit #9).** A new `edition_track_numbering.dart` renumbers each disc from 1 in edition order.
  - Only inferred numbers change. The number of hand-set numbers kept is reported back.
  - Choose songs applies its changes in one transaction and asks before overwriting hand-set numbers.
  - A disc move puts the track at the end of the destination disc.
  - Verify Library repairs never renumber (A-Q7D).
  - Changed songs are queued with the existing `recordUpsert` pattern.
- **A-Q6C (audit #8).** New `AlbumProfileEditingService.updateEditionReleaseDate` handles any edition. It records provenance (manual) and queues the edition. Release Studio shows a per-edition date card; an edition without a date shows "Not set".
- **A-Q5A–E, A-Q6D.**
  - The default source for a new edition is the primary, and a name is suggested for its type.
  - Date, cover and genre are never copied (now pinned by a test).
  - An edition without a cover is captioned as using the primary edition's cover.
- **Deferred:**
  - The one-time repair of existing gapped editions (A-Q7D: previewed individual repairs only).
  - MusicBrainz date apply still targets the primary edition.
  - The Deluxe follow-up offer renumbers inferred numbers without asking about hand-set ones.
- **Result:** 4,488 tests (+24); analyzer clean.

### 2b (`e4027e7`): display title, artwork context, disc rule, genre, sync queue

- **A-Q3/A-Q4.** Current surfaces show the primary edition's title through `releaseDisplayTitle`, falling back to the base title when the edition title is empty or only a type name.
  - New fields `LibraryAlbum.displayTitle` and `LibraryTrack.albumDisplayTitle` carry it. `albums.title` and `canonical_title` are never written.
  - Search matches both titles.
  - Chart, Moments and playback history still record the base `albumTitle`, so nothing new is written into history.
  - The Studio "Name" field now renames the selected edition.
  - Still on the base title: Now Playing and the media session (analytics-fed), Android Auto song rows, charts and Insights pages, MusicBrainz queries, and `findAlbums` ordering.
- **A-Q12.** Song artwork in lists: the song's own artwork, then the primary edition's cover if the song is listed there, then its home edition's cover, then the primary's cover. In an edition view: the song's own artwork, then that edition's cover, then the primary's cover.
- **A-Q8A.** One shared `spansMultipleDiscs` rule for the Studio and the Album page.
- **A-Q6F/A-Q17B.** A nonblocking genre-conflict note. The Album page edition view shows the release genre.
- **A-Q5F/A-Q20.** Offers to make a new Standard edition primary; the default is "Not now".
- **A-Q7A.** Placement disc moves ask before overwriting hand-set numbers.
- **A3 / audit #5.** A Track Studio non-home placement edit now queues the song (`recordUpsert`). Placements edited before this fix and never queued are still exposed to inbound reverts.
- `organization_schema.dart`: corrected the stale comment.
- **Result:** 4,510 tests; analyzer clean.
- **Interpretation to confirm (OPEN_QUESTION):** inside an edition view, a song's own custom artwork still comes before the edition cover. A-Q12 "selected edition controls" could instead mean the edition cover always wins.

### 2c (`2a10990`): release Leaked (DB v41) and edition-delete safeguards

- **A-Q2C/A-Q2D/B-Q13.** `album_release_classifications.leaked` is a manual-only flag.
  - DB v41 rebuilds the table through a staging copy of all 12 v40 columns, as v40 did for Live.
  - The column is registered in `columnsAddedLater`; the restorable set is now 31–41.
  - Release Studio has a "Leaked release" switch. Song `is_leak` never sets the release flag (tested). No chart badge.
- **§0.6 backups.**
  - Restore is tested for backups from each version v31 through v40. Classifications are kept and `leaked` is unset.
  - A v41 backup round-trips the flag.
  - The v40→v41 upgrade is tested against the literal v40 table shape.
  - Rollback means restoring the backup taken before the upgrade; the codebase has no down-migration pattern.
- **A5 (A-Q15/23/24/25/26, A-Q16).** `deleteEdition` runs as one transaction and fails closed:
  - the final edition is refused;
  - deleting the primary needs a replacement primary chosen in the same step;
  - songs listed only on the edition block the delete;
  - songs whose home edition is deleted move to an edition that lists them;
  - a primary with a cloud baseline for the signed-in user is refused.
  - No new remote propagation.
- **Result:** 4,545 tests; analyzer clean.
- **Deferred in Phase 2:**
  - The Release Studio single-screen tab layout with collapsible Shared Details (A-Q6A/B). Shared and edition editing are already separated, but the full layout restructure is not done.
  - Deluxe-first chart representation (Phase 5).
- **Incident (contained):** a subagent's relative-path write briefly changed `sonus_next_sn49/lib/core/database/app_database.dart`. It was reverted immediately; I verified the file is identical to HEAD and that sn49 shows only its seven registrant files.

## Phase 3 — Credits, display titles and identity (done, `1bce919`)

- **C-Q4 / audit #13.**
  - Track Studio seeds credits from structured rows plus legacy `featured_artists`. They are converted only when that song is saved, never in bulk.
  - Duplicate checks compare artist identities, not names. Repeats are refused with a message, and the "updated" toast appears only when something changed.
  - Import Review keeps known comma-containing names whole (`ArtistCreditParser.splitNameList`) and no longer erases co-primary or guest credits.
- **C-Q1.** `songCreditLine` formats credits as "Primary & Co feat. A, B with Guest".
- **C-Q6/C-Q8/C-Q9/C-Q22.** `songDisplayTitle` adds a concise version qualifier and never repeats one already in the title.
  - The credit line and display title are used in song lists, Search, Now Playing, Queue, the mini-player, notifications, the lock screen and Android Auto.
  - `PlaybackTrack.displayTitle` and `displayArtist` are new fields; `title` and `artistName` are unchanged, so analytics still records plain values (verified).
- **C-Q2/C-Q3.** The credit editor has a searchable artist picker with free-text fallback. Track Studio no longer auto-links a typed name to an artist.
- **Deferred:**
  - **C-Q7 future-snapshot presentation title.** Capture points are `chart_snapshot_builder_service.dart`, `all_time_chart_service.dart` and `playback_analytics_controller.dart:252`. It needs approval because those values feed history and matching.
  - **C-Q5.** Import Review does not yet use the shared credit editor.
  - Release Studio and Playlist rows still show the plain title.
- **Result:** 4,597 tests; analyzer clean.
- **OPEN_QUESTION:** confirm that Track Studio should never auto-link a typed credit name to an existing artist. Import Review and the importer still link by name.

## Phase 4 — Artist Profile (done, `70fdf64`)

- **Hero.**
  - B-Q1: the catalog-count line is removed.
  - B-Q2: a contributor's hero reads "On X, Y and others", with no counts.
  - B-Q21: without a banner, Decoration Off, High Contrast and Low Effects get a flat backdrop.
- **Sections.**
  - B-Q8/B-Q22: Albums → EPs → Singles → Live → Leaked → Needs Review, each release once.
  - B-Q7: Leaked comes before Live, with Live shown as a secondary note.
  - B-Q9: cards show format plus the primary edition's track count.
  - B-Q14/B-Q37: unconfirmed formats get a "Format needs review" note.
  - B-Q23: a kind note on the card. B-Q24: "Unavailable" releases stay listed.
- **Top Tracks.**
  - B-Q29/B-Q35: five rows plus See All, which ranks every song with lifetime qualified streams.
  - B-Q16/B-Q20: performer named when not the owner; duplicate album title omitted.
- **Collaborators.**
  - B-Q15/B-Q32: built from song credits, including featured and guest roles.
  - B-Q34: subtitle "Artists who appear on these releases".
  - B-Q33/B-Q36: unlinked names aren't tappable.
  - B-Q26/B-Q27/B-Q28/B-Q18: the Play, Collaborations-queue and Play All rules are implemented.
- **B-Q12/B-Q31.** Song Leak label only when the song itself is flagged.
- New read-only query `findProjectSongCredits` (parameterized, indexed).
- **Result:** 4,626 tests; analyzer clean.
- **Choices to confirm:**
  - See All appears only when more than five songs have streams.
  - Unlinked collaborators keep a working Play button.
  - Tagged featured names on songs with no structured credits count as unlinked collaborators.

## Phase 5 — Charts (done)

### 5a (`3dbaaa0`): presentation only

No engine, builder, finalization, schema or Moments change.

- **§0.4 / E-Q15A.** "All Time" is retired from user-facing text:
  - week label → "Career standings";
  - badge `ALL TIME` → `CURRENT`;
  - `ALL-TIME PEAK` / "All-time peak" → "Career peak";
  - Artist Profile subtitle → "Your most streamed songs".
  - A page test scans the default view's text, semantics and tooltips. No Moments template contained the phrase.
- **A-Q21/A-Q22/A-Q27/A-Q27B/A-Q28.** `ChartAlbumPresentation.resolve` (Deluxe-first) on the current album chart.
  - Position and streams are unchanged; tapping opens the edition shown.
  - If the Deluxe-edition read fails, the chart falls back to the primary edition.
- **E-Q9/E-Q10/E-Q15B/C/E-Q16/E-Q1.**
  - Rank tiers on both views.
  - `ChartLongevityIndex` per load: weeks at #1, longest #1 run, current Top 10 streak, debut, official weeks.
  - New `chartReentry` token and icon (3:1 contrast tested in all themes).
  - Bubbling Under last-week context on weekly cards.
- **E-Q3/E-Q4/E-Q7 (C-8/C-9).** The info sheet text depends on the view and states the tie-breaks.
- **C-30.** Local week label (`chartWeekLabel`, tested for UTC+2 and UTC−4).
- **C-29.** Focus outline on standings cards.
- **E-Q8 (C-28).** Weekly rows open living entities; purged ones stay display-only.
- **Result:** 4,665 tests; analyzer clean.
- **Choices to confirm:**
  - The labels "Career standings", "CURRENT" and "Career peak".
  - "Consecutive #1 streak" is read as the longest #1 run.
  - The weekly #1 uses spotlight styling on the normal card layout.
  - Tapping a weekly-history song queues that week's chart order.

### 5b (`78750b3`): provisional This Week and prospective engine corrections

- **E-Q5/E-Q18.** `ThisWeekChartService` runs the live path in memory once per load. It is never stored or published, and `LiveChartMomentService` stays unwired.
  - It sits in the week navigator: Career standings → This Week → finalized weeks.
  - IN PROGRESS badge with "Final after <local date>".
  - "Best so far #N" stays separate from the official peak.
  - If it fails, it fails on its own: logged under `sonus.charts`, with a fallback to Career standings (tested).
- **E-Q2 (C-4).** Movement compares with the last finalized official rank, even after an intra-week dip. In-week RE-ENTRY applies only to entities with no official history.
- **E-Q19 (C-7), partial.** A song blocked at finalization is excluded, matching This Week. Excluding songs or albums *missing from the library* is **not** done (OPEN_QUESTION 8).
- **E-Q13 (C-24).** New album entries credit the album's own artist, falling back to the play-time artist.
- **E-Q7.** Tie-breaks are pinned.
- **Freeze regression.** A stored old-engine week (a C-4 row, a later-blocked song, a C-24 album) stays byte-identical across passes; the next missing week uses the new rules.
- **Result:** 4,693 tests; analyzer clean.
- **Choices to confirm:**
  - This Week lives inside the week navigator rather than a separate selector.
  - On This Week, "N weeks" counts finalized weeks only.

## Phase 6 — Moments (done; copy approvals pending)

### 6a (`ba2d575`): events and publication

New rules apply only from `ChartMomentRules.refinedFromUtc` = **2026-11-01 UTC**. Earlier items keep the old families, ids, cap and text, with no backfill.

- **F-Q1/F-Q27/F-Q31/F-Q12.**
  - Mandatory debut and re-entry stories for every entry #1–200, on songs and releases, weekly and all-time.
  - They are exempt from the three-per-day minor cap.
  - Acceptance scenario 8: five Bubbling Under debuts give 5 stories after the gate, 3 before.
- **F-Q14/F-Q14B, partial.**
  - Weekly first zones from Top 75 to #1. All-time zones come from a new replay `thresholdEntry` type.
  - Top 10/5/3/2 and #1 are "major" and get separate stories; lower zones share one consolidated story with `thresholdList`.
  - Not covered: an all-time jump straight to #1 skips the Top 100 entry.
- **F-Q5/F-Q16 (audit #14, W1/W2).**
  - A #1 story names a rival only when verified.
  - Same-artist replacement gets the new self-replacement family; "retakes from itself" no longer happens.
  - Old published stories keep their old text.
- **F-Q6/F-Q7/F-Q9.** Distinct major stories stay separate.
- **F-Q10/F-Q30.** Weekly nth #1 counts all stored history and names the chart scope.
- **F-Q15.** Release roundup (new N-5 family).
- **F-Q2/F-Q3.** `songPeakMatch` and `songWeeksMilestone` are wired; `releaseWeeksMilestone` is not (F-Q29).
- **Scenario 9.** A shared cover is shown once.
- **Reachability harness.** Real detectors → SQLite → aggregator → desk. 17 families are reachable under the old rules, 31 under the new.
- **Existing copy unchanged.**
  - 0 removed lines in `moment_headlines.dart`.
  - A test pins 384 variants (192 per publisher).
  - A test checks that new lines contain no "this week's", "this stream", " its " or "all time".
- **27 new template lines** come from proposal drafts N-2 through N-6: 1–2 per publisher per family, not yet the 6+6 that full shipping needs.
- **Deferred:** F-Q4 dethronings and exits (N-7), all-time roundups.
- **Result:** 4,705 tests; analyzer clean.

### 6b (`9aee76d`): feed, new-content dot, covers, publisher, navigation

- **F-Q25.**
  - `ChartMomentRepository.getPage` uses the existing `occurred_at DESC, id DESC` index (query plan tested).
  - `ChartMomentFeedPager` loads whole local days, so caps and context match a full read (tested across page breaks).
  - The feed is a lazy sliver list with category and publisher filters.
- **F-Q26.** New-content dot with the label "Moments, new stories". Last-seen time is stored in SharedPreferences (`charts.moments.last_seen_utc`). No per-story tracking.
- **F-Q17/F-Q18, A-Q12, C-23.** New stories only:
  - song covers use the song-row cover order;
  - release covers are Deluxe-first, with a placeholder for a Deluxe without a cover.
  - Old stories keep their covers.
- **F-Q22/F-Q23.**
  - The duplicate chart tag is removed from all cards. This is display chrome only; no stored text or art changes.
  - Artist roundups and artist stream milestones have no rank badge.
- **F-Q19/F-Q20.** New song stories show the credit line, unlinked.
- **F-Q28.** New stories use `publisherFor`: measured/factual → Sonus Daily, expressive → PulsePop. Old stories keep the hash split.
- **A-Q18/A-Q29.** A real-time song story opens the played edition, or the primary edition with an explanation if that edition was removed. Purged entities have no link.
- **Result:** 4,731 tests; analyzer clean.
- **Choices to confirm:**
  - Under the mapping, Sonus Daily never covers #1 arrivals.
  - The dot shows on first launch.
  - Finalized-week song stories open the song's home edition.

## Phase 7 — Bulk actions; Trash and media identity (bulk done, `081d4ab`; Trash gated)

- **C-Q10A.**
  - Shared `TrackSelectionController` and `TrackSelectionBar` on Tracks, Album, Artist, Search and Playlist Detail.
  - Long press or the menu's Select enters selection; Escape, Back or close leaves it.
  - Rows announce their checked state. 320dp at 2× text and 9 themes are tested.
- **C-Q10B.** Bulk Add to queue keeps on-screen order and reports skipped unavailable songs. Bulk Add to playlist uses the shared sheet. No bulk Play next.
- **C-Q11.**
  - `PlaylistService.addSongs` runs one transaction and reports added / already present / failed, on top of the existing UNIQUE constraint.
  - Single adds use the same path and report duplicates honestly.
  - Concurrency and mid-batch failure are tested.
- **C-Q12.** Go to album and Go to artist appear wherever valid, plus Select. Historical chart rows get no new actions.
- **Result:** 4,761 tests; analyzer clean.
- **Deferred:** Track Studio item in the Search and Playlist Detail menus.
- **Sonus Trash, Delete from Phone, ringtones (C3/C4): GATED.** The safety design is in `SN50_Destructive_Workflows_Design.md`, with an approval checklist in its §6. No destructive code was written. Key findings:
  - sync has no deletion markers, so an inbound sync would re-create a purged song;
  - the importer silently relinks a reappearing file, which would revive a trashed song (this must change for C-Q18);
  - the wake-lock fix (D-Q11) and Android ≤12 buttons (D-Q14) need vendored-plugin patches.

## Phase 8 — Media controls and ringtone (Dart-side done, `9547ef0`; device QA and plugin patches gated)

- **D-Q1/D-Q2/D-Q3.**
  - Controls: Prev, Play/Pause, Next, Shuffle and Repeat. Shuffle and Repeat are custom actions with icons and labels that follow the mode.
  - The visible Stop is removed.
  - Compact indices stay `[0,1,2]`; `[1,2,3]` would crash on Android ≤12 (`AudioService.java:514-520`).
  - Five new vector drawables, kept through `keep.xml`.
- **D-Q12/D-Q13.** `PlaybackRepeatMode.next` cycles Off→All→One. External changes follow the Remember preference.
- **D-Q3/D-Q15/D-Q6.** End session in the Now Playing menu and a mini-player long press. It and notification dismissal both call `stop()`, which keeps the queue and position.
- **D-Q7.** The paused-only swipe that clears the queue already existed.
- **D-Q10.** Swiping from Recents is a no-op.
- **D-Q8/D-Q9, Dart side.**
  - A system Play waits up to 10 s for the restore before playing.
  - The resume card offers the saved session's song.
  - Whether a killed process reaches Dart `play()` is unverified (native).
- **D-Q16.**
  - A completed queue shows as paused on its last song; engine and analytics are unchanged, so no double count.
  - **Play after the end currently does nothing** (pinned by a test; decision M-1 is open).
  - The saved session is still cleared on completion, so a finished queue doesn't survive a process restart.
- **D-Q18, partial.** The large summary card is removed; the "subtle album atmosphere" is deferred. **D-Q19:** deferred.
- **Gated:**
  - D-Q14 Android ≤12 buttons: plugin Patch 3.
  - D-Q11 wake lock: plugin Patch 2.
  - All device QA (One UI placement, swipe callbacks, Bluetooth resume after kill, Android Auto) is listed in the design doc §4.2.
  - Ringtones (C-Q20): design only.
- **Result:** 4,783 tests; analyzer clean.

## Final batch (`14b592f`): Release Studio layout, Import Review credits, menus

- **A-Q6A/A-Q6B/A-Q4.** One scrolling Release Studio:
  - collapsible Shared details at the top;
  - edition tabs with the primary first and a Primary badge;
  - expandable edition sections;
  - no tabs for a single edition.
  - Shared values can't be edited inside an edition (tested).
- **C-Q5.** Import Review uses the shared `TrackCreditList` and editor and saves through `updateTrackWithCredits`. If credits can't be loaded, the editor doesn't open.
- **C-Q12.** Track Studio is in the Search and Playlist Detail menus.
- **Result:** 4,798 tests; analyzer clean.

## Phase 9 — Validation and handoff (done)

- Full suite: 4,798 passed (baseline 4,462). `flutter analyze`: no issues.
- Reports:
  - `SN50_Decision_Traceability.md`: 177 IDs — 118 implemented and tested, 25 partial, 22 gated, 4 deferred, 8 no change needed.
  - `SN50_QA_Report.md`.
  - `SN50_Restart_Instructions.md`.
  - `SN50_Editorial_Change_Proposal.md`.
  - `SN50_Destructive_Workflows_Design.md`.
- **Second contained sn49 incident:** an empty stray file from a subagent relative-path write (`sonus_next_sn49/lib/features/library/presentation/widgets/track_credit_editor_dialog.dart`). I confirmed it was 0 bytes, untracked, created this session and referenced nowhere, then removed it. sn49 is back to only its seven registrant files at `36d4d5d`.
- **Safe local work is exhausted for this pass**, apart from the small Partial follow-ups listed in `SN50_Restart_Instructions.md`. Everything else needs the approvals below.

## Round 2 (2026-10-29/30): R1–R6, safe partials, addendum bugs

Authorized by the user's explicit safe-local-work message. Decisions are in `C:\dev\sonus\SN50_R1-R6_Reconciliation_and_Trash_Review.md` §2; the addendum is `C:\dev\sonus\SN50_Additional_Bug_Tweaks_Addendum.md` (BUG-01 to BUG-04). BUG-05 comes from the user's message, because the referenced `..._Addendum_v2.md` file **does not exist**.

| Commit | Batch | Full suite |
|---|---|---|
| `430700d` | R1 missing-vs-blocked eligibility; R5 and E-Q8 regression tests | 4,816 |
| `8d2cbfe` | R2 approval-based Moments activation; R6 dot baseline; R1 for career Moments | 4,840 + 1 sleep-timeout flake (passes alone) |
| `9a5cdbb` | R3 direct-to-#1 entry; only #1 and first Top 10 are majors; other zones consolidated | 4,845 |
| `db79c4e` | R4 Play after a finished queue replays the last song from 0:00; finished session persisted | 4,855 |
| `d27aa50` | Batch 5 partials: A-Q13 placeholder fix, A-Q26 pin, B-Q30/F-Q7, D-Q18 queue atmosphere, A-Q7D Fix numbering, SN-44 carry-overs | 4,889 |
| `7dac818` | BUG-01 credit edits reach the playing queue; BUG-05 "Ft." connector | 4,907 |
| `4b6abbf` | BUG-02 version and credits on every current song surface | **4,916** (analyzer clean) |

### Key decisions and findings

- **R1.** Only *blocked* songs leave current charts. A song missing from the library keeps its plays and is shown with its play-time identity (`play_time_identity.dart`) and the HISTORICAL badge. If the session record is also missing, the live views skip and log that entity; finalization still throws.
- **R2.**
  - Approval flag: `--dart-define=SONUS_MOMENTS_REFINED_APPROVED=true` (documented in the README). Without it the old rules apply forever.
  - The activation instant is write-once, stored in SharedPreferences under `charts.moments.rules_activated_utc` (there is no generic key-value DB table). It is read back before use.
  - Weekly new rules apply only to weeks *starting* at or after activation. Real-time new rules apply from the activation instant.
- **R3.** Only #1 and the first Top 10 get separate stories; other zones go into one N-3 `thresholdList` story. A debut at #1 is one story. Top 5/3/2 story ids changed (only reachable after activation).
- **R4.** The replay lives in `JustAudioPlaybackEngine.play()`. "At end" means a finished queue, or paused within 1 s of the end of a track longer than 2 s with no next item. The finished session is kept at the track's end.
- **R6.** The baseline is an `(occurredAt, id)` mark. The first visit shows no dot; backdated items never raise it.
- **F-Q7.** A major stream milestone is **≥ 1,000** (`MomentStoryPlanner.majorStreamMilestone`). This is my choice; confirm it.
- **BUG-01.**
  - Root cause: saving was already correct. The playing queue, the media session, Search and Playlist were not refreshed; unlinking under the same name was ignored; older featured names were not loaded into the editor.
  - Fix: `PlaybackDisplayRefresh` / `PlaybackCoordinator.refreshTrackDisplay` / `PlaybackDisplayRefresher` update display fields in place without touching analytics identity.
  - Mirror policy: the editor always loads older `featured_artists` names not covered by credits, and save writes the mirror from the saved featured credits. This changes the earlier C-Q4 behaviour.
- **BUG-05.** `songCreditLine` gives "Primary & Co Ft. A, B with Guest". The parser still accepts feat./ft./featuring. Moments headline wording is unchanged.
- **BUG-02.**
  - Display title and credit line are applied on all current surfaces, including Home rails, Release Studio, edition pickers (Choose songs dedupes by song id), playlists, the lyrics header, career standings (`ChartsController.songPresentationFor`) and the Settings lists.
  - Left as is: This Week rows (snapshot titles), finalized weeks, Moments template text and analytics aggregates.
- **SN-44 carry-overs.**
  - The Deluxe-copy sidecar-lyrics overwrite is fixed.
  - Track Studio home reassignment is already safe.
  - **Open:** two same-title files of similar length (within 3 s) on one album at different track positions still import as one song (second reported as `duplicateRecording`). This needs a product decision.

### Workflow notes for the next session

- The machine is memory-constrained, and the background-shell reaper twice killed `flutter test` wrappers. The test runner process may keep running after its shell is killed; wait for it rather than starting a second run.
- Use `--concurrency=1`. A full suite takes about 7–10 minutes.
- Subagents run targeted tests only; the main session runs one full suite per batch.
- `sed -i` in Git Bash converts CRLF to LF, so use Python with explicit CRLF handling.
- One subagent emptied a file through a failed Python write and restored it with `git restore` before editing. Always check file sizes after scripted edits.
- Every subagent must use absolute paths under `C:\dev\sonus\sonus_next_sn50\`. Check all worktrees against the baseline after each batch.

### Remaining work

- **BUG-03:** "Other" edition custom name, using `album_editions.title`, no schema change.
- **BUG-04:** Bubbling Under debut, re-entry and movement stories, plus the first Hot 100 entrance. New copy is editorially gated: reuse accurate existing families and draft the rest.
- Then the final full regression and analyze, and refreshed Traceability and QA reports.

### Editorial proposal

`SN50_Editorial_Change_Proposal.md`:
- P-001 to P-050 are rewrites, all needing approval. No retirements and no publisher reassignments.
- N-1 to N-7 are new-path drafts.
- Four open questions are listed in its §6.
- No existing variant was changed.

## BLOCKED_NEEDS_APPROVAL / user decisions

1. **DB v41 on real devices.** The migration runs on a phone's real database the first time a build containing `2a10990` is installed. Take a `.sonusbackup` before any install. Installing is a separate approval.
2. **B-Q19.** Release Leaked rides in the cloud-archive row automatically, like Live, and the archive isn't deployed, so there is no exposure today. A client older than v41 receiving a row that holds only Leaked would fail its local CHECK, the same issue Live has for clients older than v40. Cloud activation is a separate approval.
3. **Edition delete while signed out.** The `primaryInCloud` gate checks only the signed-in user's baselines. Closing that gap needs a sync-code change, which needs approval.
4. **Placement edits never queued.** Track Studio placements made before `e4027e7` can still be reverted by an inbound copy (fixing this would need a re-queue repair, which needs approval).
5. **A-Q7D numbering repairs.** Previewed individual repairs of existing gapped editions are not built yet.
6. **Open question (A-Q12).** In an edition view, should a song's custom artwork or the edition cover come first? Currently the song's custom artwork wins.
7. **Editorial proposal.** P-001 to P-050 and N-1 to N-7 await line-by-line approval, plus the four open questions in its §6.
8. **E-Q19 remainder.** Should finalized weeks also exclude songs and albums no longer in the local library? If yes, plays synced from another device for songs not imported locally would drop out of new finalized weeks, and the SN-32 test "finalized history uses playback-session identity even when song is no longer in library" changes meaning.
9. **Moments gate date.** New Moment rules start on 2026-11-01 UTC (fixed). It should match the real release date; the alternative is a per-install marker.
10. **Major-zone noise.** A jump straight to #1 can yield the #1 story, Top 2/3/5/10 stories and a consolidated story (6–7 stories). Should majors below the final major be folded into one?
11. **Old-story repair.** Should already-published stories get the rival fix and the "this stream" removal? That counts as a historical repair, which needs separate approval.
12. **New template copy.** The 27 new lines (families N-2 to N-6, listed in the 6a report and `moment_headlines.dart`) are drafts awaiting approval and expansion to 6+6 lines.
13. **Destructive workflows.** Approve or adjust `SN50_Destructive_Workflows_Design.md` §6 items A-T0 to A-T6 (Trash and purge), P-1 to P-5 (Delete from Phone), R-1 to R-3 (ringtones) and M-1 to M-6 (media session, plugin patches 2/3, device QA).
14. **M-2/M-3 confirmation.** `9547ef0` implemented End Session (keeping the queue) and the Dart-side media-session changes under the approved D-Q3/D-Q6/D-Q1 decisions. The destructive-workflows design doc had listed them as approval items, so please confirm or ask for changes. Device QA and plugin patches were not done.
15. **Round 2 decisions to confirm:**
    - F-Q7 major milestone threshold of 1,000 streams.
    - The BUG-01 mirror policy, which changes C-Q4.
    - The Import-1 same-title, similar-length duplicate import (needs a policy).
    - BUG-04 headline copy for Bubbling Under movement (needs editorial approval).
16. **`SN50_Additional_Bug_Tweaks_Addendum_v2.md` was referenced but not found.** BUG-05 was implemented from the user's message.

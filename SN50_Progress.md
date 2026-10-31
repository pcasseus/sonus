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
  - *Superseded:* Now Playing and the media session show the edition since `0f4bb30`, career standings since `3dbaaa0`/`4b6abbf`, and Android Auto song rows since `8c8bffc` (round 6). Remaining: This Week and Insights (product decision).
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
  - Release Studio and Playlist rows still show the plain title. *Superseded by `4b6abbf` (BUG-02).*
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

*Superseded by R2 (`8d2cbfe`): there is no fixed date. The rules start only in a build compiled with `SONUS_MOMENTS_REFINED_APPROVED=true`, at a write-once per-install activation instant (see Round 2 and Round 5 F8).*

- **F-Q1/F-Q27/F-Q31/F-Q12.**
  - Mandatory debut and re-entry stories for every entry #1–200, on songs and releases, weekly and all-time.
  - They are exempt from the three-per-day minor cap.
  - Acceptance scenario 8: five Bubbling Under debuts give 5 stories after the gate, 3 before.
- **F-Q14/F-Q14B, partial.**
  - Weekly first zones from Top 75 to #1. All-time zones come from a new replay `thresholdEntry` type.
  - Top 10/5/3/2 and #1 are "major" and get separate stories; lower zones share one consolidated story with `thresholdList`.
  - Not covered: an all-time jump straight to #1 skips the Top 100 entry. *Superseded by R3 (`9a5cdbb`): the entry is kept.*
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
  - The dot shows on first launch. *Superseded by R6 (`8d2cbfe`): the first visit shows no dot.*
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
  - *Superseded by R4 (`db79c4e`): Play after the end replays the last song from 0:00 and the finished session is kept. Since `a4085a5` (round 6) the one-second end allowance applies only to a position set by a seek while paused, as a restore is.*
- **D-Q18, partial.** The large summary card is removed; the "subtle album atmosphere" is deferred. **D-Q19:** deferred. *D-Q18 superseded by `d27aa50`: the Queue has the artwork atmosphere.*
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

Done in round 3 (below). What is left needs your decisions: see BLOCKED_NEEDS_APPROVAL.

## Round 3 (2026-10-30): BUG-03, BUG-04, outstanding findings

`C:\dev\sonus\SN50_Additional_Bug_Tweaks_Addendum_v2.md` was referenced again but **still does not exist**; the work follows `SN50_Additional_Bug_Tweaks_Addendum.md` §BUG-03/§BUG-04 and your message.

| Commit | Batch | Full suite (`--concurrency=1`) |
|---|---|---|
| `0f4bb30` | BUG-03 Other edition with its own name | 4,930 passed, 0 failed |
| `2e485ae` | BUG-04 Bubbling Under / Hot 100 arrivals; Import-1 and legacy-featured regression tests | **4,941 passed, 0 failed** (analyzer clean) |

One full suite per batch, run by the main session after targeted tests. No subagents were used. Boundary check (all other worktrees) unchanged after each batch; SN-49 still `36d4d5d` with only its seven registrant files.

### BUG-03

- No schema change: the name is `album_editions.title`.
- New-edition dialog: choosing Other suggests no name (it used to suggest "Release (Other)") and hints "For example Skyline (Remixes)". A blank name or the bare word "Other" is refused. Renaming shows and keeps the saved name.
- Album page badge and edition picker: an Other edition shows its own qualifier ("Remixes" for "Skyline (Remixes)"), or its whole name when it isn't built on the release title. Typed editions keep their type label. Release Studio tabs show the full name (they already did); an unnamed edition reads "Other" instead of "other".
- Now Playing and the media session show the playing edition's name (`PlaybackTrack.displayAlbum`). A rename refreshes it in place through the BUG-01 refresher. Listening history still records the stored album and edition titles.
- Untouched: the parent title, other editions, membership, numbering, primary status, stream history. The edition is never made primary.
- **Design choice for you:** a separate custom *type label* (e.g. "Remixes" stored apart from the name) would need a new column. Not done. Today the label is derived from the name.

### BUG-04

All of it applies only under the refined-rules activation gate, and only to chart weeks starting after activation. Existing headline families are reused only where every line is true for the case.

- First Bubbling Under debut (#176): guaranteed `songBubblingUnderDebut` (was already the case; now pinned).
- Bubbling Under re-entry: guaranteed `songReentry`, chart named as Bubbling Under (pinned).
- #124 → #87, never on the Hot 100: guaranteed `songHot100Breakthrough`. **Fixed:** it could also be the week's biggest gainer, told as "up 37 places". A #101–200 → #1–100 move no longer counts as a Hot 100 climb (E-Q1).
- #112 → #90, on the Hot 100 in an earlier week: **Fixed.** It produced no story. It now gets a guaranteed Hot 100 re-entry (`songReentry`).
- Off the chart last week, back at #95, only ever on Bubbling Under before: **Fixed.** It was told as "re-enters the Hot 100" (false). It is now a first Hot 100 entry, without the four arrival lines that describe a move up from Bubbling Under.
- #171 → #139: told only when it is the week's biggest gainer (existing family; chart named as Bubbling Under).
- #122 → #168 and #94 → #121: publish nothing. They need new copy and a selection rule (Editorial §7, N-8 to N-10).
- Idempotence: composing again gives identical stories; finalizing a week again publishes nothing. Weeks before activation keep exactly their earlier stories.
- Review item, unchanged: `song-break-p3` "jumps from #124 to #87, into the Sonus Hot 100" may read as Hot 100 movement (Editorial §7.2).

### Outstanding findings

- **F-Q7 major milestone, current behaviour (recorded, not extended):** under the refined rules, a song, release or artist stream milestone of **≥ 1,000** (`MomentStoryPlanner.majorStreamMilestone`) gets its own story beside another achievement of the same play; a smaller one becomes supporting text; a milestone that is the play's only news is always its own story. Legacy rules are unaffected. 1,000 is my choice, not an approved editorial threshold. Nothing else uses it.
- **Legacy featured names:** Track Studio shows older `featured_artists` names for editing. New test: opening the editor (twice) writes nothing; the stored value changes only on an intentional save.
- **Import-1 same-title, similar-length files:** current behaviour is non-destructive. The second file is skipped as `duplicateRecording`, reported against the kept song, not bound to it, and nothing about the kept song changes, also on a second import (new test). It is **not** imported as its own song, so a genuinely different recording at another track position stays out of the library until you decide. **Proposed identity policy (for approval, not implemented):**
  1. Same artist, title, version and album, durations within tolerance, **same** disc and track position (or no position): same recording, as today.
  2. Same as 1 but a **different** disc/track position on the same edition: ambiguous. Import it as its own song flagged `alternateRecording` for review (the existing review reason), never auto-merged; the user can later merge or keep both.
  3. Never re-evaluate or split songs already in the library; the policy applies to new imports only.

### Editorial proposal

`SN50_Editorial_Change_Proposal.md`:
- P-001 to P-050 are rewrites, all needing approval. No retirements and no publisher reassignments.
- N-1 to N-7 are new-path drafts.
- Four open questions are listed in its §6.
- No existing variant was changed.

## Round 4 (2026-10-30): approved BUG-04 rules, import identity, milestones

Authority: `C:\dev\sonus\SN50_BUG04_Import_Final_Decisions_Claude_Handoff.md`. The six selection and identity rules are approved. **No new or revised wording is approved.**

| Commit | Batch | Full suite (`--concurrency=1`) |
|---|---|---|
| `59a33bd` | A + C: Bubbling Under rises 20+, falls 30+ and notable exits (detected); arrival-variant suppression; 1,000-stream milestone pinned | 4,949 passed, 0 failed |
| `83a7d96` | B: ambiguous same-title imports made visible; distinct-recording and idempotence tests | **4,954 passed, 0 failed** (analyzer clean) |

### Status by the handoff's three categories

**Implemented + tested**
- BU rise of 20+ places (#171 → #139): one guaranteed story per qualifying song, with the approved F10 `songBigClimb` lines. There is no weekly cap, and the daily minor cap never drops it. The week's biggest gainer keeps its own story instead of a second one. +19 (#140 → #121) gives no story. Five songs climbing 20+ in one week give five stories.
- First Hot 100 entry from BU (#124 → #87): guaranteed F05 story. F05-PP-03 ("jumps from #124 to #87, into the Sonus Hot 100") is no longer chosen for it; its text is unchanged. It is never told as a 37-place climb.
- Hot 100 re-entry from BU (#112 → #90, earlier Hot 100 week): guaranteed F12 re-entry, never a first debut (round 3).
- Exactly-once behaviour: composing again gives the same stories; re-finalizing a week publishes nothing; weeks before activation publish byte-identical stories and detect nothing new.
- 1,000 qualified streams as the first major milestone. This is approved rule 6, and the behaviour was already correct, so only tests were added: 999 stays supporting text; 999 → 1,000 crosses the milestone once; 1,000 → 2,499 crosses nothing; the ladder is unchanged.
- Import (approved rule 5):
  - Distinct recordings with evidence import as separate songs: a duration beyond tolerance, different featured artists, or a version label (e.g. "ErrTime" vs "ErrTime (Club Remix)", same length).
  - The same recording imported again creates no new song.
  - A same-title, same-length file at a **different disc/track position on the same edition** is no longer reported as a plain duplicate. It is now `ImportSkipReason.possibleAlternateRecording`, shown as its own row in the import result ("Possible different recordings (not imported)"). As before, nothing is written for it (no song, binding, listing, lyrics, review row or sync record), and importing again gives the same result.
  - Existing songs, playlists, plays and history are never split, merged or relinked.
  - Position alone is never treated as proof of distinctness.

**Detected but copy-gated (BLOCKED_EDITORIAL)**
- BU fall of 30+ places (#122 → #168): `GatedMomentKind.bubblingUnderFall`, id `…#bu-fall`. −29 (#131 → #160) is not detected.
- Notable Hot 100 exit into BU (#94 → #121): `GatedMomentKind.notableHot100Exit`, id `…#hot-100-exit`. Only after a verified Top 40 peak, or a fifth Hot 100 week recorded (stored longevity milestone) before the exit week; 4 weeks with a #60 peak is not detected. Missing history never counts.
- Naming last week's BU rank in the first-Hot-100-entry story: the story's publisher (PulsePop) has no approved line that names it.
- These are detected by `MomentEditorialDesk.copyGated` / `MomentStoryPlanner.copyGated`, which are never shown. Drafts for approval: `SN50_BUG04_Editorial_Approval_Sheet.md` (BU-001 to BU-071).

**Blocked (needs separate authority)**
- **Import Review for ambiguous files (rule 5, partly blocked).** The existing review contract can't hold a file that wasn't imported:
  - `song_import_reviews` is keyed by song id, and the ambiguous file has no song.
  - Its reasons are decoded with `ImportReviewReason.values.byName`, so a new reason value would make an older build fail to read a backup that contains it.
  - Putting these files into Review therefore needs new persistence, either a pending-file record or a new reason plus a payload with the file path. That is a schema/data-contract change and needs your approval.
  - Until then the files are reported in the import result only, and a rescan reports them again.

### Workflow (round 4)

- The main session reviewed every diff.
- A single focused subagent did Batch B and ran only `flutter test --concurrency=1 test/features/import`: 400 passed.
- The main session ran one full suite per code batch, never overlapping.
- The boundary check passed after both batches, and SN-49 is still `36d4d5d` with only its seven registrant files.

## Round 5 (2026-10-30): code-integrity audit corrections

**Audit.** The read-only audit at `ce51bd2` checked whether the global web-development `CLAUDE.md` (Tailwind, TypeScript, HTML, SEO, web performance) influenced Sonus. It found no contamination:
- no web dependencies or APIs in `pubspec.yaml` or `lib/`;
- every SN-50 code commit traces to an approved decision;
- accessibility work is Flutter-native (48 dp targets, `MediaQuery.disableAnimationsOf`).

The `claudeMdExcludes` setting in `.claude/settings.local.json` keeps that file out of SN-50 sessions. No rollback was warranted. Findings F1–F8 were authorized as below.

| Commit | Batch | Full suite (`--concurrency=1`) |
|---|---|---|
| `420d5d5` | F1 import identity; F2 duplicate queue keys | 4,967 passed, 0 failed (analyzer clean) |

**F1 — confirmed defect, fixed.** In `atomic_library_importer.dart`, the "another disc/track position on the same edition" check ran only when the existing song had an available file. If that song's file was missing, or it had none, an ambiguous file fell through to the relink or bind path. The song then played a file that might be a different recording, carrying its plays and chart history. This contradicted Import-1 ("never written").

When the song's own position on this edition is known (`track_number > 0`) and the file's differs, the importer now returns `possibleAlternateRecording` before any binding is considered, whatever the file state. A file at the same position still relinks or binds as before. No schema or Import Review change.

- **Unknown position:** a song listed on the edition with no known position (track 0, as restored or older listings can be) gives no positional evidence. A missing file there still relinks, so the recovery relink on a new device is unaffected.
- **Available file:** the reporting label is unchanged from round 4 (`atOtherPosition`).
- **First attempt:** the first version also blocked unknown positions. The full suite caught it with 4 failures in `recovery_audio_service_test.dart` (relink-only on a restored library); it was refined before committing.

The round 4 line "Existing songs … are never … relinked" was true only while the song's file was available. It now holds in every case.

Tests (`recording_identity_import_test.dart`, group "SN-50 F1"):
- missing file, other position: not relinked, and the song row and binding are unchanged;
- no file, other position: not bound;
- reported again on a later import;
- missing file, same position: still relinks;
- missing file listed with no known position: still relinks (recovery guard);
- no file, same position: still binds.

The three ambiguity tests fail on the pre-fix importer.

**F2 — duplicate queue keys, fixed.** `playback_queue_page.dart` keyed rows by `songId`. A song queued twice, which multi-select "Add to queue" makes easy, gave `ReorderableListView` duplicate keys.

The queue model has no per-entry identity: `PlaybackTrack` equality is by `songId`, and the persisted session, the engine and the media session are index-based. Adding an entry id would have changed the persisted queue, so rows are instead keyed by occurrence: `songId` for the first copy and `songId#n` for the nth. A distinct song keeps its key through moves, removals and display refreshes. The model, engine, persistence, media session and stream attribution are unchanged.

Tests (`playback_queue_duplicate_entries_test.dart`, real engine over the simulated player):
- rows render;
- an appended copy gets its own row;
- removing one copy, and removing the playing copy;
- dragging a copy;
- the screen-reader Move up action;
- tapping the later copy plays index 2.

All 7 fail on the pre-fix page.

**F8 — verified, no defect.** Activation of the refined Moments rules uses the approved mechanism:
- `MomentRulesActivation.buildApproved = bool.fromEnvironment('SONUS_MOMENTS_REFINED_APPROVED')` (`moment_rules_activation.dart`). Unapproved builds return `ChartMomentRules.legacy` and never read or write the store.
- A write-once, per-install marker, `charts.moments.rules_activated_utc` (`shared_preferences_moment_rules_activation_store.dart`). It is written once, read back before use, and never moved; an unreadable value is never replaced.
- One shared instance per process (`charts_scope.dart` `_deviceRulesActivation`).

The fixed `refinedFromUtc = DateTime.utc(2026, 11, 1)` was removed in `8d2cbfe`. `2026-11-01` now appears only as instants injected by tests. The two other dates in `charts_scope.dart` predate SN-50 (SN-34 weekly activation week, SN-45 all-time Moments) and are unrelated.

Tests: `moment_rules_activation_test.dart` (7) and `shared_preferences_moments_stores_test.dart`. BLOCKED #9 was stale and is updated.

Release note: no committed config sets the flag. `config/` holds only `sonus.dev.example.json`, so a release build uses the earlier rules until the flag is added (README).

**F3–F6 — investigated, documented, not implemented.** Each was confirmed by reading the code at the lines below. All are low severity.

| ID | Risk | Evidence | How it happens | Recommended correction |
|---|---|---|---|---|
| F3 | A credit-edit display refresh is lost if it lands during a queue edit | `just_audio_playback_engine.dart` `insertTrackAt` (`updatedQueue` built at :326, emitted at :331 after `await insertAudioSource`); same pattern in `removeTrackAt` (:367/:375) and `moveTrack` (:406/:414). `refreshTrackDisplay` (:339) emits synchronously. | Edit a queued song's credits while an insert, remove or move awaits the player. The stale `updatedQueue` overwrites the refreshed titles until the next library edit. | After the await, rebuild from the current `_state.queue` (apply the same insert, remove or move to it), or re-apply display fields before emitting. |
| F4 | Fast double taps on system Shuffle or Repeat lose a toggle | `sonus_audio_handler.dart:216-226` reads `c.currentState.shuffleEnabled` / `repeatMode.next` before awaiting the engine. | Two custom-action callbacks arrive before the first emit; both compute the same target. | Serialize custom actions on one `Future` chain, or track the pending target in the handler. |
| F5 | Play within the last second of the last song restarts it | `just_audio_playback_engine.dart:171-186` `_isAtEndOfQueue`: paused, no next, position ≥ duration − 1 s. | Repeat off, last song, pause at e.g. 2:59.4 of 3:00, then Play: it replays from 0:00 instead of finishing. | Use the 1 s allowance only after a restore seek (a flag set by restoration), or narrow it to about 250 ms. |
| F6 | Interrupted finalization; repository has no freeze check | `chart_finalization_service.dart:250-253` publishes Moments before `replaceSnapshot`. `sqlite_chart_repository.dart` `replaceSnapshot` checks only revision order, not `finalized_at`. | The app stops between the two writes. The next pass rebuilds the week from the library as it then is, and publish-once keeps the earlier Moments, so the stored week can disagree with them. Today only the service's `isFinalized` guard protects stored weeks. | One transaction for both writes, or skip publishing when the week has no snapshot and Moments already exist. Make the repository refuse to change a finalized week. Persistence change: needs authorization. |

**F7 — documentation reconciled (no code change).** Every Dart-side media-session behavior traces to an approved decision:

| Behavior | Commit | Approved decision |
|---|---|---|
| Shuffle and Repeat custom controls | `9547ef0` | D-Q1 |
| Visible Stop removed; End Session added | `9547ef0` | D-Q3 |
| End Session and dismissal keep queue and position | `9547ef0` | D-Q6 |
| Removing Sonus from Recents keeps state | `9547ef0` | D-Q10 |
| Repeat cycles Off → All → One | `9547ef0` | D-Q12 |
| Paused at the end of the queue, single count | `9547ef0` | D-Q16 |
| Finished queue persisted; Play replays the last song | `db79c4e` | R4, which resolves D-Q16's M-1 as option (a) |

- The D-Q16 row in the traceability file, marked "Partial, M-1 open", was stale and is updated.
- M-2 (End Session keeps the queue) matches the design's recommended option and D-Q6.
- M-3 (Dart-side changes) is covered by the decisions above.
- Still gated: vendor patches M-4 (wake lock) and M-5 (Android ≤12 actions), and device QA M-6. `third_party/audio_service` is unchanged since SN-49.

### Workflow (round 5)

- The main session made the F1/F2 changes and ran targeted tests: `test/features/import` (405 passed) and the new queue test (7 passed). Each new test was also run against the pre-fix file, which was restored byte-for-byte afterwards.
- Then `dart format` (clean) and `flutter analyze` (no issues).
- First full suite: 4,962 passed, 4 failed (recovery relink, see F1). After the refinement, `test/features/import` + `test/features/recovery` gave 782 passed, then a second full suite gave the result in the table.
- The seven registrant files (line-ending churn) were left as they were and not committed.

## Round 6 (2026-10-30): notes reconciliation, batches A–D

Authority: the user's approval of Batches A–D after `SN50_Original_Notes_Reconciliation.md` (35 requirements). No migration, history change, Trash, deletion, ringtone, plugin patch, device, cloud, push or merge.

| Commit | Batch | Full suite (`--concurrency=1`) |
|---|---|---|
| `8c8bffc` | A: edition names in Android Auto, Blacklisted, Library Health; reconciliation regression tests | 4,981 passed, 1 skipped, 0 failed |
| `a4085a5` | B: playback races F3, F4, F5 | 4,988 passed, 1 skipped, 0 failed |
| `11f30a7` | C: sync run queue bounded, one at a time, no stale accounts | 4,997 passed, 1 skipped, 0 failed |

**Batch A — display and regression tests.**
- Android Auto song rows now show the edition the song is listed on (`editionDisplayTitle`), as Now Playing does (`media_browse_catalog.dart`).
- Blacklisted rows (`albumDisplayTitle`) and the Library Health split-folder report (primary edition title read beside the stored title, `library_integrity_dao.dart` / `library_integrity_service.dart`) show the release the way current lists do.
- Stored album titles, analytics and chart history are unchanged (tested).
- New regression tests:
  - duplicate-song queue save;
  - albums without a disc number (import with disc 1 or 0, and a placement saved with disc 0 or 1, stay single-disc);
  - a refined release Moment shows the Deluxe cover while an earlier one keeps its cover (controller level);
  - self-replacement at #1 on the all-time song, all-time release and weekly release charts;
  - a weekly release re-entry at #160 (the #101–200 range) is a guaranteed story;
  - an Other edition rename persists through SQLite with `albums.title` unchanged.
- **Gap found, not fixed (scope):** restoring a queue whose current song is a later duplicate (e.g. `[a, b, a]` at the second `a`) resumes the **first** copy, because `PlaybackCoordinator.playTracks` re-finds the start track by song id (`playback_coordinator.dart:51-53`); the saved position is then applied to that copy. The restore test is skipped with this reason. See BLOCKED #22.
- Not covered by a new test: an all-time release re-entry at #101–200 (the harness cannot easily drop a release out of the cumulative chart); the weekly case is pinned.

**Batch B — playback hardening.**
- F4: system Shuffle and Repeat commands (custom actions and the absolute `setShuffleMode`/`setRepeatMode`) run one at a time in `SonusAudioHandler`, so a quick double tap toggles twice and three Repeat taps cycle Off → All → One → Off.
- F5: the one-second end allowance in `JustAudioPlaybackEngine._isAtEndOfQueue` applies only when the paused position was set by a seek while paused, as a restore is. A pause in the last second of playback now resumes there. R4 is unchanged: a completed queue, or one restored or sought to its last second, replays from 0:00.
- F3: after the player finishes an insert, removal or move, the engine re-applies the display fields the queue has at that moment, so a credit or title refresh that arrived meanwhile is kept.
- Tests: `system_controls_regression_test.dart` group "SN-50 reconciliation: playback races (F3, F4, F5)", 7 tests. Six fail on the pre-fix code; the R4 guard passes on both. No change to qualification, stream counts, queue persistence or plugin contracts.

**Batch C — sync controller stability (app side only).** The isolation model:
1. **One run at a time, really.** The next service run starts only when the previous one has **ended**, including a run the controller stopped waiting for. Two runs never write at once.
2. **Bounded runs.** A run that exceeds `SyncController.defaultRunTimeout` (10 minutes) is reported as a timeout (`SyncRunTimedOut`, kind `timeout`, "your changes are kept"), with retry pending and the pending count refreshed. The outbox is untouched. Its result, if it ends later, is never used, so it is never reported as a success.
3. **Bounded waits.** A request queued behind a run that has not ended gets an answer (`false`) within the same limit. The run keeps its place and starts when its turn comes, so no work is dropped.
4. **No stale accounts.** A run queued for an account that has since been signed out or switched away from is skipped, never signing that account back in. (Before, a queued run re-activated the signed-out account.)
5. `failureCode` is cleared with the failure (sign-out, account switch, `clearError`), as documented. Disposal cancels every time limit and makes in-flight runs stale.
- Tests: `sync_controller_test.dart` group "SN-50 reconciliation: bounded runs, one at a time" (9 tests): hang, timeout, late success and late failure, sign-out during a hung run then sign-in, a queued run after sign-out, rapid account changes, failure code, disposal. Only fakes; no Supabase contact. The pre-fix controller cannot compile these tests (no time-limit parameter), so a before/after run was not possible.
- **Inherent limit (documented, not a workaround):** the service cannot be cancelled, so a run that truly never ends keeps later runs waiting until it ends or the app restarts. The UI no longer stays on "Syncing", and nothing runs alongside it.
- **Design proposal (needs approval, not built):** cooperative cancellation. Pass a cancellation token from the controller through `SyncService._synchronize`, `OutboundSyncProcessor.pushPendingIsolated`, `InboundSyncProcessor.pullAll` and the archive sync. Check it before every remote request and before every local write batch, and make each local write batch transactional so a cancelled run stops between batches. After that, a timed-out run can be cancelled and replaced without overlapping writes. A distinct permanent-failure state (Session I, I-P1) would sit on top of it.

**Batch D — documentation.** This section; stale rows corrected and labelled in the traceability matrix, the QA report, the restart notes, earlier sections here (marked *Superseded*), and `SN50_Original_Notes_Reconciliation.md` (statuses updated).

## Round 7 (2026-10-30): duplicate-song restore (#22) and two design proposals

| Commit | Batch | Full suite (`--concurrency=1`) |
|---|---|---|
| `ec59045` | #22: a restored queue resumes the copy that was playing | **5,008 passed, 0 skipped, 0 failed** |

**#22 — fixed.**
- **Cause:** `PlaybackCoordinator.playTracks` re-found the start track by song id among the playable tracks, so `[a, b, a]` saved on the second `a` resumed the first copy, with the saved position applied to the wrong copy.
- **Fix** (`playback_coordinator.dart`, one block): the start is the requested entry's own place among the playable entries, i.e. the number of playable entries before it. For queues without duplicates this is the same index as before. An unplayable requested entry is still refused (`StateError`), never swapped for another song.
- **Restore** already maps the saved index by position (`playback_restoration_controller.dart`). An out-of-range saved index is rejected when the snapshot loads (nothing restored, nothing played). A saved song that is gone falls forward to the next playable entry at 0:00, paused.
- **Unchanged:** the queue persistence format, history, qualification, shuffle/repeat preferences and R4.
- **Tests:**
  - the round-6 restore test is unskipped;
  - `playback_coordinator_test.dart` group "SN-50 #22" (4 tests);
  - `playback_restoration_controller_test.dart`: dropped unplayable entry, gone song falls to the next copy, out-of-range index, finished queue on the second copy;
  - `system_controls_regression_test.dart`: restart resumes the second copy mid-song; a finished queue on the second copy replays that copy (R4).
- **Proof:** 8 of the new tests fail on the pre-fix coordinator. The 4 guards (unplayable start, out-of-range start, out-of-range saved index, finished-queue restore index) pass on both.

### Design proposal: cooperative sync cancellation (#23, not implemented)

**Goal:** a timed-out or obsolete run can be stopped and replaced without restarting the app, with no overlapping local writes, no lost unsent changes, and no writes for an account that is no longer active.

1. **Token.** `SyncController` creates a `SyncCancellation` per run, holding the run's `userId` and session epoch.
   - It is cancelled on timeout, sign-out, account switch or dispose.
   - It is passed through `SyncService._synchronize`, `OutboundSyncProcessor.pushPendingIsolated`, `InboundSyncProcessor.pullAll` and `CloudArchiveSyncService.synchronize`.
2. **Check points: only between atomic units, never inside one.**
   - **Outbound:** before each outbox entry is pushed, and before its acknowledgement transaction commits (`acknowledgeEntry`).
   - **Inbound:** before each page fetch, and inside each record's existing transaction as its first statement, so a cancelled run's transaction rolls back instead of writing.
   - **Archive:** between steps.
   - **Service:** between attach, push, pull and archive.
   - A cancelled check throws `SyncCancelled`, which the service reports as cancelled, never as success.
3. **No overlapping writes.**
   - The controller keeps today's rule: the next run starts only when the previous service future has ended.
   - Cancellation makes that end arrive at the next check point. That is within one HTTP timeout (connect 15 s, response 30 s, `TimedHttpClient`) plus one transaction, instead of never.
   - A run blocked on something with no timeout still holds the queue, as today. That is now the only case.
4. **Unsent changes are protected by the existing design.**
   - An outbox entry is removed only by its own acknowledgement transaction. A cancelled or interrupted entry stays pending and is pushed again.
   - Cloud writes are conditional on revision baselines, and artist writes are journalled (`recoverArtistWrites`), so a write that reached the cloud before cancellation is reconciled, not duplicated.
   - Inbound records commit one transaction at a time with their deferral ledger, so a cancelled pull leaves whole records only.
5. **Account changes.**
   - Sign-out or switch cancels the token at once.
   - Every write transaction compares the token's `userId` and epoch with the current binding, and refuses a stale one.
   - Queued runs for the old account are skipped (already true since round 6).
6. **Status.** A cancelled run reports nothing into the new account's state. For the same account it shows the timeout already used in round 6, with retry pending. A distinct permanent-failure state (Session I, I-P1) can sit on top.
7. **Tests (fakes only):**
   - cancel between outbound entries, and during an entry before its acknowledgement;
   - cancel mid-page;
   - sign-out mid-run;
   - a replacement run starts only after the cancelled one ends;
   - unsent entries remain;
   - no success is reported.
8. **Scope:** sync service and processors only. No schema, cloud or server change.

### Design proposal: atomic chart finalization (F6, not implemented)

**Goal:** a finalized week's snapshot and its published Moments are written together or not at all, and nothing already stored is ever rewritten.

1. **One transaction for both.** `ChartFinalizationService._reconcileWeek` builds the snapshot and detects its Moments in memory, as today. It then calls one repository method, `finalizeWeek(snapshot, events)`, which runs a single SQLite transaction that:
   1. re-reads the stored week inside the transaction and stops, writing nothing, if it is already finalized;
   2. inserts the snapshot and its entries;
   3. inserts the Moments with the existing `ON CONFLICT(deduplication_key) DO NOTHING`, only if the week has no finalized Moments yet;
   4. commits.
   - The restore-generation check (`_ensureNoRestoreSince`) runs immediately before the transaction, and the write goes through the library mutation coordinator, so a restore can never interleave.
2. **Freeze in the repository.** `SqliteChartRepository.replaceSnapshot` (and the new method) throws when the stored row has `finalized_at IS NOT NULL`. The service guard stays as well.
3. **Existing history is never rewritten.** No migration and no repair. A week left by the old order, with Moments published but no snapshot, is finalized by the next pass with its snapshot only. Its published Moments are kept as they are (publish-once already refuses to add to them), and the mismatch is logged, not corrected.
4. **Tests (disposable databases):**
   - a failure injected after the snapshot insert leaves neither the snapshot nor the Moments;
   - a failure after the Moments insert leaves neither;
   - a second pass on a finalized week writes nothing;
   - `replaceSnapshot` on a finalized week throws;
   - a pre-existing Moments-without-snapshot week keeps its Moments byte-identical;
   - the restore races (`chart_finalization_restore_test.dart` 1b/2a/2b) still hold;
   - the freeze suite stays row-identical.
5. **Scope:** chart repositories and finalization service. No schema change. It changes how future weeks are written, so it needs the persistence authorization noted in F6.

## Round 8 (2026-10-30): F6 atomic finalization and #23 cooperative sync cancellation

Authority: the user's approval of the Round 7 designs. No schema change, migration, backfill, history rewrite, cloud contact, device access, push or merge.

| Commit | Batch | Full suite (`--concurrency=1`) |
|---|---|---|
| `9ef4717` | 1: F6, a finalized week and its Moments in one transaction | 5,022 passed, 0 failed |
| `48c2714` | 2: #23, cooperative sync cancellation | 5,036 passed, 0 failed |

**Batch 1 — F6.**
- **Atomic write:** `ChartWeekFinalizer` (domain), implemented by `SqliteChartRepository.finalizeWeek`. One `AppDatabase.transaction`, which goes through the restore coordinator:
  1. re-read the week; if it is already finalized, return it as stored and write nothing;
  2. write the snapshot and its entries;
  3. publish the Moments only if the week has none.
  - A week left by the earlier two-step order, with Moments but no snapshot, gets its snapshot. Its Moments are kept byte-identical and the case is logged (`sonus.charts`), never repaired.
  - Moments are validated before the transaction, so the restore admission check still has no await before it.
- **Freeze:** `replaceSnapshot` throws `FinalizedChartWeekFrozen` for a finalized week.
- **Wiring:** `ChartFinalizationService` takes an explicit `weekFinalizer`, and `charts_scope.dart` passes the SQLite repository. Test doubles that cannot share a transaction keep the earlier two-step path.
- **Tests:**
  - `sqlite_chart_repository_test.dart` "SN-50 F6" (9):
    - both written by one call;
    - an entry-write failure rolls back everything;
    - a Moment-write failure rolls back the snapshot;
    - an already-finalized week writes nothing;
    - legacy Moments without a snapshot are kept exactly;
    - Moments for another week are refused;
    - an unfinalized snapshot is refused;
    - a held restore writes nothing;
    - `replaceSnapshot` on a finalized week throws.
  - `chart_finalization_restore_test.dart` "SN-50 F6: one transaction per finalized week" (5): repeated passes write nothing; a restore during Moment detection, during the build, or at admission writes nothing; legacy recovery.
  - Three revision tests now start from an unfinalized stored week, so revision rules keep their coverage without rewriting a frozen week.

**Batch 2 — #23.**
- **Token:** `SyncCancellation` (`sync_cancellation.dart`) is one token per run, carried as a zone value through everything the run starts. `SyncCancellation.checkpoint()` throws `SyncCancelled` once the run is cancelled, and does nothing outside a run.
- **Cancelled by** `SyncController` on timeout, sign-out, a switch to another account, and dispose.
- **Safe points only, never inside a unit:**
  - `SyncService`: between its steps.
  - Outbound: before the journal recovery and before each entry. An entry's cloud write and its acknowledgement always complete together.
  - Inbound: before each entity type, page and deferred-replay record. Also the first and last statements inside each record's transaction, so a run cancelled meanwhile rolls the record and its cursor back whole.
  - Archive: before each record and page.
  - `SyncCancelled` is never swallowed by a per-record retry (`replayDeferred`) or the archive error capture.
- **No overlapping writers:** unchanged from round 6. The next run starts only when the previous service run has ended. It now ends at its next safe point instead of never.
- **Unsent changes:** an outbox entry is removed only by its own acknowledgement, and an interrupted cloud write is reconciled by the existing lost-response path. Tested: the cancelled entry stays pending and the next run sends it once.
- **Old accounts:** a sign-out or switch cancels at once, so no unit starts for the old account afterwards. A unit already in flight finishes whole, then nothing follows. Queued runs for the old account are skipped (round 6).
- **Never a false success:** a cancelled or timed-out run's result is never used.
- **Remaining limit:** a run blocked on an await with no timeout of its own (not HTTP) still holds the queue until it ends or the app restarts.
- **Tests:**
  - `sync_controller_test.dart` "SN-50 #23" (6): a timed-out run stops so a retry starts at once and never alongside it; sign-out stops writes; an account switch stops the old run before the new account syncs; a late response finishes its unit whole and nothing follows, never a success; dispose; a safe point outside a run is a no-op.
  - `sync_service_test.dart`: a cancel during the push stops before the pull.
  - `outbound_sync_processor_test.dart` "SN-50 #23" (3): a late response finishes entry 1 with its ack while entry 2 stays pending; the next run sends it; nothing is cancelled outside a run.
  - `inbound_sync_cancellation_sqlite_test.dart` (3, real SQLite): a cancel inside a record's transaction rolls that record and its cursor back while earlier ones stay; a page arriving after cancellation applies nothing; the next run resumes from the last committed record.
  - `cloud_archive_sync_service_test.dart` "SN-50 #23": stops after the first record; a later run sends the rest exactly once.
  - The controller tests passed in 4 of 4 repeated runs.
- Known flake: during a targeted sync/settings/account run on a stalled machine (6.5 min instead of about 1), `supabase_sync_resilience_test.dart` "after a timeout, the next attempt succeeds" timed out once. It waits on real HTTP timeouts and never reaches a safe point; it passed 3 of 3 alone and in the full suite.

## Round 9 (2026-10-30): playback controls, shuffle order, paused sync, Import Review, chart jumps

Authority: the user's approval of Batches A–E (based on `SN50_Decision_and_Release_Checklist.md`, which stays uncommitted as asked). No migration, real-data change, cloud operation, plugin patch, device access, push or merge. The refined Moments flag stays off.

| Commit | Batch | Full suite (`--concurrency=1`) |
|---|---|---|
| `e3dd5f5` | A: Repeat One navigation (A1); Clear queue (A2) | 5,049 passed, 0 failed |
| `207e65d` | B: exact shuffled order restored with Remember (#24, option C) | 5,058 passed, 0 failed |
| `5c0071b` | C: paused sync for a cloud not ready for this version | 5,067 passed, 0 failed |
| `2af3a8b` | D: Import Review for possible different recordings (#19, option B) | 5,098 passed, 0 failed (one run for D and E together) |
| `cc680e8` | E: chart-jump detection, held for copy approval | same run |

**A1 — Repeat One.**
- just_audio's `nextIndex` returns the current item under `LoopMode.one`, so an explicit Next only restarted the song.
- `PlaybackAudioPlayer.adjacentIndex` now gives the entry one step away in play order, shuffle included, as if Repeat One were off; Repeat All still wraps.
- Under Repeat One the engine's Next and Previous seek to it, and the loop mode stays One. Previous keeps restart-after-3 s. At the queue's edge Next stays, as without Repeat One.
- The simulated player now models just_audio's Repeat One rule.
- Tests: `system_controls_regression_test.dart` "SN-50 A1" (7) plus a restart test. 5 fail on the old engine.

**A2 — Clear queue.**
- `PlaybackCoordinator.clearQueue` removes every entry except the one playing, recomputed step by step from the live queue. Playback and position are kept.
- The Queue screen has a confirmed "Clear queue" action, disabled with nothing to clear.
- The saved session follows, so cleared songs never return after a restart (tested). Songs, files, history and playlists are untouched; End Session is separate.
- The simulated player now shifts its current index when an earlier item is removed, like just_audio.

**B — exact shuffle order (#24).**
- `PlaybackSessionSnapshot` gains an optional `shuffleOrder` **inside version 1**: older builds ignore it, and an unusable value is dropped while the session is kept.
- The real engine implements a new optional `ShuffleOrderPlayback` capability, so the 30 engine test doubles are unchanged. Restoring passes a `RestoredShuffleOrder` to just_audio's `setAudioSources(shuffleOrder:)`; the first fill lays down the saved permutation, and later edits behave like `DefaultShuffleOrder`.
- The order is applied only if shuffle is on at restore, which only Remember does; with Remember off nothing changes. Songs that are gone are left out and the rest keep their saved relative order. Duplicates keep their places.
- Tests: snapshot format (3) and restart tests (6) with an opt-in shuffle model in the simulator.
- **Device-only:** the notification, lock-screen and Android Auto Next/Previous order after a restart.

**C — paused sync.**
- New `SyncFailureKind.cloudNotReady` (`isPermanent`) for clear contract failures only:
  - PostgREST missing table, column or function: `42P01`, `42883`, `42703`, `PGRST202`, `PGRST204`, `PGRST205`;
  - a conditional-write reply without a valid revision or outcome: `CloudContractMismatch`, which still extends `StateError`.
  - Never because a failure repeated.
- `SyncStatus.paused` is stored per account (`SyncStatusStore` `sync.paused.<user>`), so it survives sign-out and sign-in without leaking to another account. Only a successful run clears it.
- Automatic triggers skip while paused. The card's button retries (`trigger(retry: true)`) and shows Sync paused, the reason and code, Retry, the pending changes and the last sync time.
- Consent, the outbox, serialization and cancellation are unchanged.
- Tests: classifier (3), controller (5), card (1).

**D — Import Review for possible different recordings (#19, option B).**
- A device-local pending list in SharedPreferences (`PossibleRecordingStore`, keys `import.possible_recordings.*`): one entry per path, so rescans never duplicate. Unreadable data is ignored.
- `LibraryImportService` records each `possibleAlternateRecording` result. A file the user marked "Same recording" (path + song + length) is reported as `duplicateRecording`; a replaced file with another length is reported again.
- Import Review shows "Possible different recordings" with three actions:
  - **Import separately:** re-checks the path, the candidate song and the file's tags, then uses `AtomicLibraryImporter.import(separateFrom:)`. That only turns a still-ambiguous match into the existing evidence-based alternate-recording path: a new song flagged `alternateRecording`, with the candidate's rows unchanged (tested row by row).
  - **Same recording:** remembers the choice; nothing is written.
  - **Not now:** hides the entry for this visit.
  - Missing, already-bound, deleted-candidate and changed-tag cases write nothing and retire the entry with a message.
- Tests: store (6), service (13), widget (5).
- **Open:**
  1. Wording of the section, actions and messages (`import_review_page.dart` ~:381–430). The Imports card still says "N songs need review", and N now includes pending files.
  2. A file whose tags cannot be read (path-only metadata) counts as unreadable; there is no existence check that also covers SAF content:// paths. *Resolved in Round 10 (`49c6188`).*
  3. Moved files are retired when acted on or when the new path imports; there is no automatic clean-up during scans. *Round 10 (`49c6188`): a missing file is retired when Import Review reads its list.*
  4. `_isPossibleAlternate` repeats the importer's position rule rather than refactoring the import path.

**E — chart-jump storytelling.**
- `MomentStoryPlanner.copyGated` now also holds:
  - `hot100MajorClimb` (`#hot-100-jump`): a weekly Hot 100 climb of 25+ places;
  - `hot100ClimbRun` (`#hot-100-run`): 3+ consecutive weekly Hot 100 climbs totalling 30+ places.
- Each carries `ChartJumpFacts`: from and to rank, weeks, places gained, this week's qualified streams, last week's (verified only) and the stream gain. Positions and streams are separate facts.
- History is the stored finalized rank events, matched by week end (exact across daylight-saving changes) and by rank, so missing history never counts.
- Bubbling Under moves and BU→Hot 100 arrivals are never jumps. Weeks before activation hold nothing.
- **Nothing is published:** no headline was added, the 384 originals are unchanged, and the flag stays off. *Superseded by Round 10 (`ae0fd05`): the approved jump and run stories are told under the refined rules; the flag is still off.*
- Drafts: `SN50_Chart_Jump_Editorial_Approval_Sheet.md` (CJ-001 to CJ-041) with six decisions (thresholds, release scope, biggest-gainer overlap, jump/run overlap, publisher, streaming sentence).
- **No new persistence was needed.** Runs cannot reach before the first recorded Moments week.
- Tests: `bubbling_under_moments_test.dart` "SN-50 Batch E" (7).

## Round 10 (2026-10-30): approved chart jumps, approved-family guard, Import Review file states

Authority: the user's approval of Batch 1 (chart-jump copy, thresholds and overlaps; the approved-family guard) and Batch 2 (the non-destructive `content://` correction), and the round 10 review accepting both. No migration, schema change, real-data change, cloud operation, plugin patch, device access, push or merge. **The refined Moments release flag stays disabled** (#21).

| Commit | Batch | Full suite (`--concurrency=1`) |
|---|---|---|
| `ae0fd05` | 1: approved chart-jump headlines; fail-closed approved-family guard | **5,105 passed, 0 failed, 0 skipped**, exit code 0 |
| `49c6188` | 2: Android Import Review file states (`content://`) | **5,134 passed, 0 failed, 0 skipped**, exit code 0 |

Analyzer clean and formatting clean for both. The Batch 1 run took 158 minutes because the machine entered modern standby three times (Kernel-Power 506/507); the tests did not hang.

**Implementation complete; device QA pending.** Both batches are verified by unit, widget and disposable-SQLite tests only. The SAF behaviour of Batch 2 still needs the device check (M-6).

**Batch 1: chart jumps (supersedes Round 9 E "Nothing is published").**
- New families `songHot100MajorJump` and `songHot100ClimbRun`, told only under the refined rules (so not in release builds while the flag is off):
  - **major jump:** both ranks #1–100 and a weekly climb of 25+ places. Publisher PulsePop. Capped like a minor story unless it finishes in the Top 40;
  - **climb run:** 3+ consecutive verified weekly Hot 100 climbs worth 30+ places. Publisher Sonus Daily. Outside the daily cap.
- Overlaps: a run replaces a jump in the same week; no jump story when the song is the week's biggest gainer, or when an approved #1, zone, peak, breakthrough or self-replacement story already tells the move. A held draft never suppresses a jump, so the move is never left untold. Songs only.
- Copy: CJ-001 to CJ-031 as approved, with the revised **CJ-010**, **CJ-011** and **CJ-028** lines. The body streaming sentence is the revised **CJ-040** ("The song earned N qualified streams in the finalized chart week, G more than the preceding week.") or CJ-041. It appears only when the previous week is verified, this week has at least 10 qualified streams (`MomentFacts.notableStreams`) and the gain is positive. Kicker: BIG CLIMB.
- `GatedMomentKind.hot100MajorClimb` / `hot100ClimbRun` are replaced by the planned families; `ChartJumpFacts` moved to `chart_jump_facts.dart`.

**Batch 1: approved-family guard.**
- `MomentHeadlines.approvedFamilies` is fail-closed: 34 of 43 families. The nine SN-50 draft families stay out: `songSelfReplacement`, `releaseSelfReplacement`, `songFirstThreshold`, `releaseFirstThreshold`, `songThresholds`, `releaseThresholds`, `artistRepeatNumberOne`, `artistRepeatNumberOneRelease`, `artistSimultaneousReleases`.
- `MomentEditorialDesk.compose` skips a planned story outside the set **before** its facts or headline are built, so the neutral fallback headline can never publish a draft. The story is listed as held (`GatedMomentKind.unapprovedCopy`, keeping its planned id and family).
- Effect: under the refined rules, the N-2 to N-6 stories (thresholds, self-replacement, repeat #1, release roundups) are now held instead of published with draft copy. Legacy and pre-activation stories are unchanged.
- Composition only: no repository, finalization or schema change. Finalized charts and published Moments are only read.
- Tests (11 new or changed): `bubbling_under_moments_test.dart` "SN-50 chart jumps (approved CJ-001 to CJ-041)"; `moment_editorial_test.dart` six approved lines per publisher, exact revised renderings, "only approved families can publish"; `moments_reachability_test.dart` "with the SN-50 rules: 22 approved families publish…".

**Batch 2: Import Review file states (closes Round 9 D open points 2 and 3).**
- Typed read failures: `ImportFileMissing`, `ImportFileAccessDenied` (from the SAF v2 `SafNotFoundException` / `SafPermissionException`) and `ImportTagsUnreadable` (still a `FormatException`). `MetadataResolver` falls back exactly as before and records `ResolvedMetadata.readFailure`.
- `ImportFileProbe` / `LocalImportFileProbe`: read-only (`File.exists`; `Saf.exists` plus persisted read grants for `content://`). It never deletes, moves, renames or writes.
- Decisions in `PossibleRecordingReviewService`:
  - missing → retired, as before; also retired when Import Review reads its list (instead of during scans);
  - permission lost → **kept**: "Sonus can't read this folder any more. Reconnect it in Imports.";
  - could not check, or an unexplained read failure → **kept**: "Could not check this file. It stays in this list. Try again.";
  - unreadable tags → imported separately only if the entry was itself recorded from its path; otherwise retired as before. The candidate song's rows stay unchanged (tested).
- **Approved compatibility decision:** pending entries carry an optional `metadataSource` key in the device-local SharedPreferences JSON (`import.possible_recordings.pending`). Older entries without it are read as tag-based. This is **not** a SQLite migration and does not change backup or cloud formats; no backup or sync code reads these keys.
- Both messages are **approved** (round 10 review).
- Tests (29 new): `metadata_resolver_test.dart` "read failure kind" (6), `local_import_file_probe_test.dart` (10, fakes and a temporary directory only), `possible_recording_review_service_test.dart` "unreachable files" (11), `import_review_possible_recordings_test.dart` (2).

**Housekeeping.** `dart format` had reformatted `song_import_review_dao.dart` and `import_batch_record.dart` during Batch 2. Verified formatting-only (identical to `dart format` of the committed content, apart from checkout line endings) and restored to their committed contents, as approved. The seven registrant files and the two uncommitted review documents are preserved.

## Round 11 (2026-10-31): refined headline isolation (Batch 0) and completed-week wording (Batch 1)

Authority: the user's instruction to continue Batches 0 and 1 of `SN50_Final_Editorial_Approval_and_Implementation_Contract.md`, taken as approval of Batch 0 and of contract items P-003 (Option A), P-004, P-005 and P-006 ("the week before"), and P-007 to P-009, exactly as written. The rest of the contract is unapproved. Phone check: date-trigger risk RESOLVED for the user's phone (see `SN50_A0_Safety_Handoff.md`); global A-0 INCONCLUSIVE. The refined flag stays off.

| Commit | Batch | Full suite (`--concurrency=1`) |
|---|---|---|
| `f8088b8` | 0: legacy and refined headline views; goldens | **5,147 passed, 0 failed, 0 skipped**. The wrapper shell was stopped for low memory; the test process ran to completion and printed "All tests passed!" (exit code not captured) |
| `b0f17c4` | 1: completed-week wording for refined stories | **5,152 passed, 1 failed** (exit code 1). The failure was `supabase_sync_resilience_test.dart` "a server that never answers ends the sync as a timeout": the documented sleep flake. Kernel-Power 506/507 show repeated standby during the 221-minute run. Rerun alone: 4/4 passed. Batch 1 touches no sync code. |
| `97687a3` | 2: refined corrections P-001, P-002, P-010 to P-023; §6.4 guest exclusions (14); P-051 | **5,160 passed, 0 failed, 0 skipped, exit code 0** (captured; run held awake by a per-process `SetThreadExecutionState` request; no standby events) |

**Batch 0 (`f8088b8`).**
- `MomentHeadlines.legacyOf` is the catalog exactly as published; stories under the earlier rules (legacy and before activation) read only it. `MomentHeadlines.of` is an alias of it.
- `RefinedHeadlineCatalog` (new) serves refined stories: approved overrides in place (same id and position), approved exclusions (optionally conditional), approved additions appended. Unapproved entries are inert.
- Goldens captured at `f062551` before any change: `goldens/legacy_catalog_v1.json` (431 lines: id, order, publisher, needs, text) and `goldens/legacy_moments_v1.json` (376 stories over 32 families; weekly and career; with and without a featured performer). They must match under the legacy rules, before activation, and with a stored marker while the flag is off (the marker is not read). Written only when missing.
- A temporary refined snapshot (not committed) was byte-identical before and after Batch 0.

**Batch 1 (`b0f17c4`).** Refined stories only:
- `MomentFacts.chart` names "the weekly Sonus Hot 100 / Bubbling Under / Albums & EPs chart" (P-003, P-004);
- the previous-position body returns as "… was at #N the week before" / "… the week before, its best until then." (P-005, P-006);
- `song-gainer-d6`, `song-gainer-p6` and `artist-sim-p4` use their refined overrides (P-007 to P-009).
- Legacy goldens unchanged. The refined before/after comparison shows only 88 headlines ("this week's" → "the weekly") and 64 restored "the week before" sentences.

## BLOCKED_NEEDS_APPROVAL / user decisions

**[Round 10]** #25 is resolved and #27 is partly resolved (see each item). #12, #17 and #21 remain release blockers. Items are kept in their historical form, with corrections marked.

1. **DB v41 on real devices.** The migration runs on a phone's real database the first time a build containing `2a10990` is installed. Take a `.sonusbackup` before any install. Installing is a separate approval.
2. **B-Q19.** Release Leaked rides in the cloud-archive row automatically, like Live, and the archive isn't deployed, so there is no exposure today. A client older than v41 receiving a row that holds only Leaked would fail its local CHECK, the same issue Live has for clients older than v40. Cloud activation is a separate approval.
3. **Edition delete while signed out.** The `primaryInCloud` gate checks only the signed-in user's baselines. Closing that gap needs a sync-code change, which needs approval.
4. **Placement edits never queued.** Track Studio placements made before `e4027e7` can still be reverted by an inbound copy (fixing this would need a re-queue repair, which needs approval).
5. **A-Q7D numbering repairs.** Previewed individual repairs of existing gapped editions are not built yet.
6. **Open question (A-Q12).** In an edition view, should a song's custom artwork or the edition cover come first? Currently the song's custom artwork wins.
7. **Editorial proposal.** P-001 to P-050 and N-1 to N-7 await line-by-line approval, plus the four open questions in its §6.
    - **[Round 11]** P-003 to P-009 (`b0f17c4`), P-001, P-002, P-010 to P-023, the §6.4 guest exclusions and P-051 (`97687a3`) are done for refined stories. Open: `song-weeks-p5` (a guest-dropping line missed by §6.4) and six chart-jump lines with the same problem need decisions. The rest is in `SN50_Final_Editorial_Approval_and_Implementation_Contract.md`, unapproved.
8. **E-Q19 remainder.** Should finalized weeks also exclude songs and albums no longer in the local library? If yes, plays synced from another device for songs not imported locally would drop out of new finalized weeks, and the SN-32 test "finalized history uses playback-session identity even when song is no longer in library" changes meaning.
9. ~~**Moments gate date.**~~ **Resolved by `8d2cbfe` (R2), verified in round 5 (F8):** there is no fixed date. Activation needs the `SONUS_MOMENTS_REFINED_APPROVED=true` build flag plus the write-once per-install marker. What remains is item 21.
10. **Major-zone noise.** A jump straight to #1 can yield the #1 story, Top 2/3/5/10 stories and a consolidated story (6–7 stories). Should majors below the final major be folded into one?
11. **Old-story repair.** Should already-published stories get the rival fix and the "this stream" removal? That counts as a historical repair, which needs separate approval.
12. **New template copy.** The 27 new lines (families N-2 to N-6, listed in the 6a report and `moment_headlines.dart`) are drafts awaiting approval and expansion to 6+6 lines.
    - **[Round 10]** Still a release blocker. Since `ae0fd05` the nine draft families are outside `MomentHeadlines.approvedFamilies`, so even under the refined rules they are held (`unapprovedCopy`), never published. A family publishes only once its lines are approved and it is added to the set.
13. **Destructive workflows.** Approve or adjust `SN50_Destructive_Workflows_Design.md` §6 items A-T0 to A-T6 (Trash and purge), P-1 to P-5 (Delete from Phone), R-1 to R-3 (ringtones) and M-1 to M-6 (media session, plugin patches 2/3, device QA).
14. **M-2/M-3 confirmation.** `9547ef0` implemented End Session (keeping the queue) and the Dart-side media-session changes under the approved D-Q3/D-Q6/D-Q1 decisions. The destructive-workflows design doc had listed them as approval items, so please confirm or ask for changes. Device QA and plugin patches were not done.
    - **Round 5 (F7):** reconciled in documentation. Every behavior traces to an approved D-Q decision or R4, and M-1 is resolved by R4 (`db79c4e`).
    - An explicit M-2/M-3 sign-off remains yours to give.
    - M-4/M-5 (vendor patches) and M-6 (device QA) stay gated.
15. **Round 2 decisions to confirm:**
    - ~~F-Q7 1,000-stream threshold~~: **approved** (handoff rule 6) and pinned by tests in round 4.
    - The BUG-01 mirror policy, which changes C-Q4.
    - ~~Import-1 identity policy~~: **decided** (handoff rule 5). The Review part is blocked; see item 19.
16. **`SN50_Additional_Bug_Tweaks_Addendum_v2.md` was referenced but not found** (again in round 3). BUG-05 was implemented from the user's message.
17. **[Round 10: still open; release blocker]** **BUG-04 copy** (selection rules approved in round 4; wording is not): **see `SN50_BUG04_Editorial_Approval_Sheet.md` BU-001 to BU-071.** It supersedes the N-8 to N-11 samples. Earlier note: Editorial §7 N-8 (Hot 100 → Bubbling Under drop, proposed rule: Top 40 peak or 5+ Hot 100 weeks), N-9 (extra Bubbling Under climb, proposed: 25+ places, at most one a week), N-10 (recommend no story for falls within Bubbling Under), N-11 (optional arrival wording citing last week's Bubbling Under rank), and the §7.2 review of `song-break-p3`.
18. **BUG-03 type label:** keep deriving the Other label from the name, or approve a schema change for a stored custom type label.
19. ~~**Import Review persistence for ambiguous same-title files**~~ **Done as option B (device-local list, no migration) in `2af3a8b` (round 9); wording and the open points in Round 9 D remain.** (round 4): it needs a pending-file record, or a new review reason plus a file-path payload. Either is a schema/data-contract change. Until approved, these files are reported in the import result only.
    - Since round 5 (F1), this also holds when the existing song's file is missing or absent.
20. ~~**Audit hardening F3–F6**~~ **Done:** F6 in `9ef4717` (round 8). (round 5; F6 design in Round 7): F3, F4 and F5 are fixed in `a4085a5` (round 6). **F6** (finalization transaction and repository freeze check) remains: a persistence change needing approval.
21. **Refined Moments release flag:** no committed config sets `SONUS_MOMENTS_REFINED_APPROVED`, so release builds use the earlier rules until it is added to the release config, once the rules are approved for release.
    - **[Round 10]** Still disabled and still unset in every config. Not to be enabled while #12, #17 and the other unapproved editorial items stand.
22. ~~**Duplicate-song restore start**~~ **Fixed in `ec59045` (round 7).** (round 6): restoring `[a, b, a]` at the second `a` resumes the first copy (`playback_coordinator.dart:51-53` re-finds the start by song id). A safe fix would pass the index through for restores, without a format change. Not done because it was outside the approved batch scope; its test is skipped with the reason.
23. ~~**Sync cooperative cancellation**~~ **Done in `48c2714` (round 8).** A distinct permanent-failure state (Session I) is still open. (round 6): the design proposal in Round 7 (refines Round 6 Batch C), so a hung run can be replaced without a restart; plus a permanent-failure state (Session I).
24. ~~**Shuffle order persistence**~~ **Done as option C in `207e65d` (round 9).** Device check of system-control order still pending. (round 6 reconciliation): the shuffle permutation is never saved, and shuffle/repeat survive a restart only with "Remember". Keep, or persist by default?
25. ~~**Chart-jump copy and thresholds**~~ **Approved and implemented in `ae0fd05` (round 10)**, refined rules only. (round 9): `SN50_Chart_Jump_Editorial_Approval_Sheet.md` CJ-001 to CJ-041 and its §D decisions.
26. **Paused-sync wording** (round 9): the `cloudNotReady` message and the "Sync paused" and "Retry" labels.
27. **Import Review wording and SAF existence check** (round 9 D, open points 1–3).
    - **[Round 10]** SAF existence check done in `49c6188`; its two new messages are approved. Still open: the rest of the Import Review wording (round 9 D point 1, `SN50_Round9_Editorial_and_Release_Safety_Review.md` §5: 17 strings and the Imports "N songs need review" count), and the device check of real SAF behaviour (M-6).
28. **R-V: versioned refined headline catalogs** (2026-10-30, A-0 follow-up): required before `SONUS_MOMENTS_REFINED_APPROVED` is ever enabled, so refined stories already shown keep their headlines when the catalog grows. A-0 (whether any build ever ran refined rules) is INCONCLUSIVE; see `SN50_A0_Build_History_and_Historical_Rendering_Verification.md` and its addendum, including the date-gated builds of 2026-10-29 02:09–16:25 EDT that activate on 2026-11-01 00:00 UTC.

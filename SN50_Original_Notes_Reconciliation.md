# SN-50 Original Notes Reconciliation

**Checkpoint:** branch `sn-50-final-refinement`, HEAD `426b7c2` (code `420d5d5`). Last full suite: 4,967 passed, analyzer clean. SN-49 is protected at `36d4d5d`.
**Date:** 2026-10-30. **Mode:** read-only for application code. This report is the only file created. No tests were run for it: the evidence is source inspection plus existing test names.
**Inputs read in full:** `SN50_Progress.md`, `SN50_QA_Report.md`, `SN50_Restart_Instructions.md`, `SN50_Decision_Traceability.md`, `SN50_BUG04_Editorial_Approval_Sheet.md`. Originals cross-checked where wording was needed: `Documents\Sonus-Historical-Documents-20261030-075431\` (Master Spec §G–I, Product Decision Register Sessions H/I, Moments Editorial Catalog §7).

## Round 6 update (2026-10-30, after the approved Batches A–D)

The sections below are the original reconciliation at `426b7c2`, with statuses changed where round 6 changed the facts. Changes are marked **[Round 6]**.

| Batch | Commit | Result |
|---|---|---|
| A: edition names in Android Auto, Blacklisted, Library Health (D1, D6); regression tests | `8c8bffc` | Done. One new gap found and pinned by a skipped test (duplicate-song restore start, Progress BLOCKED #22). |
| B: playback races F3, F4, F5 (D3–D5) | `a4085a5` | Done. 7 tests; 6 fail on the pre-fix code. R4 kept. |
| C: sync run queue (D2) | `11f30a7` | Done, with the isolation model in Progress Round 6: one service run at a time, bounded runs and waits, no stale accounts. A run that never ends still holds later runs until it ends or the app restarts; cooperative cancellation is a design proposal (BLOCKED #23). |
| D: documentation | docs commit | Stale statements corrected and labelled (§5). |

Last full suite: **4,997 passed, 1 skipped, 0 failed**, analyzer clean.

**[Round 7]** `ec59045` fixes the duplicate-song restore gap (#35, BLOCKED #22); the skipped test runs again. Full suite **5,008 passed, 0 skipped, 0 failed**. Design proposals for sync cancellation (#33 residual, BLOCKED #23) and atomic finalization (F6) are in `SN50_Progress.md` Round 7.

**Status changes:** #11 UNVERIFIED → COMPLETE; #14 PARTIAL → COMPLETE; #33 PARTIAL → COMPLETE (app side). Gaps narrowed: #1 (controller test added), #6 (Auto, Blacklisted, Library Health done), #20 and #27 (tests added), #35 (F3–F5 fixed; new restore gap found).

## Round 9 update (2026-10-30)

- **#35** (queue, persistence, media controls): Repeat One navigation and Clear queue (`e3dd5f5`), and the exact shuffle order (`207e65d`), are done. Still PARTIAL only for device QA (M-6) and the vendor patches (M-4/M-5).
- **#33** (Account & Cloud): a permanent failure now pauses sync, with Retry, pending changes and the last sync time (`5c0071b`). Wording approval pending.
- **#34** (ambiguous recordings): now in Import Review, through a device-local list with no migration (`2af3a8b`): **COMPLETE** in function. Wording and a SAF existence check are open.
- **#22 / #30** (thresholds and chart movement): chart jumps and climb runs are detected and held for copy approval (`cc680e8`, `SN50_Chart_Jump_Editorial_Approval_Sheet.md`).
- **Counts after round 9:** COMPLETE 17 (adds #34); PARTIAL 9; UNVERIFIED 1; BLOCKED 5; NOT IMPLEMENTED 3.

## Round 10 update (2026-10-30)

Code `ae0fd05` (5,105 passed) and `49c6188` (5,134 passed), both 0 failed, 0 skipped, exit code 0. Implementation is complete; device QA is pending. The refined Moments flag stays disabled.

- **#34** (ambiguous recordings): the SAF existence check is done (`49c6188`). A file Sonus lost permission for, or could not check, stays listed; only a missing file is retired, also when the list is read. The optional `metadataSource` key in the device-local list is approved (no SQLite, backup or cloud change). Its two new messages are approved. Still open: the rest of the Import Review wording (Progress BLOCKED #27) and the device check (M-6). Stays COMPLETE in function.
- **#22 and #27** (thresholds, self-replacement): still BLOCKED. *Correction to §4 "22 and 27 are code-complete but print unapproved draft copy":* since `ae0fd05` they no longer print it. The approved-family guard holds the nine draft families (N-2 to N-6) even under the refined rules, so nothing unapproved can publish; they need their 6 + 6 lines approved.
- **#22 / #30** (chart movement): Hot 100 jumps (25+ places) and climb runs (3+ weeks, 30+ places) now publish with approved copy under the refined rules (`ae0fd05`). The Bubbling Under falls and exits of #30 remain gated on the BUG-04 sheet (BU-001 to BU-071): a release blocker.
- **Counts after round 10:** unchanged (COMPLETE 17; PARTIAL 9; UNVERIFIED 1; BLOCKED 5; NOT IMPLEMENTED 3).

## How to read this

- **Authority.** The source code and the existing tests decide each status. Where a document disagrees, the document is stale; see §5.
- **Status meanings:**
  - **COMPLETE:** code and tests meet the requirement.
  - **PARTIAL:** some of it is done.
  - **UNVERIFIED:** the code exists, but no test pins it, or only a device can confirm it.
  - **BLOCKED:** cannot be closed without an approval. For some of these the code is already complete.
  - **NOT IMPLEMENTED:** no code and no approved decision.
- **"Live in a release build."** Refined Moments behavior runs only in a build compiled with `SONUS_MOMENTS_REFINED_APPROVED=true`, and only after the per-install activation instant is written (`lib/features/charts/application/services/moment_rules_activation.dart:20-41`, `lib/features/charts/domain/moments/chart_moment_rules.dart:26-39`).
  - **No committed config sets the flag** (Progress BLOCKED #21). Release builds therefore use the legacy rules today.
  - Weekly refined rules apply only to weeks starting at or after activation.
- **Historical data is frozen.**
  - Finalized weeks and published Moments are never rewritten (`chart_finalization_service.dart:235`, `publishFinalizedForWeek`).
  - Everything below about Moments concerns **newly generated** stories unless it says otherwise.
  - Moments **card chrome** (badges, cover lookup) is drawn at display time for every story.
- **"Requires"** values: none · product decision · schema migration · destructive permission · cloud · real device · editorial approval.
- Paths are relative to `C:\dev\sonus\sonus_next_sn50\`. Tests are under `test\`.

---

## 1. Library, Albums and Editions

### 1. Deluxe-first cover selection in newly generated Moments — PARTIAL
- **Live in release build:** no (refined only).
- **Evidence:**
  - `lib/features/charts/presentation/editorial/moment_visuals.dart:73-82`: refined stories use `currentReleaseCover`; older ones keep `releaseCover`.
  - `lib/features/charts/presentation/controllers/charts_controller.dart:1327-1334` reads the Deluxe-first `_albumPresentations`.
  - `lib/features/charts/application/models/chart_album_presentation.dart:23-52`.
  - Tests: `chart_album_presentation_test.dart` ("a Deluxe replaces the title, cover and edition opened", "a Deluxe without a cover keeps the placeholder"); `moment_editorial_test.dart:1340` "F-Q17/C-23: SN-50 stories use the current covers; earlier ones keep theirs" (song stories, fake lookups).
- **Gap:**
  - No test drives a **release** story through `ChartsController` to a Deluxe cover.
  - The cover is looked up at display time, while the headline uses the title stored with the event (`moment_facts.dart`, `title: entity.title`). A refined release Moment can therefore show the Deluxe cover next to the primary/base title.
- **Closure:** a controller-level test (a release story shows the Deluxe cover), plus a decision on how the stored title pairs with the current cover. Active in release once the flag is approved.
- **[Round 6]** The controller-level test is added in `8c8bffc` (`charts_controller_moments_feed_test.dart` "SN-50 reconciliation: a refined release Moment shows the Deluxe cover…"). Still PARTIAL: the title/cover pairing decision.
- **Requires:** product decision (title/cover pairing); release activation (#21).

### 2. Multiselect across track lists for bulk queue and playlist actions — COMPLETE
- **Live in release build:** yes.
- **Evidence:**
  - `lib/features/library/presentation/controllers/track_selection_controller.dart` and `.../widgets/track_selection_bar.dart` (commit `081d4ab`), wired into Tracks, Album, Artist, Search and Playlist Detail.
  - Tests:
    - `track_selection_bar_test.dart` ("adds to the queue in list order and reports skipped songs", "Escape and Back leave selection mode…")
    - `tracks_page_test.dart:1512`
    - `album_profile_page_test.dart:520` "SN-50 C-Q10A: long-press selects tracks; Back leaves"
    - `artist_profile_page_test.dart:372`
    - `search_page_test.dart:970`
    - `playlist_detail_page_test.dart:215`
    - `playlist_service_test.dart` (atomic, added/already present/failed)
- **Gap:**
  - Within the approved scope (C-Q10A): none.
  - No multiselect on Home rails, Charts rows, Queue, Insights or Lyrics. That is outside the approved scope.
  - There is no bulk Play Next, by decision (C-Q10B).
- **Closure:** met. More surfaces would need a product decision.
- **Requires:** none.

### 3. Delete from Sonus vs Delete from Phone, with separate safety controls — BLOCKED
- **Live in release build:** no.
- **Evidence:**
  - No Trash, song-delete, MediaStore delete-request or music-file delete code exists.
  - The manifest has only READ_MEDIA_AUDIO and READ_EXTERNAL_STORAGE.
  - What exists today: hide/blacklist (`blacklisted_songs_page.dart`), remove from playlist, remove from queue, and a guarded edition delete (`album_edition_management_service.dart:530-560`).
  - The design is in `SN50_Destructive_Workflows_Design.md` §1–2 and §6 (A-T0…A-T8, P-1…P-7). Traceability C-Q13A–C-Q24 are Gated.
- **Gap:** the whole feature.
- **Closure:** design §6 approved; then a recoverable Trash (history kept, purge never automatic), a separately confirmed Android system-trash delete (API 30+), the importer relink change for C-Q18, sync deletion markers, and device tests.
- **Requires:** destructive permission, product decision (§6 items), real device, cloud (C-Q13B).

### 4. Glassy, album-coloured track-list backgrounds — NOT IMPLEMENTED
- **Live in release build:** no.
- **Evidence:**
  - Solid surfaces: `album_profile_page.dart:1436-1439` (`Material(color: atmosphere.surface)`), `playlist_detail_page.dart:329` and `artist_profile_page.dart:666,901` (`tileColor: atmosphere.surface`).
  - `SonusArtworkAtmosphereBuilder` is used only by Queue (`playback_queue_page.dart:33`) and Lyrics.
  - Session H is not closed (Master Spec §H; Register H-Q7, H-Q8). Traceability §7 records "no translucent or glass redesign".
- **Gap:** the whole feature.
- **Closure:**
  - H-Q7/H-Q8 decided: which pages; behaviour on greyscale or missing art; Low Effects and Monochrome.
  - Then a static pre-blurred artwork layer (the register notes `BackdropFilter` over solid looks like nothing), contrast checked in all nine themes, and widget tests.
- **Requires:** product decision.

### 5. Release-level Leaked classification and song-level Leak labels — COMPLETE
- **Live in release build:** yes, once a build carrying DB v41 is installed.
- **Evidence:**
  - `lib/core/database/schema/organization_schema.dart` (`leaked`, v41).
  - `release_studio_leaked.dart` (switch); `artist_profile_sections.dart:25,240-268` (Leaked shelf); `artist_profile_tracks_list.dart:400-403` (song Leak label only for flagged songs).
  - Tests: `release_leaked_classification_test.dart` ("A-Q2D: songs flagged as leaks never mark their release", "B-Q13: a leaked release charts exactly as before"), `release_studio_leaked_test.dart`, `artist_profile_session_b_test.dart:439`, `organization_schema_migration_test.dart`, `leaked_backup_compatibility_test.dart`.
- **Gap:**
  - The song Leak label appears only on Artist Profile rows, which is what B-Q12/B-Q31 require.
  - Album, Tracks, Search and Playlist rows show no Leak label, and the Album page has no Leaked badge. No decision asks for them.
- **Closure:** met as specified. Other surfaces need a product decision. DB v41 on the phone needs install approval (BLOCKED #1).
- **Requires:** real device (v41 install); product decision only if more surfaces are wanted.

### 6. Album and Standard/Deluxe edition naming across all current screens — PARTIAL
- **Live in release build:** yes, for the done surfaces.
- **Evidence (done):**
  - `release_display_title.dart` (`releaseDisplayTitle`, `editionLabel`).
  - Now Playing and media session: `media_session_state_mapper.dart:207,227`, `now_playing_page.dart:93`, `library_track_playback_mapper.dart:22`.
  - Also Search, Home, Tracks, Artist rows, Album, Release Studio, and career standings (`charts_controller.dart:466-476`).
- **Gaps (current screens still on the base title):**
  - **Android Auto song rows:** `lib/features/player/application/services/media_session/media_browse_catalog.dart:321-322` (`album: track.albumTitle`, `displaySubtitle: '… · ${track.albumTitle}'`). The test `media_browse_catalog_test.dart` "songs carry title, artist, album, duration and artwork" pins `'locket'`. **Defect (§2 D1).**
  - **Blacklisted songs:** `blacklisted_songs_page.dart:257`. **Library Health:** `library_health_page.dart:378`. **Defect (§2 D2).**
  - **Monthly Insights rows:** `monthly_listening_insights_enrichment_service.dart:107-120` (Session G, not closed).
  - **Provisional This Week:** `charts_controller.dart:454,467` return null outside career standings, so This Week shows snapshot titles. The doc comment says this is by design, and it is a product question.
  - **Loading-time app-bar placeholders:** `tracks_page.dart:329`, `playlist_detail_page.dart:457`, `artist_profile_page.dart:919`, `charts_page.dart:1305,1341`. These are cosmetic and shown for a moment only.
- **History by design (correct):** finalized chart cards (`chart_entry_card.dart:188`), Moments facts, Listening History and Year in Sonus.
- **Closure:** Android Auto, Blacklisted and Library Health use `albumDisplayTitle`/`editionLabel`, with tests, and the pinned Auto test is updated. This Week and Insights are decided.
- **[Round 6]** Android Auto, Blacklisted and Library Health are done in `8c8bffc`. Still PARTIAL: This Week and Insights (product decisions).
- **Requires:** none (D1/D2); product decision (This Week; Insights as Session G).

### 7. Independent edition numbering after Deluxe-only tracks are excluded — COMPLETE
- **Live in release build:** yes, for new edits.
- **Evidence:** `lib/features/library/domain/services/edition_track_numbering.dart:51-80`. Tests:
  - `album_edition_management_service_test.dart` ("A3: removing the first songs numbers the rest from 1 (defect #9)", "each disc counts from 1", "hand-set numbers are kept and reported")
  - `edition_follow_up_test.dart:117` "Deluxe-only songs are never offered to Standard"
  - `release_studio_editions_test.dart:872,1330`
  - `edition_numbering_repair_test.dart`
- **Gap:** existing gapped editions on the phone are repaired only individually, with a preview (A-Q7D), and never in bulk. Running repairs on real data is the user's action.
- **Closure:** met.
- **Requires:** none (real data repairs are user-initiated).

### 8. Artist Profile album track counts from the displayed/primary edition — COMPLETE
- **Live in release build:** yes.
- **Evidence:** `artist_profile_sections.dart:72-74`. Tests: `library_query_dao_test.dart:326` "album track count is the primary edition listing count…", `:410`; `artist_profile_session_b_test.dart:172`.
- **Gap:** none found. **Requires:** none.

### 9. One Release Studio, shared fields, separate edition editing — COMPLETE
- **Live in release build:** yes.
- **Evidence:** `release_studio_page.dart` (commit `14b592f`). Tests: `release_studio_design_test.dart:185` "Shared details, then the edition's sections (A-Q6A)", `:266` "one edition opens straight into its editor, without tabs", `:276` "editions are tabs, primary first…", `:503`; `release_studio_editions_test.dart`.
- **Gap:** none found. **Requires:** none.

### 10. Version labels appended to song titles, plus an inventory — COMPLETE
- **Live in release build:** yes.
- **Evidence:** `lib/features/library/domain/services/song_display_title.dart:46-85`. Tests: `song_display_title_test.dart` (10 tests: "appends the stored version label", "Radio Edit does not also add Edit", "never repeats a qualifier the title already has").
- **Inventory** (`lib/features/library/domain/entities/song.dart:3-14`, enum `SongVersionCharacteristic`):

  | Value | Label |
  |---|---|
  | `remix` | Remix |
  | `live` | Live |
  | `acoustic` | Acoustic |
  | `demo` | Demo |
  | `instrumental` | Instrumental |
  | `edit` | Edit |
  | `radioEdit` | Radio Edit |
  | `extended` | Extended |
  | `remaster` | Remaster |
  | `alternate` | Alternate |

  - **Qualifier order:** live, acoustic, instrumental, extended, alternate, demo, remaster, radioEdit, edit, remix.
  - **Free text wins:** a free-text `versionLabel` set in Track Studio overrides the characteristics.
  - **Format:** `Title (Qualifier)`, words separated by spaces.
  - **No repeats:** a qualifier already in the title inside `( )`, `[ ]` or after ` - ` is not added again.
  - **Credit-line symbols** (`song_credit_line.dart:24-26`): ` & ` between leads, `Ft. a, b`, `with a, b`.
  - **Possible future symbols:** none are defined. Brackets, en dash and a `·` separator are not used for versions. Adding any would be a product decision.
- **Gap:** Insights, Year in Sonus and This Week show raw titles (tracked under #6 and #13).
- **Requires:** none.

### 11. Albums without explicit discs save and appear correctly — COMPLETE **[Round 6]**
- **Live in release build:** yes.
- **Evidence:**
  - Schema `disc_number INTEGER NOT NULL DEFAULT 1` (`library_schema.dart:109,156`).
  - Import falls back to `discNumber ?? 1` (`media_metadata_reader.dart:71`, `path_fallback_metadata_reader.dart:51`); disc 0 is treated as disc 1 (`edition_track_numbering.dart:48`).
  - `spansMultipleDiscs` is used at `album_profile_page.dart:1522` and `release_studio_page.dart:2043`.
  - Tests: `album_edition_track_order_test.dart` "an unknown disc counts as disc 1"; `album_profile_design_test.dart:530` "single-disc editions have no disc headings".
- **Gap:**
  - No test imports a file with **no disc tag** end to end.
  - No test **saves** from Track Studio or Release Studio with disc 0 or the default.
  - Track Studio refuses a cleared disc field ("Enter a valid disc number.", `track_studio_page.dart:223-229`) instead of treating blank as disc 1. The field is prefilled, so this happens only if the user clears it.
- **Closure:** a missing-tag import test, Studio save tests with disc 0 and 1, and a decision on whether blank means disc 1.
- **[Round 6]** `8c8bffc` adds `recording_identity_import_test.dart` "SN-50 reconciliation: a file with no disc number (read as disc 1|0) lands on disc 1…" and `album_edition_track_ordering_service_test.dart` "SN-50 reconciliation: saving a placement with disc 0|1 keeps a single-disc edition". Remaining: only the small decision on whether a cleared Track Studio disc field means disc 1.
- **Requires:** none (blank-field behaviour: small product decision).

### 12. Featured-artist credits persist after Track Studio Save and update other screens — COMPLETE
- **Live in release build:** yes.
- **Evidence:** `PlaybackDisplayRefresher` wired at `playback_scope.dart:161-174` (BUG-01, `7dac818`). Tests:
  - `playback_display_refresher_test.dart:82` "an edited queued song shows its new credit in place…"
  - `track_profile_structured_credit_test.dart:53,261`
  - `track_credit_replacement_test.dart`
  - `tracks_page_test.dart:883,952,1125` ("…shows and keeps older featured names")
- **Gap:** the system notification and Android Auto rendering are not device-verified. Unit tests cover the mapper.
- **Closure:** device QA (M-6) for the notification and Android Auto.
- **Requires:** real device (system UI only).

### 13. Distinct song versions remain distinguishable throughout the app — PARTIAL
- **Live in release build:** yes, for the done surfaces.
- **Evidence:**
  - `displayTitle` on library rows, Queue, Now Playing, Lyrics, media session, Android Auto titles and career standings (BUG-02 `4b6abbf`).
  - Import keeps versions apart (`recording_identity_import_test.dart`: "different featured artists make a different recording", "a different version label of the same title and length is its own…").
- **Gap:**
  - **Monthly Insights** (`monthly_listening_insights_enrichment_service.dart:107-120` uses `track.title`), **Year in Sonus** and **This Week** show base titles, so two versions can look identical.
  - Ambiguous same-title files (#34) are reported but cannot be reviewed.
- **Closure:** a decision on Insights/Year (Session G) and This Week, then display titles there, with tests. Import Review persistence (#34).
- **Requires:** product decision; schema migration (#34 part).

### 14. Custom Other edition names persist and display consistently — COMPLETE **[Round 6]**
- **Live in release build:** yes, except Android Auto.
- **Evidence:** `release_display_title.dart:192-233` (`editionLabel`); `album_profile_page.dart:1343`; `album_studio_editions_section.dart:357`; `PlaybackTrack.displayAlbum`. Tests:
  - `release_display_title_test.dart` "an Other edition shows its own qualifier, never \"Other\""
  - `release_studio_editions_test.dart:1487,1512`
  - `album_profile_design_test.dart:381`
  - `playback_display_refresher_test.dart:113`
  - `media_session_state_mapper_test.dart`
- **Gap:** Android Auto song rows show the base title (§2 D1). Save-and-reload of the name is tested against a fake service only.
- **Closure:** fix D1; add a SQLite round-trip test of an Other edition rename.
- **[Round 6]** Both done in `8c8bffc`: Android Auto rows show the listed edition (`media_browse_catalog_test.dart` "SN-50: songs name the edition they are listed on…"), and `album_edition_management_service_test.dart` "SN-50 reconciliation: an Other edition renamed in Release Studio persists through SQLite…".
- **Requires:** none. A separate stored type label (BUG-03) would need a schema migration and a decision.

---

## 2. Charts and Moments

### 15. Deluxe cover and title pairing on album charts — PARTIAL
- **Live in release build:** yes (current career standings).
- **Evidence:** `chart_album_presentation.dart:23-52`; `charts_controller.dart:453-458` applies it only when `isViewingAllTime` (`:215`). Tests:
  - `chart_album_presentation_test.dart` (7 tests)
  - `charts_page_test.dart` group "Deluxe-first album standings": "shows the Deluxe and opens it", "final weeks keep their stored title", "a failing edition read falls back to the primary"
- **Finalized weeks:** keep their stored titles and covers. This is correct and frozen.
- **Gap:**
  - **This Week** (provisional, current) shows the primary edition, by the code's stated design (`charts_controller.dart:450-452`), and is untested.
  - Insights are not Deluxe-first (A-Q21 Partial, Session G).
  - The release-Moment title/cover pairing is covered under #1.
- **Closure:** decide This Week, then implement and test. Insights per Session G.
- **Requires:** product decision.

### 16. Shared-cover deduplication in song-replacement Moments — COMPLETE (songs)
- **Live in release build:** no (refined only).
- **Evidence:** `moment_visuals.dart:147-157`. Test: `moments_reachability_test.dart` "scenario 9: a weekly #1 names only the displaced leader…" expects `singleCover`.
- **Gap:** release-vs-release rivalry stories (`moment_visuals.dart:123-129`) never dedupe. Legacy stories never dedupe, and published ones are frozen.
- **Closure:** a decision on release rivalries; release activation (#21).
- **Requires:** product decision (releases).

### 17. Album-related headline coverage and variants — PARTIAL
- **Live in release build:** legacy families only.
- **Evidence:**
  - Legacy release families (`moment_family.dart:173-197`): releaseDebutNumberOne, releaseReachesNumberOne, releaseReturnsToNumberOne, releaseDebut (weekly ≤10, all-time ≤100), releaseNewPeak, releaseReentry (weekly ≤25), releaseStreamMilestone, artistFirst/NthNumberOneRelease.
  - Refined additions (`moment_story_planner.dart`): releaseSelfReplacement, releaseFirstThreshold, releaseThresholds, artistRepeatNumberOneRelease, artistSimultaneousReleases, and guaranteed releaseDebut/releaseReentry #1–200.
  - Tests: `moments_reachability_test.dart` "before the SN-50 rules: 17 families publish" and "with the SN-50 rules: 31 families publish… releaseWeeksMilestone stays unwired".
- **Gap (detected, never published):**
  - **releaseWeeksMilestone** (refined longevity block is `weekly && !albums`, `moment_story_planner.dart:411-415`; F-Q3)
  - artist career Top 10/Top 100 for releases
  - artistHighestCharting{Song,Album}
  - artistReturnsToNumberOne{Song,Album}
  - release exits
- **Closure:** wire or explicitly retire each detected-only family. Approved copy for every new family (6 SD + 6 PP).
- **Requires:** product decision, editorial approval.

### 18. Featured-performer recognition in Moments — COMPLETE
- **Live in release build:** no (refined only).
- **Evidence:** `charts_controller.dart:631-654` (`creditForMoment` only when `facts.refined`); `moment_post_card.dart:102-110`; `moment_facts.dart:404,457`. Tests:
  - `charts_page_test.dart` "F-Q19/F-Q20: an SN-50 song story names every performer as text"
  - `charts_controller_moments_feed_test.dart` "SN-50 song stories name every performer; earlier stories and solo songs show no credit line"
- **Gap:** none, once activated (#21). Published stories show no credit line, by decision.
- **Requires:** release activation only.

### 19. Removal of redundant chart tags on Moments cards — COMPLETE
- **Live in release build:** yes (chrome, every story).
- **Evidence:** `moment_editorial_desk.dart:234-240` (no rank badge for roundups or artist milestones) and `:362-372` (the kicker is the single chart mention). Tests: `charts_page_test.dart:1245` (F-Q22, finds no `HOT 100 #` chip); `moment_editorial_test.dart` "F-Q23: an artist roundup shows no song rank".
- **Gap:** none found. Artist-career cards keep the song's rank, which looks intended.
- **Requires:** none.

### 20. Guaranteed eligible chart debuts and re-entries through #200 — COMPLETE
- **Live in release build:** no.
  - Refined only.
  - Legacy publishes weekly song debuts ≤10, weekly re-entries ≤25 and all-time release debuts ≤100, with deep debuts capped at 3 a day.
- **Evidence:** `moment_story_planner.dart:211-244` (`mandatory: true`), `:463-474`. Tests: `moments_reachability_test.dart` "scenario 7: a #190 debut…", "scenario 8: five deep debuts on one day are five stories…" (also five weekly release debuts at #120–124).
- **Gap:**
  - No explicit test for an **all-time release re-entry at #101–200**.
  - Weekly song stories reuse approved F03/F04/F12 lines that still say "this week's", pending P-003/P-004 (#25).
  - Release #101–200 naming is Editorial §6 Q2 / N-1.
- **Closure:** add the release re-entry test; release activation; P-003/P-004 and the N-1 naming approved.
- **[Round 6]** A weekly release re-entry at #160 is pinned in `8c8bffc` (`moments_reachability_test.dart`). The all-time case is still untested: the harness cannot easily drop a release from the cumulative chart.
- **Requires:** editorial approval (wording); release activation.

### 21. New-content indicator, no dot on the first visit — COMPLETE
- **Live in release build:** yes.
- **Evidence:** `charts_controller.dart:330-339`; `moments_last_seen_store.dart:29-36`; wired at `charts_scope.dart:213-214`. Tests: `charts_controller_moments_feed_test.dart` "R6: the first visit records a mark without a dot, even with older stories" (and the other R6 tests); `charts_page_test.dart` "F-Q26: Moments shows a dot…".
- **Gap:** none found. The traceability F-Q26 note "dot shows on first launch" is stale (R6 superseded it).
- **Requires:** none.

### 22. Re-entry and Top 75/50/30/20/15/10/5/3/2/#1 threshold coverage — BLOCKED (code complete)
- **Live in release build:** no.
  - Refined only.
  - Legacy publishes only the all-time Top 100 crossing.
- **Evidence:**
  - Zones (`chart_moment_finalized_detector.dart:12-27`, same list in the live detector): 200, 100, 75, 50, 40, 30, 25, 20, 15, 10, 5, 3, 2, 1. Every requested zone is present, plus 40 and 25.
  - #1, Top 10 and the songs' Hot 100 stand alone. 75–15, 5, 3, 2 (and 100 for releases) consolidate into one story (`moment_story_planner.dart:94,328-361`, R3 `9a5cdbb`).
  - Tests: `moments_reachability_test.dart` "scenario 7", "an all-time jump from Bubbling Under straight to #1 keeps its Top 100 entry; only #1 and the Top 10 stand alone", "without an activation the jump records no Top 100 entry".
- **Why blocked:**
  - These stories print the **N-2/N-3 draft lines**, only 1–2 per publisher (`moment_headlines.dart:2674-2860`, "awaiting six lines per publisher"), not approved copy.
  - Returning into a zone (`thresholdReturn`) is told only for the Hot 100.
  - Which zones are "major" is Editorial §6 Q3 (BLOCKED #10).
- **Closure:** 6 SD + 6 PP approved lines for N-2/N-3; the major-zone question answered; activation.
- **Requires:** editorial approval; product decision (major zones, zone returns).

### 23. Artist multi-song chart achievements and roundups — PARTIAL
- **Live in release build:** weekly song roundups yes (legacy). The rest no.
- **Evidence:**
  - Weekly song roundups, legacy and refined: `moment_family.dart:270-272`, `moment_story_planner.dart:177-188`.
  - Weekly release roundups: refined only (N-5 drafts).
  - Repeat #1 and nth Top 10 are covered.
- **Gap:**
  - **No all-time roundups:** `all_time_moment_service.dart:306-354` has no simultaneous mapping, and the detector is weekly only (`chart_moment_artist_achievement_detector.dart:290`).
  - Roundups for Top 15 and wider zones are detected but not published.
- **Closure:** a decision on all-time roundups and the Top 200 wording (Editorial §6 Q2); N-5 copy approved to 6 + 6; tests.
- **Requires:** product decision, editorial approval.

### 24. Cleaner artist header without release/song counts — COMPLETE
- **Live in release build:** yes.
- **Evidence:** `artist_profile_header.dart:292-337`; `artist_profile_page.dart:781,875-878` ("On X and Y and others"). Tests: `artist_profile_session_b_test.dart` "a contributor on several projects names two, without counts"; `artist_profile_identity_test.dart`.
- **Gap:** none found. Charts and Moments carry no artist header counts; roundup headlines state counts, which are the news.
- **Requires:** none.

### 25. New-peak and movement headlines without misleading "this stream" wording — BLOCKED
- **Live in release build:** the misleading wording is live.
- **Evidence:**
  - Headlines: `moment_headlines.dart` has no literal "this stream" or "this week's". But:
    - `moment_facts.dart:233-238` renders `${f.chart}` as "this week's Sonus Hot 100 / Albums & EPs / Bubbling Under" for weekly stories. 118 headlines use it; only 11 use `scopedChart`.
    - "this week" appears at `moment_headlines.dart:960` (song-gainer-d6), `:1006` (song-gainer-p6) and `:1895` (artist-sim-p4). These are reachable under both rule sets.
  - **Body:** "before this stream" (`moment_editorial_desk.dart:322-323`) is suppressed only for weekly refined stories (`:314`).
  - Test: `moment_editorial_test.dart` "SN-50 headlines never call a finished week 'this week'" covers only the nine SN-50 families.
- **Gap:** every legacy weekly story still says "this week's" for a finished week, and legacy weekly bodies still say "before this stream".
- **Closure:** Editorial P-003, P-005 to P-009 approved and applied prospectively (published stories keep their text), with a test that no weekly story or body uses the phrases.
- **Requires:** editorial approval.

### 26. Hot 100 arrows, movement counts, rank-tier styling, visual quality — UNVERIFIED
- **Live in release build:** yes.
- **Evidence:** `chart_movement_indicator.dart:57-72,110`; `chart_rank_tier.dart:41-65`. Tests:
  - `chart_movement_indicator_test.dart` ("NEW and RE-ENTRY have their own colours and icons", "up and down icons use the theme chart colours")
  - `chart_entry_card_test.dart` ("#1 is the spotlight…", "#4–10 are restrained; #11 is standard", "fits at 320px with 2x text in every theme")
  - `sonus_theme_catalog_test.dart` (RE-ENTRY 3:1)
- **Gap:** the functional parts are complete and tested. "Visual quality" needs a human sign-off on the device.
- **Closure:** a device visual review across the nine themes.
- **Requires:** real device.

### 27. Self-replacement at #1 — BLOCKED (code complete)
- **Live in release build:** no (refined only).
- **Evidence:** `moment_story_planner.dart:196-209,249-256` (songs and releases, weekly and all-time). Test: `moments_reachability_test.dart` "scenario 9…" (weekly songs only).
- **Why blocked:** the copy is the **N-4 draft** (1–2 lines per publisher). The all-time and release paths have no test.
- **Closure:** N-4 approved to 6 + 6; tests for all-time and release self-replacement; activation.
- **[Round 6]** The all-time song, all-time release and weekly release tests are added in `8c8bffc`. Still BLOCKED on the N-4 copy and activation.
- **Requires:** editorial approval.

### 28. NEW badge expiration after a movement or one hour — NOT IMPLEMENTED
- **Live in release build:** n/a.
- **Evidence:**
  - NEW lasts until the comparison baseline rolls over: all-time at the week start (`all_time_chart_ranking_engine.dart:20-41,106-111`), weekly against the previous finalized week (`chart_ranking_engine.dart:268-296`).
  - Nothing is hour-based or movement-based.
  - E-Q3 approved "keep NEW/RE-ENTRY; explain them" (`charts_page_test.dart` info sheet).
- **Gap:** the whole request. It may conflict with E-Q3 and with the all-time NEW meaning "first entry this week".
- **Closure:** a product decision on the expiry rule; then badge logic plus tests in all views. Finalized weeks are unaffected.
- **Requires:** product decision.

### 29. Daily streaks, daily #1 stories, daily streaming peaks, percentage-change reporting — NOT IMPLEMENTED
- **Live in release build:** n/a.
- **Evidence:**
  - No daily chart and no daily event type in `chart_moment_event_type.dart`. The Moments catalog §7 lists "Daily #1 holds: No", "Percent changes: No".
  - Related but different pieces exist:
    - the weekly Top 10 streak (`chart_longevity_facts.dart:40`);
    - all-time week-over-week % on cards (`all_time_chart_cards.dart:23-63`);
    - Monthly Insights `percentChange` (`monthly_duration_change.dart:13`, `monthly_ranking_change.dart:12`).
- **Gap:** the whole request.
- **Closure:** a product decision on the daily chart definition and the stories; copy; tests.
- **Requires:** product decision, editorial approval; a schema migration if daily snapshots must be stored.

### 30. Bubbling Under rises, declines, notable exits, promotion into the Hot 100 — PARTIAL
- **Live in release build:** no (refined only).
- **Evidence:**
  - Published (mandatory): BU rises of 20+ (`moment_story_planner.dart:420-427`), first Hot 100 entry (`:224-235,341-349`), Hot 100 re-entry from BU (`:323-326`).
  - Detected but not published: falls of 30+ and notable exits (`copyGated`, `:546-580`).
  - Tests: `bubbling_under_moments_test.dart` ("#124 to #87 is a first Hot 100 entry…", "#112 to #90 … Hot 100 re-entry", "five songs climbing 20+…", "a fall of 30+ … held…", "a Hot 100 exit … held…").
- **Gap:**
  - Falls and exits have no approved copy (approval sheet §D, §E).
  - PulsePop has no line naming the BU rank (§C).
  - BU rise headlines say "this week's Sonus Bubbling Under" (#25).
- **Closure:** approval sheet lines BU-001 to BU-071 decided; wire D/E from `copyGated` with 6 + 6 lines; tests per the sheet's §G; activation.
- **Requires:** editorial approval.

---

## 3. Other application features

### 31. Set as ringtone from song actions — BLOCKED
- **Live in release build:** no.
- **Evidence:** no ringtone action, WRITE_SETTINGS or `RingtoneManager` in `lib\` or `android\`. Design: `SN50_Destructive_Workflows_Design.md` §3 (R-1 to R-4). Traceability C-Q20A/B/C are Gated.
- **Gap:** the whole feature.
- **Closure:** R-1 to R-3 decided; a song action with the WRITE_SETTINGS flow, a native channel, read-back verification, Sonus ringtone outputs excluded from import, and emulator feasibility tests; then R-4 on the S26.
- **Requires:** product decision, destructive permission, real device.

### 32. Consistent help/info icons replacing cluttered tutorial text — PARTIAL
- **Live in release build:** charts info sheet only.
- **Evidence:**
  - The only help sheet is `chart_info_sheet.dart:11,27`, opened from `charts_page.dart:946-947`. Other `info_outline` icons are decorative.
- **Inline explanatory text remains at:**
  - `release_studio_page.dart:390`
  - `album_studio_editions_section.dart:67,532-533,1050` ("kept" statements)
  - `charts_page.dart:110,117` (qualified-listen text)
  - `settings_sync_card.dart:166-169`
  - `account_cloud_settings_page.dart:37,44` (sync coverage)
  - Insights explainers
- **Gap:** no shared info-button or sheet component; the listed screens still carry inline text. Session H (H-P4, H-Q9, H-Q10) and G-Q13 are not closed.
- **Closure:** decide which text moves; one reusable info button and sheet, applied per screen, with widget tests.
- **Requires:** product decision, editorial approval.

### 33. Account & Cloud page stuck in a syncing state — COMPLETE (app side) **[Round 6]**
- **Live in release build:** yes; cloud is not activated.
- **Evidence (exits from "syncing"):**
  - `lib/features/sync/application/controllers/sync_controller.dart` enters syncing at `:261`. It leaves at :282, :299, :306, :312 and :318, with notify in `finally`.
  - HTTP has connect/response timeouts (`lib/core/network/timed_http_client.dart:44-45`).
  - A bad `server_revision` throws and ends the run as an error (`cloud_conditional_write_result.dart:16-31`).
  - Tests: `settings_sync_card_test.dart` "a stalled sync leaves Syncing, explains, and retries"; `sync_controller_test.dart` ("serializes overlapping sync requests", "many Sync Now taps run once more, not once per tap", "a run that ends after sign-out changes nothing").
- **Gap (verified in code):**
  - **The run queue never recovers from a hung run.** `synchronize` chains every run onto `_pending` (`sync_controller.dart:84, 234-245`). Neither `resetForSignedOut` (`:362-373`) nor `activateUser` (`:164-181`) resets the chain.
  - **There is no whole-run deadline** (`sync_service.dart` `_synchronize`; `sync_controller.dart:270`). One non-HTTP await that never completes would leave the status at Syncing and block every later run, even after sign-out and sign-in.
  - The trigger for a real hang is **not proven**, since HTTP is time-limited. The inability to recover is certain.
  - A permanent server error cycles Syncing → "Waiting to retry" on every resume or connectivity change, with no permanent-failure state.
  - Minor: `failureCode` is not cleared in `activateUser`, `resetForSignedOut` or `clearError`, which contradicts its doc at `:121-123`. It is not visible to the user.
- **[Round 6]** Fixed in `11f30a7`: runs and waits are bounded (10 minutes, reported as a timeout with changes kept); the next run starts only after the previous service run ends; a run queued for a signed-out or switched account is skipped (this also fixed a sign-out resurrection found during the work); `failureCode` is cleared. Tests: `sync_controller_test.dart` group "SN-50 reconciliation: bounded runs, one at a time" (9). Not verified against a real server (no cloud contact). Residual: a run that never ends holds later runs until it ends or the app restarts; cooperative cancellation and a permanent-failure state need approval (Progress BLOCKED #23).
- **Closure (original):** a whole-run timeout that ends in an error code; a queue that cannot be blocked by a hung run (or resets on sign-out); tests with a never-completing fake (sync, sign-out, sign-in, sync completes). A distinct permanent-failure state needs a product decision (Session I, I-P1).
- **Requires:** none for the client-side fix (it touches sync controller code only; no server, schema or activation). Product decision for the permanent-failure state; cloud for any real-server verification.

### 34. Safe Import Review handling for ambiguous same-title recordings — PARTIAL
- **Live in release build:** yes (reporting).
- **Evidence:**
  - `lib/features/import/application/services/atomic_library_importer.dart:766-793` (F1, `420d5d5`): nothing is written for a file at another known position, whatever the existing song's file state. Unknown positions still relink (`:780-784`).
  - Sidecar lyrics are suppressed (`library_import_service.dart:196`).
  - Shown as "Possible different recordings (not imported)" (`import_result_card.dart:62-67`).
  - Tests: `recording_identity_import_test.dart` (Import-1 tests and group "SN-50 F1", 6 tests), `import_execution_summary_test.dart`, `import_result_card_test.dart`.
- **Gap:** the result shows a count only, with no file paths and nothing durable, so the person cannot act on these files later.
- **Closure:** a durable Import Review item per ambiguous file (path plus candidate song) with keep-both and merge actions, plus tests.
- **Requires:** schema migration (BLOCKED #19), product decision.
- **[Round 9/10]** *Superseded:* done without a schema change through the device-local list (`2af3a8b`) and the file states (`49c6188`). Remaining: Import Review wording (BLOCKED #27) and the device check (M-6).

### 35. Duplicate queue entries, relinking protection, session persistence, media controls — PARTIAL
- **Live in release build:** yes.
- **Evidence:**
  - F2 occurrence keys: `playback_queue_page.dart`; `playback_queue_duplicate_entries_test.dart` (7 tests). F1: see #34.
  - The snapshot (`playback_session_snapshot.dart:9-26`) stores `songIds`, `currentIndex` and `positionMs` (version 1). Duplicates survive save and restore by list order (`playback_restoration_controller.dart:90-101,166-170`).
  - R4 finished queue: `playback_restoration_controller_test.dart` "a finished queue is kept at the end of its last song (R4)".
  - Media session: `sonus_audio_handler_test.dart`, `system_controls_regression_test.dart`, `media_session_state_mapper_test.dart`.
- **Gap:**
  - **No test** saves and restores a queue holding the same song twice.
  - **Shuffle order is never persisted**, and the queue is reshuffled (`just_audio_playback_engine.dart:422-432`). Shuffle and repeat persist only with the opt-in "Remember" (`playback_preferences.dart:7-21`, default off). No document records this.
  - F3, F4 and F5 remain (§4).
  - D-Q8/D-Q9 killed-process resume is native and unverified.
  - Gated: M-4/M-5 vendor patches and M-6 device QA. M-2/M-3 sign-off is pending (BLOCKED #14).
- **Closure:** F3–F5 fixed with tests; a duplicate save/restore test; a decision on shuffle-order persistence; device QA.
- **[Round 6]** F3–F5 fixed in `a4085a5`. The duplicate **save** test passes. The duplicate **restore** test found a gap: restoring `[a, b, a]` at the second `a` resumes the first copy (`playback_coordinator.dart:51-53`). Its test is skipped with the reason, and the fix awaits approval (Progress BLOCKED #22). Still PARTIAL.
- **[Round 7]** Fixed in `ec59045`: the restored queue resumes the copy that was playing (restart, mid-song and finished-queue cases tested). Still PARTIAL only for the shuffle-persistence decision (#24), device QA and the vendor patches.
- **Requires:** none (F3–F5, test); product decision (shuffle persistence, M-2/M-3); destructive permission (vendor patches); real device (M-6).

---

## 4. Summary

### Counts (35 requirements, after round 6)

| Status | Count | Requirements |
|---|---|---|
| COMPLETE | 16 | 2, 5, 7, 8, 9, 10, 11, 12, 14, 16, 18, 19, 20, 21, 24, 33 |
| PARTIAL | 10 | 1, 6, 13, 15, 17, 23, 30, 32, 34, 35 |
| UNVERIFIED | 1 | 26 |
| BLOCKED | 5 | 3, 22, 25, 27, 31 (22 and 27 are code-complete but print unapproved draft copy) |
| NOT IMPLEMENTED | 3 | 4, 28, 29 |

Six of the 13 COMPLETE items, and items 22 and 27, run **only under the refined Moments rules**: 1, 16, 18, 20, 22, 27 and 30. Release builds won't show them until the activation flag is approved and set (#21).

### Confirmed functional defects fixable without database changes or real user data (priority order)

**[Round 6]** D1 and D6 are fixed in `8c8bffc`, D3–D5 in `a4085a5`, and D2 in `11f30a7`. New: restoring a later duplicate resumes the first copy (BLOCKED #22, awaiting approval).

| # | Defect | Evidence | Fix |
|---|---|---|---|
| D1 | Android Auto song rows show the base album title, not the edition/display title (contradicts A-Q3, C-Q9, BUG-03) | `media_browse_catalog.dart:321-322`; pinned by `media_browse_catalog_test.dart` "songs carry title, artist, album…" | Use `albumDisplayTitle` for `album` and the subtitle; update the test; add Deluxe and Other-edition cases |
| D2 | The sync run queue cannot recover from a hung run; there is no whole-run deadline (#33) | `sync_controller.dart:84,234-245,362-373,270` | Whole-run timeout leading to an error code; a queue a hung run can't block; clear `failureCode` on reset; tests with a never-completing fake |
| D3 | F4: a double tap on system Shuffle or Repeat loses a toggle | `sonus_audio_handler.dart:216-226` | Serialize custom actions, or track the pending target |
| D4 | F5: Play within 1 s of the end of the last song restarts it | `just_audio_playback_engine.dart:171-186` | Apply the allowance only after a restore seek (keeps R4) |
| D5 | F3: a credit refresh can be overwritten by an in-flight queue edit | `just_audio_playback_engine.dart:326/331, 367/375, 406/414` | Rebuild from the current `_state.queue` after each await |
| D6 | Blacklisted and Library Health rows show the base album title | `blacklisted_songs_page.dart:257`, `library_health_page.dart:378` | Use `albumDisplayTitle`; tests |

**Test-coverage gaps to close alongside (no behaviour change):**
- duplicate-song queue save/restore;
- disc-less import and Studio saves with disc 0/1 (#11);
- a release Moment showing a Deluxe cover through `ChartsController` (#1);
- self-replacement on all-time and release charts (#27);
- all-time release re-entry at #101–200 (#20);
- an Other-edition rename SQLite round trip (#14).

### Changes requiring approval

- **Release activation and editorial**
  - The refined Moments build flag in the release config (#21).
  - BUG-04 sheet BU-001 to BU-071 (#30).
  - P-001 to P-050, including P-003 and P-005 to P-009, for "this week's" and "before this stream" (#25).
  - N-1 release #101–200 naming (#20).
  - N-2 to N-6 to 6 + 6 lines (#22, #23, #27).
  - New-family copy for release longevity and exits (#17).
  - Help-text moves (#32).
- **Product decisions**
  - Moment title/cover pairing (#1).
  - This Week Deluxe-first and display titles (#6, #13, #15).
  - Insights and Year in Sonus display titles (#6, #13; Session G).
  - Release rivalry cover dedupe (#16).
  - Wire or retire detected-only families (#17).
  - All-time roundups (#23).
  - Major zones and zone returns (#22).
  - NEW badge expiry (#28; may conflict with E-Q3).
  - Daily charts and % stories (#29).
  - Glass tracklists, H-Q7 and H-Q8 (#4).
  - Info-icon scope (#32).
  - A permanent sync-failure state (#33).
  - Shuffle-order persistence (#35).
  - Blank disc field means disc 1 (#11).
  - Extra Leak-label surfaces (#5).
  - M-2/M-3 sign-off (#35).
- **Schema migration**
  - ~~Import Review persistence for ambiguous files (#34, BLOCKED #19).~~ *Done without a migration (rounds 9–10).*
  - BUG-03 stored type label (#14, optional).
  - Daily snapshots, if wanted (#29).
- **Destructive permission:** Trash and Delete from Phone (#3), ringtones (#31), vendor patches M-4/M-5 (#35).
- **Real device:** the DB v41 install (#5), M-6 media QA (#12, #35), visual chart sign-off (#26), ringtone R-4 (#31).
- **Cloud:** B-Q19 Leaked sync, the A-Q16 signed-out gap, Trash sync (#3), real-server sync verification (#33).
- ~~**Persistence change:** F6 finalization transaction and repository freeze check (Progress Round 5).~~ *Done in `9ef4717` (round 8).*

## 5. Stale statements in the existing reports

**[Round 6]** All corrected in the Batch D docs commit. Superseded passages in `SN50_Progress.md` are kept and labelled *Superseded*. The traceability matrix rows were rewritten, with their totals updated (C-Q6 and F-Q14 to Implemented+tested). The shuffle and sync findings are recorded in Progress BLOCKED #23 and #24.

| Document | Statement | Reality |
|---|---|---|
| `SN50_Decision_Traceability.md` §6 header (line 215) and §9 row 1 (line 276) | New rules apply from `ChartMomentRules.refinedFromUtc` = 2026-11-01 | Removed in `8d2cbfe`; build flag plus per-install marker |
| `SN50_QA_Report.md` §3 (line 70) | Gated at `refinedFromUtc` (2026-11-01 UTC) | As above |
| `SN50_Progress.md` Phase 6a (line 198) | New rules from `refinedFromUtc` | Historical text; superseded by R2 (noted in Round 5) |
| Traceability A-Q3, A-Q7, A-Q19 (lines 36, 50, 68) | Now Playing and media session use the base title | Fixed by `0f4bb30`/`4b6abbf`. Remaining gaps: Android Auto rows, Insights, Blacklisted, Library Health, This Week |
| Traceability C-Q6 (line 128) and §10 scenario 6 (line 294) | Release Studio and Playlist rows show plain titles | Fixed by `4b6abbf` (`release_studio_page.dart:1857,1953`, `playlist_detail_page.dart:708`) |
| Traceability F-Q14 (line 230) | An all-time jump to #1 skips the Top 100 entry | Fixed by `9a5cdbb` (refined only) |
| Traceability F-Q26 (line 243) | The dot shows on first launch | Superseded by R6 (`8d2cbfe`): no dot on the first visit |
| Traceability F-Q16 and F-Q18 | Implemented+tested | True, but refined only, and F-Q16 prints N-4 draft copy |
| Progress Phase 8 (lines 285-287) | Play after the end does nothing; queue cleared on completion; D-Q18 atmosphere deferred | Historical; superseded by `db79c4e` (R4) and `d27aa50` (D-Q18) |
| Not recorded anywhere | Shuffle order isn't persisted; shuffle and repeat persist only with Remember; the sync queue can't recover from a hang | See #33 and #35 |

## 6. Batch plan for the unfinished safe work

**[Round 6]** Approved and done: A `8c8bffc`, B `a4085a5`, C `11f30a7`, D (docs). The plan below is kept as approved.

Each code batch follows the existing workflow:
- targeted tests;
- `dart format` and `flutter analyze`;
- one full suite with `--concurrency=1` in the main session;
- the boundary check;
- a local commit through the allowlist script.

No schema change, migration, real data, cloud, device or editorial text is involved.

1. **Batch A: display consistency (D1, D6) plus pure test gaps.**
   - Android Auto, Blacklisted and Library Health use display titles; the pinned Auto test is updated.
   - Add the tests listed under §4 for #1, #11, #14, #20 and #27.
   - Low risk. One full suite.
2. **Batch B: playback hardening (D3, D4, D5) plus the duplicate save/restore test.**
   - Serialize the custom actions; restrict the end-of-queue allowance to the restore seek (R4 unchanged); rebuild the queue after each await.
   - Tests for each, including a double-tap test and the 2:59.4 pause case.
   - One full suite.
3. **Batch C: sync controller robustness (D2), client side only.**
   - A whole-run timeout leading to an error code; a queue chain that a hung run can't block; reset on sign-out; `failureCode` cleared.
   - Fake-driven tests only; no server contact.
   - It touches sync code, so confirm this is in scope before starting. One full suite.
4. **Batch D: docs.** Correct the stale rows in §5. Record the shuffle-persistence behaviour and the sync findings. Refresh Progress, QA and Restart.

Batches A and B are independent and could share one full-suite run if you prefer fewer runs. C should stay separate because it is a different subsystem.

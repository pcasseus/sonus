# SN-50 Decision Traceability Matrix

**Purpose:** trace every approved Session A–F decision ID in `C:\dev\sonus\SN50_Master_Implementation_Spec.md` (§§1–6) to what the `sn-50-final-refinement` branch actually did: the commit, the tests or other evidence, and what is still missing, gated or open. This is the spec's Phase 9 "source vs spec traceability matrix".

- **Branch:** `sn-50-final-refinement`, worktree `C:\dev\sonus\sonus_next_sn50`. Local only: no upstream and no remote `sn-50*` branch.
- **Base:** `36d4d5d` (SN-49 HEAD).
- **Commits covered** (`git log --oneline 36d4d5d..HEAD`, oldest first): `8956e3a`, `1a017eb`, `e4027e7`, `2a10990`, `1bce919`, `70fdf64`, `3dbaaa0`, `78750b3`, `ba2d575`, `9aee76d`, `081d4ab`, `9547ef0`. HEAD = `9547ef0` when this was written.
- **Date:** 2026-10-29.
- **Sources:** the Master Spec; `SN50_Progress.md`; `SN50_Destructive_Workflows_Design.md` (cited as "Design"); `SN50_Editorial_Change_Proposal.md` (cited as "Editorial"); commit messages and `git show --stat`; test names read with `git show` / `git grep` at HEAD. No tests were run for this document. Test counts come from `SN50_Progress.md`; the last recorded result is 4,783 passing with a clean analyzer after `9547ef0`.

## Status legend

| Status | Meaning |
|---|---|
| **Implemented+tested** | A commit implements it and a test pins it (test file named). Any "choice to confirm" is listed in Notes. |
| **Partial** | Some of it is implemented. Notes say what is missing. |
| **Gated** | Needs a specific approval first: *cloud*, *destructive*, *device*, *plugin* or *editorial*. Notes say which, with the approval ID from Design §6 where there is one. |
| **Deferred** | Safe to build but not done yet. |
| **No change needed** | Already true at `36d4d5d`. Evidence is cited. |
| **Open question** | Needs a user choice before it can be implemented. (No ID is wholly in this state. Open sub-questions are attached to rows and collected in §8.) |
| **In progress (final batch)** | Being worked on by the final commit batch, which was not in the log when this was written. |

Test paths are under `test/features/` unless they start with `test/core/`. Basenames are used where they are unique.

---

## 1. Session A: Release Studio and Editions

| ID | Decision (short) | Status | Commit(s) | Tests / evidence | Notes |
|---|---|---|---|---|---|
| A-Q1 | Album/EP/Single format is release-wide | No change needed | — | At `36d4d5d`, `album_release_classifications` (keyed by `album_id`) holds `format`/`format_authority` (`organization_schema.dart:23-67`). `release_studio_format_test.dart` is still green after `2a10990`. | Never edition-scoped. |
| A-Q2A | Live is a release-wide classification | No change needed | — | `live` column on the same release table since SN-49 v40 (`organization_schema.dart:72`). `release_studio_live_test.dart`. | |
| A-Q2B | Soundtrack/Cast/Compilation describe the whole release | No change needed | — | `kind` column on the release-wide table at `36d4d5d`. | |
| A-Q2C | Leaked is a manual release-wide classification | Implemented+tested | `2a10990` | `release_leaked_classification_test.dart`, `release_studio_leaked_test.dart`, `organization_schema_migration_test.dart` (DB v41) | Manual only. Real-device DB v41 migration is gated by install approval (Progress BLOCKED #1). |
| A-Q2D | Song Leak flags never mark the release Leaked | Implemented+tested | `2a10990` | `release_leaked_classification_test.dart` | |
| A-Q3 | Displayed title comes from the primary edition; base title preserved | Partial | `e4027e7` | `library_query_dao_test.dart`, `release_studio_editions_test.dart` | Done on library surfaces and Search via `releaseDisplayTitle`. `albums.title` is never written. **Missing:** Now Playing/media session, Android Auto song rows, Charts/Insights pages, MusicBrainz queries and `findAlbums` ordering still use the base title (Progress 2b). |
| A-Q4 | The edition header is the single title editor | Implemented+tested | `e4027e7` | `release_studio_editions_test.dart` | The Studio "Name" field renames the selected edition. There is no competing parent-title editor. |
| A-Q5A | New edition copies the primary by default; source selectable | Implemented+tested | `1a017eb` | `album_edition_management_service_test.dart`, `release_studio_editions_test.dart` | |
| A-Q5B | Copy membership, order, discs and numbering | Implemented+tested | `1a017eb` | `album_edition_management_service_test.dart` | Progress groups this under "A-Q5A–E". |
| A-Q5C | Suggested editable title for the edition type | Implemented+tested | `1a017eb` | `release_studio_editions_test.dart` | |
| A-Q5D | New edition date starts blank ("Not set") | Implemented+tested | `1a017eb` | `album_edition_management_service_test.dart` (date, cover and genre are never copied) | |
| A-Q5E | New edition has no artwork | Implemented+tested | `1a017eb` | same as A-Q5D | |
| A-Q5F | Adding Standard to a Deluxe-only release asks about primary | Implemented+tested | `e4027e7` | `release_studio_editions_test.dart` | Default is "Not now". |
| A-Q6A | Release Studio: one screen with edition tabs and collapsible Shared Details | Implemented+tested | `14b592f` | `release_studio_editions_test.dart` and the Release Studio page tests (shared values only in Shared details; primary-first tabs; keyboard expand/collapse; 9 themes at 320dp and 2×) | One scroll view: collapsible Shared details, then edition tabs, then expandable edition sections. Existing editors are reused. |
| A-Q6B | One-edition releases open straight into the editor | Implemented+tested | `14b592f` | Release Studio tests ("one edition means no tabs") | No tabs or selection step for a single edition. |
| A-Q6C | Edition release date editable; "Not set" when blank | Implemented+tested | `1a017eb` | `album_profile_editing_service_test.dart`, `release_studio_editions_test.dart` | `updateEditionReleaseDate` records manual provenance and queues the edition. |
| A-Q6D | Label the primary-cover fallback in the editor | Implemented+tested | `1a017eb` | `release_studio_editions_test.dart` | |
| A-Q6E | MusicBrainz suggests shared and edition fields for review | Deferred | — | No SN-50 change found | Progress 2a: MusicBrainz date apply still targets the primary edition. Per-edition suggestions are not built. |
| A-Q6F | Nonblocking genre-conflict indicator | Implemented+tested | `e4027e7` | `release_studio_editions_test.dart` | Shared with A-Q17B. |
| A-Q7 | (Earlier-session reference cited with A-Q19) A primary switch never moves home editions or streams | Partial | `e4027e7`, `8956e3a` | See A-Q19 | Same status and gaps as A-Q19. |
| A-Q7A | Auto-renumber, but ask before overwriting hand-set numbers | Implemented+tested | `1a017eb`, `e4027e7` | `album_edition_track_ordering_service_test.dart`, `album_edition_management_service_test.dart`, `release_studio_editions_test.dart` | Choose songs and disc moves ask first. The Deluxe follow-up offer changes only inferred numbers and keeps hand-set ones without asking (Progress 2a). |
| A-Q7B | Numbering restarts at 1 per disc | Implemented+tested | `1a017eb` | `album_edition_track_ordering_service_test.dart` (`edition_track_numbering.dart`) | |
| A-Q7C | Drag-and-drop renumbers from the actual order | Implemented+tested | `1a017eb` | `album_edition_track_ordering_service_test.dart` | |
| A-Q7D | Previewed individual legacy repairs; no silent bulk renumbering | Partial | `1a017eb` | Verify Library repairs never renumber (tested in `1a017eb`) | **Missing:** the previewed individual repair flow (Progress BLOCKED #5). |
| A-Q8A | Disc Organization stays accessible; headings only for real multi-disc editions | Implemented+tested | `e4027e7` | `album_profile_page_test.dart`, `release_studio_editions_test.dart` | One shared `spansMultipleDiscs` rule. |
| A-Q9 | A disc move puts the track at the end of the destination disc | Implemented+tested | `1a017eb` | `album_edition_track_ordering_service_test.dart` | |
| A-Q10 | Historical charts and Moments stay frozen | Implemented+tested | `8956e3a` | `chart_finalization_restore_test.dart` (freeze suite), `chart_finalization_service_test.dart`, `sqlite_chart_moment_repository_test.dart` | |
| A-Q12 | Context-aware song artwork | Implemented+tested | `e4027e7`, `9aee76d` | `library_query_dao_test.dart`, `album_edition_track_order_test.dart`, `moment_editorial_test.dart` | **Open question** (Progress BLOCKED #6): in an edition view, song custom art currently comes before the edition cover. |
| A-Q13 | Primary without artwork shows a neutral placeholder, not another edition's cover | Partial | `3dbaaa0` (Deluxe case) | `chart_album_presentation_test.dart` "a Deluxe without a cover keeps the placeholder" | No test was found for a release card or profile whose **primary** has no cover. Song-row fallback (A-Q12) can show a home-edition cover. Needs verification. |
| A-Q14A | Cards show the displayed edition's track count | Implemented+tested | `1a017eb` | `library_query_dao_test.dart` | `songCount` keeps the all-edition count. |
| A-Q14B | The primary-edition count drives possible-Single review | Implemented+tested | `1a017eb` | `library_query_dao_test.dart` | Can move a release into review and off the current chart. Finalized weeks are unaffected. |
| A-Q15 | Block deletion until exclusive songs are relocated | Implemented+tested | `2a10990` | `album_edition_management_service_test.dart` | |
| A-Q16 | Block unsafe cloud-linked edition deletes | Partial | `2a10990` | `album_edition_management_service_test.dart` "SN-50 A-Q16" | A primary in the signed-in user's cloud baseline is refused. **Missing (Gated: cloud):** the signed-out gap (Progress BLOCKED #3). No remote propagation was added. |
| A-Q16B | Fail closed for older or incompatible devices | Gated (cloud) | — | — | Needs deletion reconciliation and a cloud design. Remote deletion is not authorized. |
| A-Q17A | No speculative mass rewrite of titles, art, dates or genres | No change needed | `e4027e7`, `2a10990` | No migration rewrites them. v41 copies all 12 v40 columns unchanged. `albums.title`/`canonical_title` are never written. | Genuine conflicts are flagged (A-Q17B). |
| A-Q17B | Genre conflicts get a review indicator; stored values unchanged | Implemented+tested | `e4027e7` | `release_studio_editions_test.dart` | |
| A-Q18 | A historic song Moment opens the verified event edition | Implemented+tested | `9aee76d` | `charts_controller_moments_feed_test.dart` | Real-time stories open the played edition. **Choice to confirm:** finalized-week song stories open the home edition. |
| A-Q19 | A primary switch updates current display only | Partial | `e4027e7`, `1a017eb`, `8956e3a` | `library_query_dao_test.dart`, `release_studio_editions_test.dart` | Title, count and art follow the primary on library surfaces. History is frozen. **Missing:** the same base-title surfaces as A-Q3. |
| A-Q20 | Adding Standard preserves the existing edition exactly | Implemented+tested | `e4027e7` | `release_studio_editions_test.dart` | |
| A-Q21 | Current album Charts and Insights prefer Deluxe | Partial | `3dbaaa0` | `chart_album_presentation_test.dart`, `charts_page_test.dart` | Charts done. **Insights not done** (G is a separate track). Position and streams stay the parent's. |
| A-Q22 | Tapping a chart entry opens the edition shown | Implemented+tested | `3dbaaa0` | `charts_page_test.dart` | |
| A-Q23 | Deleting the primary requires a replacement primary | Implemented+tested | `2a10990` | `album_edition_management_service_test.dart` | |
| A-Q24 | The final edition can't be deleted | Implemented+tested | `2a10990` | `album_edition_management_service_test.dart` "SN-50 A-Q24", `release_studio_editions_test.dart` | The release Trash route itself is gated (Session C). |
| A-Q25 | Exclusive songs block the delete | Implemented+tested | `2a10990` | `album_edition_management_service_test.dart` | |
| A-Q26 | Removing a song's last membership needs preservation or relocation | Partial | `2a10990` | `album_edition_management_service_test.dart` "SN-50 A-Q26" (delete path) | Pinned for edition delete. Not verified for other membership-removal paths, such as Choose songs. |
| A-Q27 | Several Deluxes: the most recently released wins | Implemented+tested | `3dbaaa0` | `chart_album_presentation_test.dart` | |
| A-Q27B | Missing or ambiguous dates: the most recently added Deluxe wins | Implemented+tested | `3dbaaa0` | `chart_album_presentation_test.dart` | Falls back to the primary if the Deluxe read fails. |
| A-Q28 | A Deluxe without a cover shows its title plus a placeholder | Implemented+tested | `3dbaaa0` | `chart_album_presentation_test.dart` | Release Moments do the same (`9aee76d`). |
| A-Q29 | A deleted edition falls back to the surviving primary, with an explanation | Implemented+tested | `9aee76d` | `charts_controller_moments_feed_test.dart` | |

## 2. Session B: Artist Profile

Main test file: `library/presentation/pages/artist_profile_session_b_test.dart` ("B test"). All rows are commit `70fdf64` unless noted.

| ID | Decision (short) | Status | Commit(s) | Tests / evidence | Notes |
|---|---|---|---|---|---|
| B-Q1 | Remove the catalogue-count hero line | Implemented+tested | `70fdf64` | B test, `artist_profile_identity_test.dart` | |
| B-Q2 | Contributor hero gives short project context, no count | Implemented+tested | `70fdf64` | B test "a contributor on several projects names two, without counts" | |
| B-Q7 | Leaked takes precedence over Live; Live shown as secondary | Implemented+tested | `70fdf64` | B test, `artist_profile_sections_test.dart` | |
| B-Q8 | Section order Albums → EPs → Singles → Live → Leaked → Needs Review | Implemented+tested | `70fdf64` | B test "run Albums, EPs, Singles, Live, Leaked, Needs Review…" | |
| B-Q9 | Card shows format and the shown edition's track count | Implemented+tested | `70fdf64`, `1a017eb` | B test "cards say format, track count…" | |
| B-Q12 | Song Leak label only when the song itself is flagged | Implemented+tested | `70fdf64` | B test "song Leak label" | |
| B-Q13 | Release Leaked adds no chart badge | Implemented+tested | `2a10990` | `release_leaked_classification_test.dart` | |
| B-Q14 | Unconfirmed-format Live/Leaked stay in their section with a review note | Implemented+tested | `70fdf64` | `artist_profile_sections_test.dart` | |
| B-Q15 | Featured and guest credits in rows and Collaborators | Implemented+tested | `70fdf64` | B test "Collaborators lists featured, guest and unverified credits" | |
| B-Q16 | Show the performer when not the profile owner | Implemented+tested | `70fdf64` | B test "a row names a performer other than the owner…" | |
| B-Q17 | A song may appear in both Top Tracks and Collaborations | Implemented+tested | `70fdf64` | B test "(B-Q17)" | |
| B-Q18 | Play All = main catalogue, no featured-only songs | Implemented+tested | `70fdf64` | B test "Play All is the main catalogue…" | |
| B-Q19 | Release-level Leaked cloud sync, compatible clients only | Gated (cloud) | `2a10990` (local column only) | `cloud_archive_sync_service_test.dart` | Rides in the archive row like Live. The archive is not deployed. Clients older than v41 would fail CHECK (Progress BLOCKED #2). |
| B-Q20 | Omit an album title identical to the song title | Implemented+tested | `70fdf64` | B test (same as B-Q16) | |
| B-Q21 | Hero gradients respect Decoration Off, High Contrast and Low Effects | Implemented+tested | `70fdf64` | B test "…draws no gradient behind a hero without a banner" | |
| B-Q22 | (= B-Q8 ordering) | Implemented+tested | `70fdf64` | B test | |
| B-Q23 | Soundtrack/Cast/Compilation stay in their format section with a kind note | Implemented+tested | `70fdf64` | `artist_profile_sections_test.dart` | |
| B-Q24 | Unavailable releases stay visible and marked | Implemented+tested | `70fdf64` | `artist_profile_sections_test.dart`, B test | |
| B-Q25 | Sections ordered newest primary-edition date first | Implemented+tested | `70fdf64` | `artist_profile_sections_test.dart` "(B-Q8, B-Q25)" | The test pins that the given order is kept. The date sort is in `artist_profile_sections.dart:281`. |
| B-Q26 | Collaborator Play = all credited contributions | Implemented+tested | `70fdf64` | B test "collaborator Play plays every credited contribution" | |
| B-Q27 | Tapping a Collaboration plays the Collaborations queue | Implemented+tested | `70fdf64` | B test "a Collaboration plays within the Collaborations queue" | |
| B-Q28 | Unavailable Collaborations stay visible and marked | Implemented+tested | `70fdf64` | B test | |
| B-Q29 | Top Tracks: five rows plus See All | Implemented+tested | `70fdf64` | B test "five rows, then See All…", "no See All when five or fewer…" | **Choice to confirm:** See All only appears when more than five songs have streams. |
| B-Q30 | Contributor-only profiles keep project-based playback | Partial | `70fdf64` | `artist_profile_controller.dart:248-254` (`playbackTracks` for contributors) | Implemented in code. No test was found that names this rule. |
| B-Q31 | Leak label inside a Leaked release only for flagged songs | Implemented+tested | `70fdf64` | B test "song Leak label" | |
| B-Q32 | Co-primary, featured and guest roles preserved | Implemented+tested | `70fdf64`, `1bce919` | B test, `song_artist_credit_service_test.dart` | |
| B-Q33 | Unverified credit names display but don't link | Implemented+tested | `70fdf64` | B test "an unverified name is shown but opens nothing (B-Q33)" | **Choice to confirm:** unlinked collaborators keep a working Play button. |
| B-Q34 | Collaborators subtitle "Artists who appear on these releases" | Implemented+tested | `70fdf64` | B test | |
| B-Q35 | See All ranks every track with qualified lifetime streams | Implemented+tested | `70fdf64` | B test | |
| B-Q36 | Link only after identity verification | Implemented+tested | `70fdf64` | B test (as B-Q33) | **Choice to confirm:** tagged featured names without structured credits count as unlinked. |
| B-Q37 | Other unconfirmed formats go to Needs Review; >3-track inferred eligibility kept with a note | Implemented+tested | `70fdf64` | `artist_profile_sections_test.dart` | |

## 3. Session C: Credits, Versions, Bulk Actions, Trash, Ringtones

| ID | Decision (short) | Status | Commit(s) | Tests / evidence | Notes |
|---|---|---|---|---|---|
| C-Q1 | Role-aware credits across lists, playback, notification, lock screen, Auto and Search | Implemented+tested | `1bce919` | `song_credit_line_test.dart`, `media_session_state_mapper_test.dart`, `library_track_playback_mapper_test.dart`, `tracks_page_test.dart`, `library_query_dao_test.dart` | `PlaybackTrack.displayArtist`. Analytics still records plain values (verified, Progress Ph3). |
| C-Q2 | Ask before merging same-name identities | Implemented+tested | `1bce919` | `track_credit_editor_dialog_test.dart`, `song_artist_credit_service_test.dart` | Duplicates are compared by identity. **Open question:** Track Studio never auto-links a typed name, but Import Review and the importer still link by name. |
| C-Q3 | Searchable artist picker with free-text fallback | Implemented+tested | `1bce919` | `track_credit_editor_dialog_test.dart` | |
| C-Q4 | Reconcile legacy `featured_artists` on edit; no bulk writes | Implemented+tested | `1bce919` | `track_profile_structured_credit_test.dart`, `artist_credit_parser_test.dart`, `track_profile_edit_draft_test.dart` | Converted only on save. |
| C-Q5 | Import Review uses the shared credit editor | Implemented+tested | `1bce919`, `14b592f` | `track_profile_edit_dialog` tests ("Crane, The Lantern"; no auto-link on typed names; picked artist links), Import Review page and service tests | Import Review uses the shared `TrackCreditList` and saves through `updateTrackWithCredits`. If credits can't be loaded, the editor doesn't open. |
| C-Q6 | One concise version suffix; canonical title untouched | Partial | `1bce919` | `song_display_title_test.dart` | **Missing:** Release Studio and Playlist rows still show the plain title. |
| C-Q7 | Freeze old title snapshots; capture presentation titles for future events | Deferred | — | Old snapshots frozen by `8956e3a` | Future-snapshot capture is not built. Capture points are listed in Progress Ph3. Needs approval because the values feed history and matching. |
| C-Q8 | Display titles in Now Playing, Queue and notifications | Implemented+tested | `1bce919` | `media_session_state_mapper_test.dart`, `library_track_playback_mapper_test.dart` | |
| C-Q9 | Same for lock screen, Auto and Search | Implemented+tested | `1bce919` | as C-Q8, plus `library_query_dao_test.dart` (Search matches labels and characteristics) | Device rendering is not verified (device QA). |
| C-Q10A | Multi-select on Tracks, Album, Artist, Search and Playlist Detail | Implemented+tested | `081d4ab` | `track_selection_bar_test.dart`, `tracks_page_test.dart`, `album_profile_page_test.dart`, `artist_profile_page_test.dart`, `search_page_test.dart`, `playlist_detail_page_test.dart` | Tested at 320dp, 2× text, 9 themes. |
| C-Q10B | Bulk Add to Playlist and Add to Queue in visible order; no bulk Play Next | Implemented+tested | `081d4ab` | `track_selection_bar_test.dart`, `playback_coordinator_test.dart` | Unavailable songs are skipped and counted. |
| C-Q11 | One membership; added/already present/failed counts; atomic | Implemented+tested | `081d4ab` | `playlist_service_test.dart`, `add_to_playlist_sheet_test.dart` | Concurrency and mid-batch failure tested. |
| C-Q12 | Consistent context-sensitive per-track actions | Implemented+tested | `081d4ab`, `14b592f` | `tracks_page_test.dart`, `search_page_test.dart`, `playlist_detail_page_test.dart` | Go to album/artist and Select added. Track Studio is now in the Search and Playlist Detail menus. Historical rows get none. |
| C-Q13A | Sonus Trash: new logical recoverable state | Gated (destructive) | — | Design §1, approvals A-T0, A-T3–A-T8 | No code. |
| C-Q13B | Cloud syncs logical Trash only | Gated (cloud) | — | Design §1.9, approval C-1 | Separate cloud track. |
| C-Q14 | Trash removes playlist memberships and snapshots them | Gated (destructive) | — | Design §1.5.1 | |
| C-Q14B | Ask on restore whether to re-create memberships | Gated (destructive) | — | Design §1.5.2, A-T4 | |
| C-Q15 | Day-30 purge of the active Song record | Gated (destructive) | — | Design §1.5.3/§1.6, A-T1/A-T2 | Never automatic or unattended. |
| C-Q15R | Keep minimal historical identity and snapshots after purge | Gated (destructive) | — | Design §1.3, A-T0/A-T7 | |
| C-Q16 | Disable phone delete without recoverable system trash | Gated (destructive/device) | — | Design §2.1 (API 30+ only), P-1 | |
| C-Q17 | Physical delete via Android recoverable trash with consent | Gated (destructive/device) | — | Design §2.3–2.4, P-1, P-6/P-7 | |
| C-Q18 | Ask before restoring after an external file restore | Gated (destructive) | — | Design §2.6, P-3 | The importer's silent relink must change first. |
| C-Q19 | Multi-signal identity matching; review when ambiguous | Gated (destructive) | — | Design §2.7, P-2/P-5 | |
| C-Q20A | Unedited ringtone uses the original recording | Gated (device/destructive) | — | Design §3.1, R-1/R-4 | |
| C-Q20B | Full ringtone editor | Gated (device/destructive) | — | Design §3.2, R-3 | |
| C-Q20C | Edited ringtone written as a separate file | Gated (device/destructive) | — | Design §3.1, R-2/R-3 | |
| C-Q21 | v31–40 backups: absent Trash info is unknown, sent to review | Gated (destructive) | — | Design §1.7, A-T3 | |
| C-Q22 | Show qualifiers for already-imported tracks from existing metadata | Implemented+tested | `1bce919` | `song_display_title_test.dart` | Read-time only. |
| C-Q23 | Remove from Sonus and Delete from Phone stay separate | Gated (destructive) | — | Design §2.1 | |
| C-Q24 | Durable pending-operation journal and crash reconciliation | Gated (destructive) | — | Design §1.8, A-T0 | |

## 4. Session D: Playback, Notification, Queue, Android Auto

Dart-side work is in `9547ef0`. Every row also needs device QA (Design §4.2, approval M-6) before release. Design §6.1 listed M-2 (End Session keeps the queue) and M-3 (Dart-side media changes) as approve-before-implementation items. `9547ef0` implements both. Confirm those approvals were given.

| ID | Decision (short) | Status | Commit(s) | Tests / evidence | Notes |
|---|---|---|---|---|---|
| D-Q1 | Request Shuffle, Prev, Play/Pause, Next, Repeat | Implemented+tested | `9547ef0` | `media_session_state_mapper_test.dart`, `media_session_wiring_test.dart` | Custom actions, plus 5 drawables kept via `keep.xml`. One UI placement is device QA. |
| D-Q2 | Accept the system's placement | Implemented+tested | `9547ef0` | as D-Q1 | Compact `[0,1,2]` kept (Android ≤12 crash otherwise). |
| D-Q3 | Remove visible Stop; add End Session | Implemented+tested | `9547ef0` | `media_session_state_mapper_test.dart`, `shell_playback_slot_test.dart` "End session keeps the queue" | |
| D-Q4 | Prioritize reliable paused resumption | No change needed | — | `androidStopForegroundOnPause: false` kept (Design §4.1, `media_session_bootstrap.dart:33-36`) | |
| D-Q5 | Allow notification dismissal while playing where Android allows | Gated (device) | `9547ef0` (Dart path) | `sonus_audio_handler_test.dart` "(SN-50 D-Q5/D-Q6/D-Q7)" | Whether One UI lets the user dismiss, and whether that fires deleteIntent, is device QA only. |
| D-Q6 | Dismissal ends the session, keeps queue and position | Implemented+tested | `9547ef0` | `sonus_audio_handler_test.dart` "dismissing the notification ends the session but keeps the queue" | |
| D-Q7 | A paused-only mini-player swipe clears the queue | No change needed | `9547ef0` (pin) | Behavior already existed (`dismissPausedSession`). Pinned in `sonus_audio_handler_test.dart` (notification path never clears). | |
| D-Q8 | Bluetooth Play restores the saved queue and position | Partial | `9547ef0` | `sonus_audio_handler_test.dart` "Play restores the saved session first (SN-50 D-Q8)" | Dart side waits up to 10 s for restore. **Missing:** whether a killed process reaches Dart `play()` is native and unverified (device). |
| D-Q9 | System Resume restores the saved queue, never Recent | Partial | `9547ef0` | `sonus_audio_handler_browse_test.dart` "the resume card resumes the saved session (SN-50 D-Q9)" | Device behavior after process death is unverified. |
| D-Q10 | Removing from Recents keeps state | Implemented+tested | `9547ef0` | `sonus_audio_handler_test.dart` "removing Sonus from Recents changes nothing (SN-50 D-Q10)" | |
| D-Q11 | No paused timeout; no needless wake lock | Gated (plugin) | — | Design §4.1, vendor Patch 2, approval M-4 | |
| D-Q12 | Repeat cycles Off → All → One → Off | Implemented+tested | `9547ef0` | `playback_repeat_mode_test.dart`, `sonus_audio_handler_test.dart` | |
| D-Q13 | External Shuffle/Repeat follow "Remember" | Implemented+tested | `9547ef0` | `system_controls_regression_test.dart` "(D-Q13)" | |
| D-Q14 | Android ≤12 Shuffle/Repeat via a vendor patch | Gated (plugin) | — | Design §4.1, vendor Patch 3, approval M-5 | |
| D-Q15 | End Session in the Now Playing overflow and the mini-player menu | Implemented+tested | `9547ef0` | `shell_playback_slot_test.dart` (overflow, long press, screen-reader action), `sonus_mini_player_test.dart` | |
| D-Q16 | Completed queue stays paused on the last track; no double count | Partial | `9547ef0` | `system_controls_regression_test.dart` "the end of the queue with Repeat off (D-Q16)" | Paused-at-end and the single count are done. **Missing:** the saved session is still cleared on completion, so a finished queue doesn't survive a restart. **Open question M-1:** Play after the end currently does nothing (pinned). |
| D-Q17 | One authoritative queue shared with Android Auto | No change needed | — | One queue already published to the session (Design §4.1, `media_session_state_mapper.dart:104-112`) | Car-side editing is device QA. |
| D-Q18 | Queue: subtle atmosphere, highlighted row, no big summary | Partial | `9547ef0` | `shell_playback_slot_test.dart` "(D-Q18)" | Summary card removed. **Missing:** the subtle album atmosphere. |
| D-Q19 | Mini-player interactive behind nonblocking overlays | Deferred | — | — | Progress Ph8. |

## 5. Session E: Hot 100 and Charts

| ID | Decision (short) | Status | Commit(s) | Tests / evidence | Notes |
|---|---|---|---|---|---|
| E-Q1 | Show the previous Bubbling Under rank as context | Implemented+tested | `3dbaaa0` | `chart_entry_card_test.dart` | Weekly cards only. |
| E-Q2 | Movement uses the previous **finalized** rank | Implemented+tested | `78750b3` | `chart_movement_baseline_test.dart`, `chart_finalization_restore_test.dart` | Applies to newly finalized weeks only. Stored weeks are frozen. |
| E-Q3 | Keep NEW/RE-ENTRY; explain them in the info sheet | Implemented+tested | `3dbaaa0` | `charts_page_test.dart` (info sheet per view) | |
| E-Q4 | Career re-entry has no minimum absence | Implemented+tested | `3dbaaa0` | `charts_page_test.dart`; `chart_info_sheet.dart:10` | Wording pinned. Engine behavior predates SN-50. |
| E-Q5 | Provisional This Week next to frozen Weekly History | Implemented+tested | `78750b3` | `chart_snapshot_builder_service_test.dart` "SN-50 This Week", `charts_controller_test.dart`, `charts_page_test.dart` | Never stored or published. **Choices to confirm:** it lives in the week navigator; "N weeks" counts finalized weeks only. |
| E-Q7 | Tie-breaks: weekly recency vs lifetime incumbency | Implemented+tested | `78750b3`, `3dbaaa0` | `chart_snapshot_builder_service_test.dart`, `charts_page_test.dart` | |
| E-Q8 | Weekly entries open living entities; snapshots unchanged; purged ones display-only | Implemented+tested | `8956e3a`, `3dbaaa0` | `charts_page_test.dart`, `chart_finalization_restore_test.dart` | **Choice to confirm:** tapping a weekly song queues that week's order. |
| E-Q9 | Rank tiers adapted to the nine themes | Implemented+tested | `3dbaaa0` | `chart_entry_card_test.dart`, `all_time_chart_cards_test.dart`, `sonus_theme_catalog_test.dart` | |
| E-Q10A | Longevity stats on cards | Implemented+tested | `3dbaaa0` | `chart_longevity_test.dart`, `chart_entry_card_test.dart` | **Choice to confirm:** "consecutive #1 streak" is read as the longest #1 run. |
| E-Q10B | Reflow for large text rather than omit data | Implemented+tested | `3dbaaa0` | `all_time_chart_cards_test.dart`, `chart_entry_card_test.dart` | |
| E-Q13 | Correct future album owner attribution; no historical repair | Implemented+tested | `78750b3` | `chart_snapshot_builder_service_test.dart` "SN-50 future album owner attribution (E-Q13)" | |
| E-Q14 | Static Hot 100 heading | No change needed | `3dbaaa0` (pinned) | `charts_page_test.dart` (`find.text('Hot 100')`) | |
| E-Q15A | Retire the "All Time" phrase globally | Implemented+tested | `3dbaaa0` | `charts_page_test.dart` (scans text, semantics and tooltips) | No quoted "all time"/"all-time" string remains in `lib/` (grep at HEAD). The 10 base occurrences are gone. **Choice to confirm:** the labels "Career standings", "CURRENT", "Career peak". |
| E-Q15B | Understated Bubbling Under labels | Implemented+tested | `3dbaaa0` | `chart_entry_card_test.dart` | |
| E-Q15C | Distinct NEW/RE-ENTRY colors plus non-color cues | Implemented+tested | `3dbaaa0` | `chart_movement_indicator_test.dart`, `sonus_theme_catalog_test.dart` (3:1) | |
| E-Q16 | (as E-Q15C) | Implemented+tested | `3dbaaa0` | as E-Q15C | |
| E-Q18 | "Best so far #N" separate from the official peak | Implemented+tested | `78750b3` | `chart_snapshot_builder_service_test.dart`, `charts_page_test.dart` | |
| E-Q19 | One eligibility policy at finalization, then frozen | Partial | `78750b3` | `chart_snapshot_builder_service_test.dart` "SN-50 one eligibility policy (E-Q19)" | Songs blocked at finalization are excluded. **Open question** (Progress BLOCKED #8): exclude songs and albums no longer in the local library? The Trash leg waits on Session C. |

## 6. Session F: Sonus Moments

New rules apply from `ChartMomentRules.refinedFromUtc` = 2026-11-01 UTC (open question: Progress BLOCKED #9). Earlier items are unchanged and nothing is backfilled.

| ID | Decision (short) | Status | Commit(s) | Tests / evidence | Notes |
|---|---|---|---|---|---|
| F-Q1 | Every chart entry #1–200 gets a story | Implemented+tested | `ba2d575` | `moments_reachability_test.dart` scenarios 7/8 | |
| F-Q2 | Exceptional peak-match stories | Partial | `ba2d575` | `moments_reachability_test.dart` "31 families publish, including peak matches" | `songPeakMatch` is wired. No release equivalent. |
| F-Q3 | #1, Top 10 and longevity streak stories | Partial | `ba2d575` | as F-Q2 | `songWeeksMilestone` is wired. **`releaseWeeksMilestone` still never publishes.** |
| F-Q4 | Selective falls, exits and dethronings | Deferred | — | Editorial N-7 draft only | |
| F-Q5 | Name only a verified displaced leader | Implemented+tested | `ba2d575` | `moments_reachability_test.dart` scenario 9, `moment_editorial_test.dart` "a displaced #1 with the same artist name but no verified artist…" | Old stories keep their text (repair would need approval, BLOCKED #11). |
| F-Q6 | One play may produce several distinct major stories | Implemented+tested | `ba2d575` | `moments_reachability_test.dart` "scenario 8: a career milestone on the same play never replaces…", `moment_editorial_test.dart` "one play tells its debut and its new top artist" | |
| F-Q7 | Major stream milestones get their own story; minor ones become supporting text | Partial | `ba2d575` | Progress 6a groups it with F-Q6/F-Q9 | No test was found that names the major-vs-supporting split for stream milestones. |
| F-Q8 | Finalized-week stories refer to the completed week | Partial | `ba2d575` | `moment_editorial_test.dart` "SN-50 headlines never call a finished week 'this week'" | New lines only. Existing variants are unchanged pending editorial approval (Gated: editorial, P-items). |
| F-Q9 | Keep debut and career milestone separate | Implemented+tested | `ba2d575` | as F-Q6 | |
| F-Q10 | Nth #1 ordinals with explicit chart scope | Partial | `ba2d575` | `moments_reachability_test.dart` "a weekly repeat #1 counts the stored weeks and names the weekly…" | Weekly chart only. Explicit scope in existing repeat-#1 lines is Editorial §6 Q1 (open). |
| F-Q12 | Mandatory entries exempt from the 3/day minor cap | Implemented+tested | `ba2d575` | `moments_reachability_test.dart` scenario 8 | |
| F-Q14 | First entries into Top 75…#1 plus Top 100 and initial entry | Partial | `ba2d575` | `moments_reachability_test.dart` scenario 7 | **Missing:** an all-time jump straight to #1 skips the Top 100 entry story (Progress 6a). |
| F-Q14B | Separate major stories; lower thresholds consolidated | Implemented+tested | `ba2d575` | `moments_reachability_test.dart` scenario 7 | **Open questions:** which crossings are "major" (Editorial §6 Q3); major-zone noise, up to 6–7 stories (BLOCKED #10). |
| F-Q15 | Artist simultaneous-entry roundups alongside individual stories | Partial | `ba2d575` | Progress 6a (new N-5 release roundup) | Release roundup done. **Missing:** all-time roundups. Top 200 naming is Editorial §6 Q2. |
| F-Q16 | Self-replacement wording at #1 | Implemented+tested | `ba2d575` | `moments_reachability_test.dart` scenario 9 | |
| F-Q17 | Current song Moments use verified song or edition art | Implemented+tested | `9aee76d` | `moment_editorial_test.dart`, `charts_controller_moments_feed_test.dart` | New stories only. |
| F-Q18 | Shared-cover layout in a two-song rivalry | Implemented+tested | `ba2d575`, `9aee76d` | `moments_reachability_test.dart` scenario 9 | |
| F-Q19 | Role-aware verified performers | Implemented+tested | `9aee76d` | `moment_editorial_test.dart` | New song stories show the credit line, unlinked. |
| F-Q20 | All featured names; no invented links or stream credit | Implemented+tested | `9aee76d` | `moment_editorial_test.dart` | |
| F-Q21 | Natural person/project phrasing; no "its" for people | Partial | `ba2d575` | `moment_editorial_test.dart` (new lines contain no " its ") | Existing copy rewrites (P-items) are Gated (editorial). |
| F-Q22 | Chart context appears once; no duplicate chrome | Implemented+tested | `9aee76d` | `charts_page_test.dart`, `moment_editorial_test.dart` | Display chrome only. |
| F-Q23 | Artist-focused stories have no song-rank badge | Implemented+tested | `9aee76d` | `charts_page_test.dart` | |
| F-Q24 | Real-time vs completed-week wording | Partial | `ba2d575` | as F-Q8 | As F-Q8. |
| F-Q25 | One chronological feed, filters, lazy bounded paging | Implemented+tested | `9aee76d` | `chart_moment_feed_pager_test.dart`, `sqlite_chart_moment_repository_test.dart` (query plan), `charts_controller_moments_feed_test.dart` | |
| F-Q26 | Simple new-content dot; no per-story tracking | Implemented+tested | `9aee76d` | `charts_page_test.dart`, `charts_controller_moments_feed_test.dart` | **Choice to confirm:** the dot shows on first launch. |
| F-Q27 | Finalized-week entries only after finalization; real-time career achievements | Implemented+tested | `8956e3a`, `ba2d575` | `chart_finalization_service_test.dart`, `moments_reachability_test.dart` | `LiveChartMomentService` stays unwired for This Week. |
| F-Q28 | Publisher by story character | Implemented+tested | `9aee76d` | `moment_editorial_test.dart` "F-Q28: an SN-50 story's publisher follows its character" | **Choice to confirm:** Sonus Daily never covers #1 arrivals. Old stories keep the hash split. |
| F-Q29 | Distinct, varied, publisher-specific template families | Gated (editorial) | `ba2d575` (27 draft lines) | `moment_editorial_test.dart` "the SN-45 catalog keeps its 384 headlines" | 27 new draft lines, not the 6+6 per family needed (BLOCKED #12). Existing 384 variants unchanged pending line-by-line review (Editorial P-001–P-050). |
| F-Q30 | Count all verified history; no backfill | Partial | `ba2d575` | as F-Q10 | Weekly scope counts all stored history. No backfill. |
| F-Q31 | Every verified re-entry, no minimum | Implemented+tested | `ba2d575` | `moments_reachability_test.dart`; `moment_story_planner.dart:18` | Follows E-Q2. Editorial §6 Q4 notes the register/spec numbering conflict; this matrix follows the Master Spec. |

---

## 7. Separate tracks: G Insights, H Visual Polish, I Account & Cloud

**G Insights, H General Visual Polish and I Account & Cloud remain separate tracks.** They were not implemented beyond the explicitly approved cross-surface effects. No file under Insights, analytics or qualification logic changed on this branch (`git diff --name-only 36d4d5d..HEAD -- lib` has no insights/analytics/qualif paths). No cloud, Supabase, OAuth or sync activation work was done.

Cross-surface effects that were done:
- **"All Time" wording retired** in Charts and in Artist Profile (Top Tracks subtitle now "Your most streamed songs") (`3dbaaa0`).
- **Accessibility and theme work within A–F surfaces only:** RE-ENTRY token with 3:1 contrast in all nine themes, focus outline on standings cards, flat Artist hero backdrop for Decoration Off / High Contrast / Low Effects (`3dbaaa0`, `70fdf64`).
- **Release Leaked column** travels in the local cloud-archive row shape like Live. It is not deployed (B-Q19, Gated: cloud).
- **Edition delete refuses** a primary in the signed-in user's cloud baseline. This is a local guard only, with no sync-code change (A-Q16).

Not done (by design):
- **Deluxe-first was not applied to Insights.** A-Q21 is Partial for that reason.
- No Insights album-ranking or Singles changes, no Year in Sonus fix, no translucent or glass redesign, no sync or cloud activation.

## 8. Open questions and choices to confirm (collected)

From Progress BLOCKED_NEEDS_APPROVAL: #1 DB v41 on real devices (install approval) · #2 B-Q19 cloud · #3 signed-out edition delete · #4 pre-`e4027e7` unqueued placements (re-queue repair) · #5 A-Q7D repairs · #6 A-Q12 edition-view precedence · #7 editorial P-001–P-050 / N-1–N-7 · #8 E-Q19 library-missing exclusion · #9 Moments gate date · #10 major-zone noise · #11 old-story repair · #12 new template copy · #13 Design §6 approvals (A-T0…A-T8, P-1…P-7, R-1…R-4, M-1…M-7).

Also: D-Q16 M-1 (Play after a completed queue) · C-Q2 Track Studio auto-link policy · Editorial §6 Q1–Q4 · confirm M-2/M-3 were approved before `9547ef0`.

## 9. Cross-cutting requirements (§0, 1–8)

| # | Requirement | Status | Evidence |
|---|---|---|---|
| 1 | Never silently modify finalized charts, published Moments or qualified history | Implemented+tested | `8956e3a`: stored weeks never rebuilt, `publishFinalizedForWeek` inserts once and never replaces. `chart_finalization_restore_test.dart` freeze suite (late plays, renames, 25 passes; 7 tests fail with the freeze disabled). `78750b3` old-engine week stays byte-identical. Moments rules are cut over at 2026-11-01 with no backfill. |
| 2 | No identity reclassification or merge, invented plays or backfill; qualification rules unchanged | Implemented+tested | No analytics or qualification file changed. `PlaybackTrack.title/artistName` unchanged; analytics records plain values (`library_track_playback_mapper_test.dart`). Credit duplicates compared by identity; no auto-link (`track_credit_editor_dialog_test.dart`). Completed queue counted once (`system_controls_regression_test.dart`). |
| 3 | Nine dark themes, Decoration Off / High Contrast / Low Effects, responsive, screen-reader semantics | Implemented+tested | `artist_profile_session_b_test.dart` and `track_selection_bar_test.dart` (320dp, 2× text, 9 themes); `sonus_theme_catalog_test.dart` (RE-ENTRY 3:1); B-Q21 hero test; selection rows announce checked state. No light redesign. |
| 4 | Retire "All Time" globally; keep Hot 100 heading; period keys and snapshots unchanged | Implemented+tested | `3dbaaa0`; `charts_page_test.dart` scan; no quoted "all time"/"all-time" string remains in `lib/` (the 10 base occurrences in charts and artist profile are gone). Hot 100 pinned. No new Moments line contains "all time" (`moment_editorial_test.dart`). |
| 5 | One release identity across editions; one-play attribution | Implemented+tested | `chart_album_presentation_test.dart` (Deluxe changes display only; position and streams are the parent's); `chart_snapshot_builder_service_test.dart` "one qualified song play contributes one album chart unit"; B-Q18/B-Q26 playback rules don't double-credit. |
| 6 | v31–40 backups restorable; versioned migrations; cloud and deletion gated | Implemented+tested | `2a10990`: `leaked_backup_compatibility_test.dart` (each v31–v40, v41 round-trip), `organization_schema_migration_test.dart` (literal v40 shape), `portable_schema_compatibility_test.dart`. No down-migration pattern exists; rollback means restoring the pre-upgrade backup. |
| 7 | No real phone, production, cloud, MP3 or remote-Git operation without approval | No change needed (complied) | Progress Ph0: local worktree, `config/sonus.dev.json` not copied. Branch has no upstream and no remote `sn-50*`. `sonus_next_sn49` left with only its 7 registrants (one contained subagent incident reverted and verified, Progress 2c). Destructive work is design-only. |
| 8 | Don't infer that design choices remove safety restrictions; record gates | Implemented | Gates recorded in `SN50_Destructive_Workflows_Design.md` §6/§7 and Progress BLOCKED #1–13. Plugin patches, Trash, phone delete and ringtones were not coded. |

## 10. Acceptance scenarios (§9, 1–12)

| # | Scenario | Status | Evidence |
|---|---|---|---|
| 1 | Finalized week unchanged across reloads, edition change, new play, rename, block/Trash, synced event | Implemented+tested (Trash leg N/A) | `chart_finalization_restore_test.dart` (late plays, renames, 25 passes, restore races); `78750b3` freeze regression with a later-blocked song. Trash doesn't exist yet. |
| 2 | Context-correct song art; historical art unchanged | Implemented+tested | `e4027e7` artwork order (`library_query_dao_test.dart`); `9aee76d` new-story covers, old covers kept. Open question A-Q12 (edition view precedence). |
| 3 | Deluxe presentation in Charts/Insights, single aggregation, profile uses primary count, tap opens shown edition | Partial | Charts: `chart_album_presentation_test.dart`, `charts_page_test.dart`; profile count: `1a017eb`. **Insights not done** (G track). |
| 4 | Standard renumbers after dropping Deluxe-only tracks; manual prompt; per-disc restart; one-disc headings hidden | Implemented+tested | `album_edition_track_ordering_service_test.dart`, `album_edition_management_service_test.dart`, `release_studio_editions_test.dart`, `album_profile_page_test.dart` |
| 5 | Artist sections and collaboration playback, role-aware, no double counting, unavailable handling | Implemented+tested | `artist_profile_session_b_test.dart`, `artist_profile_sections_test.dart` |
| 6 | Version suffix in Search, Now Playing, Queue and system; canonical title and history untouched | Implemented+tested | `song_display_title_test.dart`, `media_session_state_mapper_test.dart`, `library_track_playback_mapper_test.dart`, `library_query_dao_test.dart`. Playlist and Release Studio rows still plain (C-Q6 Partial). |
| 7 | #190 debut, then each first threshold, including a multi-threshold jump | Partial | `moments_reachability_test.dart` "scenario 7". Gap: an all-time jump straight to #1 skips the Top 100 entry (F-Q14). |
| 8 | Five deep debuts give five stories; minor cap 3; milestones never suppress entries | Implemented+tested | `moments_reachability_test.dart` "scenario 8" (both tests) |
| 9 | Verified #1 rival; self-replacement; featured names; shared cover once | Implemented+tested | `moments_reachability_test.dart` "scenario 9"; `moment_editorial_test.dart` |
| 10 | Day-30 logical purge, history kept, no resurrection, no remote physical delete | Gated (destructive) | Design §1.6, §5.1; approvals A-T0–A-T8, A-T1/A-T2 |
| 11 | Dismiss keeps queue; BT/system resume restores; completed queue paused on last track; no duplicate stream | Partial | `sonus_audio_handler_test.dart` (dismiss, D-Q8 restore-then-play), `sonus_audio_handler_browse_test.dart` (D-Q9), `system_controls_regression_test.dart` (D-Q16). Device QA gated (M-6). Killed-process native path unverified. Finished queue not kept across restart. |
| 12 | No token/config display, cloud contact, production write, ADB, MP3 op, remote Git or old-week repair | No change needed (complied, by inspection) | Progress Ph0/Ph7/Ph8; no upstream or remote branch; config not copied; freeze prevents old-week repair; destructive and device work design-only. |

## 11. Totals per status

| Session | IDs | Implemented+tested | Partial | Gated | Deferred | No change needed | Open question | In progress (final batch) |
|---|---|---|---|---|---|---|---|---|
| A | 49 | 35 | 8 | 1 | 1 | 4 | 0 | 0 |
| B | 31 | 29 | 1 | 1 | 0 | 0 | 0 | 0 |
| C | 30 | 12 | 1 | 16 | 1 | 0 | 0 | 0 |
| D | 19 | 8 | 4 | 3 | 1 | 3 | 0 | 0 |
| E | 18 | 16 | 1 | 0 | 0 | 1 | 0 | 0 |
| F | 30 | 18 | 10 | 1 | 1 | 0 | 0 | 0 |
| **Total** | **177** | **118** | **25** | **22** | **4** | **8** | **0** | **0** |

Gated breakdown (22): cloud 3 (A-Q16B, B-Q19, C-Q13B) · destructive or destructive/device 15 (the rest of Session C: Trash, phone delete, ringtones) · device 1 (D-Q5) · plugin 2 (D-Q11, D-Q14) · editorial 1 (F-Q29). A-Q16's cloud remainder is inside a Partial row and isn't counted here.

Updated after `14b592f`: A-Q6A, A-Q6B, C-Q5 and C-Q12 are now Implemented+tested. A-Q7 is an earlier-session reference the spec cites inside A-Q19; it is counted separately. IDs the spec never mentions (for example A-Q11, B-Q3–B-Q6, E-Q6, F-Q11, F-Q13) are not included.

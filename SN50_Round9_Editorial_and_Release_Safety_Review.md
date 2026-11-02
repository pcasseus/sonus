# SN-50 Round 9 Editorial and Release Safety Review

**Checkpoint:** `6f5214c`, with 5,098 tests passing. Read-only for application code: no Dart, schema, plugin or cloud change, no test run, and the refined Moments flag stays off. Paths are relative to `C:\dev\sonus\sonus_next_sn50\`.

## 1. Chart-jump approvals needed (`SN50_Chart_Jump_Editorial_Approval_Sheet.md`)

Detection is in `lib/features/charts/presentation/editorial/moment_story_planner.dart` (`copyGated`, `GatedMomentKind.hot100MajorClimb` / `hot100ClimbRun`, `ChartJumpFacts`, constants `hot100MajorClimbMinimum` = 25, `hot100ClimbRunWeeks` = 3, `hot100ClimbRunMinimum` = 30). It is held and never published.

### Headlines (26 lines)

| Family | IDs | SD / PP | Facts needed | Issues found in review |
|---|---|---|---|---|
| A. Major Hot 100 jump | CJ-001 to CJ-012 | 6 / 6 | existing `subject`, `work`, `artist`, `rank`, `previousRank`, `places` | CJ-011 ("the jump of the week") would contradict the biggest-gainer story when both exist: approve only with the D3 rule, or reject |
| B. Climb run | CJ-020 to CJ-031 | 6 / 6 | NEW `runFromRank`, `runWeeks`, `runPlaces` | CJ-028 builds the ordinal as `${f.runWeeks}th` ("3th"): needs an ordinal fact (the desk already has `ordinal` helpers for #1 counts) or a rewrite |
| C. Streaming sentence (body only) | CJ-040, CJ-041 | — | NEW `weekStreams`, `streamGain` | CJ-040 says "this week", which breaks the completed-week rule: revise to "in the week". Both must follow the approved SN-49 floor (`MomentFacts.notableStreams` = 10, `moment_facts.dart:199-205`): no sentence when `weekStreams` < 10 |

### Selection rules (provisional; your approval needed)

- **R-J1, major jump:** both ranks are #1–100 and the climb is ≥ 25 places (`_withinHot100`, `copyGated`).
- **R-J2, run:** ≥ 3 consecutive verified weekly Hot 100 climbs totalling ≥ 30 places. Each link is matched by week end and previous rank (`_previousWeek`, `_climbRun`).
- **R-J3, stream gain:** only when the previous week's entry is verified. Never shown when negative (sheet §C).

### Publisher

- Under refined rules the desk uses **one publisher per family** (`MomentEditorialDesk.publisherFor`, `moment_editorial_desk.dart:433`). Only the other publisher's lines are used as a fallback when none fits (`_write`, ~:173–210).
- The sheet's "6 SD + 6 PP like F10" therefore means only one half is normally used. **Decide:**
  - assign each family to one publisher (suggestion: A to PulsePop, like `songBiggestGainer` and `songBigClimb`; B to Sonus Daily, a measured, counted record); and
  - whether the 6 + 6 rule still applies, or 6 lines from the assigned publisher are enough.

### Overlap policies

| ID | Question | Suggestion |
|---|---|---|
| O-1 | A jump that is also the week's biggest gainer | The biggest gainer keeps its story; no jump story. This matches the approved BU rise rule (`moment_story_planner.dart:480-487`) |
| O-2 | A jump and a run in the same week for the same song | Tell the run only (it includes the jump) |
| O-3 | A jump that also first enters a zone (e.g. #40 → #8 is +32 and a first Top 10), or a new peak | The zone or #1 story leads (R3), and the jump becomes supporting body text, not a second headline |
| O-4 | Mandatory (outside the daily cap, like BU rises 20+) or minor (capped)? | Mandatory for runs; jumps capped like other minor stories unless in the Top 40 |
| O-5 | Releases (albums and EPs)? | Songs only for now (detection is songs only) |

## 2. Reconciliation with the approved rules

| Approved rule (source) | Interaction with chart jumps | Status |
|---|---|---|
| Guaranteed debuts and re-entries #1–200; a first Hot 100 entry from BU is guaranteed and never a climb (F-Q1, BUG-04; planner `:224-244`, `:323-349`) | A jump needs both ranks in the Hot 100, so an entry is never a jump; BU → Hot 100 is excluded (test "Bubbling Under moves are never Hot 100 jumps") | Consistent |
| BU rise 20+ is one guaranteed story, outside the cap; the biggest gainer keeps its own (approved rule 1; `:483-487`) | Jumps are Hot 100 only, so they never overlap | Consistent; mirror this for O-1 |
| BU falls 30+ and notable exits are detected and held (rules 2–3) | Same held mechanism (`copyGated`), separate ids | Consistent |
| Biggest gainer: one per finalized chart week, ≥ 10 places, never a BU → Hot 100 move (`moment_editorial_desk.dart:478-530`) | The song chart's gainer may be a BU song, so a Hot 100 jump of 25+ in the same week is otherwise untold. That is the gap jumps fill | Needs O-1 |
| Zones: first Top 75…#1 entries; only #1 and the first Top 10 stand alone, others consolidated (R3, `9a5cdbb`) | A big jump can cross zones | Needs O-3 |
| Movement measured against the previous **finalized** rank (E-Q2) | Jumps and runs read the finalized events' `previousRank` and check each link | Consistent |
| Stream milestone ≥ 1,000 is major (F-Q7, rule 6); counts under 10 are never quoted (SN-49) | Run and jump stream facts are separate from places; the CJ-040/041 sentence must apply the floor of 10 | Fix the sheet §C wording as above |
| Published Moments and finalized weeks frozen (F6, `8956e3a`) | Detection only reads stored events | Consistent |

**Consecutive upward movements:** no earlier approved rule covers them. R-J2 is new and fully provisional.

## 3. Approved-family guard (recommended before the flag can ever be set)

**What could publish today if the flag were on.** The refined planner emits these nine families (`moment_story_planner.dart`, `plan`). Their only lines are the N-2 to N-6 drafts in `moment_headlines.dart` under "SN-50 new pathways" (`:2674`):

| Family | Draft lines (SD / PP) | Line |
|---|---|---|
| `songSelfReplacement` | 2 / 2 | `moment_headlines.dart:2678` |
| `releaseSelfReplacement` | 1 / 1 | `:2712` |
| `songFirstThreshold` | 2 / 2 | `:2732` |
| `releaseFirstThreshold` | 1 / 1 | `:2766` |
| `songThresholds` | 1 / 1 | `:2786` |
| `releaseThresholds` | 1 / 1 | `:2804` |
| `artistRepeatNumberOne` | 1 / 1 | `:2824` |
| `artistRepeatNumberOneRelease` | 1 / 1 | `:2842` |
| `artistSimultaneousReleases` | 2 / 1 | `:2862` |

Two further paths publish text nobody approved line by line:
- **Neutral fallback:** when no line's facts fit, `_write` uses `neutral-${family}` built by `_neutralHeadline` (`moment_editorial_desk.dart` ~:205–212). This applies to every family, approved ones included.
- **Approved families with pending rewrites:** weekly refined stories in approved families still print "this week's" through `${f.chart}` (`moment_facts.dart:233-238`; Editorial P-003, P-005 to P-009). That copy is approved but has open rewrite proposals.

**Recommended guard (small, code-level):**

1. **Approved set.** `MomentHeadlines.approvedFamilies` is a const set listing every family declared before the "SN-50 new pathways" marker. A family joins it only when its approved lines land (at least 6 for its `publisherFor` publisher, per the §1 decision).
2. **Gate in the desk.** In `MomentEditorialDesk.compose`, under refined rules (`refined == true`), a planned moment whose family is not in the set is **held**, not written. It is added to `copyGated` as a new `GatedMomentKind.unapprovedCopy`, keeping its planned id so detection, ids and tests stay stable. Legacy planning is untouched: legacy only uses approved families.
3. **Neutral fallback.** Keep it for approved families. It is also refused for families outside the set; the gate already prevents that.
4. **Tests:**
   - every approved family has at least 6 distinct lines for its assigned publisher;
   - with activated rules, the reachability harness (`moments_reachability_test.dart`) publishes no story from the nine draft families, and lists them as held;
   - legacy and pre-activation stories stay byte-identical (existing tests);
   - moving a family into the set (in a test) makes it publish.
   - Existing tests that assert refined publication of N-2 to N-6 stories (scenarios 7 and 9, the R3 group, the round-6 self-replacement tests) would change from "published" to "held". That is the intended change and needs your approval.
5. **Optional build check.** `tool/build-release.ps1` prints whether `SONUS_MOMENTS_REFINED_APPROVED` is set. It could refuse the flag while any planner-reachable family is outside the approved set (a Dart test can export that list).

## 4. Android `content://` Import Review limitation

**Cause (verified):**
- `MediaMetadataReader.read` (`lib/features/import/data/services/media_metadata_reader.dart:18-50`) copies a `content://` file to a temp file with the v2 `Saf.copyToLocalFile`, then reads its tags. It throws `FormatException` when the tags are unreadable.
- `MetadataResolver` (`lib/features/import/application/services/metadata_resolver.dart:16-27`) catches every primary-reader error (`catch (_)`) and falls back to path-derived metadata (`MetadataSource.fallback`).
- `PossibleRecordingReviewService.importSeparately` (`lib/features/import/application/services/possible_recording_review_service.dart:126-136`) treats `MetadataSource.fallback` as "missing or unreadable" and **removes the entry**.

The three distinct cases (gone, present but untagged, permission lost) therefore all end the same way:
1. The file is gone: correct to retire.
2. The file is present but has no readable tags: wrongly retired, and it can never be imported separately.
3. Sonus lost SAF access to the folder: wrongly retired, and the user loses the entry.

**Available read-only abstractions (no deletion):**
- `package:saf` 2.1.2 v2 `Saf`: `exists(uri)`, `stat(uri)` and `persistedPermissions()`, plus typed `SafNotFoundException` and `SafPermissionException` (`saf-2.1.2/lib/src/v2/saf.dart:69-85`, `exceptions.dart:18-27`). The legacy 1.x `exists`/`canRead` functions are deprecated; use v2.
- `dart:io` `File(path).exists()` for plain paths.

**Recommended fix (non-destructive):**
1. **Probe interface.** Add `ImportFileProbe` (application layer): `Future<ImportFileState> probe(ImportCandidate)` → `present`, `missing`, `permissionLost` or `unknown`.
   - The data implementation uses `File.exists()` for plain paths, and `Saf.exists` for `content://`, mapping `SafPermissionException` to `permissionLost`.
   - It never calls `delete`, `moveTo`, `rename` or any writer.
2. **Typed read failures.** `MediaMetadataReader` throws `ImportFileMissing` (from `SafNotFoundException` or a missing path), `ImportFileAccessDenied` (from `SafPermissionException`), or `ImportTagsUnreadable` (in place of the bare `FormatException`).
   - `MetadataResolver` still falls back exactly as today for imports, but records the failure kind on `ResolvedMetadata` (a new optional field), so callers can tell the cases apart.
3. **Review decisions.**
   - `missing` → retire the entry (as today).
   - `permissionLost` → **keep** the entry, with the message "Sonus can't read this folder any more. Reconnect it in Imports."
   - `unreadableTags` → keep the entry and allow Import separately only if the entry was itself recorded from path metadata. That needs a new optional `metadataSource` key in the pending-list JSON; older entries without it are treated as tag-based. Otherwise retire it as "changed".
   - `unknown` → keep it and say "Try again".
4. **Clean-up during scans.** When a scan sees a pending path probe as `missing`, retire it. That resolves moved-file leftovers without touching any file.
5. **Tests (fakes only, no device files):**
   - a fake `SafPlatform` (exported by `package:saf`) throwing each typed exception;
   - a fake `ImportFileProbe`;
   - resolver failure kinds;
   - each review decision (entry kept vs retired, nothing written);
   - an old JSON entry without `metadataSource`;
   - a path-metadata entry importing separately while the candidate's rows stay unchanged (reusing the round-9 row comparison).
   - A device check (M-6) confirms the real SAF behavior.

## 5. Wording awaiting approval

**Paused sync**

| Location | Text |
|---|---|
| `lib/features/sync/application/models/sync_failure.dart:26-29` (`cloudNotReady`) | "The Sonus cloud isn't ready for this version of Sonus yet. Your changes are kept on this device. Retry once the cloud is updated." |
| `lib/features/settings/presentation/widgets/settings/settings_sync_card.dart:331` (status) | "Sync paused" |
| `settings_sync_card.dart:303` (button) | "Retry" |
| `settings_sync_card.dart:199` (code line) | "Details: <code>" (same pattern as existing errors) |

**Import Review: possible different recordings** (`lib/features/import/presentation/pages/import_review_page.dart`)

| Location | Text |
|---|---|
| `:753` heading | "Possible different recordings" |
| `:758-760` explanation | "These files have the same title as a song in your library but sit at another track position. They were not imported. Choose what each one is." |
| `:834-835` card line | "May be the same as "<title>" (<disc/track/length>)" |
| `:833` card line | "The song it may duplicate is no longer in your library." |
| `:846`, `:851`, `:856` actions | "Import separately", "Same recording", "Not now" |
| `:867-869` positions | "Disc N", "Track N" / "No track number", "<length>" / "No length" |
| `:392` | "Imported as its own song. It is listed for review." |
| `:394` | "This file no longer matches that song. It was imported as usual." |
| `:396` | "This file now matches a different song. Review it again." |
| `:398` | "This file is already in your library. Removed from this list." |
| `:400-401` | "This file is missing or cannot be read. Removed from this list; nothing was imported." (changes with §4) |
| `:403-404` | "The song it may duplicate is no longer in your library. Removed from this list; rescan to import the file." |
| `:409` | "Could not import this file. It stays in this list." |
| `:425-427` | "Marked as the same recording. Nothing was added to your library." / "Could not save this choice. The file stays in this list." |
| `lib/features/import/presentation/pages/imports_page.dart:377` | "N song(s) need(s) review". N now includes pending files: suggest "N need review" or a separate count |
| `:667` (existing reason label, reused) | "Possibly a different recording of an existing song" |

## 6. Outstanding decisions (summary)

1. **Chart jumps:**
   - approve, revise or reject CJ-001 to CJ-031 and CJ-040/041, fixing CJ-028 (ordinal) and CJ-040 ("this week");
   - the R-J1 to R-J3 thresholds;
   - publisher per family, and 6+6 vs 6;
   - overlaps O-1 to O-5.
2. **Approved-family guard** (§3): approve the implementation, including that today's refined N-2 to N-6 stories become held until their copy is approved.
3. **`content://` fix** (§4): approve the probe, the typed failures, and keeping entries on permission loss.
4. **Wording** (§5): paused sync (4 strings), Import Review (17 strings), and the Imports count.
5. **Unchanged:** the refined flag stays off (#21); BUG-04 sheet; P-001 to P-050; N-1 album #101–200 naming.

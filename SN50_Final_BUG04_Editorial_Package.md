# SN-50 Final BUG-04 Editorial Package

**Status: RECOMMENDATIONS ONLY — NOT APPROVED.** Every "Recommended final wording" below is a proposal for your decision. Nothing here is in the app, and nothing is marked approved.
**Date:** 2026-10-30. **Checkpoint:** `f062551` (5,134 tests passing). Editorial preparation only: no Dart, test, SQL, Android or cloud change. The refined Moments flag stays off.
**Consolidates:** `SN50_BUG04_Editorial_Approval_Sheet.md` (BU-001 to BU-071, the original proposals, quoted verbatim below), `SN50_Editorial_Change_Proposal.md` §7, `SN50_Round9_Editorial_and_Release_Safety_Review.md`, `SN50_Progress.md` BLOCKED #17, and the current code (`moment_headlines.dart`, `moment_facts.dart`, `moment_story_planner.dart`, `moment_editorial_desk.dart`).

**How to answer:** for each ID write **Approve recommendation**, **Approve original**, **Revise: …** or **Reject**. A new family ships only with 6 Sonus Daily (SD) and 6 PulsePop (PP) distinct approved lines.

---

## 1. Three kinds of copy in this package

| Kind | Where | Status |
|---|---|---|
| **Existing approved copy** | F05 `songHot100Breakthrough` (12 lines), F10 `songBigClimb`, F12 `songReentry`, F04 `songBubblingUnderDebut` | Approved and live. Unchanged unless you approve BU-001/BU-002. |
| **Proposed revision of existing copy** | BU-001 (F05-PP-03 `song-break-p3`), BU-002 (F05-SD-02 `song-break-d2`) | Pending. |
| **New drafts** | BU-010 to BU-015 (new F05 lines), BU-020 to BU-031 (new family `songBubblingUnderFall`), BU-040 to BU-051 (new family `songHot100Exit`), BU-060 to BU-071 (optional new rise family) | Pending. |

## 2. Findings that apply across the sheet

These are the reasons behind most "Revise" recommendations.

1. **Song titles render in quotes.** `MomentFacts.work` is `"Paper Moon"` and `subject` is `"Paper Moon" by Mira Vale` (`moment_facts.dart:297-305`). The original sheet's examples drop the quotes; every example below is rendered exactly as the app would show it.
2. **Incomplete performer credits.** `${f.subject}` names featured artists ("…featuring Guest"). `${f.work} by ${f.artist}` and `${f.artist}'s ${f.work}` name only the primary artist, which reads as a full credit and leaves the guest out (F-Q19/F-Q20). A bare `${f.work}` is fine, because the card's credit line names every performer. **Recommendation:** use `${f.subject}` or a bare `${f.work}`, never `work by artist` or `artist's work`, in new lines (affects BU-012, -022, -025, -029, -043, -045, -049, -062, -065, -069).
3. **"Last week" is misleading in a finalized-week story.** These stories are published after the chart week ends, so a reader can take "last week" to mean the chart week itself. **Recommendation:** "the week before" (BU-010, BU-012, BU-013, BU-015). The approved CJ-041 ("up G on last week") has the same ambiguity; it is noted here but not reopened.
4. **Artist debut implied by a song debut.** BU-015 ("Mira Vale lands a Sonus Hot 100 debut") claims the artist is new to the Hot 100. That is a different, career fact (`artistFirstHot100`). **Revise.**
5. **Unsupported future claims.** "for now" (BU-046, BU-047), "the run pauses" (BU-051) and "Knocking on the Hot 100's door" (BU-068) predict a return or an entry. **Revise.**
6. **Unsupported claims about streams.** "cools off" (BU-030) implies listening declined; a rank can fall because other songs rose. **Revise.** No line in this package states or implies stream changes.
7. **Movement across the chart boundary.** No line shows ▲/▼N or "N places" between a Bubbling Under rank and a Hot 100 rank. Lines that give both ranks name both charts (BU-001, BU-002, BU-010 to BU-015, BU-041, BU-049).
8. **A missing fact for falls.** `MomentFacts.places` is null when the rank got worse (`moment_facts.dart:205-209`). Lines that count a fall need **NEW FACT `placesDown`** (= this week's rank − previous rank).
9. **Publishers under the refined rules.** One publisher per family (`publisherFor`). F05 is PulsePop, so BU-010 to BU-012 (SD) are used only as a fallback. Recommended: falls and exits Sonus Daily, rises PulsePop. The 6 + 6 catalog rule still applies.
10. **Published stories must not change.** Headlines are composed when the feed is shown (`charts_controller.dart:250`), and the variant is chosen by a hash modulo the number of fitting lines (`moment_editorial_desk.dart`, `_write`). Adding lines to F05 or F10, or rewording `song-break-p3`/`-d2`, would therefore **change already-published stories**. Any approved change must apply only to stories under the refined rules (after activation), so legacy and pre-activation stories stay byte-identical, as the existing tests require.

**Eligibility shorthand used below**
- **[LINK]** previousRank comes from the immediately preceding **finalized** week, matched by week end and by the stored previous rank; missing history never counts.
- **[BU]** a rank of #101–200 (Sonus Bubbling Under). **[H100]** a rank of #1–100.
- **[FIRST]** no earlier Sonus Hot 100 week for the song in stored finalized history (the rule F05 already uses).
- **[REFINED]** only stories under the refined rules, prospectively; no backfill.

---

## 3. Section B — existing F05 lines (BU-001, BU-002)

| ID | Pub | Original proposed template | Recommended final wording | Rec. | Required facts and guards | Rendered example |
|---|---|---|---|---|---|---|
| BU-001 | PP | **Current** F05-PP-03: `${f.work} jumps from #${f.previousRank} to #${f.rank}, into the Sonus Hot 100.` **Sheet proposal:** `Previously #${f.previousRank} on Sonus Bubbling Under, ${f.work} enters the Sonus Hot 100 at #${f.rank}.` | `Previously #${f.previousRank} on Sonus Bubbling Under, ${f.work} enters the Sonus Hot 100 at #${f.rank}.` | **Approve the sheet proposal** (as a new refined-only variant; the current text stays for legacy stories, finding 10) | rank [H100], previousRank [BU] [LINK], [FIRST], [REFINED]. The current line is already excluded for these stories in code. | Previously #124 on Sonus Bubbling Under, "Paper Moon" enters the Sonus Hot 100 at #87. |
| BU-002 | SD | **Current** F05-SD-02: `${f.subject} climbs from #${f.previousRank} on Sonus Bubbling Under to #${f.rank} on the Sonus Hot 100.` **Sheet proposal:** `${f.subject} enters the Sonus Hot 100 at #${f.rank}, after #${f.previousRank} on Sonus Bubbling Under last week.` | Keep the current text: `${f.subject} climbs from #${f.previousRank} on Sonus Bubbling Under to #${f.rank} on the Sonus Hot 100.` | **Approve as written (keep current)**. It names both charts, so it is not a Hot 100 movement. The sheet proposal nearly duplicates BU-010 and uses "last week" (finding 3). | rank [H100], previousRank [BU] [LINK]. | "Paper Moon" by Mira Vale climbs from #124 on Sonus Bubbling Under to #87 on the Sonus Hot 100. |

Unchanged and approved: F05-SD-05, F05-SD-06, F05-PP-02 and F05-PP-04 stay excluded only when the song was **not** on Bubbling Under the week before (round 3). See also §8, item 4, about F05-PP-04.

---

## 4. Section C — new F05 lines: first Hot 100 entry from Bubbling Under (BU-010 to BU-015)

**Family:** existing `songHot100Breakthrough` (F05, PulsePop). **Common guard:** rank [H100], previousRank [BU] [LINK], [FIRST]; "debut" wording only for a first Hot 100 entry (a song with an earlier Hot 100 week gets F12 re-entry instead). [REFINED] only (finding 10). If approved, the desk prefers these lines whenever the Bubbling Under rank is verified.

| ID | Pub | Original proposed template | Recommended final wording | Rec. | Required facts and guards | Rendered example |
|---|---|---|---|---|---|---|
| BU-010 | SD | `${f.subject} enters the Sonus Hot 100 at #${f.rank}; last week it was #${f.previousRank} on Sonus Bubbling Under.` | `${f.subject} enters the Sonus Hot 100 at #${f.rank}; the week before, it was #${f.previousRank} on Sonus Bubbling Under.` | **Revise** (finding 3) | common guard | "Paper Moon" by Mira Vale enters the Sonus Hot 100 at #87; the week before, it was #124 on Sonus Bubbling Under. |
| BU-011 | SD | `After #${f.previousRank} on Sonus Bubbling Under, ${f.subject} makes its Sonus Hot 100 debut at #${f.rank}.` | unchanged | **Approve as written** ("its" is the song) | common guard; "debut" needs [FIRST] | After #124 on Sonus Bubbling Under, "Paper Moon" by Mira Vale makes its Sonus Hot 100 debut at #87. |
| BU-012 | SD | `${f.work} by ${f.artist} debuts on the Sonus Hot 100 at #${f.rank}, having been #${f.previousRank} on Sonus Bubbling Under.` | `${f.subject} debuts on the Sonus Hot 100 at #${f.rank}, having been #${f.previousRank} on Sonus Bubbling Under the week before.` | **Revise** (findings 2, 3) | common guard; [FIRST] | "Paper Moon" by Mira Vale debuts on the Sonus Hot 100 at #87, having been #124 on Sonus Bubbling Under the week before. |
| BU-013 | PP | `Hot 100 debut! ${f.work} arrives at #${f.rank}, up from Sonus Bubbling Under (#${f.previousRank} last week).` | `Hot 100 debut! ${f.work} arrives at #${f.rank}, up from Sonus Bubbling Under (#${f.previousRank} the week before).` | **Revise** (finding 3) | common guard; [FIRST] | Hot 100 debut! "Paper Moon" arrives at #87, up from Sonus Bubbling Under (#124 the week before). |
| BU-014 | PP | `From #${f.previousRank} on Sonus Bubbling Under to a Sonus Hot 100 debut at #${f.rank}: ${f.subject} is in.` | unchanged | **Approve as written** | common guard; [FIRST] | From #124 on Sonus Bubbling Under to a Sonus Hot 100 debut at #87: "Paper Moon" by Mira Vale is in. |
| BU-015 | PP | `${f.artist} lands a Sonus Hot 100 debut as ${f.work} arrives at #${f.rank} (it was #${f.previousRank} on Sonus Bubbling Under).` | `Promoted! ${f.work} leaves Sonus Bubbling Under (#${f.previousRank}) for a Sonus Hot 100 debut at #${f.rank}.` | **Revise** (finding 4: song debut, not artist debut) | common guard; [FIRST] | Promoted! "Paper Moon" leaves Sonus Bubbling Under (#124) for a Sonus Hot 100 debut at #87. |

F05 after approval: 6 + 3 SD and 6 + 3 PP lines (plus BU-001 for refined stories). All distinct.

---

## 5. Section D — new family `songBubblingUnderFall`: Bubbling Under falls of 30+ (BU-020 to BU-031)

**Approved rule 2.** Detected today as `GatedMomentKind.bubblingUnderFall` (`#bu-fall`), never published. **Common guard:** rank [BU] and previousRank [BU] [LINK]; rank − previousRank ≥ 30; not told when the song leaves the chart (beyond #200) or enters the Hot 100; one story per song per finalized week; [REFINED]. **Recommended publisher:** Sonus Daily. Weekly scope only: SD lines say "the weekly Sonus Bubbling Under". PP lines omit "weekly", as the approved CJ PulsePop lines do; the card's kicker carries the scope.

| ID | Pub | Original proposed template | Recommended final wording | Rec. | Required facts and guards | Rendered example |
|---|---|---|---|---|---|---|
| BU-020 | SD | `${f.subject} falls from #${f.previousRank} to #${f.rank} on the weekly Sonus Bubbling Under.` | unchanged | **Approve as written** | common guard | "Paper Moon" by Mira Vale falls from #122 to #168 on the weekly Sonus Bubbling Under. |
| BU-021 | SD | `${f.subject} drops ${f.placesDown} places on the weekly Sonus Bubbling Under, to #${f.rank}.` | unchanged | **Approve as written** | common guard; NEW FACT `placesDown` | "Paper Moon" by Mira Vale drops 46 places on the weekly Sonus Bubbling Under, to #168. |
| BU-022 | SD | `${f.work} by ${f.artist} slips to #${f.rank} on the weekly Sonus Bubbling Under, down from #${f.previousRank}.` | `${f.subject} slips to #${f.rank} on the weekly Sonus Bubbling Under, down from #${f.previousRank}.` | **Revise** (finding 2) | common guard | "Paper Moon" by Mira Vale slips to #168 on the weekly Sonus Bubbling Under, down from #122. |
| BU-023 | SD | `A ${f.placesDown}-place fall on the weekly Sonus Bubbling Under takes ${f.subject} to #${f.rank}.` | unchanged | **Approve as written** | common guard; `placesDown` | A 46-place fall on the weekly Sonus Bubbling Under takes "Paper Moon" by Mira Vale to #168. |
| BU-024 | SD | `${f.subject} moves down the weekly Sonus Bubbling Under, from #${f.previousRank} to #${f.rank}.` | unchanged | **Approve as written** | common guard | "Paper Moon" by Mira Vale moves down the weekly Sonus Bubbling Under, from #122 to #168. |
| BU-025 | SD | `${f.artist}'s ${f.work} loses ${f.placesDown} places on the weekly Sonus Bubbling Under and sits at #${f.rank}.` | `${f.subject} loses ${f.placesDown} places on the weekly Sonus Bubbling Under and sits at #${f.rank}.` | **Revise** (finding 2) | common guard; `placesDown` | "Paper Moon" by Mira Vale loses 46 places on the weekly Sonus Bubbling Under and sits at #168. |
| BU-026 | PP | `Down ${f.placesDown}: ${f.work} slides to #${f.rank} on Sonus Bubbling Under.` | unchanged | **Approve as written** | common guard; `placesDown` | Down 46: "Paper Moon" slides to #168 on Sonus Bubbling Under. |
| BU-027 | PP | `${f.work} takes a tumble on Sonus Bubbling Under, from #${f.previousRank} to #${f.rank}.` | unchanged | **Approve as written** | common guard | "Paper Moon" takes a tumble on Sonus Bubbling Under, from #122 to #168. |
| BU-028 | PP | `Rough week for ${f.subject}: down to #${f.rank} on Sonus Bubbling Under.` | unchanged | **Approve as written** ("rough week" refers to the completed chart week, not to streams) | common guard | Rough week for "Paper Moon" by Mira Vale: down to #168 on Sonus Bubbling Under. |
| BU-029 | PP | `${f.artist} sees ${f.work} drop ${f.placesDown} spots to #${f.rank} on Sonus Bubbling Under.` | `${f.work} drops ${f.placesDown} spots to #${f.rank} on Sonus Bubbling Under.` | **Revise** (finding 2; also drops the implied artist agency) | common guard; `placesDown` | "Paper Moon" drops 46 spots to #168 on Sonus Bubbling Under. |
| BU-030 | PP | `From #${f.previousRank} to #${f.rank}: ${f.work} cools off on Sonus Bubbling Under.` | `From #${f.previousRank} to #${f.rank}: ${f.work} loses ground on Sonus Bubbling Under.` | **Revise** (finding 6: "cools off" implies fewer streams) | common guard | From #122 to #168: "Paper Moon" loses ground on Sonus Bubbling Under. |
| BU-031 | PP | `${f.subject} slips ${f.placesDown} places on Sonus Bubbling Under, now at #${f.rank}.` | unchanged | **Approve as written** | common guard; `placesDown` | "Paper Moon" by Mira Vale slips 46 places on Sonus Bubbling Under, now at #168. |

After the recommendations: 6 SD + 6 PP, all distinct.

---

## 6. Section E — new family `songHot100Exit`: notable Hot 100 exits into Bubbling Under (BU-040 to BU-051)

**Approved rule 3.** Detected today as `GatedMomentKind.notableHot100Exit` (`#hot-100-exit`), never published. **Common guard:** previousRank [H100] [LINK]; rank [BU]; history verifies a Top 40 peak **or** at least 5 Hot 100 weeks before the exit week; once per Hot 100 run; [REFINED]. **Peak lines** also need a verified `previousPeak` ≤ 40. No line states the number of Hot 100 weeks (only "≥ 5" is known). Both ranks are cited as positions on two different charts, never as "down 27". A song that leaves both charts (beyond #200) is not covered. **Recommended publisher:** Sonus Daily.

| ID | Pub | Original proposed template | Recommended final wording | Rec. | Required facts and guards | Rendered example |
|---|---|---|---|---|---|---|
| BU-040 | SD | `${f.subject} leaves the Sonus Hot 100 and is #${f.rank} on the weekly Sonus Bubbling Under.` | unchanged | **Approve as written** | common guard | "Paper Moon" by Mira Vale leaves the Sonus Hot 100 and is #121 on the weekly Sonus Bubbling Under. |
| BU-041 | SD | `${f.subject} slips from #${f.previousRank} on the Sonus Hot 100 to #${f.rank} on Sonus Bubbling Under.` | unchanged | **Approve as written** (names both charts) | common guard | "Paper Moon" by Mira Vale slips from #94 on the Sonus Hot 100 to #121 on Sonus Bubbling Under. |
| BU-042 | SD | `Once #${f.previousPeak} on the Sonus Hot 100, ${f.subject} moves to Sonus Bubbling Under at #${f.rank}.` | unchanged | **Approve as written** | common guard; previousPeak ≤ 40 | Once #35 on the Sonus Hot 100, "Paper Moon" by Mira Vale moves to Sonus Bubbling Under at #121. |
| BU-043 | SD | `${f.work} by ${f.artist} exits the Sonus Hot 100; it peaked at #${f.previousPeak} and is now #${f.rank} on Sonus Bubbling Under.` | `${f.subject} exits the Sonus Hot 100 after peaking at #${f.previousPeak}; it is now #${f.rank} on Sonus Bubbling Under.` | **Revise** (finding 2) | common guard; previousPeak ≤ 40 | "Paper Moon" by Mira Vale exits the Sonus Hot 100 after peaking at #35; it is now #121 on Sonus Bubbling Under. |
| BU-044 | SD | `After its Sonus Hot 100 run, ${f.subject} continues on Sonus Bubbling Under at #${f.rank}.` | unchanged | **Approve as written** | common guard | After its Sonus Hot 100 run, "Paper Moon" by Mira Vale continues on Sonus Bubbling Under at #121. |
| BU-045 | SD | `${f.artist}'s ${f.work} drops out of the Sonus Hot 100, to #${f.rank} on Sonus Bubbling Under.` | `${f.subject} drops out of the Sonus Hot 100, to #${f.rank} on Sonus Bubbling Under.` | **Revise** (finding 2) | common guard | "Paper Moon" by Mira Vale drops out of the Sonus Hot 100, to #121 on Sonus Bubbling Under. |
| BU-046 | PP | `Out of the Hot 100 for now: ${f.work} drops to #${f.rank} on Sonus Bubbling Under.` | `Out of the Sonus Hot 100: ${f.work} drops to #${f.rank} on Sonus Bubbling Under.` | **Revise** (finding 5: "for now" predicts a return) | common guard | Out of the Sonus Hot 100: "Paper Moon" drops to #121 on Sonus Bubbling Under. |
| BU-047 | PP | `${f.work} says goodbye to the Sonus Hot 100 (for now) and lands at #${f.rank} on Sonus Bubbling Under.` | `${f.work} says goodbye to the Sonus Hot 100 and lands at #${f.rank} on Sonus Bubbling Under.` | **Revise** (finding 5) | common guard | "Paper Moon" says goodbye to the Sonus Hot 100 and lands at #121 on Sonus Bubbling Under. |
| BU-048 | PP | `A #${f.previousPeak} peak behind it, ${f.subject} slides to Sonus Bubbling Under at #${f.rank}.` | unchanged | **Approve as written** | common guard; previousPeak ≤ 40 | A #35 peak behind it, "Paper Moon" by Mira Vale slides to Sonus Bubbling Under at #121. |
| BU-049 | PP | `${f.artist}'s ${f.work} falls out of the Sonus Hot 100, from #${f.previousRank} to #${f.rank} on Sonus Bubbling Under.` | `${f.work} falls from #${f.previousRank} on the Sonus Hot 100 to #${f.rank} on Sonus Bubbling Under.` | **Revise** (finding 2; the original "from #94 to #121 on Sonus Bubbling Under" can read as two Bubbling Under ranks) | common guard | "Paper Moon" falls from #94 on the Sonus Hot 100 to #121 on Sonus Bubbling Under. |
| BU-050 | PP | `Hot 100 exit: ${f.subject} is now #${f.rank} on Sonus Bubbling Under.` | unchanged | **Approve as written** | common guard | Hot 100 exit: "Paper Moon" by Mira Vale is now #121 on Sonus Bubbling Under. |
| BU-051 | PP | `The Sonus Hot 100 run pauses for ${f.work}, now #${f.rank} on Sonus Bubbling Under.` | `A Sonus Hot 100 run comes to an end: ${f.work} is now #${f.rank} on Sonus Bubbling Under.` | **Revise** (finding 5: "pauses" predicts a return) | common guard | A Sonus Hot 100 run comes to an end: "Paper Moon" is now #121 on Sonus Bubbling Under. |

After the recommendations: 6 SD + 6 PP, all distinct.

---

## 7. Section F — optional new rise family: dedicated Bubbling Under rises (BU-060 to BU-071)

**Approved rule 1.** BU rises of 20+ are **already published** with approved F10 `songBigClimb` lines, one story per song, outside the cap; the week's biggest gainer keeps its own story. This family is needed only if you want every rise headline to name Bubbling Under (F10 d3, d4, d5, p1, p2, p3, p5 and p6 name no chart). **Common guard:** rank and previousRank both [BU] [LINK]; places ≥ 20; not the week's biggest gainer; [REFINED]. **Recommended publisher:** PulsePop (as F10). If approved, it would replace F10 for Bubbling Under rises only (decision D-1, §9).

| ID | Pub | Original proposed template | Recommended final wording | Rec. | Required facts and guards | Rendered example |
|---|---|---|---|---|---|---|
| BU-060 | SD | `${f.subject} climbs ${f.places} places on the weekly Sonus Bubbling Under, to #${f.rank}.` | unchanged | **Approve as written** | common guard | "Paper Moon" by Mira Vale climbs 32 places on the weekly Sonus Bubbling Under, to #139. |
| BU-061 | SD | `${f.subject} rises from #${f.previousRank} to #${f.rank} on the weekly Sonus Bubbling Under.` | unchanged | **Approve as written** | common guard | "Paper Moon" by Mira Vale rises from #171 to #139 on the weekly Sonus Bubbling Under. |
| BU-062 | SD | `${f.work} by ${f.artist} gains ${f.places} places on the weekly Sonus Bubbling Under and reaches #${f.rank}.` | `${f.subject} gains ${f.places} places on the weekly Sonus Bubbling Under and reaches #${f.rank}.` | **Revise** (finding 2) | common guard | "Paper Moon" by Mira Vale gains 32 places on the weekly Sonus Bubbling Under and reaches #139. |
| BU-063 | SD | `A ${f.places}-place climb on the weekly Sonus Bubbling Under brings ${f.subject} to #${f.rank}.` | unchanged | **Approve as written** | common guard | A 32-place climb on the weekly Sonus Bubbling Under brings "Paper Moon" by Mira Vale to #139. |
| BU-064 | SD | `${f.subject} moves up the weekly Sonus Bubbling Under, from #${f.previousRank} to #${f.rank}.` | unchanged | **Approve as written** | common guard | "Paper Moon" by Mira Vale moves up the weekly Sonus Bubbling Under, from #171 to #139. |
| BU-065 | SD | `${f.artist}'s ${f.work} is up ${f.places} places on the weekly Sonus Bubbling Under, at #${f.rank}.` | `${f.subject} is up ${f.places} places on the weekly Sonus Bubbling Under, at #${f.rank}.` | **Revise** (finding 2) | common guard | "Paper Moon" by Mira Vale is up 32 places on the weekly Sonus Bubbling Under, at #139. |
| BU-066 | PP | `Up ${f.places}! ${f.work} jumps to #${f.rank} on Sonus Bubbling Under.` | unchanged | **Approve as written** | common guard | Up 32! "Paper Moon" jumps to #139 on Sonus Bubbling Under. |
| BU-067 | PP | `${f.work} is on the move on Sonus Bubbling Under: #${f.previousRank} to #${f.rank}.` | unchanged | **Approve as written** | common guard | "Paper Moon" is on the move on Sonus Bubbling Under: #171 to #139. |
| BU-068 | PP | `Knocking on the Hot 100's door: ${f.subject} climbs to #${f.rank} on Sonus Bubbling Under.` (guard rank ≤ 120) | `Just outside the Sonus Hot 100: ${f.subject} climbs to #${f.rank} on Sonus Bubbling Under.` | **Revise** (finding 5: states position, not a prediction) | common guard; rank ≤ 120 | Just outside the Sonus Hot 100: "Paper Moon" by Mira Vale climbs to #112 on Sonus Bubbling Under. |
| BU-069 | PP | `${f.artist} gets ${f.work} moving: up ${f.places} spots to #${f.rank} on Sonus Bubbling Under.` | `${f.work} gets moving: up ${f.places} spots to #${f.rank} on Sonus Bubbling Under.` | **Revise** (finding 2; drops the implied artist agency) | common guard | "Paper Moon" gets moving: up 32 spots to #139 on Sonus Bubbling Under. |
| BU-070 | PP | `Big week on Sonus Bubbling Under: ${f.work} climbs ${f.places} places to #${f.rank}.` | unchanged | **Approve as written** | common guard | Big week on Sonus Bubbling Under: "Paper Moon" climbs 32 places to #139. |
| BU-071 | PP | `${f.subject} surges ${f.places} spots on Sonus Bubbling Under, landing at #${f.rank}.` | unchanged | **Approve as written** | common guard | "Paper Moon" by Mira Vale surges 32 spots on Sonus Bubbling Under, landing at #139. |

After the recommendations: 6 SD + 6 PP, all distinct.

---

## 8. Tally of recommendations

| Section | Approve as written | Revise | Reject |
|---|---|---|---|
| B (BU-001, BU-002) | 1 (BU-002, keep current) | 1 (BU-001: adopt the sheet proposal) | 0 |
| C (BU-010 to BU-015) | 2 | 4 | 0 |
| D (BU-020 to BU-031) | 8 | 4 | 0 |
| E (BU-040 to BU-051) | 6 | 6 | 0 |
| F (BU-060 to BU-071) | 8 | 4 | 0 |
| **Total (44 IDs)** | **25** | **19** | **0** |

Related observations outside the BU IDs (no change proposed here):
1. F10 rises still print `${f.chart}` = "this week's Sonus Bubbling Under" under the refined rules (`moment_facts.dart:251`); fixed by P-003/P-004 (`SN50_Existing_Headline_Approval_Summary.md`).
2. Approved CJ-041 says "last week" (finding 3).
3. F05-PP-03 is only suppressed for Bubbling Under arrivals. Legacy stories that used it keep it (finding 10).
4. Existing F05-PP-04 (`${f.artist} cracks the Sonus Hot 100 as ${f.work} rises to …`) can read as the artist's first Hot 100 entry (finding 4). It is approved copy; flagged for a later P-item if you want one.

---

## 9. Decisions only you can make

| # | Decision | Recommendation |
|---|---|---|
| D-1 | Adopt the optional rise family (Section F), replacing F10 for Bubbling Under rises, or keep F10 and fix its chart name through P-003/P-004? | Keep F10 and approve P-003/P-004 first. Adopt F only if every rise headline must name Bubbling Under. |
| D-2 | BU-002: keep the current approved line, or adopt the sheet's rewrite? | Keep (§3). |
| D-3 | Tier for falls and exits: capped minor stories, or outside the daily cap like BU rises? | Falls: capped (minor). Exits: outside the cap only when the peak was Top 40. |
| D-4 | Convention for the previous week: "the week before" (recommended) or "last week"? | "the week before" everywhere in finalized-week stories. |
| D-5 | PulsePop lines without "weekly" (kicker carries the scope), as in the approved CJ lines? | Accept. |
| D-6 | 6 + 6 per family, although each family has one publisher under the refined rules? | Keep 6 + 6 (catalog rule; the other publisher is the fallback). |

## 10. Recommended approval order

1. **Section E (exits)** and **Section D (falls)**: new families. Nothing publishes them today, and their detection is ready.
2. **Section C (BU-013 to BU-015 first)**: gives PulsePop, F05's publisher, an approved line that names the Bubbling Under rank (sheet §A gap).
3. **Section B**: BU-001 (refined-only replacement) and BU-002 (keep).
4. **Section F**: only after D-1.

After your approval, implementation would add only the approved lines, gated to refined stories (finding 10). It would add NEW FACT `placesDown`, wire D and E from the existing `copyGated` ids and extend the editorial tests: 6 + 6 distinct lines, banned phrases, punctuation, quoted titles and no cross-chart movement figures. Until then the refined flag stays off and BUG-04 remains a release blocker (Progress BLOCKED #17).

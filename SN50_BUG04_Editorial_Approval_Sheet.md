# SN-50 BUG-04 Editorial Approval Sheet

**Status:** AWAITING YOUR LINE-BY-LINE APPROVAL. Nothing on this sheet is in the app. The 384 original headline variants and P-001 to P-050 are unchanged.
**Date:** 2026-10-30. **Code checkpoint:** `83a7d96` (4,954 tests passing). Detection described here is in `59a33bd`.
**Authority:** `C:\dev\sonus\SN50_BUG04_Import_Final_Decisions_Claude_Handoff.md` (six approved rules; wording not approved). Supersedes the BUG-04 drafts N-8 to N-11 in `SN50_Editorial_Change_Proposal.md` §7.3, which were short samples.

**How to answer:** for each ID write **Approve**, **Revise: …** or **Reject**. A new family ships only when at least 6 Sonus Daily (SD) and 6 PulsePop (PP) lines are approved, all distinct. Under the refined rules each family has one publisher (`MomentEditorialDesk.publisherFor`), but the catalog's 6 + 6 rule still applies.

**Placeholders** (existing `MomentFacts`): `${f.subject}` = "Paper Moon by Mira Vale"; `${f.work}` = "Paper Moon"; `${f.artist}` = "Mira Vale"; `${f.rank}` = this week's rank; `${f.previousRank}` = last finalized week's rank; `${f.places}` = places moved; `${f.previousPeak}` = best rank before this week. **NEW FACT** marks a value `MomentFacts` doesn't have yet.

**Common rules for every line:** completed-week wording (never "this stream"); a #101–200 rank is named as Sonus Bubbling Under, never the Hot 100; no ▲N between a Bubbling Under rank and a Hot 100 rank; no "lifetime", "all-time" or other retired phrases; ends in "." or "!".

---

## A. Coverage today (no approval needed)

| Case | Today | Copy used |
|---|---|---|
| BU rise of 20+ (#171 → #139) | **Published** (one story per qualifying song, outside the daily cap; the week's biggest gainer keeps its own story instead) | Approved F10 `songBigClimb`, e.g. "Paper Moon by Mira Vale climbs 32 places to #139 on this week's Sonus Bubbling Under." (the "this week's" wording is the pending P-003 item) |
| First Hot 100 entry from BU (#124 → #87) | **Published** (guaranteed) | Approved F05 `songHot100Breakthrough`, without F05-PP-03 (see BU-001) |
| Hot 100 re-entry from BU (#112 → #90) | **Published** (guaranteed) | Approved F12 `songReentry` |
| BU fall of 30+ (#122 → #168) | **Detected, not published: BLOCKED_EDITORIAL** (section D) | none approved |
| Notable Hot 100 exit to BU (#94 → #121, Top 40 peak or 5+ Hot 100 weeks) | **Detected, not published: BLOCKED_EDITORIAL** (section E) | none approved |
| First Hot 100 entry naming last week's BU rank | **Partial**: the story publishes, but its publisher (PulsePop) has no approved line that names the BU rank (section C) | — |

---

## B. Existing variants implicated by Bubbling Under → Hot 100 moves

| ID | Catalog ID / source id | Current text (verbatim) | Issue | Proposed prospective replacement | Facts / guard | Example | Decision |
|---|---|---|---|---|---|---|---|
| BU-001 | F05-PP-03 `song-break-p3` | `${f.work} jumps from #${f.previousRank} to #${f.rank}, into the Sonus Hot 100.` | Reads as a 37-place Hot 100 climb; doesn't say #124 was Bubbling Under (E-Q1). **Already suppressed** for these stories in code; no text was changed. | `Previously #${f.previousRank} on Sonus Bubbling Under, ${f.work} enters the Sonus Hot 100 at #${f.rank}.` | rank + previousRank; previousRank 101–200, last finalized week | "Previously #124 on Sonus Bubbling Under, Paper Moon enters the Sonus Hot 100 at #87." | Approve / Revise / Reject |
| BU-002 | F05-SD-02 `song-break-d2` | `${f.subject} climbs from #${f.previousRank} on Sonus Bubbling Under to #${f.rank} on the Sonus Hot 100.` | Accurate (names both charts) and still selectable; "climbs" may suggest official movement. Optional. | `${f.subject} enters the Sonus Hot 100 at #${f.rank}, after #${f.previousRank} on Sonus Bubbling Under last week.` | same as BU-001 | "Paper Moon by Mira Vale enters the Sonus Hot 100 at #87, after #124 on Sonus Bubbling Under last week." | Keep / Revise / Reject |

F05-SD-05, F05-SD-06, F05-PP-02 and F05-PP-04 are skipped in code only when the song was **not** on Bubbling Under last week (round 3). No text change is proposed for them.

---

## C. First Hot 100 entry with verified Bubbling Under context (additions to F05)

New variants inside the existing F05 family. They require `previousRank` (#101–200, last finalized week); without it they are never chosen. If approved, the desk would prefer them when the rank is verified.

| ID | Publisher | Proposed text | Example | Decision |
|---|---|---|---|---|
| BU-010 | SD | `${f.subject} enters the Sonus Hot 100 at #${f.rank}; last week it was #${f.previousRank} on Sonus Bubbling Under.` | "Paper Moon by Mira Vale enters the Sonus Hot 100 at #87; last week it was #124 on Sonus Bubbling Under." | Approve / Revise / Reject |
| BU-011 | SD | `After #${f.previousRank} on Sonus Bubbling Under, ${f.subject} makes its Sonus Hot 100 debut at #${f.rank}.` | "After #124 on Sonus Bubbling Under, Paper Moon by Mira Vale makes its Sonus Hot 100 debut at #87." | Approve / Revise / Reject |
| BU-012 | SD | `${f.work} by ${f.artist} debuts on the Sonus Hot 100 at #${f.rank}, having been #${f.previousRank} on Sonus Bubbling Under.` | "Paper Moon by Mira Vale debuts on the Sonus Hot 100 at #87, having been #124 on Sonus Bubbling Under." | Approve / Revise / Reject |
| BU-013 | PP | `Hot 100 debut! ${f.work} arrives at #${f.rank}, up from Sonus Bubbling Under (#${f.previousRank} last week).` | "Hot 100 debut! Paper Moon arrives at #87, up from Sonus Bubbling Under (#124 last week)." | Approve / Revise / Reject |
| BU-014 | PP | `From #${f.previousRank} on Sonus Bubbling Under to a Sonus Hot 100 debut at #${f.rank}: ${f.subject} is in.` | "From #124 on Sonus Bubbling Under to a Sonus Hot 100 debut at #87: Paper Moon by Mira Vale is in." | Approve / Revise / Reject |
| BU-015 | PP | `${f.artist} lands a Sonus Hot 100 debut as ${f.work} arrives at #${f.rank} (it was #${f.previousRank} on Sonus Bubbling Under).` | "Mira Vale lands a Sonus Hot 100 debut as Paper Moon arrives at #87 (it was #124 on Sonus Bubbling Under)." | Approve / Revise / Reject |

Guard: "debut" lines (BU-011 to BU-015) are used only for a **first** Hot 100 entry. A song with an earlier Hot 100 week gets the F12 re-entry story instead (already enforced).

---

## D. New family: Bubbling Under fall of 30+ places (`songBubblingUnderFall`, approved rule 2)

Detected today (`GatedMomentKind.bubblingUnderFall`); ships only with 6 + 6 approved lines. Facts: previousRank and rank both 101–200; places ≥ 30 (NEW FACT `placesDown`, or `${f.previousRank} - ${f.rank}` computed as a fall). Recommended publisher: Sonus Daily.

| ID | Pub | Proposed text | Example | Decision |
|---|---|---|---|---|
| BU-020 | SD | `${f.subject} falls from #${f.previousRank} to #${f.rank} on the weekly Sonus Bubbling Under.` | "Paper Moon by Mira Vale falls from #122 to #168 on the weekly Sonus Bubbling Under." | A / R / Rj |
| BU-021 | SD | `${f.subject} drops ${f.placesDown} places on the weekly Sonus Bubbling Under, to #${f.rank}.` | "… drops 46 places on the weekly Sonus Bubbling Under, to #168." | A / R / Rj |
| BU-022 | SD | `${f.work} by ${f.artist} slips to #${f.rank} on the weekly Sonus Bubbling Under, down from #${f.previousRank}.` | "Paper Moon by Mira Vale slips to #168 …, down from #122." | A / R / Rj |
| BU-023 | SD | `A ${f.placesDown}-place fall on the weekly Sonus Bubbling Under takes ${f.subject} to #${f.rank}.` | "A 46-place fall … takes Paper Moon by Mira Vale to #168." | A / R / Rj |
| BU-024 | SD | `${f.subject} moves down the weekly Sonus Bubbling Under, from #${f.previousRank} to #${f.rank}.` | "… from #122 to #168." | A / R / Rj |
| BU-025 | SD | `${f.artist}'s ${f.work} loses ${f.placesDown} places on the weekly Sonus Bubbling Under and sits at #${f.rank}.` | "Mira Vale's Paper Moon loses 46 places … and sits at #168." | A / R / Rj |
| BU-026 | PP | `Down ${f.placesDown}: ${f.work} slides to #${f.rank} on Sonus Bubbling Under.` | "Down 46: Paper Moon slides to #168 on Sonus Bubbling Under." | A / R / Rj |
| BU-027 | PP | `${f.work} takes a tumble on Sonus Bubbling Under, from #${f.previousRank} to #${f.rank}.` | "Paper Moon takes a tumble …, from #122 to #168." | A / R / Rj |
| BU-028 | PP | `Rough week for ${f.subject}: down to #${f.rank} on Sonus Bubbling Under.` | "Rough week for Paper Moon by Mira Vale: down to #168 on Sonus Bubbling Under." | A / R / Rj |
| BU-029 | PP | `${f.artist} sees ${f.work} drop ${f.placesDown} spots to #${f.rank} on Sonus Bubbling Under.` | "Mira Vale sees Paper Moon drop 46 spots to #168 …" | A / R / Rj |
| BU-030 | PP | `From #${f.previousRank} to #${f.rank}: ${f.work} cools off on Sonus Bubbling Under.` | "From #122 to #168: Paper Moon cools off on Sonus Bubbling Under." | A / R / Rj |
| BU-031 | PP | `${f.subject} slips ${f.placesDown} places on Sonus Bubbling Under, now at #${f.rank}.` | "Paper Moon by Mira Vale slips 46 places on Sonus Bubbling Under, now at #168." | A / R / Rj |

---

## E. New family: notable Hot 100 exit into Bubbling Under (`songHot100Exit`, approved rule 3)

Detected today (`GatedMomentKind.notableHot100Exit`) only when history verifies a Top 40 peak **or** a fifth Hot 100 week recorded before the exit week. Facts: previousRank 1–100 (last finalized week), rank 101–200, previousPeak. Lines that name the peak require a verified previousPeak ≤ 40. No line states the number of Hot 100 weeks (the count is only known to be ≥ 5; an exact count would be a NEW FACT). Recommended publisher: Sonus Daily.

| ID | Pub | Proposed text | Guard | Example | Decision |
|---|---|---|---|---|---|
| BU-040 | SD | `${f.subject} leaves the Sonus Hot 100 and is #${f.rank} on the weekly Sonus Bubbling Under.` | any notable exit | "Paper Moon by Mira Vale leaves the Sonus Hot 100 and is #121 on the weekly Sonus Bubbling Under." | A / R / Rj |
| BU-041 | SD | `${f.subject} slips from #${f.previousRank} on the Sonus Hot 100 to #${f.rank} on Sonus Bubbling Under.` | any | "… slips from #94 on the Sonus Hot 100 to #121 on Sonus Bubbling Under." | A / R / Rj |
| BU-042 | SD | `Once #${f.previousPeak} on the Sonus Hot 100, ${f.subject} moves to Sonus Bubbling Under at #${f.rank}.` | previousPeak ≤ 40 | "Once #35 on the Sonus Hot 100, Paper Moon by Mira Vale moves to Sonus Bubbling Under at #121." | A / R / Rj |
| BU-043 | SD | `${f.work} by ${f.artist} exits the Sonus Hot 100; it peaked at #${f.previousPeak} and is now #${f.rank} on Sonus Bubbling Under.` | previousPeak ≤ 40 | "… peaked at #35 and is now #121 …" | A / R / Rj |
| BU-044 | SD | `After its Sonus Hot 100 run, ${f.subject} continues on Sonus Bubbling Under at #${f.rank}.` | any | "After its Sonus Hot 100 run, Paper Moon by Mira Vale continues on Sonus Bubbling Under at #121." | A / R / Rj |
| BU-045 | SD | `${f.artist}'s ${f.work} drops out of the Sonus Hot 100, to #${f.rank} on Sonus Bubbling Under.` | any | "Mira Vale's Paper Moon drops out of the Sonus Hot 100, to #121 …" | A / R / Rj |
| BU-046 | PP | `Out of the Hot 100 for now: ${f.work} drops to #${f.rank} on Sonus Bubbling Under.` | any | "Out of the Hot 100 for now: Paper Moon drops to #121 on Sonus Bubbling Under." | A / R / Rj |
| BU-047 | PP | `${f.work} says goodbye to the Sonus Hot 100 (for now) and lands at #${f.rank} on Sonus Bubbling Under.` | any | "Paper Moon says goodbye to the Sonus Hot 100 (for now) and lands at #121 …" | A / R / Rj |
| BU-048 | PP | `A #${f.previousPeak} peak behind it, ${f.subject} slides to Sonus Bubbling Under at #${f.rank}.` | previousPeak ≤ 40 | "A #35 peak behind it, Paper Moon by Mira Vale slides to Sonus Bubbling Under at #121." | A / R / Rj |
| BU-049 | PP | `${f.artist}'s ${f.work} falls out of the Sonus Hot 100, from #${f.previousRank} to #${f.rank} on Sonus Bubbling Under.` | any | "… from #94 to #121 on Sonus Bubbling Under." | A / R / Rj |
| BU-050 | PP | `Hot 100 exit: ${f.subject} is now #${f.rank} on Sonus Bubbling Under.` | any | "Hot 100 exit: Paper Moon by Mira Vale is now #121 on Sonus Bubbling Under." | A / R / Rj |
| BU-051 | PP | `The Sonus Hot 100 run pauses for ${f.work}, now #${f.rank} on Sonus Bubbling Under.` | any | "The Sonus Hot 100 run pauses for Paper Moon, now #121 on Sonus Bubbling Under." | A / R / Rj |

Constraint: BU-041 and BU-049 cite #94 → #121 as a move between two charts, never as "down 27". The in-Bubbling Under 30-place rule does not apply to this boundary.

---

## F. Optional: dedicated Bubbling Under rise family (approved rule 1)

**Not needed for coverage**: rises are published today with approved F10 lines. Approve these only if you want rise stories to name Bubbling Under in every headline (F10's d3, d4, d5, p1, p2, p3, p5 and p6 don't name a chart). Recommended publisher: PulsePop (as F10).

| ID | Pub | Proposed text | Example | Decision |
|---|---|---|---|---|
| BU-060 | SD | `${f.subject} climbs ${f.places} places on the weekly Sonus Bubbling Under, to #${f.rank}.` | "Paper Moon by Mira Vale climbs 32 places on the weekly Sonus Bubbling Under, to #139." | A / R / Rj |
| BU-061 | SD | `${f.subject} rises from #${f.previousRank} to #${f.rank} on the weekly Sonus Bubbling Under.` | "… rises from #171 to #139 …" | A / R / Rj |
| BU-062 | SD | `${f.work} by ${f.artist} gains ${f.places} places on the weekly Sonus Bubbling Under and reaches #${f.rank}.` | "… gains 32 places … and reaches #139." | A / R / Rj |
| BU-063 | SD | `A ${f.places}-place climb on the weekly Sonus Bubbling Under brings ${f.subject} to #${f.rank}.` | "A 32-place climb … brings Paper Moon by Mira Vale to #139." | A / R / Rj |
| BU-064 | SD | `${f.subject} moves up the weekly Sonus Bubbling Under, from #${f.previousRank} to #${f.rank}.` | "… from #171 to #139." | A / R / Rj |
| BU-065 | SD | `${f.artist}'s ${f.work} is up ${f.places} places on the weekly Sonus Bubbling Under, at #${f.rank}.` | "Mira Vale's Paper Moon is up 32 places … at #139." | A / R / Rj |
| BU-066 | PP | `Up ${f.places}! ${f.work} jumps to #${f.rank} on Sonus Bubbling Under.` | "Up 32! Paper Moon jumps to #139 on Sonus Bubbling Under." | A / R / Rj |
| BU-067 | PP | `${f.work} is on the move on Sonus Bubbling Under: #${f.previousRank} to #${f.rank}.` | "Paper Moon is on the move on Sonus Bubbling Under: #171 to #139." | A / R / Rj |
| BU-068 | PP | `Knocking on the Hot 100's door: ${f.subject} climbs to #${f.rank} on Sonus Bubbling Under.` *(guard: rank ≤ 120)* | "Knocking on the Hot 100's door: Paper Moon by Mira Vale climbs to #112 …" | A / R / Rj |
| BU-069 | PP | `${f.artist} gets ${f.work} moving: up ${f.places} spots to #${f.rank} on Sonus Bubbling Under.` | "Mira Vale gets Paper Moon moving: up 32 spots to #139 …" | A / R / Rj |
| BU-070 | PP | `Big week on Sonus Bubbling Under: ${f.work} climbs ${f.places} places to #${f.rank}.` | "Big week on Sonus Bubbling Under: Paper Moon climbs 32 places to #139." | A / R / Rj |
| BU-071 | PP | `${f.subject} surges ${f.places} spots on Sonus Bubbling Under, landing at #${f.rank}.` | "… surges 32 spots … landing at #139." | A / R / Rj |

---

## G. After approval (what I would do)

- Section B: apply only approved rewrites, prospectively (stories already published keep their text; stored events are unchanged).
- Sections C to F: add the approved lines as new variants or families. Wire D and E from the existing `copyGated` detection (same story ids, `#bu-fall` and `#hot-100-exit`). Extend `moment_editorial_test.dart` (6 + 6 distinct, banned phrases, punctuation) and `bubbling_under_moments_test.dart` (fixtures from the handoff's §4 table).
- Any family left with fewer than 6 approved lines per publisher stays unpublished.

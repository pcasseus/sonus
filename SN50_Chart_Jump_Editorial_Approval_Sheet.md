# SN-50 Chart-Jump Editorial Approval Sheet (Batch E)

**Status:** awaiting your line-by-line approval. Nothing on this sheet is in the app: `moment_headlines.dart` and its 384 original variants are unchanged, and no new family can publish. Detection runs only under the refined Moments rules, which stay off in release builds (flag not set).
**Detection:** `MomentStoryPlanner.copyGated` (`moment_story_planner.dart`), which is never shown:
- `GatedMomentKind.hot100MajorClimb`, id `…#hot-100-jump`;
- `GatedMomentKind.hot100ClimbRun`, id `…#hot-100-run`.

Tests: `bubbling_under_moments_test.dart` group "SN-50 Batch E".

**How to answer:** for each ID write **Approve**, **Revise: …** or **Reject**. A family ships only with at least 6 Sonus Daily (SD) and 6 PulsePop (PP) distinct approved lines, after the threshold decisions in §D.

**Common rules for every line:**
- **Completed-week wording:** never "this stream" or "this week's" for a finished week.
- **Hot 100 only.** Both ranks are #1–100; Bubbling Under moves are separate (BUG-04).
- **Positions and streams are different facts.** "Places" counts chart positions only. Streams appear only as qualified streams, and only when verified.
- No "lifetime", "all-time" or other retired phrases. Every line ends in "." or "!".

**Facts:**

| Placeholder | Meaning | Status |
|---|---|---|
| `${f.subject}` | e.g. "Paper Moon by Mira Vale" | existing |
| `${f.work}` | the song title | existing |
| `${f.artist}` | the artist | existing |
| `${f.rank}` | this finalized week's rank | existing |
| `${f.previousRank}` | last finalized week's rank | existing |
| `${f.places}` | places gained this week | existing |
| `${f.runFromRank}` | the rank before a run's first climbing week | NEW FACT, from `ChartJumpFacts.fromRank` |
| `${f.runWeeks}` | consecutive climbing weeks | NEW FACT, from `ChartJumpFacts.weeks` |
| `${f.runPlaces}` | places gained over the run | NEW FACT, from `ChartJumpFacts.placesGained` |
| `${f.weekStreams}` | qualified streams this week | NEW FACT, from `ChartJumpFacts.weekStreams` |
| `${f.streamGain}` | qualified streams gained on last week | NEW FACT, from `ChartJumpFacts.streamGain`; only when both weeks are verified |

## A. Major Hot 100 jump (`songHot100MajorJump`, provisional threshold 25+ places)

| ID | Pub | Proposed text | Example | Decision |
|---|---|---|---|---|
| CJ-001 | SD | `${f.subject} jumps ${f.places} places on the weekly Sonus Hot 100, from #${f.previousRank} to #${f.rank}.` | "Paper Moon by Mira Vale jumps 32 places on the weekly Sonus Hot 100, from #80 to #48." | A / R / Rj |
| CJ-002 | SD | `${f.subject} climbs from #${f.previousRank} to #${f.rank} on the weekly Sonus Hot 100.` | "… climbs from #80 to #48 …" | A / R / Rj |
| CJ-003 | SD | `A ${f.places}-place climb takes ${f.subject} to #${f.rank} on the weekly Sonus Hot 100.` | "A 32-place climb takes … to #48 …" | A / R / Rj |
| CJ-004 | SD | `${f.work} by ${f.artist} rises ${f.places} places to #${f.rank} on the weekly Sonus Hot 100.` | "… rises 32 places to #48 …" | A / R / Rj |
| CJ-005 | SD | `${f.subject} moves up the weekly Sonus Hot 100, from #${f.previousRank} to #${f.rank}.` | "… from #80 to #48." | A / R / Rj |
| CJ-006 | SD | `${f.artist}'s ${f.work} gains ${f.places} places on the weekly Sonus Hot 100 and reaches #${f.rank}.` | "Mira Vale's Paper Moon gains 32 places … reaches #48." | A / R / Rj |
| CJ-007 | PP | `Up ${f.places}! ${f.work} leaps to #${f.rank} on the Sonus Hot 100.` | "Up 32! Paper Moon leaps to #48 on the Sonus Hot 100." | A / R / Rj |
| CJ-008 | PP | `${f.work} is flying: #${f.previousRank} to #${f.rank} on the Sonus Hot 100.` | "Paper Moon is flying: #80 to #48 …" | A / R / Rj |
| CJ-009 | PP | `Big move for ${f.subject}: up ${f.places} spots to #${f.rank} on the Sonus Hot 100.` | "Big move for Paper Moon by Mira Vale: up 32 spots to #48 …" | A / R / Rj |
| CJ-010 | PP | `${f.artist} sends ${f.work} soaring ${f.places} places to #${f.rank} on the Sonus Hot 100.` | "Mira Vale sends Paper Moon soaring 32 places to #48 …" | A / R / Rj |
| CJ-011 | PP | `From #${f.previousRank} to #${f.rank}: ${f.work} makes the jump of the week on the Sonus Hot 100.` | Only if it is not the week's biggest gainer story (§D3) | A / R / Rj |
| CJ-012 | PP | `${f.subject} surges ${f.places} spots, landing at #${f.rank} on the Sonus Hot 100.` | "… surges 32 spots, landing at #48 …" | A / R / Rj |

## B. Hot 100 climb run (`songHot100ClimbRun`, provisional 3+ weeks and 30+ places in total)

| ID | Pub | Proposed text | Example | Decision |
|---|---|---|---|---|
| CJ-020 | SD | `${f.subject} has climbed the weekly Sonus Hot 100 for ${f.runWeeks} weeks in a row, from #${f.runFromRank} to #${f.rank}.` | "… for 3 weeks in a row, from #90 to #55." | A / R / Rj |
| CJ-021 | SD | `${f.runWeeks} straight weekly climbs take ${f.subject} from #${f.runFromRank} to #${f.rank} on the Sonus Hot 100.` | "3 straight weekly climbs take … from #90 to #55 …" | A / R / Rj |
| CJ-022 | SD | `${f.work} by ${f.artist} is up ${f.runPlaces} places over ${f.runWeeks} weeks on the weekly Sonus Hot 100, now #${f.rank}.` | "… up 35 places over 3 weeks …, now #55." | A / R / Rj |
| CJ-023 | SD | `${f.subject} rises again on the weekly Sonus Hot 100, to #${f.rank}: ${f.runPlaces} places in ${f.runWeeks} weeks.` | "… to #55: 35 places in 3 weeks." | A / R / Rj |
| CJ-024 | SD | `Week after week, ${f.subject} moves up the Sonus Hot 100: #${f.runFromRank} to #${f.rank} in ${f.runWeeks} weeks.` | "… #90 to #55 in 3 weeks." | A / R / Rj |
| CJ-025 | SD | `${f.artist}'s ${f.work} keeps climbing the weekly Sonus Hot 100 and reaches #${f.rank}.` | "Mira Vale's Paper Moon keeps climbing … #55." | A / R / Rj |
| CJ-026 | PP | `${f.runWeeks} weeks, ${f.runPlaces} places: ${f.work} keeps climbing the Sonus Hot 100.` | "3 weeks, 35 places: Paper Moon keeps climbing …" | A / R / Rj |
| CJ-027 | PP | `${f.work} won't stop rising: #${f.runFromRank} to #${f.rank} on the Sonus Hot 100.` | "Paper Moon won't stop rising: #90 to #55 …" | A / R / Rj |
| CJ-028 | PP | `Up, up, up: ${f.subject} climbs for a ${f.runWeeks}th straight week, now #${f.rank}.` | Needs an ordinal fact (NEW) | A / R / Rj |
| CJ-029 | PP | `${f.artist}'s ${f.work} is on a run, up ${f.runPlaces} spots in ${f.runWeeks} weeks to #${f.rank}.` | "… up 35 spots in 3 weeks to #55." | A / R / Rj |
| CJ-030 | PP | `The climb continues for ${f.work}: #${f.rank} on the Sonus Hot 100, ${f.runPlaces} places higher than ${f.runWeeks} weeks ago.` | "… #55 …, 35 places higher than 3 weeks ago." | A / R / Rj |
| CJ-031 | PP | `${f.subject} keeps moving up: ${f.runWeeks} weeks, ${f.runPlaces} places, now #${f.rank}.` | "… 3 weeks, 35 places, now #55." | A / R / Rj |

## C. Optional streaming sentence (body text, never the headline)

Shown only when `${f.streamGain}` is verified, as its own sentence after the headline, so streams and places are never combined.

| ID | Proposed text | Example | Decision |
|---|---|---|---|
| CJ-040 | `It had ${f.weekStreams} qualified streams this week, ${f.streamGain} more than the week before.` | "It had 245 qualified streams this week, 10 more than the week before." | A / R / Rj |
| CJ-041 | `Qualified streams: ${f.weekStreams} (up ${f.streamGain} on last week).` | "Qualified streams: 245 (up 10 on last week)." | A / R / Rj |

Rule: a negative `streamGain` shows no streaming sentence. A climb with fewer streams is still a climb, and the line must not imply otherwise.

## D. Decisions needed before anything ships

1. **Thresholds** (provisional in code): a major jump is 25+ places; a run is 3+ consecutive climbing weeks totalling 30+ places.
2. **Scope:** songs only, or also releases (albums and EPs)? Detection is songs only today.
3. **Overlap with the week's biggest gainer** (an existing approved family): suggestion, as for Bubbling Under rises, the biggest gainer keeps its own story instead of a second jump story.
4. **Overlap between a jump and a run in the same week:** tell one (suggestion: the run, which includes the jump), or both?
5. **Publisher:** suggestion, both families split SD/PP like F10 (6 + 6), or one publisher per `publisherFor`.
6. **Streaming sentence:** keep (§C) or omit. Streams are always the verified qualified count for the finalized week.

## E. Data notes (no new persistence)

- History comes from stored finalized Moments events: each charting song's weekly rank event with its previous finalized rank and qualified-stream count.
- Consecutive weeks are matched by week end, which is exact across daylight-saving changes. Each link must match the previous week's rank.
- Weeks before Moments were first recorded have no events, so runs cannot reach back before then, and **missing history never counts**.
- Nothing is backfilled, and finalized charts and published Moments are only read.

# SN-50 Refined Moments Family Approval Package

**Status: DRAFT — NOT APPROVED.** Every new line in this document is labelled **DRAFT**, and every change to an existing draft line is a **PROPOSED REVISION**. None is approved. The nine families stay outside `MomentHeadlines.approvedFamilies` (`ae0fd05`), so they are held and never published, even under the refined rules.
**Date:** 2026-10-30. **Checkpoint:** `f062551`. Editorial preparation only: no Dart, test or config change. The refined Moments flag stays off.
**Sources:** current code (`moment_headlines.dart` "SN-50 new pathways", `moment_story_planner.dart`, `moment_facts.dart`, `moment_editorial_desk.dart publisherFor`), `SN50_Editorial_Change_Proposal.md` §3 (N-2 to N-6) and §6, `SN50_Round9_Editorial_and_Release_Safety_Review.md` §3, and `SN50_Progress.md` BLOCKED #10 and #12.

**How to answer:** per line, **Approve**, **Revise: …** or **Reject**; per family, confirm the open choices in §11. A family joins `approvedFamilies` only when it has 6 distinct approved Sonus Daily (SD) and 6 distinct approved PulsePop (PP) lines.

---

## 1. Kinds of copy

| Kind | Meaning here |
|---|---|
| **Existing approved copy** | None in these nine families. The 384 original variants and the approved chart-jump families are not touched by this package. |
| **Existing DRAFT (in code)** | The 23 N-2 to N-6 lines already in `moment_headlines.dart`, listed with their source ids. Never approved; held by the guard. |
| **PROPOSED REVISION** | A change to one of those 23 draft lines (10 lines). |
| **DRAFT (new)** | A new line written for this package (85 lines), with a proposed source id that follows the existing pattern. |

## 2. Checks applied to every line

- **Facts.** Every placeholder exists in `MomentFacts` today; no NEW FACT is needed. Each line's facts are included in its family's `requires` set: `_rival` = {rival}; `_zone` = {rank, threshold}; `_zones` = {rank, thresholdList}; `_ordinal` = {rank, ordinal}; `_count` = {count, threshold}.
- **Rendering.** Song titles render in quotes (`"Paper Moon"`); `${f.subject}` adds "featuring …" when there is a guest. Release titles are unquoted. `_pc(f)` / `_p1(f)` are the existing possessive helpers ("Mira Vale's").
- **Performer credits.** New song lines use `${f.subject}` or a bare `${f.work}` (the card's credit line names every performer). None uses `${f.work} by ${f.artist}` or `${f.artist}'s ${f.work}`, which would drop a featured guest.
- **Chart scope.** `${f.scopedChart}` renders "the weekly Sonus Hot 100" / "the weekly Sonus Bubbling Under" / "the weekly Sonus Albums & EPs chart" for finalized weeks, and "the Sonus Hot 100" / "the Sonus Albums & EPs chart" for career (all-time) standings. Never "this week's".
- **Completed-week wording.** No "this week", "this stream", "now" claims about streams, or "last week". "Now at #N" refers to the published position.
- **Retired expressions.** None of "all-time", "lifetime", "summit", "all-time leader", "another chart cycle", "steady movement", "points".
- **#1 families** (self-replacement, repeat #1): every headline contains "#1" (existing catalog test).
- **Punctuation.** Every line ends in "." or "!".
- **Song vs release (F-Q29).** Release lines are written to differ from the song lines, not just by the format word.
- **No future or stream claims.** No "and counting", "for now", "more to come" or claims that streams rose or fell.
- **Historical immutability.** These families are refined-only and have never been published in a release build. The flag was never set, and dev and test builds use the old rules. Adding lines therefore changes no published story. Variant choice is a hash over the fitting lines (`_write`), so the line set must be final before activation; changing it later would re-pick headlines on refined stories already shown.
- **Publisher.** Under the refined rules each family has one publisher (`publisherFor`); the other publisher's lines are a fallback only. The 6 + 6 catalog rule is kept (decision Q-4).

**Rendering fixtures** (fictional): song "Paper Moon" by Mira Vale; rival song "Glass Harbor" (Mira Vale); album *Night Signals* by Mira Vale; rival release *Low Tide* (Mira Vale); weekly scope unless stated.

---

## 3. `songSelfReplacement` (N-4, songs) — publisher **PulsePop**

**Planner rule (verified):** a #1 story where the displaced leader is verified (the previous week's #1 for weekly; the related entity for career standings), is a different song, and `_sameArtist` returns true (`moment_story_planner.dart:238-254`). It replaces the generic rival lines. Both scopes. **Duplicates:** told instead of the plain #1 or career #1 story for that move. A chart jump is suppressed only once this family is approved (`_toldMove`).
**Current:** 2 SD + 2 PP. **Missing:** 4 SD + 4 PP.

| Source id | Pub | Status | Template | Rendered example | Note |
|---|---|---|---|---|---|
| `song-self-1-d1` | SD | Existing DRAFT | `${f.careerArtist} replaces ${f.rivalWork} with ${f.work} at #1 on ${f.scopedChart}.` | Mira Vale replaces "Glass Harbor" with "Paper Moon" at #1 on the weekly Sonus Hot 100. | Approve as written |
| `song-self-1-d2` | SD | Existing DRAFT | `${f.work} takes over #1 on ${f.scopedChart} from ${f.rivalWork}, keeping the top spot with ${f.careerArtist}.` | "Paper Moon" takes over #1 on the weekly Sonus Hot 100 from "Glass Harbor", keeping the top spot with Mira Vale. | Approve as written |
| `song-self-1-p1` | PP | PROPOSED REVISION | was `Out with ${f.rivalWork}, in with ${f.work}: ${f.careerArtist} stays at #1.` → `Out with ${f.rivalWork}, in with ${f.work}: ${f.careerArtist} stays at #1 on ${f.scopedChart}.` | Out with "Glass Harbor", in with "Paper Moon": Mira Vale stays at #1 on the weekly Sonus Hot 100. | Adds the chart scope (career and weekly #1s differ). Keep the original if Q-1 says the kicker is enough. |
| `song-self-1-p2` | PP | Existing DRAFT | `${f.careerArtist} follows one #1 with another: ${f.work} replaces ${f.rivalWork}.` | Mira Vale follows one #1 with another: "Paper Moon" replaces "Glass Harbor". | Approve (scope via kicker, Q-1) |
| `song-self-1-d3` | SD | DRAFT | `${f.careerArtist} holds #1 on ${f.scopedChart} as ${f.work} succeeds ${f.rivalWork}.` | Mira Vale holds #1 on the weekly Sonus Hot 100 as "Paper Moon" succeeds "Glass Harbor". | |
| `song-self-1-d4` | SD | DRAFT | `${f.work} replaces ${f.rivalWork} at #1 on ${f.scopedChart}; both songs are by ${f.careerArtist}.` | "Paper Moon" replaces "Glass Harbor" at #1 on the weekly Sonus Hot 100; both songs are by Mira Vale. | |
| `song-self-1-d5` | SD | DRAFT | `${f.careerArtist} has a new #1 on ${f.scopedChart}: ${f.work} takes over from ${f.rivalWork}.` | Mira Vale has a new #1 on the weekly Sonus Hot 100: "Paper Moon" takes over from "Glass Harbor". | |
| `song-self-1-d6` | SD | DRAFT | `#1 on ${f.scopedChart} stays with ${f.careerArtist}, as ${f.work} replaces ${f.rivalWork}.` | #1 on the weekly Sonus Hot 100 stays with Mira Vale, as "Paper Moon" replaces "Glass Harbor". | |
| `song-self-1-p3` | PP | DRAFT | `#1 swap, same artist: ${f.work} takes over from ${f.rivalWork} for ${f.careerArtist}.` | #1 swap, same artist: "Paper Moon" takes over from "Glass Harbor" for Mira Vale. | |
| `song-self-1-p4` | PP | DRAFT | `${f.work} bumps ${f.rivalWork} from #1, and ${f.careerArtist} keeps the top spot!` | "Paper Moon" bumps "Glass Harbor" from #1, and Mira Vale keeps the top spot! | |
| `song-self-1-p5` | PP | DRAFT | `Still #1, new song: ${f.careerArtist} trades ${f.rivalWork} for ${f.work} at the top.` | Still #1, new song: Mira Vale trades "Glass Harbor" for "Paper Moon" at the top. | |
| `song-self-1-p6` | PP | DRAFT | `Back-to-back #1s for ${f.careerArtist}: ${f.work} succeeds ${f.rivalWork}.` | Back-to-back #1s for Mira Vale: "Paper Moon" succeeds "Glass Harbor". | True in both scopes: the displaced song was the immediately previous #1. |

**After the package:** 6 SD + 6 PP.

---

## 4. `releaseSelfReplacement` (N-4, releases) — publisher **PulsePop**

**Planner rule:** as §3, for the Sonus Albums & EPs chart. "#1 album" is never said of the displaced release, whose format may differ; `${f.releaseWord}` describes only the new #1.
**Current:** 1 SD + 1 PP. **Missing:** 5 SD + 5 PP.

| Source id | Pub | Status | Template | Rendered example | Note |
|---|---|---|---|---|---|
| `release-self-1-d1` | SD | PROPOSED REVISION | was `${f.careerArtist} replaces ${f.rivalWork} with ${f.title} at #1 on ${f.scopedChart}.` → `${f.careerArtist} replaces ${f.rivalWork} with the ${f.releaseWord} ${f.title} at #1 on ${f.scopedChart}.` | Mira Vale replaces Low Tide with the album Night Signals at #1 on the weekly Sonus Albums & EPs chart. | The original copies the song line's structure (F-Q29). |
| `release-self-1-p1` | PP | PROPOSED REVISION | was `${f.careerArtist} follows one #1 with another: ${f.title} replaces ${f.rivalWork}.` → `${f.careerArtist} follows one #1 release with another: the ${f.releaseWord} ${f.title} replaces ${f.rivalWork}.` | Mira Vale follows one #1 release with another: the album Night Signals replaces Low Tide. | Same reason. |
| `release-self-1-d2` | SD | DRAFT | `The ${f.releaseWord} ${f.title} succeeds ${f.rivalWork} at #1 on ${f.scopedChart}, keeping the top spot with ${f.careerArtist}.` | The album Night Signals succeeds Low Tide at #1 on the weekly Sonus Albums & EPs chart, keeping the top spot with Mira Vale. | |
| `release-self-1-d3` | SD | DRAFT | `The top of ${f.scopedChart} changes hands within ${_pc(f)} catalog: ${f.title} is the new #1.` | The top of the weekly Sonus Albums & EPs chart changes hands within Mira Vale's catalog: Night Signals is the new #1. | |
| `release-self-1-d4` | SD | DRAFT | `Two ${f.careerArtist} releases in a row at #1 on ${f.scopedChart}: ${f.title} follows ${f.rivalWork}.` | Two Mira Vale releases in a row at #1 on the weekly Sonus Albums & EPs chart: Night Signals follows Low Tide. | |
| `release-self-1-d5` | SD | DRAFT | `${f.title} is ${_pc(f)} new #1 ${f.releaseWord} on ${f.scopedChart}, replacing ${f.rivalWork}.` | Night Signals is Mira Vale's new #1 album on the weekly Sonus Albums & EPs chart, replacing Low Tide. | |
| `release-self-1-d6` | SD | DRAFT | `With the ${f.releaseWord} ${f.title}, ${f.careerArtist} follows ${f.rivalWork} at #1 on ${f.scopedChart}.` | With the album Night Signals, Mira Vale follows Low Tide at #1 on the weekly Sonus Albums & EPs chart. | |
| `release-self-1-p2` | PP | DRAFT | `New ${f.releaseWord}, same #1 artist: ${f.title} replaces ${f.rivalWork} for ${f.careerArtist}!` | New album, same #1 artist: Night Signals replaces Low Tide for Mira Vale! | |
| `release-self-1-p3` | PP | DRAFT | `${f.title} unseats ${f.rivalWork} at #1, and the top spot stays in ${_pc(f)} hands!` | Night Signals unseats Low Tide at #1, and the top spot stays in Mira Vale's hands! | |
| `release-self-1-p4` | PP | DRAFT | `Catalog takeover: ${f.careerArtist} swaps one #1 for another with the ${f.releaseWord} ${f.title}.` | Catalog takeover: Mira Vale swaps one #1 for another with the album Night Signals. | |
| `release-self-1-p5` | PP | DRAFT | `${f.careerArtist} still rules #1! The ${f.releaseWord} ${f.title} replaces ${f.rivalWork}.` | Mira Vale still rules #1! The album Night Signals replaces Low Tide. | |
| `release-self-1-p6` | PP | DRAFT | `The #1 ${f.releaseWord} is new, the artist isn't: ${f.title} by ${f.careerArtist} replaces ${f.rivalWork}.` | The #1 album is new, the artist isn't: Night Signals by Mira Vale replaces Low Tide. | |

**After the package:** 6 SD + 6 PP.

---

## 5. `songFirstThreshold` (N-2, songs) — publisher **Sonus Daily**

**Planner rule (verified, `moment_story_planner.dart:365-420`):** the first entry into one zone, from {75, 50, 40, 30, 25, 20, 15, 10, 5, 3, 2}. #1 has its own families; the Top 100 is F05; 200 is excluded. The **Top 10 always stands alone** (`majorThreshold` = 10); any other zone has its own story only when it is the only zone crossed in that move (otherwise §7). **Duplicates:** never with a debut or re-entry story (the entry tells the zone); replaces a new-peak story for the same move; for career songs, not for the zone told by an artist's career Top 10 / Top 100 story. First entry is judged on stored history for that scope.
**Current:** 2 SD + 2 PP. **Missing:** 4 SD + 4 PP. Example zone: Top 40 at #38.

| Source id | Pub | Status | Template | Rendered example | Note |
|---|---|---|---|---|---|
| `song-zone-d1` | SD | Existing DRAFT | `${f.subject} enters the Top ${f.threshold} of ${f.scopedChart} for the first time, at #${f.rank}.` | "Paper Moon" by Mira Vale enters the Top 40 of the weekly Sonus Hot 100 for the first time, at #38. | Approve as written |
| `song-zone-d2` | SD | PROPOSED REVISION | was `${f.work} by ${f.artist} reaches the Top ${f.threshold} for the first time, at #${f.rank}.` → `For the first time, ${f.subject} is in the Top ${f.threshold}, at #${f.rank}.` | For the first time, "Paper Moon" by Mira Vale is in the Top 40, at #38. | Credit fix (drops the guest). |
| `song-zone-p1` | PP | PROPOSED REVISION | was `Into the Top ${f.threshold}! ${f.subject} reaches #${f.rank} for the first time.` → `Into the Top ${f.threshold}! ${f.subject} gets there for the first time, at #${f.rank}.` | Into the Top 40! "Paper Moon" by Mira Vale gets there for the first time, at #38. | The original says the song reached #38 for the first time, which is not the fact. |
| `song-zone-p2` | PP | PROPOSED REVISION | was `${f.artist} cracks the Top ${f.threshold}: ${f.work} reaches #${f.rank}.` → `${f.work} cracks the Top ${f.threshold} for the first time, at #${f.rank}.` | "Paper Moon" cracks the Top 40 for the first time, at #38. | The original can read as the artist's first Top 40 (a career fact). |
| `song-zone-d3` | SD | DRAFT | `${f.subject} reaches #${f.rank} on ${f.scopedChart}, its first time in the Top ${f.threshold}.` | "Paper Moon" by Mira Vale reaches #38 on the weekly Sonus Hot 100, its first time in the Top 40. | |
| `song-zone-d4` | SD | DRAFT | `A first Top ${f.threshold} position for ${f.subject}: #${f.rank} on ${f.scopedChart}.` | A first Top 40 position for "Paper Moon" by Mira Vale: #38 on the weekly Sonus Hot 100. | |
| `song-zone-d5` | SD | DRAFT | `${f.subject} moves into the Top ${f.threshold} of ${f.scopedChart} at #${f.rank}, a first for the song.` | "Paper Moon" by Mira Vale moves into the Top 40 of the weekly Sonus Hot 100 at #38, a first for the song. | |
| `song-zone-d6` | SD | DRAFT | `At #${f.rank}, ${f.subject} is inside the Top ${f.threshold} of ${f.scopedChart} for the first time.` | At #38, "Paper Moon" by Mira Vale is inside the Top 40 of the weekly Sonus Hot 100 for the first time. | |
| `song-zone-p3` | PP | DRAFT | `Hello, Top ${f.threshold}! ${f.work} makes it in at #${f.rank}.` | Hello, Top 40! "Paper Moon" makes it in at #38. | |
| `song-zone-p4` | PP | DRAFT | `${f.work} breaks new ground at #${f.rank}: a first Top ${f.threshold} spot.` | "Paper Moon" breaks new ground at #38: a first Top 40 spot. | |
| `song-zone-p5` | PP | DRAFT | `New territory for ${f.work}: #${f.rank} and a place in the Top ${f.threshold}.` | New territory for "Paper Moon": #38 and a place in the Top 40. | |
| `song-zone-p6` | PP | DRAFT | `Top ${f.threshold}, unlocked: ${f.subject} lands at #${f.rank}.` | Top 40, unlocked: "Paper Moon" by Mira Vale lands at #38. | |

No line says "climbs": a zone entry can come from a move that is not a climb from a charted rank. Zones 2 and 3 read as "the Top 2" / "the Top 3". **After the package:** 6 SD + 6 PP.

---

## 6. `releaseFirstThreshold` (N-2, releases) — publisher **Sonus Daily**

**Planner rule:** as §5 for the Sonus Albums & EPs chart. Zone 100 is included for releases (there is no breakthrough family for albums); 200 is excluded. The name for album positions #101–200 is still open (N-1, Q-5); no line here names it.
**Current:** 1 SD + 1 PP. **Missing:** 5 SD + 5 PP. Example zone: Top 20 at #18.

| Source id | Pub | Status | Template | Rendered example | Note |
|---|---|---|---|---|---|
| `release-zone-d1` | SD | Existing DRAFT | `The ${f.releaseWord} ${f.subject} reaches the Top ${f.threshold} of ${f.scopedChart} for the first time, at #${f.rank}.` | The album Night Signals by Mira Vale reaches the Top 20 of the weekly Sonus Albums & EPs chart for the first time, at #18. | Approve as written |
| `release-zone-p1` | PP | PROPOSED REVISION | was `${f.artist} takes the ${f.releaseWord} ${f.title} into the Top ${f.threshold}, at #${f.rank}.` → `${f.artist} takes the ${f.releaseWord} ${f.title} into the Top ${f.threshold} for the first time, at #${f.rank}.` | Mira Vale takes the album Night Signals into the Top 20 for the first time, at #18. | States the fact the story is about. |
| `release-zone-d2` | SD | DRAFT | `${f.artist} earns a first Top ${f.threshold} position for the ${f.releaseWord} ${f.title}, at #${f.rank} on ${f.scopedChart}.` | Mira Vale earns a first Top 20 position for the album Night Signals, at #18 on the weekly Sonus Albums & EPs chart. | |
| `release-zone-d3` | SD | DRAFT | `${f.subject} is now a Top ${f.threshold} ${f.releaseWord}: it reaches #${f.rank} on ${f.scopedChart}, a first.` | Night Signals by Mira Vale is now a Top 20 album: it reaches #18 on the weekly Sonus Albums & EPs chart, a first. | |
| `release-zone-d4` | SD | DRAFT | `${f.subject} moves into the Top ${f.threshold} of ${f.scopedChart} at #${f.rank}, the ${f.releaseWord}'s first time there.` | Night Signals by Mira Vale moves into the Top 20 of the weekly Sonus Albums & EPs chart at #18, the album's first time there. | |
| `release-zone-d5` | SD | DRAFT | `At #${f.rank}, the ${f.releaseWord} ${f.subject} enters the Top ${f.threshold} of ${f.scopedChart} for the first time.` | At #18, the album Night Signals by Mira Vale enters the Top 20 of the weekly Sonus Albums & EPs chart for the first time. | |
| `release-zone-d6` | SD | DRAFT | `${f.subject} records its first Top ${f.threshold} placing on ${f.scopedChart}, at #${f.rank}.` | Night Signals by Mira Vale records its first Top 20 placing on the weekly Sonus Albums & EPs chart, at #18. | |
| `release-zone-p2` | PP | DRAFT | `Top ${f.threshold} for the ${f.releaseWord}! ${f.subject} arrives at #${f.rank}.` | Top 20 for the album! Night Signals by Mira Vale arrives at #18. | |
| `release-zone-p3` | PP | DRAFT | `${f.title} breaks into the Top ${f.threshold} at #${f.rank}, a first for the ${f.releaseWord}.` | Night Signals breaks into the Top 20 at #18, a first for the album. | |
| `release-zone-p4` | PP | DRAFT | `New high-water mark: the ${f.releaseWord} ${f.title} enters the Top ${f.threshold} at #${f.rank}.` | New high-water mark: the album Night Signals enters the Top 20 at #18. | |
| `release-zone-p5` | PP | DRAFT | `${_p1(f)} ${f.releaseWord} ${f.title} makes the Top ${f.threshold} for the first time, at #${f.rank}!` | Mira Vale's album Night Signals makes the Top 20 for the first time, at #18! | A release has no featured guest, so the possessive is a full credit. |
| `release-zone-p6` | PP | DRAFT | `First Top ${f.threshold} spot for ${f.title}: the ${f.releaseWord} lands at #${f.rank}.` | First Top 20 spot for Night Signals: the album lands at #18. | |

**After the package:** 6 SD + 6 PP.

---

## 7. `songThresholds` (N-3, songs) — publisher **Sonus Daily**

**Planner rule:** two or more zones first entered in one move, other than #1, the Top 10 (stands alone, §5) and the Top 100 (F05); listed largest first by `${f.thresholdList}` ("the Top 75, Top 50 and Top 40"). One story for all of them (F-Q14B). Which zones count as "major" and stand alone is still open (Q-3, BLOCKED #10).
**Current:** 1 SD + 1 PP. **Missing:** 5 SD + 5 PP. Example: the Top 75, Top 50 and Top 40 at #38.

| Source id | Pub | Status | Template | Rendered example | Note |
|---|---|---|---|---|---|
| `song-zones-d1` | SD | Existing DRAFT | `${f.subject} moves into ${f.thresholdList} for the first time, now at #${f.rank}.` | "Paper Moon" by Mira Vale moves into the Top 75, Top 50 and Top 40 for the first time, now at #38. | Approve as written |
| `song-zones-p1` | PP | PROPOSED REVISION | was `Up and through: ${f.work} by ${f.artist} enters ${f.thresholdList} at #${f.rank}.` → `Up and through: ${f.subject} enters ${f.thresholdList} at #${f.rank}.` | Up and through: "Paper Moon" by Mira Vale enters the Top 75, Top 50 and Top 40 at #38. | Credit fix (same text without a guest). |
| `song-zones-d2` | SD | DRAFT | `${f.subject} enters ${f.thresholdList} of ${f.scopedChart} in one move, reaching #${f.rank}.` | "Paper Moon" by Mira Vale enters the Top 75, Top 50 and Top 40 of the weekly Sonus Hot 100 in one move, reaching #38. | |
| `song-zones-d3` | SD | DRAFT | `At #${f.rank} on ${f.scopedChart}, ${f.subject} is in ${f.thresholdList} for the first time.` | At #38 on the weekly Sonus Hot 100, "Paper Moon" by Mira Vale is in the Top 75, Top 50 and Top 40 for the first time. | |
| `song-zones-d4` | SD | DRAFT | `${f.subject} reaches #${f.rank}, its first time in ${f.thresholdList}.` | "Paper Moon" by Mira Vale reaches #38, its first time in the Top 75, Top 50 and Top 40. | |
| `song-zones-d5` | SD | DRAFT | `A move to #${f.rank} takes ${f.subject} into ${f.thresholdList} of ${f.scopedChart} for the first time.` | A move to #38 takes "Paper Moon" by Mira Vale into the Top 75, Top 50 and Top 40 of the weekly Sonus Hot 100 for the first time. | |
| `song-zones-d6` | SD | DRAFT | `${f.subject} records first entries into ${f.thresholdList}, at #${f.rank} on ${f.scopedChart}.` | "Paper Moon" by Mira Vale records first entries into the Top 75, Top 50 and Top 40, at #38 on the weekly Sonus Hot 100. | |
| `song-zones-p2` | PP | DRAFT | `Zone after zone: ${f.work} is now in ${f.thresholdList}, at #${f.rank}!` | Zone after zone: "Paper Moon" is now in the Top 75, Top 50 and Top 40, at #38! | |
| `song-zones-p3` | PP | DRAFT | `Big move for ${f.subject}: into ${f.thresholdList} at #${f.rank}.` | Big move for "Paper Moon" by Mira Vale: into the Top 75, Top 50 and Top 40 at #38. | Never told with a jump story for the same move (`_toldMove`). |
| `song-zones-p4` | PP | DRAFT | `${f.work} enters ${f.thresholdList} all at once, landing at #${f.rank}.` | "Paper Moon" enters the Top 75, Top 50 and Top 40 all at once, landing at #38. | |
| `song-zones-p5` | PP | DRAFT | `New heights for ${f.work}: ${f.thresholdList}, all for the first time, at #${f.rank}.` | New heights for "Paper Moon": the Top 75, Top 50 and Top 40, all for the first time, at #38. | |
| `song-zones-p6` | PP | DRAFT | `Straight into ${f.thresholdList}: ${f.subject} reaches #${f.rank}.` | Straight into the Top 75, Top 50 and Top 40: "Paper Moon" by Mira Vale reaches #38. | |

No line says "past" or "through" a zone the song is still inside, and none states how many zones (that would be a NEW FACT). **After the package:** 6 SD + 6 PP.

---

## 8. `releaseThresholds` (N-3, releases) — publisher **Sonus Daily**

**Planner rule:** as §7 for the Sonus Albums & EPs chart (zone 100 can be in the list).
**Current:** 1 SD + 1 PP. **Missing:** 5 SD + 5 PP. Example: the Top 50, Top 40 and Top 30 at #27.

| Source id | Pub | Status | Template | Rendered example | Note |
|---|---|---|---|---|---|
| `release-zones-d1` | SD | Existing DRAFT | `The ${f.releaseWord} ${f.subject} moves into ${f.thresholdList} for the first time, now at #${f.rank}.` | The album Night Signals by Mira Vale moves into the Top 50, Top 40 and Top 30 for the first time, now at #27. | Approve as written |
| `release-zones-p1` | PP | Existing DRAFT | `${f.title} by ${f.artist} breaks into ${f.thresholdList} in one move, landing at #${f.rank}.` | Night Signals by Mira Vale breaks into the Top 50, Top 40 and Top 30 in one move, landing at #27. | Approve as written |
| `release-zones-d2` | SD | DRAFT | `The ${f.releaseWord} ${f.subject} reaches #${f.rank} on ${f.scopedChart}, entering ${f.thresholdList} for the first time.` | The album Night Signals by Mira Vale reaches #27 on the weekly Sonus Albums & EPs chart, entering the Top 50, Top 40 and Top 30 for the first time. | |
| `release-zones-d3` | SD | DRAFT | `In one move, ${f.subject} enters ${f.thresholdList} of ${f.scopedChart}, at #${f.rank}.` | In one move, Night Signals by Mira Vale enters the Top 50, Top 40 and Top 30 of the weekly Sonus Albums & EPs chart, at #27. | |
| `release-zones-d4` | SD | DRAFT | `${f.subject} is in ${f.thresholdList} for the first time, a new best for the ${f.releaseWord} at #${f.rank}.` | Night Signals by Mira Vale is in the Top 50, Top 40 and Top 30 for the first time, a new best for the album at #27. | A first zone entry is always a new best position. |
| `release-zones-d5` | SD | DRAFT | `At #${f.rank}, the ${f.releaseWord} ${f.subject} sits in ${f.thresholdList} for the first time.` | At #27, the album Night Signals by Mira Vale sits in the Top 50, Top 40 and Top 30 for the first time. | |
| `release-zones-d6` | SD | DRAFT | `First entries into ${f.thresholdList} for the ${f.releaseWord} ${f.subject}, now #${f.rank} on ${f.scopedChart}.` | First entries into the Top 50, Top 40 and Top 30 for the album Night Signals by Mira Vale, now #27 on the weekly Sonus Albums & EPs chart. | |
| `release-zones-p2` | PP | DRAFT | `${f.title} storms into ${f.thresholdList} at #${f.rank}!` | Night Signals storms into the Top 50, Top 40 and Top 30 at #27! | |
| `release-zones-p3` | PP | DRAFT | `Several firsts at once for the ${f.releaseWord} ${f.title}: ${f.thresholdList}, at #${f.rank}.` | Several firsts at once for the album Night Signals: the Top 50, Top 40 and Top 30, at #27. | |
| `release-zones-p4` | PP | DRAFT | `Up, up and in: the ${f.releaseWord} ${f.title} lands in ${f.thresholdList} at #${f.rank}.` | Up, up and in: the album Night Signals lands in the Top 50, Top 40 and Top 30 at #27. | |
| `release-zones-p5` | PP | DRAFT | `${_p1(f)} ${f.releaseWord} ${f.title} breaks new ground: ${f.thresholdList}, at #${f.rank}.` | Mira Vale's album Night Signals breaks new ground: the Top 50, Top 40 and Top 30, at #27. | |
| `release-zones-p6` | PP | DRAFT | `Landmark move for ${f.title}: into ${f.thresholdList} at #${f.rank}.` | Landmark move for Night Signals: into the Top 50, Top 40 and Top 30 at #27. | |

**After the package:** 6 SD + 6 PP.

---

## 9. `artistRepeatNumberOne` (N-6, songs) — publisher **Sonus Daily**

**Planner rule (verified, `_careerNumberOne`):** a song #1 that is the artist's second or later #1, **weekly chart only** (career standings use the approved `artistNthNumberOne`). `${f.ordinal}` counts the artist's weekly #1s from all verified stored history (F-Q30), with no backfill of old stories. Not used when §3 applies (self-replacement wins). A #1 debut can also take this story, so no line says the song "rose" or "climbed".
**Current:** 1 SD + 1 PP. **Missing:** 5 SD + 5 PP. Example: ordinal 2 ("a second", "second", "2").

| Source id | Pub | Status | Template | Rendered example | Note |
|---|---|---|---|---|---|
| `artist-repeat-1-d1` | SD | Existing DRAFT | `${f.careerArtist} earns ${f.aOrdinalText} #1 on ${f.scopedChart} as ${f.work} takes the top spot.` | Mira Vale earns a second #1 on the weekly Sonus Hot 100 as "Paper Moon" takes the top spot. | Approve as written |
| `artist-repeat-1-p1` | PP | PROPOSED REVISION | was `#1 number ${f.ordinal} on ${f.scopedChart} for ${f.careerArtist}! ${f.work} takes the top spot.` → `That's ${f.aOrdinalText} weekly #1 for ${f.careerArtist}: ${f.work} tops the Sonus Hot 100!` | That's a second weekly #1 for Mira Vale: "Paper Moon" tops the Sonus Hot 100! | "#1 number 2" reads as two ranks. |
| `artist-repeat-1-d2` | SD | DRAFT | `${f.work} takes #1 on ${f.scopedChart}, ${f.aOrdinalText} #1 there for ${f.careerArtist}.` | "Paper Moon" takes #1 on the weekly Sonus Hot 100, a second #1 there for Mira Vale. | |
| `artist-repeat-1-d3` | SD | DRAFT | `${f.careerArtist} collects ${f.aOrdinalText} #1 on ${f.scopedChart} with ${f.work}.` | Mira Vale collects a second #1 on the weekly Sonus Hot 100 with "Paper Moon". | |
| `artist-repeat-1-d4` | SD | DRAFT | `With ${f.work} at the top, ${f.careerArtist} now has ${f.ordinal} #1s on ${f.scopedChart}.` | With "Paper Moon" at the top, Mira Vale now has 2 #1s on the weekly Sonus Hot 100. | |
| `artist-repeat-1-d5` | SD | DRAFT | `${f.work} is ${_pc(f)} ${f.ordinalText} #1 on ${f.scopedChart}.` | "Paper Moon" is Mira Vale's second #1 on the weekly Sonus Hot 100. | |
| `artist-repeat-1-d6` | SD | DRAFT | `The weekly Sonus Hot 100 has a new #1 in ${f.work}, ${f.aOrdinalText} for ${f.careerArtist}.` | The weekly Sonus Hot 100 has a new #1 in "Paper Moon", a second for Mira Vale. | Weekly songs only, so the chart is written out to start the sentence. |
| `artist-repeat-1-p2` | PP | DRAFT | `${f.careerArtist} is back on top with ${f.aOrdinalText} weekly #1: ${f.work}!` | Mira Vale is back on top with a second weekly #1: "Paper Moon"! | "Back": the artist has had a #1 before. |
| `artist-repeat-1-p3` | PP | DRAFT | `Another one! ${f.work} gives ${f.careerArtist} ${f.aOrdinalText} weekly #1.` | Another one! "Paper Moon" gives Mira Vale a second weekly #1. | |
| `artist-repeat-1-p4` | PP | DRAFT | `${f.careerArtist} does it again: ${f.work} hits #1 on the weekly Sonus Hot 100.` | Mira Vale does it again: "Paper Moon" hits #1 on the weekly Sonus Hot 100. | |
| `artist-repeat-1-p5` | PP | DRAFT | `#1 again for ${f.careerArtist}! This time it's ${f.work}, the artist's ${f.ordinalText}.` | #1 again for Mira Vale! This time it's "Paper Moon", the artist's second. | |
| `artist-repeat-1-p6` | PP | DRAFT | `${f.careerArtist} adds another weekly #1: ${f.work} takes the top spot!` | Mira Vale adds another weekly #1: "Paper Moon" takes the top spot! | |

**After the package:** 6 SD + 6 PP.

---

## 10. `artistRepeatNumberOneRelease` (N-6, releases) — publisher **Sonus Daily**

**Planner rule:** as §9 for the weekly Sonus Albums & EPs chart. The count is of #1 **releases** (albums and EPs together), so no line says "#1 album" for the earlier ones.
**Current:** 1 SD + 1 PP. **Missing:** 5 SD + 5 PP. Example: ordinal 2.

| Source id | Pub | Status | Template | Rendered example | Note |
|---|---|---|---|---|---|
| `artist-release-repeat-1-d1` | SD | Existing DRAFT | `${f.title} gives ${f.careerArtist} ${f.aOrdinalText} #1 on ${f.scopedChart}.` | Night Signals gives Mira Vale a second #1 on the weekly Sonus Albums & EPs chart. | Approve as written |
| `artist-release-repeat-1-p1` | PP | PROPOSED REVISION | was `${f.careerArtist} collects #1 number ${f.ordinal} on ${f.scopedChart} with the ${f.releaseWord} ${f.title}.` → `${f.careerArtist} collects ${f.aOrdinalText} #1 release with the ${f.releaseWord} ${f.title}!` | Mira Vale collects a second #1 release with the album Night Signals! | "#1 number 2"; PulsePop voice. |
| `artist-release-repeat-1-d2` | SD | DRAFT | `${f.careerArtist} reaches #1 on ${f.scopedChart} for the ${f.ordinalText} time, with the ${f.releaseWord} ${f.title}.` | Mira Vale reaches #1 on the weekly Sonus Albums & EPs chart for the second time, with the album Night Signals. | |
| `artist-release-repeat-1-d3` | SD | DRAFT | `${f.careerArtist} now counts ${f.ordinal} #1 releases on ${f.scopedChart}, the latest being the ${f.releaseWord} ${f.title}.` | Mira Vale now counts 2 #1 releases on the weekly Sonus Albums & EPs chart, the latest being the album Night Signals. | |
| `artist-release-repeat-1-d4` | SD | DRAFT | `${_pc(f)} ${f.ordinalText} #1 on ${f.scopedChart} is the ${f.releaseWord} ${f.title}.` | Mira Vale's second #1 on the weekly Sonus Albums & EPs chart is the album Night Signals. | |
| `artist-release-repeat-1-d5` | SD | DRAFT | `${f.title} takes #1 on ${f.scopedChart}, ${_pc(f)} ${f.ordinalText} release to get there.` | Night Signals takes #1 on the weekly Sonus Albums & EPs chart, Mira Vale's second release to get there. | |
| `artist-release-repeat-1-d6` | SD | DRAFT | `The ${f.releaseWord} ${f.title} becomes ${_pc(f)} latest #1 on ${f.scopedChart}, the ${f.ordinalText} in all.` | The album Night Signals becomes Mira Vale's latest #1 on the weekly Sonus Albums & EPs chart, the second in all. | |
| `artist-release-repeat-1-p2` | PP | DRAFT | `Back at #1! ${f.careerArtist} returns to the top of the Sonus Albums & EPs chart with ${f.title}.` | Back at #1! Mira Vale returns to the top of the Sonus Albums & EPs chart with Night Signals. | |
| `artist-release-repeat-1-p3` | PP | DRAFT | `#1 again! ${f.title} hands ${f.careerArtist} ${f.aOrdinalText} chart-topping release.` | #1 again! Night Signals hands Mira Vale a second chart-topping release. | |
| `artist-release-repeat-1-p4` | PP | DRAFT | `Another #1 release for ${f.careerArtist}: the ${f.releaseWord} ${f.title} takes the top spot!` | Another #1 release for Mira Vale: the album Night Signals takes the top spot! | |
| `artist-release-repeat-1-p5` | PP | DRAFT | `${f.title} makes it ${f.ordinal} weekly #1s for ${f.careerArtist}!` | Night Signals makes it 2 weekly #1s for Mira Vale! | |
| `artist-release-repeat-1-p6` | PP | DRAFT | `Chart-topper number ${f.ordinal} for ${f.careerArtist}: the ${f.releaseWord} ${f.title} is #1!` | Chart-topper number 2 for Mira Vale: the album Night Signals is #1! | |

**After the package:** 6 SD + 6 PP.

---

## 11. `artistSimultaneousReleases` (N-5) — publisher **Sonus Daily**

**Planner rule (verified, `moment_story_planner.dart:209-219`):** an artist roundup on the Sonus Albums & EPs chart with a zone of **Top 10 or narrower** (`roundupThreshold` = 10) and `${f.count}` ≥ 2 releases. It is told **in addition to** each release's own story. Because the zone is at most 10, the open "Top 200" naming question (N-5) does not arise for this family. "Releases" covers albums and EPs together.
**Current:** 2 SD + 1 PP. **Missing:** 4 SD + 5 PP. Example: 3 releases in the Top 10.

| Source id | Pub | Status | Template | Rendered example | Note |
|---|---|---|---|---|---|
| `artist-sim-release-d1` | SD | Existing DRAFT | `${f.artist} has ${f.count} releases in the Top ${f.threshold} of ${f.scopedChart} at once.` | Mira Vale has 3 releases in the Top 10 of the weekly Sonus Albums & EPs chart at once. | Approve as written |
| `artist-sim-release-d2` | SD | Existing DRAFT | `${f.count} releases by ${f.artist} sit in the Top ${f.threshold} of ${f.scopedChart}.` | 3 releases by Mira Vale sit in the Top 10 of the weekly Sonus Albums & EPs chart. | Approve as written |
| `artist-sim-release-p1` | PP | Existing DRAFT | `Catalog power: ${f.artist} has ${f.count} releases in the Top ${f.threshold}.` | Catalog power: Mira Vale has 3 releases in the Top 10. | Approve (scope via kicker, Q-1) |
| `artist-sim-release-d3` | SD | DRAFT | `${f.artist} holds ${f.count} places in the Top ${f.threshold} of ${f.scopedChart}.` | Mira Vale holds 3 places in the Top 10 of the weekly Sonus Albums & EPs chart. | |
| `artist-sim-release-d4` | SD | DRAFT | `${f.count} of the Top ${f.threshold} releases on ${f.scopedChart} are by ${f.artist}.` | 3 of the Top 10 releases on the weekly Sonus Albums & EPs chart are by Mira Vale. | |
| `artist-sim-release-d5` | SD | DRAFT | `${f.artist} places ${f.count} releases in the Top ${f.threshold} of ${f.scopedChart}.` | Mira Vale places 3 releases in the Top 10 of the weekly Sonus Albums & EPs chart. | |
| `artist-sim-release-d6` | SD | DRAFT | `${f.artist} appears ${f.count} times in the Top ${f.threshold} of ${f.scopedChart}.` | Mira Vale appears 3 times in the Top 10 of the weekly Sonus Albums & EPs chart. | |
| `artist-sim-release-p2` | PP | DRAFT | `${f.count} at once! ${f.artist} crowds the Top ${f.threshold}.` | 3 at once! Mira Vale crowds the Top 10. | |
| `artist-sim-release-p3` | PP | DRAFT | `${f.artist} is everywhere: ${f.count} releases in the Top ${f.threshold}!` | Mira Vale is everywhere: 3 releases in the Top 10! | |
| `artist-sim-release-p4` | PP | DRAFT | `Top ${f.threshold} takeover: ${f.count} releases from ${f.artist}.` | Top 10 takeover: 3 releases from Mira Vale. | |
| `artist-sim-release-p5` | PP | DRAFT | `${f.artist} stacks the Top ${f.threshold} with ${f.count} releases at the same time.` | Mira Vale stacks the Top 10 with 3 releases at the same time. | |
| `artist-sim-release-p6` | PP | DRAFT | `${f.artist} fills ${f.count} Top ${f.threshold} slots on ${f.scopedChart} at once!` | Mira Vale fills 3 Top 10 slots on the weekly Sonus Albums & EPs chart at once! | |

No line states the count twice (P-012). **After the package:** 6 SD + 6 PP.

---

## 12. Summary

| Family | Publisher | Existing drafts | Proposed revisions | New drafts | After package |
|---|---|---|---|---|---|
| songSelfReplacement | PP | 4 | 1 | 8 | 6 + 6 |
| releaseSelfReplacement | PP | 2 | 2 | 10 | 6 + 6 |
| songFirstThreshold | SD | 4 | 3 | 8 | 6 + 6 |
| releaseFirstThreshold | SD | 2 | 1 | 10 | 6 + 6 |
| songThresholds | SD | 2 | 1 | 10 | 6 + 6 |
| releaseThresholds | SD | 2 | 0 | 10 | 6 + 6 |
| artistRepeatNumberOne | SD | 2 | 1 | 10 | 6 + 6 |
| artistRepeatNumberOneRelease | SD | 2 | 1 | 10 | 6 + 6 |
| artistSimultaneousReleases | SD | 3 | 0 | 9 | 6 + 6 |
| **Total** | | **23** | **10** | **85** | **108 lines** |

## 13. Choices that need your input

| # | Question | Recommendation |
|---|---|---|
| Q-1 | Does the card's kicker count as the explicit chart scope (Editorial §6 Q1), or must every #1 and zone headline name the chart? Affects `song-self-1-p1`/`-p2`, `song-zone-d2`, the PP zone lines and `artist-sim-release-p1`. | Kicker counts for PulsePop lines; SD lines name the chart. Then `song-self-1-p1` can stay unrevised. |
| Q-2 | Career (all-time) stories render the scope as plain "the Sonus Hot 100" / "the Sonus Albums & EPs chart", while the app calls that view "Career standings". Keep, or say "the Sonus Hot 100 career standings"? | Keep the plain chart name in headlines; the kicker says Career. Confirm. |
| Q-3 | Which zones are "major" and stand alone (Editorial §6 Q3, BLOCKED #10)? Today only #1 and the Top 10 stand alone. | Keep #1 and Top 10 only; answer this before §7–§8 are approved, because it decides how often the threshold families appear. |
| Q-4 | 6 + 6 per family, although each family has one publisher under the refined rules? | Keep 6 + 6 (same choice as for the chart jumps). |
| Q-5 | Name for album positions #101–200 (N-1). Not used by these families, but needed before release zone 100 stories link to it. | See `SN50_Existing_Headline_Approval_Summary.md`. |
| Q-6 | Numerals or words for counts ("2 #1s", "3 releases")? | Numerals, as the approved copy does. |

## 14. Recommended approval order

1. **`songFirstThreshold` and `releaseFirstThreshold`:** the most frequent refined stories (every first Top 10, and single zones), with clear facts.
2. **`songSelfReplacement` and `releaseSelfReplacement`:** answer Q-1 first.
3. **`artistRepeatNumberOne` and `artistRepeatNumberOneRelease`.**
4. **`artistSimultaneousReleases`.**
5. **`songThresholds` and `releaseThresholds`:** last, after Q-3.

A family joins `approvedFamilies` only when all 12 of its lines are approved. Until then it stays held, and the refined flag stays off (BLOCKED #12, #21).

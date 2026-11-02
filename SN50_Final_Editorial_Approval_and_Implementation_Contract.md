# SN-50 Final Editorial Approval and Implementation Contract

**Status: EDITORIAL FREEZE FOR REVIEW — NOT A PUBLICATION AUTHORIZATION.** Every template below is a *final proposed* text. None is approved until you tick it in §11. Nothing here is in the app, and the refined Moments flag (`SONUS_MOMENTS_REFINED_APPROVED`) stays off.
**Date:** 2026-10-30. **Checkpoint:** `f062551` (5,134 passed, 0 failed, 0 skipped). This pass changed no Dart, test, SQL, Android or configuration file, and ran no tests.
**Baselines:** `SN50_Final_BUG04_Editorial_Package.md`, `SN50_Refined_Moments_Family_Approval_Package.md`, `SN50_Existing_Headline_Approval_Summary.md`, and your Stage 1B direction. Lines that differ from those packages are marked **[Changed in contract]**.

**Notation.** `${…}` placeholders are the existing `MomentFacts` getters. `_pc(f)` = possessive career artist; `_p1(f)` = possessive artist (existing helpers). **SD** = Sonus Daily, **PP** = PulsePop. Rendering fixtures: song "Paper Moon" by Mira Vale (titles render in quotes), rival song "Glass Harbor", album *Night Signals*, rival release *Low Tide*, weekly scope.

---

## 1. Locked editorial policy (proposed final direction)

| # | Policy | How this contract applies it |
|---|---|---|
| E-1 | Historical Moments keep exactly the same rendered headlines and bodies | §5 isolation boundary; golden fixtures (§8) |
| E-2 | New wording applies only to refined stories after activation | Every change is a refined-view change (§5) |
| E-3 | No historical repair, regeneration, backfill or rewriting | No stored data is touched; legacy view frozen |
| E-4 | 6 distinct SD + 6 distinct PP per family | Every new or extended family below has exactly 6 + 6 |
| E-5 | One primary publisher per family; the other catalog is fallback | `publisherFor` unchanged; new families assigned in §4 |
| E-6 | Standalone major zones: #1 and the first Top 10 only | Planner unchanged (`majorThreshold` = 10) |
| E-7 | Other first zone entries consolidated by the existing planner | `songThresholds` / `releaseThresholds` |
| E-8 | The kicker may carry chart context for concise PP lines; SD names the chart where practical | SD lines name the chart, except the long multi-zone lines (noted) |
| E-9 | Plain "Sonus Hot 100" naming for career stories | `scopedChart` career branch unchanged |
| E-10 | Release positions #101–200 are "the Sonus Albums & EPs chart"; releases are never "Bubbling Under" | `chart` album branch unchanged |
| E-11 | No stories for exits from both charts | Not planned |
| E-12 | Keep F10 for Bubbling Under rises; BU-060 to BU-071 deferred | §6.1.F |
| E-13 | BU falls of 30+ count toward the minor-story cap | `songBubblingUnderFall` tier = minor |
| E-14 | Notable Hot 100 exits are capped, except with a verified prior Top 40 peak (major treatment, uncapped) | `songHot100Exit` tier rule (§4) |
| E-15 | Completed-week phrasing: "the week before", never relative "last week" | Applied to BU lines and to P-005/P-006 **[Changed in contract]** |
| E-16 | Exact artist and featured-performer attribution | Song lines use `${f.subject}` or a bare `${f.work}`; 14 legacy lines excluded for refined songs with a guest (§6.4) |
| E-17 | Numerals for counts; correct ordinal formatting | `${f.count}`, `${f.ordinal}` as numerals; `ordinalText` / `aOrdinalText` for words ("a second", "an eighth") |

## 2. Facts verified for this freeze (code at `f062551`)

| Question | Finding | Consequence |
|---|---|---|
| Is a weekly self-replacement's displaced #1 really the previous week's #1? | Yes. The displaced leader is the entity with a `losesNumberOne` event in the same finalized week (`moment_story_planner.dart` `_displacedLeaders`). For career standings it is the event's related entity at that play. | "Back-to-back" is supported weekly but not obviously for career standings, so it is replaced by wording true in both scopes. |
| Does a repeat #1 ordinal count songs or weeks? | Distinct entities. The ordinal = (entities whose peak is already #1) + 1, and the event fires only when an entity reaches #1 for the first time (`chart_moment_artist_achievement_detector.dart:157-178`). | Lines say "#1 song" / "#1 release". "2 weekly #1s" is removed because it can read as weeks. |
| Are release roundup counts distinct releases? | Yes. Album-chart entries are keyed by `albumId` (`chart_snapshot_builder_service.dart:262, 388`), so editions are not counted separately. The count is the artist's entries at or above the zone. | "Releases" is accurate. |
| Do headlines get stored? | No. They are composed at display time (`charts_controller.dart:250`), and the variant is `hash(storyId) % candidates.length` (`MomentEditorialDesk._write`). | §5 is required before any catalog change. |
| Has a refined story ever been shown to a user? | The flag is set in no committed config; dev and test builds use the old rules (Restart Instructions). | Refined-view changes alter no published story. **You confirm this in checklist item A-0.** |

## 3. Catalog inventory

| Catalog | Lines | Status | Publishes today |
|---|---|---|---|
| SN-45 originals (F01–F32), bodies B1–B9 | 384 | **Approved**, legacy | Yes (legacy and refined) |
| Chart jumps `songHot100MajorJump`, `songHot100ClimbRun` | 12 + 12 | **Approved** (`ae0fd05`) | Refined only (flag off) |
| P-001 to P-050 refined overrides | 50 items | **Unapproved** (this contract) | No |
| Featured-guest exclusions (§6.4) | 14 lines | **Unapproved** | No |
| F05 additions BU-001, BU-002, BU-010 to BU-015 | 8 | **Unapproved** | No |
| `songBubblingUnderFall` BU-020 to BU-031 | 12 | **Unapproved**; detection exists (`#bu-fall`) | No (held) |
| `songHot100Exit` BU-040 to BU-051 | 12 | **Unapproved**; detection exists (`#hot-100-exit`) | No (held) |
| BU-060 to BU-071 | 12 | **Deferred** (E-12) | No |
| Nine refined draft families | 108 (23 existing drafts + 85 new) | **Unapproved**; held by `approvedFamilies` | No |
| CJ-041 | 1 | **Approved**; "last week" flagged (§6.5) | Refined only |

## 4. Publisher and selection rules

- **Unchanged:** `MomentEditorialDesk.publisherFor` decides the publisher for refined stories. If no line of that publisher fits, any fitting line of the family is used. If none fits, the neutral headline is used, **only for approved families**. Unapproved families are skipped before facts are built (`ae0fd05`), so neutral text can never publish them.
- **New family publishers:** `songBubblingUnderFall` → Sonus Daily. `songHot100Exit` → Sonus Daily. The nine families keep their current `publisherFor` entries (self-replacement PP; the other seven SD).
- **Tiers (refined only):**
  - `songBubblingUnderFall` → minor (counts toward the cap).
  - `songHot100Exit` → notable (uncapped) when a verified `previousPeak` ≤ 40; otherwise minor.
  - `MomentFamily.tierFor` takes only the rank today, so the exit rule needs the peak as well. This is an implementation detail inside Batch 5.
- **Rival rule (unchanged):** with a verified rival, lines that name the rival are preferred.
- **Per-line approval:** a line is selectable in the refined view only when it is marked approved. A family joins `approvedFamilies` only with 6 approved SD and 6 approved PP lines (a test enforces it).

## 5. Historical rendering isolation design

**Problem.** Legacy and refined stories share `MomentHeadlines.of(family)`. The variant index depends on the size and order of the fitting set, so adding, removing, reordering or rewording any line in a family changes old headlines. Keeping the story id alone does not protect them.

**Design (Batch 0, no copy change):**
1. **Two catalog views.**
   - `MomentHeadlines.legacyOf(family)` returns the current list for that family: the same objects, texts and order as at `f062551`. It is frozen.
   - `MomentHeadlines.refinedOf(family)` derives the refined list from the frozen legacy list in four steps, in this order:
     - start from the frozen list;
     - apply refined overrides **in place**: same id and position, new template;
     - drop refined exclusions (by id, optionally by a fact predicate such as "has a featured artist");
     - append refined-only additions, each with a new id.
2. **One switch.** `_write` uses `facts.refined ? refinedOf : legacyOf`. `facts.refined` already reflects `ChartMomentRules.appliesTo` (activation instant, weekly rules from the first week starting at or after it), so pre-activation stories always take the legacy view.
3. **Never edit a legacy template in place.** Any wording change is an override record (id → refined template) in a separate refined table, with an `approved` flag. Unapproved overrides, exclusions and additions are inert.
4. **Helpers and bodies.** `MomentFacts.chart` keeps its legacy branch byte for byte. The P-003/P-004 refined branch is used only when `refined` is true. Body sentences B3/B4 (P-005/P-006) change only for weekly refined stories. Kickers, status and the neutral headline stay unchanged in the legacy view.
5. **Fail-closed guards stay.**
   - `approvedFamilies` is unchanged in purpose.
   - Neutral fallback stays limited to approved families.
   - New families enter `approvedFamilies` only in their own batch, after line approval.
6. **No data change.** No stored event, Moment, snapshot or schema is touched. Nothing is regenerated or backfilled.

## 6. Final proposed templates

### 6.1 BUG-04 (BU-001 to BU-051)

Proposed variant ids follow the existing pattern. "Refined replacement" means the legacy line stays in the legacy view and the new line takes its place in the refined view.

**B. Existing F05 lines (family `songHot100Breakthrough`, PP)**

| BU ID | Variant id | Pub | Final proposed template | Rendered | Change |
|---|---|---|---|---|---|
| BU-001 | `song-break-p3` (refined override) | PP | `Previously #${f.previousRank} on Sonus Bubbling Under, ${f.work} enters the Sonus Hot 100 at #${f.rank}.` | Previously #124 on Sonus Bubbling Under, "Paper Moon" enters the Sonus Hot 100 at #87. | as package |
| BU-002 | `song-break-d2` (refined override) | SD | `${f.subject} enters the Sonus Hot 100 at #${f.rank}, from #${f.previousRank} on Sonus Bubbling Under in the preceding chart week.` | "Paper Moon" by Mira Vale enters the Sonus Hot 100 at #87, from #124 on Sonus Bubbling Under in the preceding chart week. | **[Changed in contract]** cross-chart "enters"; legacy text unchanged |

**C. New F05 lines** (guard: rank #1–100; previousRank #101–200 from the preceding finalized week; first Hot 100 entry in stored history)

| BU ID | Variant id | Pub | Final proposed template | Rendered | Change |
|---|---|---|---|---|---|
| BU-010 | `song-break-d7` | SD | `${f.subject} enters the Sonus Hot 100 at #${f.rank}; the week before, it was #${f.previousRank} on Sonus Bubbling Under.` | "Paper Moon" by Mira Vale enters the Sonus Hot 100 at #87; the week before, it was #124 on Sonus Bubbling Under. | as package |
| BU-011 | `song-break-d8` | SD | `After #${f.previousRank} on Sonus Bubbling Under, ${f.subject} makes its Sonus Hot 100 debut at #${f.rank}.` | After #124 on Sonus Bubbling Under, "Paper Moon" by Mira Vale makes its Sonus Hot 100 debut at #87. | as package |
| BU-012 | `song-break-d9` | SD | `${f.subject} debuts on the Sonus Hot 100 at #${f.rank}, having been #${f.previousRank} on Sonus Bubbling Under the week before.` | "Paper Moon" by Mira Vale debuts on the Sonus Hot 100 at #87, having been #124 on Sonus Bubbling Under the week before. | as package |
| BU-013 | `song-break-p7` | PP | `New to the Sonus Hot 100: ${f.work} arrives at #${f.rank}, after #${f.previousRank} on Sonus Bubbling Under the week before.` | New to the Sonus Hot 100: "Paper Moon" arrives at #87, after #124 on Sonus Bubbling Under the week before. | **[Changed in contract]** no "up from"; distinct opener from BU-015 |
| BU-014 | `song-break-p8` | PP | `From #${f.previousRank} on Sonus Bubbling Under to a Sonus Hot 100 debut at #${f.rank}: ${f.subject} is in.` | From #124 on Sonus Bubbling Under to a Sonus Hot 100 debut at #87: "Paper Moon" by Mira Vale is in. | as package |
| BU-015 | `song-break-p9` | PP | `Hot 100 debut! ${f.work} arrives on the Sonus Hot 100 at #${f.rank}, having been #${f.previousRank} on Sonus Bubbling Under the week before.` | Hot 100 debut! "Paper Moon" arrives on the Sonus Hot 100 at #87, having been #124 on Sonus Bubbling Under the week before. | **[Changed in contract]** "Hot 100 debut!"; the song debuts, not the artist |

**D. New family `songBubblingUnderFall`** (SD primary; minor tier. Guard: both ranks #101–200; previousRank from the preceding finalized week; fall ≥ 30; NEW FACT `placesDown` = rank − previousRank, added only after authorization)

| BU ID | Variant id | Pub | Final proposed template |
|---|---|---|---|
| BU-020 | `song-bu-fall-d1` | SD | `${f.subject} falls from #${f.previousRank} to #${f.rank} on the weekly Sonus Bubbling Under.` |
| BU-021 | `song-bu-fall-d2` | SD | `${f.subject} drops ${f.placesDown} places on the weekly Sonus Bubbling Under, to #${f.rank}.` |
| BU-022 | `song-bu-fall-d3` | SD | `${f.subject} slips to #${f.rank} on the weekly Sonus Bubbling Under, down from #${f.previousRank}.` |
| BU-023 | `song-bu-fall-d4` | SD | `A ${f.placesDown}-place fall on the weekly Sonus Bubbling Under takes ${f.subject} to #${f.rank}.` |
| BU-024 | `song-bu-fall-d5` | SD | `${f.subject} moves down the weekly Sonus Bubbling Under, from #${f.previousRank} to #${f.rank}.` |
| BU-025 | `song-bu-fall-d6` | SD | `${f.subject} loses ${f.placesDown} places on the weekly Sonus Bubbling Under and sits at #${f.rank}.` |
| BU-026 | `song-bu-fall-p1` | PP | `Down ${f.placesDown}: ${f.work} slides to #${f.rank} on Sonus Bubbling Under.` |
| BU-027 | `song-bu-fall-p2` | PP | `${f.work} takes a tumble on Sonus Bubbling Under, from #${f.previousRank} to #${f.rank}.` |
| BU-028 | `song-bu-fall-p3` | PP | `Rough week for ${f.subject}: down to #${f.rank} on Sonus Bubbling Under.` |
| BU-029 | `song-bu-fall-p4` | PP | `${f.work} drops ${f.placesDown} spots to #${f.rank} on Sonus Bubbling Under.` |
| BU-030 | `song-bu-fall-p5` | PP | `From #${f.previousRank} to #${f.rank}: ${f.work} loses ground on Sonus Bubbling Under.` |
| BU-031 | `song-bu-fall-p6` | PP | `${f.subject} slips ${f.placesDown} places on Sonus Bubbling Under, now at #${f.rank}.` |

Rendered examples (#122 → #168, 46 places) are in the BUG-04 package §5; every text above matches the package recommendation.

**E. New family `songHot100Exit`** (SD primary; notable tier with a verified previousPeak ≤ 40, otherwise minor. Guard: previousRank #1–100 from the preceding finalized week; rank #101–200; verified Top 40 peak or 5+ Hot 100 weeks; once per run. **[P]** lines need previousPeak ≤ 40.)

| BU ID | Variant id | Pub | Final proposed template |
|---|---|---|---|
| BU-040 | `song-exit-d1` | SD | `${f.subject} leaves the Sonus Hot 100 and is #${f.rank} on the weekly Sonus Bubbling Under.` |
| BU-041 | `song-exit-d2` | SD | `${f.subject} slips from #${f.previousRank} on the Sonus Hot 100 to #${f.rank} on Sonus Bubbling Under.` |
| BU-042 | `song-exit-d3` [P] | SD | `Once #${f.previousPeak} on the Sonus Hot 100, ${f.subject} moves to Sonus Bubbling Under at #${f.rank}.` |
| BU-043 | `song-exit-d4` [P] | SD | `${f.subject} exits the Sonus Hot 100 after peaking at #${f.previousPeak}; it is now #${f.rank} on Sonus Bubbling Under.` |
| BU-044 | `song-exit-d5` | SD | `After its Sonus Hot 100 run, ${f.subject} continues on Sonus Bubbling Under at #${f.rank}.` |
| BU-045 | `song-exit-d6` | SD | `${f.subject} drops out of the Sonus Hot 100, to #${f.rank} on Sonus Bubbling Under.` |
| BU-046 | `song-exit-p1` | PP | `Out of the Sonus Hot 100: ${f.work} drops to #${f.rank} on Sonus Bubbling Under.` |
| BU-047 | `song-exit-p2` | PP | `${f.work} says goodbye to the Sonus Hot 100 and lands at #${f.rank} on Sonus Bubbling Under.` |
| BU-048 | `song-exit-p3` [P] | PP | `A #${f.previousPeak} peak behind it, ${f.subject} slides to Sonus Bubbling Under at #${f.rank}.` |
| BU-049 | `song-exit-p4` | PP | `${f.work} falls from #${f.previousRank} on the Sonus Hot 100 to #${f.rank} on Sonus Bubbling Under.` |
| BU-050 | `song-exit-p5` | PP | `Hot 100 exit: ${f.subject} is now #${f.rank} on Sonus Bubbling Under.` |
| BU-051 | `song-exit-p6` | PP | `A Sonus Hot 100 run comes to an end: ${f.work} is now #${f.rank} on Sonus Bubbling Under.` |

Rendered examples (#94 → #121, peak #35) are in the BUG-04 package §6; every text matches the package.

**F. BU-060 to BU-071:** deferred proposals (E-12). Not implemented; F10 stays the rise family.

**F05 in the refined view after Batch 4:** SD d1, d2 (override), d3–d6, d7–d9 = 9; PP p1, p2, p3 (override), p4–p6, p7–p9 = 9. The `misleadingArrivalVariants` exclusions and the §6.4 guest exclusion (`song-break-d5`) still apply. `song-break-p4` has a proposed exclusion (§6.5).

### 6.2 Nine refined families (6 SD + 6 PP each)

All lines are DRAFT until approved. Lines are identical to the family package unless marked **[Changed in contract]**.

**`songSelfReplacement` (PP primary)**

| Id | Pub | Final proposed template | Change |
|---|---|---|---|
| `song-self-1-d1` | SD | `${f.careerArtist} replaces ${f.rivalWork} with ${f.work} at #1 on ${f.scopedChart}.` | |
| `song-self-1-d2` | SD | `${f.work} takes over #1 on ${f.scopedChart} from ${f.rivalWork}, keeping the top spot with ${f.careerArtist}.` | |
| `song-self-1-d3` | SD | `${f.careerArtist} holds #1 on ${f.scopedChart} as ${f.work} succeeds ${f.rivalWork}.` | |
| `song-self-1-d4` | SD | `${f.work} replaces ${f.rivalWork} at #1 on ${f.scopedChart}; both songs are by ${f.careerArtist}.` | |
| `song-self-1-d5` | SD | `${f.careerArtist} has a new #1 on ${f.scopedChart}: ${f.work} takes over from ${f.rivalWork}.` | |
| `song-self-1-d6` | SD | `#1 on ${f.scopedChart} stays with ${f.careerArtist}, as ${f.work} replaces ${f.rivalWork}.` | |
| `song-self-1-p1` | PP | `Out with ${f.rivalWork}, in with ${f.work}: ${f.careerArtist} stays at #1.` | **[Changed in contract]** original draft kept (the kicker carries the scope, E-8) |
| `song-self-1-p2` | PP | `${f.careerArtist} follows one #1 with another: ${f.work} replaces ${f.rivalWork}.` | |
| `song-self-1-p3` | PP | `#1 swap, same artist: ${f.work} takes over from ${f.rivalWork} for ${f.careerArtist}.` | |
| `song-self-1-p4` | PP | `${f.work} bumps ${f.rivalWork} from #1, and ${f.careerArtist} keeps the top spot!` | |
| `song-self-1-p5` | PP | `Still #1, new song: ${f.careerArtist} trades ${f.rivalWork} for ${f.work} at the top.` | |
| `song-self-1-p6` | PP | `One ${f.careerArtist} #1 makes way for another: ${f.work} succeeds ${f.rivalWork}.` | **[Changed in contract]** replaces "Back-to-back #1s", which isn't clearly true for career standings |

**`releaseSelfReplacement` (PP primary)** — the displaced release is never called an album.

| Id | Pub | Final proposed template | Change |
|---|---|---|---|
| `release-self-1-d1` | SD | `${f.careerArtist} replaces ${f.rivalWork} with the ${f.releaseWord} ${f.title} at #1 on ${f.scopedChart}.` | revision of the existing draft |
| `release-self-1-d2` | SD | `The ${f.releaseWord} ${f.title} succeeds ${f.rivalWork} at #1 on ${f.scopedChart}, keeping the top spot with ${f.careerArtist}.` | |
| `release-self-1-d3` | SD | `The top of ${f.scopedChart} changes hands within ${_pc(f)} catalog: ${f.title} is the new #1.` | |
| `release-self-1-d4` | SD | `Two ${f.careerArtist} releases in a row at #1 on ${f.scopedChart}: ${f.title} follows ${f.rivalWork}.` | |
| `release-self-1-d5` | SD | `${f.title} is ${_pc(f)} new #1 ${f.releaseWord} on ${f.scopedChart}, replacing ${f.rivalWork}.` | `releaseWord` describes the new #1 only |
| `release-self-1-d6` | SD | `With the ${f.releaseWord} ${f.title}, ${f.careerArtist} follows ${f.rivalWork} at #1 on ${f.scopedChart}.` | |
| `release-self-1-p1` | PP | `${f.careerArtist} follows one #1 release with another: the ${f.releaseWord} ${f.title} replaces ${f.rivalWork}.` | revision of the existing draft |
| `release-self-1-p2` | PP | `New ${f.releaseWord}, same #1 artist: ${f.title} replaces ${f.rivalWork} for ${f.careerArtist}!` | |
| `release-self-1-p3` | PP | `${f.title} unseats ${f.rivalWork} at #1, and the top spot stays in ${_pc(f)} hands!` | |
| `release-self-1-p4` | PP | `Catalog takeover: ${f.careerArtist} swaps one #1 for another with the ${f.releaseWord} ${f.title}.` | |
| `release-self-1-p5` | PP | `${f.careerArtist} still rules #1! The ${f.releaseWord} ${f.title} replaces ${f.rivalWork}.` | |
| `release-self-1-p6` | PP | `The #1 ${f.releaseWord} is new, the artist isn't: ${f.title} by ${f.careerArtist} replaces ${f.rivalWork}.` | |

**`songFirstThreshold` (SD primary)** — the achievement belongs to the song; no line says "climbs".

| Id | Pub | Final proposed template | Change |
|---|---|---|---|
| `song-zone-d1` | SD | `${f.subject} enters the Top ${f.threshold} of ${f.scopedChart} for the first time, at #${f.rank}.` | |
| `song-zone-d2` | SD | `First time in the Top ${f.threshold} of ${f.scopedChart}: ${f.subject} is at #${f.rank}.` | **[Changed in contract]** SD now names the chart (E-8) |
| `song-zone-d3` | SD | `${f.subject} reaches #${f.rank} on ${f.scopedChart}, its first time in the Top ${f.threshold}.` | |
| `song-zone-d4` | SD | `A first Top ${f.threshold} position for ${f.subject}: #${f.rank} on ${f.scopedChart}.` | |
| `song-zone-d5` | SD | `${f.subject} moves into the Top ${f.threshold} of ${f.scopedChart} at #${f.rank}, a first for the song.` | |
| `song-zone-d6` | SD | `At #${f.rank}, ${f.subject} is inside the Top ${f.threshold} of ${f.scopedChart} for the first time.` | |
| `song-zone-p1` | PP | `Into the Top ${f.threshold}! ${f.subject} gets there for the first time, at #${f.rank}.` | revision of the existing draft |
| `song-zone-p2` | PP | `${f.work} cracks the Top ${f.threshold} for the first time, at #${f.rank}.` | revision (song, not artist) |
| `song-zone-p3` | PP | `Hello, Top ${f.threshold}! ${f.work} makes it in at #${f.rank}.` | |
| `song-zone-p4` | PP | `${f.work} breaks new ground at #${f.rank}: a first Top ${f.threshold} spot.` | |
| `song-zone-p5` | PP | `New territory for ${f.work}: #${f.rank} and a place in the Top ${f.threshold}.` | |
| `song-zone-p6` | PP | `Top ${f.threshold}, unlocked: ${f.subject} lands at #${f.rank}.` | |

**`releaseFirstThreshold` (SD primary)** — the achievement belongs to the release, not the artist.

| Id | Pub | Final proposed template | Change |
|---|---|---|---|
| `release-zone-d1` | SD | `The ${f.releaseWord} ${f.subject} reaches the Top ${f.threshold} of ${f.scopedChart} for the first time, at #${f.rank}.` | |
| `release-zone-d2` | SD | `${f.subject} earns its first Top ${f.threshold} position, at #${f.rank} on ${f.scopedChart}.` | **[Changed in contract]** release as subject, not the artist |
| `release-zone-d3` | SD | `${f.subject} is now a Top ${f.threshold} ${f.releaseWord}: it reaches #${f.rank} on ${f.scopedChart}, a first.` | |
| `release-zone-d4` | SD | `${f.subject} moves into the Top ${f.threshold} of ${f.scopedChart} at #${f.rank}, the ${f.releaseWord}'s first time there.` | |
| `release-zone-d5` | SD | `At #${f.rank}, the ${f.releaseWord} ${f.subject} enters the Top ${f.threshold} of ${f.scopedChart} for the first time.` | |
| `release-zone-d6` | SD | `For the ${f.releaseWord} ${f.subject}, #${f.rank} on ${f.scopedChart} means a first Top ${f.threshold} placing.` | **[Changed in contract]** keeps d2 and d6 distinct |
| `release-zone-p1` | PP | `${f.title} reaches the Top ${f.threshold} for the first time, at #${f.rank}!` | **[Changed in contract]** release as subject |
| `release-zone-p2` | PP | `Top ${f.threshold} for the ${f.releaseWord}! ${f.subject} arrives at #${f.rank}.` | |
| `release-zone-p3` | PP | `${f.title} breaks into the Top ${f.threshold} at #${f.rank}, a first for the ${f.releaseWord}.` | |
| `release-zone-p4` | PP | `New high-water mark: the ${f.releaseWord} ${f.title} enters the Top ${f.threshold} at #${f.rank}.` | |
| `release-zone-p5` | PP | `${_p1(f)} ${f.releaseWord} ${f.title} makes the Top ${f.threshold} for the first time, at #${f.rank}!` | |
| `release-zone-p6` | PP | `First Top ${f.threshold} spot for ${f.title}: the ${f.releaseWord} lands at #${f.rank}.` | |

**`songThresholds` (SD primary)** — the multi-zone SD lines d1 and d4 omit the chart for length (E-8 "where practical").

| Id | Pub | Final proposed template |
|---|---|---|
| `song-zones-d1` | SD | `${f.subject} moves into ${f.thresholdList} for the first time, now at #${f.rank}.` |
| `song-zones-d2` | SD | `${f.subject} enters ${f.thresholdList} of ${f.scopedChart} in one move, reaching #${f.rank}.` |
| `song-zones-d3` | SD | `At #${f.rank} on ${f.scopedChart}, ${f.subject} is in ${f.thresholdList} for the first time.` |
| `song-zones-d4` | SD | `${f.subject} reaches #${f.rank}, its first time in ${f.thresholdList}.` |
| `song-zones-d5` | SD | `A move to #${f.rank} takes ${f.subject} into ${f.thresholdList} of ${f.scopedChart} for the first time.` |
| `song-zones-d6` | SD | `${f.subject} records first entries into ${f.thresholdList}, at #${f.rank} on ${f.scopedChart}.` |
| `song-zones-p1` | PP | `Up and through: ${f.subject} enters ${f.thresholdList} at #${f.rank}.` (revision: credit) |
| `song-zones-p2` | PP | `Zone after zone: ${f.work} is now in ${f.thresholdList}, at #${f.rank}!` |
| `song-zones-p3` | PP | `Big move for ${f.subject}: into ${f.thresholdList} at #${f.rank}.` |
| `song-zones-p4` | PP | `${f.work} enters ${f.thresholdList} all at once, landing at #${f.rank}.` |
| `song-zones-p5` | PP | `New heights for ${f.work}: ${f.thresholdList}, all for the first time, at #${f.rank}.` |
| `song-zones-p6` | PP | `Straight into ${f.thresholdList}: ${f.subject} reaches #${f.rank}.` |

**`releaseThresholds` (SD primary)** — d1, d4 and d5 omit the chart for length.

| Id | Pub | Final proposed template |
|---|---|---|
| `release-zones-d1` | SD | `The ${f.releaseWord} ${f.subject} moves into ${f.thresholdList} for the first time, now at #${f.rank}.` |
| `release-zones-d2` | SD | `The ${f.releaseWord} ${f.subject} reaches #${f.rank} on ${f.scopedChart}, entering ${f.thresholdList} for the first time.` |
| `release-zones-d3` | SD | `In one move, ${f.subject} enters ${f.thresholdList} of ${f.scopedChart}, at #${f.rank}.` |
| `release-zones-d4` | SD | `${f.subject} is in ${f.thresholdList} for the first time, a new best for the ${f.releaseWord} at #${f.rank}.` |
| `release-zones-d5` | SD | `At #${f.rank}, the ${f.releaseWord} ${f.subject} sits in ${f.thresholdList} for the first time.` |
| `release-zones-d6` | SD | `First entries into ${f.thresholdList} for the ${f.releaseWord} ${f.subject}, now #${f.rank} on ${f.scopedChart}.` |
| `release-zones-p1` | PP | `${f.title} by ${f.artist} breaks into ${f.thresholdList} in one move, landing at #${f.rank}.` |
| `release-zones-p2` | PP | `${f.title} storms into ${f.thresholdList} at #${f.rank}!` |
| `release-zones-p3` | PP | `Several firsts at once for the ${f.releaseWord} ${f.title}: ${f.thresholdList}, at #${f.rank}.` |
| `release-zones-p4` | PP | `Up, up and in: the ${f.releaseWord} ${f.title} lands in ${f.thresholdList} at #${f.rank}.` |
| `release-zones-p5` | PP | `${_p1(f)} ${f.releaseWord} ${f.title} breaks new ground: ${f.thresholdList}, at #${f.rank}.` |
| `release-zones-p6` | PP | `Landmark move for ${f.title}: into ${f.thresholdList} at #${f.rank}.` |

**`artistRepeatNumberOne` (SD primary; weekly songs only)** — the ordinal counts distinct #1 songs, so lines say "#1 song" and never "weekly #1s".

| Id | Pub | Final proposed template | Rendered (ordinal 2) | Change |
|---|---|---|---|---|
| `artist-repeat-1-d1` | SD | `${f.careerArtist} earns ${f.aOrdinalText} #1 on ${f.scopedChart} as ${f.work} takes the top spot.` | Mira Vale earns a second #1 on the weekly Sonus Hot 100 as "Paper Moon" takes the top spot. | |
| `artist-repeat-1-d2` | SD | `${f.work} takes #1 on ${f.scopedChart}, ${f.aOrdinalText} #1 song there for ${f.careerArtist}.` | "Paper Moon" takes #1 on the weekly Sonus Hot 100, a second #1 song there for Mira Vale. | **[Changed in contract]** |
| `artist-repeat-1-d3` | SD | `${f.careerArtist} collects ${f.aOrdinalText} #1 on ${f.scopedChart} with ${f.work}.` | Mira Vale collects a second #1 on the weekly Sonus Hot 100 with "Paper Moon". | |
| `artist-repeat-1-d4` | SD | `With ${f.work} at the top, ${f.careerArtist} now has ${f.ordinal} #1 songs on ${f.scopedChart}.` | With "Paper Moon" at the top, Mira Vale now has 2 #1 songs on the weekly Sonus Hot 100. | **[Changed in contract]** |
| `artist-repeat-1-d5` | SD | `${f.work} is ${_pc(f)} ${f.ordinalText} #1 song on ${f.scopedChart}.` | "Paper Moon" is Mira Vale's second #1 song on the weekly Sonus Hot 100. | **[Changed in contract]** |
| `artist-repeat-1-d6` | SD | `The weekly Sonus Hot 100 has a new #1 in ${f.work}, ${f.aOrdinalText} #1 song for ${f.careerArtist}.` | The weekly Sonus Hot 100 has a new #1 in "Paper Moon", a second #1 song for Mira Vale. | **[Changed in contract]** |
| `artist-repeat-1-p1` | PP | `That's ${f.aOrdinalText} #1 song for ${f.careerArtist}: ${f.work} tops the weekly Sonus Hot 100!` | That's a second #1 song for Mira Vale: "Paper Moon" tops the weekly Sonus Hot 100! | **[Changed in contract]** |
| `artist-repeat-1-p2` | PP | `${f.careerArtist} is back on top with ${f.aOrdinalText} #1 song: ${f.work}!` | Mira Vale is back on top with a second #1 song: "Paper Moon"! | **[Changed in contract]** "back" holds: the self-replacement case is told separately |
| `artist-repeat-1-p3` | PP | `Another one! ${f.work} gives ${f.careerArtist} ${f.aOrdinalText} #1 song.` | Another one! "Paper Moon" gives Mira Vale a second #1 song. | **[Changed in contract]** |
| `artist-repeat-1-p4` | PP | `${f.careerArtist} does it again: ${f.work} hits #1 on the weekly Sonus Hot 100.` | Mira Vale does it again: "Paper Moon" hits #1 on the weekly Sonus Hot 100. | |
| `artist-repeat-1-p5` | PP | `#1 again for ${f.careerArtist}! This time it's ${f.work}, the artist's ${f.ordinalText} #1 song.` | #1 again for Mira Vale! This time it's "Paper Moon", the artist's second #1 song. | **[Changed in contract]** |
| `artist-repeat-1-p6` | PP | `${f.careerArtist} adds another #1 song: ${f.work} takes the top spot!` | Mira Vale adds another #1 song: "Paper Moon" takes the top spot! | **[Changed in contract]** |

**`artistRepeatNumberOneRelease` (SD primary; weekly releases only)** — the ordinal counts distinct #1 releases (albums and EPs together).

| Id | Pub | Final proposed template | Change |
|---|---|---|---|
| `artist-release-repeat-1-d1` | SD | `${f.title} gives ${f.careerArtist} ${f.aOrdinalText} #1 on ${f.scopedChart}.` | |
| `artist-release-repeat-1-d2` | SD | `The ${f.releaseWord} ${f.title} is ${_pc(f)} ${f.ordinalText} release to reach #1 on ${f.scopedChart}.` | **[Changed in contract]** "second time" could mean weeks |
| `artist-release-repeat-1-d3` | SD | `${f.careerArtist} now counts ${f.ordinal} #1 releases on ${f.scopedChart}, the latest being the ${f.releaseWord} ${f.title}.` | |
| `artist-release-repeat-1-d4` | SD | `${_pc(f)} ${f.ordinalText} #1 release on ${f.scopedChart} is the ${f.releaseWord} ${f.title}.` | **[Changed in contract]** |
| `artist-release-repeat-1-d5` | SD | `${f.title} takes #1 on ${f.scopedChart}, adding ${f.aOrdinalText} #1 release to ${_pc(f)} record.` | **[Changed in contract]** |
| `artist-release-repeat-1-d6` | SD | `The ${f.releaseWord} ${f.title} becomes ${_pc(f)} latest #1 release on ${f.scopedChart}, the ${f.ordinalText} in all.` | **[Changed in contract]** |
| `artist-release-repeat-1-p1` | PP | `${f.careerArtist} collects ${f.aOrdinalText} #1 release with the ${f.releaseWord} ${f.title}!` | revision of the existing draft |
| `artist-release-repeat-1-p2` | PP | `Back at #1! ${f.careerArtist} returns to the top of the Sonus Albums & EPs chart with ${f.title}.` | |
| `artist-release-repeat-1-p3` | PP | `#1 again! ${f.title} hands ${f.careerArtist} ${f.aOrdinalText} chart-topping release.` | |
| `artist-release-repeat-1-p4` | PP | `Another #1 release for ${f.careerArtist}: the ${f.releaseWord} ${f.title} takes the top spot!` | |
| `artist-release-repeat-1-p5` | PP | `${f.title} makes it ${f.ordinal} #1 releases for ${f.careerArtist}!` | **[Changed in contract]** no "weekly #1s" |
| `artist-release-repeat-1-p6` | PP | `Chart-topper number ${f.ordinal} for ${f.careerArtist}: the ${f.releaseWord} ${f.title} is #1!` | |

**`artistSimultaneousReleases` (SD primary)** — guard: Albums & EPs chart, zone ≤ 10, count ≥ 2 distinct releases (`albumId`), in addition to each release's own story.

| Id | Pub | Final proposed template |
|---|---|---|
| `artist-sim-release-d1` | SD | `${f.artist} has ${f.count} releases in the Top ${f.threshold} of ${f.scopedChart} at once.` |
| `artist-sim-release-d2` | SD | `${f.count} releases by ${f.artist} sit in the Top ${f.threshold} of ${f.scopedChart}.` |
| `artist-sim-release-d3` | SD | `${f.artist} holds ${f.count} places in the Top ${f.threshold} of ${f.scopedChart}.` |
| `artist-sim-release-d4` | SD | `${f.count} of the Top ${f.threshold} releases on ${f.scopedChart} are by ${f.artist}.` |
| `artist-sim-release-d5` | SD | `${f.artist} places ${f.count} releases in the Top ${f.threshold} of ${f.scopedChart}.` |
| `artist-sim-release-d6` | SD | `${f.artist} appears ${f.count} times in the Top ${f.threshold} of ${f.scopedChart}.` |
| `artist-sim-release-p1` | PP | `Catalog power: ${f.artist} has ${f.count} releases in the Top ${f.threshold}.` |
| `artist-sim-release-p2` | PP | `${f.count} at once! ${f.artist} crowds the Top ${f.threshold}.` |
| `artist-sim-release-p3` | PP | `${f.artist} is everywhere: ${f.count} releases in the Top ${f.threshold}!` |
| `artist-sim-release-p4` | PP | `Top ${f.threshold} takeover: ${f.count} releases from ${f.artist}.` |
| `artist-sim-release-p5` | PP | `${f.artist} stacks the Top ${f.threshold} with ${f.count} releases at the same time.` |
| `artist-sim-release-p6` | PP | `${f.artist} fills ${f.count} Top ${f.threshold} slots on ${f.scopedChart} at once!` |

Every #1-family line above contains "#1"; every line ends in "." or "!"; no line uses a retired phrase.

### 6.3 Refined overrides of existing approved copy (P-001 to P-050)

Each override uses the same variant id and position, in the refined view only (§5). Legacy text is unchanged. Unless marked, the text is the proposal's text verbatim.

| Item | Target | Final proposed refined text | Change |
|---|---|---|---|
| P-001 | `artist-hot100-d5` | `${f.subject} gives ${f.ownerName} a first Sonus Hot 100 entry, at #${f.rank}.` | **[Changed in contract]** `${f.subject}` for the full credit |
| P-002 | `artist-1-d6` | `${f.subject} gives ${f.ownerName} a first #1 on ${f.chart}.` | **[Changed in contract]** same |
| P-003 | `MomentFacts.chart`, refined weekly | songs `the weekly Sonus Hot 100`; albums `the weekly Sonus Albums & EPs chart` (Option A) | |
| P-004 | `MomentFacts.chart`, refined weekly #101–200 | `the weekly Sonus Bubbling Under`, checked before the Hot 100 branch | replaces today's refined "this week's Sonus Bubbling Under" |
| P-005 | Body B3, weekly refined | `'$it was at #$previous the week before, its best until then.'` | **[Changed in contract]** "the week before" (E-15) |
| P-006 | Body B4, weekly refined | `'$it was at #$previous the week before.'` | **[Changed in contract]** same; replaces today's suppression |
| P-007 | `song-gainer-d6` | `No song climbed further in the chart week than ${f.subject}, up ${f.places} places to #${f.rank}.` | |
| P-008 | `song-gainer-p6` | `${f.work} leads every climber of the chart week, rising ${f.places} places to #${f.rank}.` | |
| P-009 | `artist-sim-p4` | `${f.artist} lands ${f.count} songs in the Top ${f.threshold} of ${f.chart}.` | |
| P-010 | `artist-hot100-p4` | `${f.careerArtist} cracks the Sonus Hot 100 for the first time: ${f.work} enters at #${f.rank} with ${f.streamsText}.` | |
| P-011 | `artist-top-p3` | `Head to head with ${f.rivalTitle}, ${f.title} pulls ahead as your #1 artist.` | |
| P-012 | `artist-sim-p2` | `${f.count} songs, one artist: ${f.artist} is all over the Top ${f.threshold}.` | |
| P-013 | `artist-1-d1` | `${f.careerArtist} earns a first #1 hit as ${f.work} tops ${f.chart}.` | |
| P-014 | `artist-1-n-d1` | `${f.careerArtist} earns ${f.aOrdinalText} #1 hit as ${f.work} tops ${f.chart}.` | |
| P-015 | `artist-release-1-d1` | `${f.careerArtist} earns a first #1 ${f.releaseWord} as ${f.title} tops ${f.chart}.` | |
| P-016 | `artist-release-1-n-d1` | `${f.careerArtist} earns ${f.aOrdinalText} #1 release as ${f.title} tops ${f.chart}.` | |
| P-017 | `release-debut-1-d6` | `A #1 debut for ${f.artist}: the ${f.releaseWord} ${f.title} opens at the top of ${f.chart}.` | |
| P-018 | `release-debut-1-p5` | `New ${f.releaseWord}, new #1: ${f.subject} debuts at the top.` | |
| P-019 | `release-debut-1-p6` | `${f.artist} lands a #1 debut: ${f.title} enters ${f.chart} at the very top.` | |
| P-020 | `song-debut-10-p4` | `Out of the gate with ${f.streamsText}, ${f.subject} debuts in the Top 10 at #${f.rank}.` | |
| P-021 | `song-1-p4` | `${f.streamsText} and the top spot: ${f.subject} hits #1!` | |
| P-022 | `song-debut-p6` | `New arrival alert: ${f.subject} makes its debut at #${f.rank} on ${f.chart}.` | |
| P-023 | `release-debut-p3` | `Straight onto the chart: ${f.subject} enters at #${f.rank} with ${f.streamsText}.` | |
| P-024 | `release-debut-1-d1` | `${f.subject} opens its chart run at #1 on ${f.chart}.` | |
| P-025 | `release-debut-1-d3` | `The ${f.releaseWord} ${f.subject} debuts at #1 on ${f.chart} with ${f.streamsText}.` | |
| P-026 | `release-debut-d1` | `The ${f.releaseWord} ${f.subject} debuts at #${f.rank} on ${f.chart}.` | |
| P-027 | `release-debut-d3` | `The ${f.releaseWord} ${f.subject} opens at #${f.rank} with ${f.streamsText}.` | |
| P-028 | `release-1-d1` | `The ${f.releaseWord} ${f.subject} reaches #1 on ${f.chart}.` | |
| P-029 | `release-1-d2` | `${f.subject} succeeds ${f.rivalSubject} at #1 on ${f.chart}, the new #1 ${f.releaseWord}.` | revised (summary §4) |
| P-030 | `release-1-d3` | `${f.subject} rises from #${f.previousRank} to become the #1 ${f.releaseWord} on ${f.chart}.` | |
| P-031 | `release-1-d4` | `${f.subject} tops ${f.chart} with ${f.streamsText}, the new #1 ${f.releaseWord}.` | |
| P-032 | `release-1-again-d1` | `The ${f.releaseWord} ${f.subject} returns to #1 on ${f.chart}.` | |
| P-033 | `release-1-again-d2` | `${f.subject} is the #1 ${f.releaseWord} again, taking over from ${f.rivalSubject}.` | |
| P-034 | `release-1-again-p1` | `Back at #1! The ${f.releaseWord} ${f.subject} reclaims the top spot.` | |
| P-035 | `release-1-again-p5` | `Once more at #1: ${_p1(f)} ${f.releaseWord} ${f.title} heads ${f.chart} again.` | |
| P-036 | `release-peak-d1` | `The ${f.releaseWord} ${f.subject} reaches a new peak of #${f.rank} on ${f.chart}.` | |
| P-037 | `release-peak-d4` | `The ${f.releaseWord} ${f.subject} enters the Top ${f.threshold} at #${f.rank} on ${f.chart}.` | |
| P-038 | `release-peak-d5` | `With ${f.streamsText}, the ${f.releaseWord} ${f.subject} hits a new peak of #${f.rank}.` | |
| P-039 | `release-peak-d6` | `${f.subject} moves from #${f.previousRank} to #${f.rank}, a new peak for the ${f.releaseWord}.` | |
| P-040 | `release-peak-p1` | `New peak for the ${f.releaseWord}! ${f.subject} climbs to #${f.rank}.` | |
| P-041 | `release-peak-p5` | `${f.streamsText} and a new peak: the ${f.releaseWord} ${f.subject} reaches #${f.rank}.` | |
| P-042 | `release-reentry-d1` | `The ${f.releaseWord} ${f.subject} re-enters ${f.chart} at #${f.rank}.` | |
| P-043 | `release-reentry-d2` | `Back on ${f.chart}: the ${f.releaseWord} ${f.subject} returns at #${f.rank}.` | |
| P-044 | `release-reentry-d4` | `The ${f.releaseWord} ${f.subject} returns at #${f.rank}, having peaked at #${f.previousPeak}.` | |
| P-045 | `release-reentry-p1` | `The ${f.releaseWord} is back! ${f.subject} re-enters at #${f.rank}.` | |
| P-046 | `release-streams-d1` | `The ${f.releaseWord} ${f.subject} reaches ${f.milestoneText} on Sonus.` | |
| P-047 | `release-streams-d3` | `The ${f.releaseWord} ${f.subject} reaches ${f.milestoneText} and stands at #${f.rank} on ${f.chart}.` | |
| P-048 | `release-streams-d6` | `The ${f.releaseWord} ${f.subject} passes ${f.milestoneText}.` | |
| P-049 | `release-streams-p1` | `${f.milestoneText}! The ${f.releaseWord} ${f.subject} hits a streaming milestone.` | |
| P-050 | `release-streams-p5` | `Milestone unlocked: the ${f.releaseWord} ${f.subject} reaches ${f.milestoneText}.` | |

In refined stories, `${f.chart}` renders through P-003/P-004, so no override says "this week's". Overrides P-024 to P-050 apply to approved release families; the release variants of P-028 to P-035 that name a rival keep the verified-rival rule.

### 6.4 Featured-guest exclusions (refined stories with a featured artist only)

These approved legacy lines render `${f.work} by ${f.artist}` (or similar) and drop the guest. Legacy rendering is unchanged. In the refined view they are **excluded when `featured != null`**, until a replacement is approved: `song-debut-1-p4`, `song-debut-10-p6`, `song-debut-p2`, `song-bu-debut-p2`, `song-bu-debut-p5`, `song-break-d5`, `song-peak-p2`, `song-repeak-d5`, `song-climb-d5`, `song-gainer-d5`, `song-reentry-d5`, `song-streams-d4`, `song-streams-p6`, `artist-top10-d5` (14).

`artist-hot100-d5` and `artist-1-d6` leave this list if P-001/P-002 are approved with `${f.subject}`; otherwise they join it. A test checks that each affected family still has a fitting line for both publishers when a guest is present.

### 6.5 Flagged, not proposed for this release

| Item | Issue | Proposal |
|---|---|---|
| CJ-041 (approved) `Qualified streams: N (up G on last week).` | "last week" vs E-15 | Unchanged now. A separately authorized refined override could be `Qualified streams: ${week} (up ${gain} on the week before).` |
| `song-break-p4` (approved) `${f.artist} cracks the Sonus Hot 100 as ${f.work} rises to …` | Can read as the artist's first Hot 100 entry | **P-051 (proposed):** refined-only exclusion of this line when the artist already had a Hot 100 entry. Requires your approval; not counted in the F05 totals. |
| BU-060 to BU-071 | Deferred (E-12) | None |

## 7. Implementation batches (after approval only)

Each batch: targeted tests, `dart format`, `flutter analyze`, one full suite (`--concurrency=1`) in the main session, the worktree boundary check, and a local commit with an allowlist. No batch sets the refined flag.

| Batch | Content | Needs approval of | New publishable copy |
|---|---|---|---|
| **0** | Isolation boundary (§5): `legacyOf` / `refinedOf`, override/exclusion/addition tables (all empty or unapproved), golden fixtures captured at `f062551` **before** any catalog change | Checklist A-0 to A-3 | None |
| 1 | P-003 + P-004 (helper), P-005 + P-006 (bodies), P-007 to P-009 | B-1 | Refined overrides |
| 2 | P-001, P-002, P-010 to P-023; §6.4 exclusions | B-2, B-3 | Refined overrides |
| 3 | P-024 to P-050 | B-4 | Refined overrides |
| 4 | F05: BU-001, BU-002 overrides; BU-010 to BU-015 additions; P-051 if approved | C-1 | F05 refined lines |
| 5 | NEW FACT `placesDown`; families `songBubblingUnderFall` and `songHot100Exit` wired from the existing `copyGated` ids (`#bu-fall`, `#hot-100-exit`); tier rules (§4); both added to `approvedFamilies` | C-2, C-3 | Two new families |
| 6 | `songFirstThreshold`, `releaseFirstThreshold` | D-1 | Two families |
| 7 | `songSelfReplacement`, `releaseSelfReplacement` | D-2 | Two families |
| 8 | `artistRepeatNumberOne`, `artistRepeatNumberOneRelease`, `artistSimultaneousReleases` | D-3 | Three families |
| 9 | `songThresholds`, `releaseThresholds` | D-4 | Two families |
| 10 | Documentation: Progress, QA, Restart, Traceability, Reconciliation | — | — |

Batches 1–3 and 6–9 are independent once Batch 0 is in. Batch 5 depends on nothing but Batch 0. The refined flag (BLOCKED #21) is a separate, later decision.

## 8. Regression-test requirements

**Golden fixtures (Batch 0, captured at `f062551` before any catalog change).** Store them as a test resource, for example `test/features/charts/presentation/editorial/goldens/legacy_moments_v1.json`. Each record holds the full `MomentStory`: headline, body, kicker, status, publisher, variantId, rank and cover fields. Representative stories, at least:
- **Weekly songs:** debut #1, Top 10 debut, #11–100 debut, Bubbling Under debut, first Hot 100 entry from Bubbling Under, re-entry, new peak, peak match, big climb (Hot 100 and Bubbling Under), biggest gainer, #1 with a verified rival, return to #1, stream milestone, weeks milestone.
- **Weekly releases:** debut #1, debut, #1 with a rival, re-entry, new peak, stream milestone.
- **Career (all-time) songs and releases:** arrival, #1, career Top 10 / Hot 100 / first #1 / nth #1, top artist, stream milestones.
- **Artist roundups:** songs.
- **Each case twice:** once with a featured performer, once without.
- **Each case under three rule settings:**
  - no activation (legacy);
  - activation set, with the story before the activation instant or week (pre-activation);
  - pre-activation career stories.

**Tests required:**
1. **Byte-identical legacy:** every golden fixture renders exactly the stored record, after every batch.
2. **Selection sweep:** for every legacy family and every publisher, 500 synthetic story ids pick the same variant ids as the golden sweep (catches order or size changes in a family).
3. **View isolation:**
   - with all refined tables populated, the legacy view of every family equals the frozen list (ids, order, texts);
   - `legacyOf` is used whenever `facts.refined` is false.
4. **Fail-closed:** unapproved overrides, exclusions and additions are inert; families outside `approvedFamilies` publish nothing, and the neutral fallback never names them; a family joins only with 6 + 6 approved distinct lines.
5. **Copy rules (refined view):**
   - every family has 6 SD + 6 PP distinct rendered texts;
   - #1 families contain "#1";
   - lines end in "." or "!";
   - no "this week", "this stream", "last week" (CJ-041 excepted until authorized), "all-time", "lifetime", "for now";
   - weekly #101–200 song ranks are named Sonus Bubbling Under;
   - releases are never named Bubbling Under.
6. **Facts:**
   - `placesDown` is computed only for verified links;
   - exit tier: notable with previousPeak ≤ 40, otherwise minor;
   - falls are minor;
   - repeat ordinals count distinct songs or releases (a song holding #1 for several weeks does not raise the next ordinal);
   - roundup counts are distinct `albumId`s;
   - self-replacement wording is never used for a different artist.
7. **Attribution:** in refined stories with a guest, the §6.4 lines are never chosen and every headline that names the artist also names the guest, or names neither.
8. **Existing suites keep passing:** `moment_editorial_test.dart`, `moments_reachability_test.dart`, `bubbling_under_moments_test.dart`, chart-jump tests, and the approved-family guard tests.

## 9. Remaining release blockers

| Blocker | Source |
|---|---|
| Editorial approval of this contract (§11), then Batches 0–9 | Progress #7, #12, #17 |
| Refined Moments flag stays off until the copy is approved and implemented | #21 |
| Paused-sync wording | #26 |
| Remaining Import Review wording (17 strings, Imports count) | #27 |
| Device QA (M-6): SAF file states, Repeat One, shuffle order, Clear queue, media session, Android Auto | #14, #24, #27, QA §9 |
| M-2/M-3 sign-off; plugin patches M-4/M-5 | #14 |
| DB v41 on real devices (take a backup first) | #1 |
| Cloud: B-Q19 Leaked rows, signed-out edition delete, cloud verification | #2, #3 |
| Placement re-queue repair | #4 |
| Destructive workflows (Trash, Delete from Phone, ringtones) | #13 |
| Release signing, `versionCode`, Supabase migrations | QA report §9 |
| Optional: CJ-041 "last week" correction | §6.5 |

## 10. Conflicts with existing rules

**No proposed wording conflicts with an approved rule** after the corrections in this contract. Points to note:
1. **CJ-041** (already approved) uses "last week", against E-15. It is kept unchanged as you instructed and flagged for a separate refined-only correction.
2. **`song-break-p4`** (approved legacy copy) can imply an artist debut, against E-16 and the song-debut rule. It stays in the legacy view; the refined exclusion P-051 needs your approval.
3. **E-8 "where practical":** five Sonus Daily multi-zone lines do not name the chart (`song-zones-d1`, `-d4`, `release-zones-d1`, `-d4`, `-d5`), because the zone list is long. Confirm that this is acceptable.
4. **E-14 and the tier model:** `MomentFamily.tierFor(rank)` takes only the rank; the exit rule needs the verified peak too. This is a code change inside Batch 5, not a policy conflict.
5. **F05 publisher:** F05 is PulsePop under the refined rules, so the SD additions BU-010 to BU-012 are fallback lines. This is consistent with E-5.
6. **P-005/P-006** now say "the week before" instead of the proposal's "the previous week" (E-15). Both are completed-week wording; the change is for consistency only.

## 11. Approval checklist

Tick or annotate each item. Nothing is implemented until its item is ticked, and ticking an item does not activate the refined flag.

**A. Policy and safety**
- [ ] A-0 Confirm that no build distributed to users ever had `SONUS_MOMENTS_REFINED_APPROVED` set, so that no refined story has been displayed.
- [ ] A-1 Approve policy E-1 to E-17 (§1).
- [ ] A-2 Approve the isolation design (§5) and Batch 0.
- [ ] A-3 Approve the golden-fixture and test requirements (§8).

**B. Existing approved copy (refined-only overrides)**
- [ ] B-1 P-003 (Option A) + P-004, P-005 + P-006 (with "the week before"), P-007 to P-009.
- [ ] B-2 P-001 and P-002 (with `${f.subject}`), P-010 to P-023 (P-013 to P-019 optional; tick individually if wanted).
- [ ] B-3 §6.4 featured-guest exclusions (14 lines).
- [ ] B-4 P-024 to P-050, with P-029 revised.
- [ ] B-5 (optional) P-051 `song-break-p4` refined exclusion.

**C. BUG-04**
- [ ] C-1 F05: BU-001, BU-002 (contract text), BU-010 to BU-015 (BU-013 and BU-015 contract text).
- [ ] C-2 `songBubblingUnderFall` BU-020 to BU-031, the NEW FACT `placesDown`, and the minor tier.
- [ ] C-3 `songHot100Exit` BU-040 to BU-051, with the tier rule (notable with a verified Top 40 peak, otherwise minor).
- [ ] C-4 Confirm BU-060 to BU-071 stay deferred.

**D. Nine refined families (each family all 12 lines, or annotate per line)**
- [ ] D-1 `songFirstThreshold`, `releaseFirstThreshold`.
- [ ] D-2 `songSelfReplacement`, `releaseSelfReplacement`.
- [ ] D-3 `artistRepeatNumberOne`, `artistRepeatNumberOneRelease`, `artistSimultaneousReleases`.
- [ ] D-4 `songThresholds`, `releaseThresholds`, including the §10 item 3 note on chart naming.

**E. Separate items**
- [ ] E-a CJ-041 correction: authorize now, or leave it for later.
- [ ] E-b Authorize implementation Batches 0–10 as listed in §7 (code, tests and local commits only; no flag, no push).

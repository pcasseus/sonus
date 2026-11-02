# SN-50 Moments: Editorial Change Proposal

**Status:** PROPOSAL. Every item needs your explicit approval, one line at a time. Nothing in this document has been applied.
**Date:** 2026-10-29
**Source catalog:** `C:\dev\sonus\SN50_Moments_Full_Editorial_Catalog.md` (audit of `36d4d5d`). Variant IDs (`Fnn-SD-kk` / `Fnn-PP-kk` and source ids such as `song-debut-1-d1`) and body IDs (`B1`–`B9`) are used exactly as the catalog gives them.
**Authority:** `C:\dev\sonus\SN50_Master_Implementation_Spec.md` §0 and §6 (Session F, F-Q1 to F-Q31). Where the October 28 `SN50_Product_Decision_Register.md` conflicts with it, the Master Spec wins.

**Rule:** Every existing variant stays word for word as it is until you approve its item here (Decision Register F-C1, Master Spec §6 F3: "F-Q29 approves the new direction, not blanket deletion"). If you reject an item, that variant stays unchanged. Sections 3 and 4 are new drafts and do not change any existing copy.

**How to read an item:** "Current" is the catalog text, verbatim. "Proposed" keeps the catalog's placeholder syntax (`${f.x}`, `${_pc(f)}`, `${_p1(f)}`, `MomentFacts.…`). Unless an item says otherwise, the required facts ("Needs") stay the same, so the variant becomes eligible in exactly the same situations as before.

**Constraints the proposals respect** (from the existing test `moment_editorial_test.dart`, catalog §8):
- Each family keeps at least 6 Sonus Daily and 6 PulsePop variants, and every rendered text in a family is distinct.
- Headlines in a #1 family contain "#1".
- No banned filler: lifetime, summit, all-time leader, another chart cycle, steady movement, points.
- Every headline ends in "." or "!".

---

## 1. Summary of what drives the changes

| Driver | Decision / defect | Effect on existing copy |
|---|---|---|
| Wrong word for people | F-Q21 ("its" for people; redundant names) | P-001, P-002, P-011, P-012 |
| Finalized weeks must not be called "this week" or described by "this stream" | F-Q8 / F-Q24, catalog W3, W9 | P-003, P-005 to P-009 |
| Bubbling Under labelled "Hot 100" on weekly stories | catalog W5 (Register F-P3) | P-004 |
| Factual accuracy for both publishers | F-Q28 ("both must be factually accurate"), catalog §6 item 3 | P-010 |
| "#1" stated twice in one headline | catalog §6 item 9 (editorial flag, no decision; lowest priority) | P-013 to P-019 |
| PulsePop variants that repeat a Sonus Daily variant in a flat voice | F-Q28 / F-Q29 | P-020 to P-023 |
| Release variants that copy song variants word for word | F-Q29 (song and release families must be distinct), catalog O10 (27 copies) | P-024 to P-050 |
| Retire the words "All Time" | Master Spec §0 item 4 | **No item.** No Moments headline, body, kicker, status or tag uses "All Time" (checked in the catalog and in `presentation/editorial/`). The test already bans "lifetime", "summit" and "all-time leader" in headlines. |

---

## 2. Proposed changes to existing copy

### 2A. Factual and decision-driven (highest priority)

| Item | Catalog ID(s) | Current text (verbatim) | Problem | Proposed text | Type |
|---|---|---|---|---|---|
| P-001 | F15-SD-05 `artist-hot100-d5` | `${f.work} by ${f.artist} gives ${f.ownerName} its first Sonus Hot 100 entry, at #${f.rank}.` | F-Q21: "its" refers to a person or group (catalog §6 item 12). | `${f.work} by ${f.artist} gives ${f.ownerName} a first Sonus Hot 100 entry, at #${f.rank}.` | rewrite |
| P-002 | F18-SD-06 `artist-1-d6` | `${f.work} by ${f.artist} gives ${f.ownerName} its first #1 on ${f.chart}.` | F-Q21: same "its" for a person or group. | `${f.work} by ${f.artist} gives ${f.ownerName} a first #1 on ${f.chart}.` | rewrite |
| P-003 | Facts helper `chart` (catalog §3.1), weekly branches. Affects every `${f.chart}` headline in weekly scope (118 source headlines use `${f.chart}`). | songs weekly: `"this week's Sonus Hot 100"`; albums weekly: `"this week's Sonus Albums & EPs chart"` | F-Q24 / W9: weekly stories are published after the week ends, so "this week's" is wrong. | **Option A (recommended):** `"the weekly Sonus Hot 100"` / `"the weekly Sonus Albums & EPs chart"`. **Option B:** `"the Sonus Hot 100 for the week ending ${weekEnding}"` / `"the Sonus Albums & EPs chart for the week ending ${weekEnding}"`. Option B needs a new week-ending fact and gives long headlines. | rewrite (helper) |
| P-004 | Facts helper `chart`, branch order | `ChartType.songs when weekly` is checked before `ChartType.songs when bubblingUnder`, so a weekly song at #101–200 renders as the Hot 100 | W5: the headline says Hot 100 while the kicker and tag say Bubbling Under (a factual mismatch). | Check Bubbling Under first and return `"the weekly Sonus Bubbling Under"` for weekly songs ranked above 100. This uses Option A wording; with Option B it would be "the Sonus Bubbling Under for the week ending …". This is a factual fix. You may approve it on its own, separate from P-003. | rewrite (helper) |
| P-005 | Body B3 (weekly scope only) | `'$it was at #$previous, its best so far, before this stream.'` | F-Q8 / F-Q24, W3: on weekly stories no single stream caused the move. `previousRank` there means the previous week's rank. | Weekly scope: `'$it was at #$previous the previous week, its best until then.'` All-time scope stays verbatim, since F-Q8 allows real-time stories to mention the qualifying play. | rewrite (weekly scope only) |
| P-006 | Body B4 (weekly scope only) | `'$it was at #$previous before this stream.'` | Same as P-005. | Weekly scope: `'$it was at #$previous the previous week.'` All-time scope stays verbatim. | rewrite (weekly scope only) |
| P-007 | F11-SD-06 `song-gainer-d6` | `No song climbs further this week than ${f.subject}, up ${f.places} places to #${f.rank}.` | F-Q24: F11 is weekly-only and is published after the week has ended. | `No song climbed further in the chart week than ${f.subject}, up ${f.places} places to #${f.rank}.` | rewrite |
| P-008 | F11-PP-06 `song-gainer-p6` | `${f.work} leads every climber this week, rising ${f.places} places to #${f.rank}.` | F-Q24: same issue. | `${f.work} leads every climber of the chart week, rising ${f.places} places to #${f.rank}.` | rewrite |
| P-009 | F22-PP-04 `artist-sim-p4` | `${f.artist} lands ${f.count} songs in the Top ${f.threshold} this week.` | F-Q24 (finalized week). Also F-Q15 extends simultaneous stories to other chart scopes, where "this week" would be false. | `${f.artist} lands ${f.count} songs in the Top ${f.threshold} of ${f.chart}.` (The chart name then carries the scope; see P-003.) | rewrite |
| P-010 | F15-PP-04 `artist-hot100-p4` | `${f.careerArtist} cracks the Sonus Hot 100 for the first time as ${f.work} reaches ${f.streamsText}.` | F-Q28 accuracy: the stream count is presented as the cause of the entry (catalog §6 item 3), and the rank is required but never stated. | `${f.careerArtist} cracks the Sonus Hot 100 for the first time: ${f.work} enters at #${f.rank} with ${f.streamsText}.` | rewrite |

### 2B. Redundant wording (F-Q21 "redundant names"; catalog §6 item 10)

| Item | Catalog ID(s) | Current text (verbatim) | Problem | Proposed text | Type |
|---|---|---|---|---|---|
| P-011 | F20-PP-03 `artist-top-p3` | `${f.title} vs. ${f.rivalTitle}: ${f.title} pulls ahead as your #1 artist.` | The artist's name appears twice (F-Q21). | `Head to head with ${f.rivalTitle}, ${f.title} pulls ahead as your #1 artist.` | rewrite |
| P-012 | F22-PP-02 `artist-sim-p2` | `${f.count} songs, one artist: ${f.artist} holds ${f.count} Top ${f.threshold} spots.` | The count appears twice (catalog §6 item 10). | `${f.count} songs, one artist: ${f.artist} is all over the Top ${f.threshold}.` | rewrite |

### 2C. "#1" stated twice in one sentence (catalog §6 item 9; editorial only, optional)

No Session F decision requires these changes. They are offered because the catalog flags them. Of the 13 flagged variants, the 6 others read acceptably and are **not** proposed: F19-SD-05, F19-PP-05, F31-SD-06, F32-SD-05, F32-PP-03, F32-PP-05.

| Item | Catalog ID(s) | Current text (verbatim) | Proposed text | Type |
|---|---|---|---|---|
| P-013 | F18-SD-01 `artist-1-d1` | `${f.careerArtist} earns a first #1 hit as ${f.work} reaches #1 on ${f.chart}.` | `${f.careerArtist} earns a first #1 hit as ${f.work} tops ${f.chart}.` | rewrite |
| P-014 | F19-SD-01 `artist-1-n-d1` | `${f.careerArtist} earns ${f.aOrdinalText} #1 hit as ${f.work} reaches #1 on ${f.chart}.` | `${f.careerArtist} earns ${f.aOrdinalText} #1 hit as ${f.work} tops ${f.chart}.` | rewrite |
| P-015 | F31-SD-01 `artist-release-1-d1` | `${f.careerArtist} earns a first #1 ${f.releaseWord} as ${f.title} reaches #1 on ${f.chart}.` | `${f.careerArtist} earns a first #1 ${f.releaseWord} as ${f.title} tops ${f.chart}.` | rewrite |
| P-016 | F32-SD-01 `artist-release-1-n-d1` | `${f.careerArtist} earns ${f.aOrdinalText} #1 release as ${f.title} reaches #1.` | `${f.careerArtist} earns ${f.aOrdinalText} #1 release as ${f.title} tops ${f.chart}.` (This also adds the chart scope; see F-Q10.) | rewrite |
| P-017 | F23-SD-06 `release-debut-1-d6` | `A #1 debut for ${f.artist}: the ${f.releaseWord} ${f.title} opens at #1.` | `A #1 debut for ${f.artist}: the ${f.releaseWord} ${f.title} opens at the top of ${f.chart}.` | rewrite |
| P-018 | F23-PP-05 `release-debut-1-p5` | `New ${f.releaseWord}, new #1: ${f.subject} debuts at #1.` | `New ${f.releaseWord}, new #1: ${f.subject} debuts at the top.` | rewrite |
| P-019 | F23-PP-06 `release-debut-1-p6` | `${f.artist} lands a #1 debut as ${f.title} enters ${f.chart} at #1.` | `${f.artist} lands a #1 debut: ${f.title} enters ${f.chart} at the very top.` | rewrite |

### 2D. Publisher voice (F-Q28 / F-Q29): PulsePop variants that repeat a Sonus Daily variant in a flat voice

F-Q28 assigns publishers by the character of the story. It does not move individual variants, so this proposal contains **no publisher-reassign items**. Moving a variant to the other publisher would leave its family with 5 variants for one publisher. That breaks the six-per-publisher test, so every move would also need a newly written replacement. The items below instead give the PulsePop line a PulsePop voice. If you prefer to reassign an item instead, mark it "reassign to Sonus Daily", and a replacement PulsePop line will be drafted for your review.

| Item | Catalog ID(s) | Current text (verbatim) | Problem | Proposed text | Type |
|---|---|---|---|---|---|
| P-020 | F02-PP-04 `song-debut-10-p4` | `${f.subject} debuts at #${f.rank} with ${f.streamsText}.` | Word for word the same as F24-SD-03 (a Sonus Daily release line), and nearly the same as F02-SD-03. It has no PulsePop character (F-Q28/F-Q29). | `Out of the gate with ${f.streamsText}, ${f.subject} debuts in the Top 10 at #${f.rank}.` (F02 always ranks #2–#10, so "Top 10" is accurate.) | rewrite |
| P-021 | F06-PP-04 `song-1-p4` | `${f.subject} reaches #1 with ${f.streamsText}.` | F06-SD-02 minus the chart name (F-Q28/F-Q29). | `${f.streamsText} and the top spot: ${f.subject} hits #1!` | rewrite |
| P-022 | F03-PP-06 `song-debut-p6` | `${f.subject} makes its debut at #${f.rank} on ${f.chart}.` | Restates F03-SD-01 in the same measured voice (F-Q28). | `New arrival alert: ${f.subject} makes its debut at #${f.rank} on ${f.chart}.` | rewrite |
| P-023 | F24-PP-03 `release-debut-p3` | `${f.subject} enters at #${f.rank} with ${f.streamsText}.` | Near copy of F24-SD-03 (F-Q28/F-Q29). | `Straight onto the chart: ${f.subject} enters at #${f.rank} with ${f.streamsText}.` | rewrite |

### 2E. Release variants that copy a song variant word for word (F-Q29; catalog O10)

The catalog counts **27** release templates (in F23–F29) that are exact copies of a song template. In every pair below, the **song** line stays as it is and the **release** line is made release-specific. Most often this is done by naming the format through `${f.releaseWord}` ("album", "EP", or "release" when the format is unknown). All needs are unchanged. You can approve or reject each line on its own, or approve the whole group of rows.

| Item | Release ID (rewritten) | Song twin (kept) | Current text (verbatim, identical in both) | Proposed release text | Type |
|---|---|---|---|---|---|
| P-024 | F23-SD-01 `release-debut-1-d1` | F01-SD-01 | `${f.subject} debuts at #1 on ${f.chart}.` | `${f.subject} opens its chart run at #1 on ${f.chart}.` | rewrite |
| P-025 | F23-SD-03 `release-debut-1-d3` | F01-SD-03 | `${f.subject} debuts at #1 on ${f.chart} with ${f.streamsText}.` | `The ${f.releaseWord} ${f.subject} debuts at #1 on ${f.chart} with ${f.streamsText}.` | rewrite |
| P-026 | F24-SD-01 `release-debut-d1` | F02-SD-01, F03-SD-01 | `${f.subject} debuts at #${f.rank} on ${f.chart}.` | `The ${f.releaseWord} ${f.subject} debuts at #${f.rank} on ${f.chart}.` | rewrite |
| P-027 | F24-SD-03 `release-debut-d3` | F02-PP-04 (see P-020) | `${f.subject} debuts at #${f.rank} with ${f.streamsText}.` | `The ${f.releaseWord} ${f.subject} opens at #${f.rank} with ${f.streamsText}.` | rewrite |
| P-028 | F25-SD-01 `release-1-d1` | F06-SD-01 | `${f.subject} reaches #1 on ${f.chart}.` | `The ${f.releaseWord} ${f.subject} reaches #1 on ${f.chart}.` | rewrite |
| P-029 | F25-SD-02 `release-1-d2` | F06-SD-04 | `${f.subject} replaces ${f.rivalSubject} at #1 on ${f.chart}.` | `${f.subject} succeeds ${f.rivalSubject} as the #1 ${f.releaseWord} on ${f.chart}.` | rewrite |
| P-030 | F25-SD-03 `release-1-d3` | F06-SD-03 | `${f.subject} rises from #${f.previousRank} to #1 on ${f.chart}.` | `${f.subject} rises from #${f.previousRank} to become the #1 ${f.releaseWord} on ${f.chart}.` | rewrite |
| P-031 | F25-SD-04 `release-1-d4` | F06-SD-02 | `${f.subject} reaches #1 on ${f.chart} with ${f.streamsText}.` | `${f.subject} tops ${f.chart} with ${f.streamsText}, the new #1 ${f.releaseWord}.` | rewrite |
| P-032 | F26-SD-01 `release-1-again-d1` | F07-SD-01 | `${f.subject} returns to #1 on ${f.chart}.` | `The ${f.releaseWord} ${f.subject} returns to #1 on ${f.chart}.` | rewrite |
| P-033 | F26-SD-02 `release-1-again-d2` | F07-SD-03 | `${f.subject} takes #1 back from ${f.rivalSubject}.` | `${f.subject} is the #1 ${f.releaseWord} again, taking over from ${f.rivalSubject}.` | rewrite |
| P-034 | F26-PP-01 `release-1-again-p1` | F07-PP-01 | `Back at #1! ${f.subject} reclaims the top spot.` | `Back at #1! The ${f.releaseWord} ${f.subject} reclaims the top spot.` | rewrite |
| P-035 | F26-PP-05 `release-1-again-p5` | F07-PP-05 | `Once more at #1: ${f.subject} heads ${f.chart} again.` | `Once more at #1: ${_p1(f)} ${f.releaseWord} ${f.title} heads ${f.chart} again.` | rewrite |
| P-036 | F27-SD-01 `release-peak-d1` | F08-SD-01 | `${f.subject} reaches a new peak of #${f.rank} on ${f.chart}.` | `The ${f.releaseWord} ${f.subject} reaches a new peak of #${f.rank} on ${f.chart}.` | rewrite |
| P-037 | F27-SD-04 `release-peak-d4` | F08-SD-04 | `${f.subject} enters the Top ${f.threshold} at #${f.rank} on ${f.chart}.` | `The ${f.releaseWord} ${f.subject} enters the Top ${f.threshold} at #${f.rank} on ${f.chart}.` | rewrite |
| P-038 | F27-SD-05 `release-peak-d5` | F08-SD-05 | `${f.subject} hits a new peak of #${f.rank} with ${f.streamsText}.` | `With ${f.streamsText}, the ${f.releaseWord} ${f.subject} hits a new peak of #${f.rank}.` | rewrite |
| P-039 | F27-SD-06 `release-peak-d6` | F08-SD-06 | `${f.subject} moves from #${f.previousRank} to a new peak of #${f.rank}.` | `${f.subject} moves from #${f.previousRank} to #${f.rank}, a new peak for the ${f.releaseWord}.` | rewrite |
| P-040 | F27-PP-01 `release-peak-p1` | F08-PP-01 | `New peak! ${f.subject} climbs to #${f.rank}.` | `New peak for the ${f.releaseWord}! ${f.subject} climbs to #${f.rank}.` | rewrite |
| P-041 | F27-PP-05 `release-peak-p5` | F08-PP-05 | `${f.subject} reaches #${f.rank} with ${f.streamsText}, a new peak.` | `${f.streamsText} and a new peak: the ${f.releaseWord} ${f.subject} reaches #${f.rank}.` | rewrite |
| P-042 | F28-SD-01 `release-reentry-d1` | F12-SD-01 | `${f.subject} re-enters ${f.chart} at #${f.rank}.` | `The ${f.releaseWord} ${f.subject} re-enters ${f.chart} at #${f.rank}.` | rewrite |
| P-043 | F28-SD-02 `release-reentry-d2` | F12-SD-02 | `${f.subject} returns to ${f.chart} at #${f.rank}.` | `Back on ${f.chart}: the ${f.releaseWord} ${f.subject} returns at #${f.rank}.` | rewrite |
| P-044 | F28-SD-04 `release-reentry-d4` | F12-SD-04 | `${f.subject} returns at #${f.rank}; it previously peaked at #${f.previousPeak}.` | `The ${f.releaseWord} ${f.subject} returns at #${f.rank}, having peaked at #${f.previousPeak}.` | rewrite |
| P-045 | F28-PP-01 `release-reentry-p1` | F12-PP-01 | `It's back! ${f.subject} re-enters at #${f.rank}.` | `The ${f.releaseWord} is back! ${f.subject} re-enters at #${f.rank}.` | rewrite |
| P-046 | F29-SD-01 `release-streams-d1` | F13-SD-01 | `${f.subject} reaches ${f.milestoneText} on Sonus.` | `The ${f.releaseWord} ${f.subject} reaches ${f.milestoneText} on Sonus.` | rewrite |
| P-047 | F29-SD-03 `release-streams-d3` | F13-SD-03 | `${f.subject} reaches ${f.milestoneText} and stands at #${f.rank} on ${f.chart}.` | `The ${f.releaseWord} ${f.subject} reaches ${f.milestoneText} and stands at #${f.rank} on ${f.chart}.` | rewrite |
| P-048 | F29-SD-06 `release-streams-d6` | F13-SD-06 | `${f.subject} crosses ${f.milestoneText}.` | `The ${f.releaseWord} ${f.subject} passes ${f.milestoneText}.` | rewrite |
| P-049 | F29-PP-01 `release-streams-p1` | F13-PP-01 | `${f.milestoneText}! ${f.subject} hits a streaming milestone.` | `${f.milestoneText}! The ${f.releaseWord} ${f.subject} hits a streaming milestone.` | rewrite |
| P-050 | F29-PP-05 `release-streams-p5` | F13-PP-05 | `Milestone unlocked: ${f.subject} reaches ${f.milestoneText}.` | `Milestone unlocked: the ${f.releaseWord} ${f.subject} reaches ${f.milestoneText}.` | rewrite |

Note on 2E: release subjects render as `Title by Artist` (catalog §3.1), so "The album Title by Artist …" reads naturally. Many of these lines still differ from their song twins only by the format word. If you want the release families to be more varied than that, reject the row and a fuller rewrite will be drafted.

### 2F. Requirements met outside the copy (no copy item; listed so nothing is lost)

- **F-Q5 / W1 / W2 (unverified or self rival):** The rival headlines (catalog §6 item 1: F01-SD-04, F01-PP-05, F06-SD-04, F06-PP-02, F07-SD-03, F07-PP-02, F18-SD-03, F18-PP-02, F23-SD-04, F23-PP-04, F25-SD-02, F25-PP-02, F26-SD-02, F26-PP-02, and body B2) read correctly once the rival really is the verified displaced #1. The fix belongs in the facts layer: only the displaced leader may become `rival`, and if none is verified there is no rival. No copy change is proposed. P-029 and P-033 change two of these lines only for F-Q29 reasons.
- **F-Q16 (self-replacement):** When the verified displaced #1 belongs to the same artist, the rival lines above repeat the artist's name ("…by Ava replaces …by Ava"). The desk should send these stories to the new self-replacement wording (section 3, N-4) instead of using the generic rival lines.
- **F-Q19 / F-Q20 / O8 (featured artists):** Variants built on `${f.work}` / `${f.artist}` leave guests out, while `${f.subject}` includes one. Naming every featured artist is best handled in `subject` and the facts layer (support two or more names), not by rewriting dozens of lines. If you want every variant to name all performers, that needs a separate review pass.
- **F-Q22 / F-Q23 (duplicate chrome; artist stories without a song-rank badge):** These are changes to the kicker, tag and badge (catalog §3.2), not to headlines. 154 of 372 headlines name a chart. This proposal does not remove the chart name from headlines. With P-003, the headline carries the scope and the card can drop the repeated pill.

---

## 3. New template families needed (no existing copy changed)

These are **new drafts** for event paths the Master Spec requires and no existing variant covers. Every line needs your approval. Placeholders marked **NEW FACT** do not exist today and would have to be added to `MomentFacts`. Each family will need 6 Sonus Daily and 6 PulsePop lines before it ships. Two or three lines per publisher are drafted here to set the voice; the rest follow after you approve the direction.

### N-1. Guaranteed debuts and re-entries at every rank #1–200 (F1: F-Q1/F-Q27, F-Q31, F-Q13)

- **Songs, weekly #11–200 and re-entries at any rank:** No new copy is needed. Existing F03, F04 and F12 can be wired to the weekly path, provided P-003 and P-004 are approved first, because otherwise they would print "this week's".
- **Releases at #101–200 (debuts):** New wording is needed because F24 says `${f.chart}` and the catalog shows no Bubbling Under name for albums. *Draft (assumes positions 101–200 stay "the Sonus Albums & EPs chart"):*
  - SD: `The ${f.releaseWord} ${f.subject} enters ${f.chart} at #${f.rank}.`
  - SD: `${f.title} by ${f.artist} joins ${f.chart} at #${f.rank}.`
  - PP: `On the board: the ${f.releaseWord} ${f.title} by ${f.artist} arrives at #${f.rank}.`
  - PP: `${f.artist} gets the ${f.releaseWord} ${f.title} onto ${f.chart} at #${f.rank}.`

### N-2. First entry into one threshold: Top 75 / 50 / 40 / 30 / 25 / 20 / 15 / 10 / 5 / 3 / 2 (F-Q14)

The Top 100 entry already exists (F05). #1 has its own families. New peaks in the Top 50/25/10/5/3/2 zones overlap with F08/F27, so these must be merged so that one move produces one story.

- Songs SD: `${f.subject} enters the Top ${f.threshold} of ${f.chart} for the first time, at #${f.rank}.`
- Songs SD: `${f.work} by ${f.artist} reaches the Top ${f.threshold} for the first time, at #${f.rank}.`
- Songs PP: `Into the Top ${f.threshold}! ${f.subject} reaches #${f.rank} for the first time.`
- Songs PP: `${f.artist} cracks the Top ${f.threshold}: ${f.work} reaches #${f.rank}.`
- Releases SD: `The ${f.releaseWord} ${f.subject} reaches the Top ${f.threshold} of ${f.chart} for the first time, at #${f.rank}.`
- Releases PP: `${f.artist} takes the ${f.releaseWord} ${f.title} into the Top ${f.threshold}, at #${f.rank}.`

### N-3. Several thresholds crossed in one move, lower ones combined into one story (F-Q14B)

This needs **NEW FACT** `${f.thresholdList}`, rendered for example as "the Top 75, Top 50 and Top 40". Which crossings count as "major breakthroughs" and get their own story is still undecided (see section 6).

- Songs SD: `${f.subject} moves into ${f.thresholdList} for the first time, now at #${f.rank}.`
- Songs PP: `Up and through: ${f.work} by ${f.artist} enters ${f.thresholdList} at #${f.rank}.`
- Releases SD: `The ${f.releaseWord} ${f.subject} moves into ${f.thresholdList} for the first time, now at #${f.rank}.`
- Releases PP: `${f.title} by ${f.artist} breaks into ${f.thresholdList} in one move, landing at #${f.rank}.`

### N-4. Verified self-replacement at #1 (F-Q16)

This applies only when the displaced #1 is verified and has the same career artist. It needs a **NEW FACT** flag (for example `selfReplacement`). Each song or release is named once, and the artist is named once.

- Songs SD: `${f.careerArtist} replaces ${f.rivalWork} with ${f.work} at #1 on ${f.chart}.`
- Songs SD: `${f.work} takes over #1 on ${f.chart} from ${f.rivalWork}, keeping the top spot with ${f.careerArtist}.`
- Songs PP: `Out with ${f.rivalWork}, in with ${f.work}: ${f.careerArtist} stays at #1.`
- Songs PP: `${f.careerArtist} follows one #1 with another: ${f.work} replaces ${f.rivalWork}.`
- Releases SD: `${f.careerArtist} replaces ${f.rivalWork} with ${f.title} at #1 on ${f.chart}.`
- Releases PP: `${f.careerArtist} follows one #1 with another: ${f.title} replaces ${f.rivalWork}.` ("#1 album" is deliberately avoided, because the earlier #1 may have been an EP.)

### N-5. Artist simultaneous-entry roundup, songs and releases, all applicable chart scopes (F-Q15)

This story is published **in addition to** the individual entry stories. Today, F22 covers songs only, on weekly charts, and only for the Top 10 and higher. The release version has no family.

- Releases SD: `${f.artist} has ${f.count} releases in the Top ${f.threshold} of ${f.chart} at once.`
- Releases SD: `${f.count} releases by ${f.artist} sit in the Top ${f.threshold} of ${f.chart}.`
- Releases PP: `Catalog power: ${f.artist} has ${f.count} releases in the Top ${f.threshold}.`
- Optional roundup that names the titles (**NEW FACT** `${f.titleList}`): SD `${f.artist} has ${f.count} songs in the Top ${f.threshold} at once: ${f.titleList}.`
- Threshold 200: "Top 200 of the Sonus Hot 100" would be false, since #101–200 is Bubbling Under. The wording is undecided (see section 6).

### N-6. Repeat #1s with an explicit chart scope (F-Q10 / F-Q30)

Weekly repeat #1s are currently told as F06 "NUMBER ONE" (W7), and weekly release #1s never use career wording. The count must be **per chart scope**, must include verified history from before Moments started and purged songs (F-Q30), and old Moments must never be backfilled.

- Songs SD: `${f.careerArtist} earns ${f.aOrdinalText} #1 on ${f.chart} as ${f.work} takes the top spot.`
- Songs PP: `#1 number ${f.ordinal} on ${f.chart} for ${f.careerArtist}! ${f.work} takes the top spot.`
- Releases SD: `${f.title} gives ${f.careerArtist} ${f.aOrdinalText} #1 on ${f.chart}.`
- Releases PP: `${f.careerArtist} collects #1 number ${f.ordinal} on ${f.chart} with the ${f.releaseWord} ${f.title}.`

### N-7. Selected dethronings and exits (F-Q4)

The spec says "selectively", and the selection rules are not yet defined. Recommendation: tell a dethroning through the new #1's story with a verified rival (existing lines, once F-Q5 is fixed). Separate copy is drafted only for notable exits.

- SD: `${f.subject} leaves ${f.chart} after ${MomentFacts.weeksText(f.weeks!)}.`
- PP: `Farewell for now: ${f.work} exits ${f.chart} after ${MomentFacts.weeksText(f.weeks!)}.`

### Paths that need no new copy

- **Debut plus career milestone as separate stories (F-Q6/F-Q9):** reuse the existing debut and career families.
- **Major stream milestones as their own story (F-Q7):** reuse F13, F21 and F29.
- **Streaks (F-Q2/F-Q3):** reuse F14 and F30 (see section 4).
- **Exceptional peak matches:** reuse F09 (see section 4).

---

## 4. The three unreachable families

All three exist in the catalog and pass the template tests, but the real pipeline never publishes them (catalog §1.4, §2A). F-Q2 and F-Q3 now require streak and exceptional peak-match coverage.

| Family | What it says | Wording verdict before wiring |
|---|---|---|
| F09 `songPeakMatch` (`song-repeak-d1…d6`, `song-repeak-p1…p6`) | Weekly Top 10 return to an earlier peak, for example `${f.subject} matches its best position, #${f.rank}, on ${f.chart}.` / `Same peak, new week: ${f.work} returns to #${f.rank}.` | **Fine for weekly use**, once P-003 removes "this week's" from `${f.chart}`. F09-PP-06 ("new week") must stay weekly-only. If peak matches are ever told in real time, that line must be excluded. "Its" here refers to the song, which is acceptable. No release version exists. If one is wanted, it needs a new set (F-Q29). |
| F14 `songWeeksMilestone` (`song-weeks-d1…p6`, from shared `_weeksVariants`) | "N weeks at #1 / in the Top X / on the weekly chart", for example `${f.subject} spends ${MomentFacts.withArticle(MomentFacts.ordinalWord(f.weeks!))} consecutive week ${f.weeksPlace}.` | **Fine for songs on weekly charts.** `${f.weeksPlace}` with no threshold gives "on the weekly chart", which is wrong if streaks are ever counted on another scope. F14-SD-06 `completes week ${f.weeks} ${f.weeksPlace}` is ambiguous for non-consecutive totals; consider requiring `consecutive` for it. |
| F30 `releaseWeeksMilestone` (`release-weeks-d1…p6`, same shared set) | The same 12 lines as F14 with release ids | **Needs its own wording before wiring.** It is a word-for-word copy of the song set, which conflicts with F-Q29. A release-specific set should be drafted, for example `The ${f.releaseWord} ${f.subject} spends ${MomentFacts.withArticle(MomentFacts.ordinalWord(f.weeks!))} consecutive week ${f.weeksPlace}.`. Not itemized here: it is proposed as a follow-up once wiring is approved. |

The real blocker is the pipeline, not the wording. A rank event always outranks the milestone and peak-match events (harness A, A2 and B). Reachability tests from events to published stories are required (§6 F3).

---

## 5. Counts

| Type | Items |
|---|---|
| rewrite | **50** (P-001 to P-050). Of these, 46 are headline variants, 2 are the `chart` helper (P-003, P-004) and 2 are weekly-only body versions (P-005, P-006). |
| retire | **0** |
| publisher-reassign | **0** (see the note in 2D) |
| **Total proposals for existing copy** | **50** |
| New families drafted (section 3) | 7 path groups (N-1 to N-7), all new drafts |
| Unreachable families reviewed (section 4) | 3: F09 and F14 are usable once wired (after P-003); F30 needs its own wording |

By priority: 10 factual or decision items (2A), 2 redundancy items (2B), 7 optional "#1 twice" items (2C), 4 voice items (2D) and 27 song/release twin items (2E).

---

## 6. Open questions for your review

1. **F-Q10 "explicit chart scope" versus F-Q22 "chart context appears once":** Several repeat-#1 lines name no chart in the headline: F19-SD-03/04/06, all F19-PP lines, F32-SD-01/03/04/06 and all F32-PP lines. The card's kicker names the chart. Does the kicker count as the explicit scope, or must every repeat-#1 headline name the chart? No rewrite is proposed until you decide. P-016 adds the chart to one line only.
2. **The name for album positions #101–200** (N-1) and the wording for a **Top 200** roundup on the song chart (N-5).
3. **Which threshold crossings are "major breakthroughs"** that get their own story under F-Q14B, and which are combined (N-3).
4. **Numbering conflict:** in the Master Spec, F-Q31 means re-entry rules ("no rank or absence minimum"). In the October 28 register, F-Q31 is the "Hot 100" page header question. This document follows the Master Spec.

---

## 7. BUG-04 addendum: Bubbling Under movement and Hot 100 arrivals (2026-10-30)

**Status:** PROPOSAL. Nothing in this section ships. Every line below is a new draft that needs your approval, and no existing variant was changed. Source: `C:\dev\sonus\SN50_Additional_Bug_Tweaks_Addendum.md` §BUG-04.

### 7.1 What already ships with approved copy (code, not copy, changed)

These paths use existing families whose wording is factually accurate for the case. They are reachable only under the refined-rules activation gate (`ChartMomentRules`), and only for chart weeks starting at or after activation. Frozen weeks and stories published earlier are untouched.

| Case (addendum test) | Story told | Family reused | Why the wording is accurate |
|---|---|---|---|
| First Bubbling Under debut, #176 | Guaranteed entry, exempt from the minor cap | `songBubblingUnderDebut` | Every line names Sonus Bubbling Under. |
| Re-entry onto Bubbling Under | Guaranteed entry | `songReentry` | `${f.chart}` names Bubbling Under for #101–200. |
| #124 → #87, never on the Hot 100 before | Guaranteed Hot 100 arrival | `songHot100Breakthrough` | Lines say "enters / breaks into the Sonus Hot 100"; d2 cites the Bubbling Under rank as context. |
| #124 → #87 and also the week's largest raw climb | **No** biggest-gainer story | — | Fixed: a move from #101–200 into #1–100 no longer counts as a Hot 100 climb (E-Q1). Before the fix it could be told as "up 37 places". |
| #112 → #90, on the Hot 100 in an earlier week | Guaranteed Hot 100 re-entry | `songReentry` | Fixed: this move previously produced **no** story. Every `songReentry` line ("re-enters / returns to / is back on the Sonus Hot 100 at #90", "previously peaked at #X") is true. No movement figure is shown. |
| Off the chart last week, back at #90, only ever on Bubbling Under before | Guaranteed Hot 100 arrival | `songHot100Breakthrough`, minus four lines | Fixed: this was told as "re-enters the Hot 100", which is false. The four lines that describe a move up from Bubbling Under (`song-break-d5`, `-d6`, `-p2`, `-p4`) are skipped for this story only, because last week the song was not on Bubbling Under. |

### 7.2 Review item on existing copy (no change made)

- **`song-break-p3`** ("`${f.work} jumps from #${f.previousRank} to #${f.rank}, into the Sonus Hot 100.`") reads as a 37-place move for #124 → #87. E-Q1 measures official movement against the previous *official* rank. The line does not show "▲37", but you may prefer to rewrite it in the style of N-11 below or retire it. Until you decide, it stays as it is.

### 7.3 New drafts needed (blocked on editorial approval)

> **Superseded 2026-10-30 (round 4):** the selection rules below were replaced by the six approved decisions in `C:\dev\sonus\SN50_BUG04_Import_Final_Decisions_Claude_Handoff.md` (rises 20+, falls 30+, exits after a Top 40 peak or 5 Hot 100 weeks). Full 6 + 6 drafts for approval are in `SN50_BUG04_Editorial_Approval_Sheet.md` (BU-001 to BU-071). The N-8 to N-11 lines below are kept for reference only.

Each family needs 6 Sonus Daily and 6 PulsePop lines before it ships. Two or three per publisher are drafted here to set the voice.

**N-8. Hot 100 → Bubbling Under drop (#94 → #121).** F-Q4 approves *selective* coverage of consequential falls, but the selection rule is not defined. **Proposed rule for approval:** tell the drop only when the song reached the Top 40, or spent 5 or more weeks on the Hot 100, and only once per run (not on every later Bubbling Under week). Without approval, a drop produces no story (current behaviour).
- SD: `${f.subject} slips from #${f.previousRank} on the Sonus Hot 100 to #${f.rank} on Sonus Bubbling Under.`
- SD: `${f.work} by ${f.artist} leaves the Sonus Hot 100 and is now #${f.rank} on Sonus Bubbling Under.`
- PP: `Out of the Hot 100 for now: ${f.work} drops to #${f.rank} on Sonus Bubbling Under.`

**N-9. Rises within Bubbling Under (#171 → #139).** Today only the week's single biggest gainer (10+ places, across #1–200) is told. **Proposed rule for approval:** besides the biggest gainer, tell at most one more Bubbling Under climb a week, of 25 or more places, as a minor story that counts toward the daily cap. Without approval, no extra story (current behaviour).
- SD: `${f.subject} climbs from #${f.previousRank} to #${f.rank} on the weekly Sonus Bubbling Under.`
- SD: `${f.work} by ${f.artist} gains ${f.places} places on the weekly Sonus Bubbling Under, to #${f.rank}.`
- PP: `On the move: ${f.work} rises ${f.places} places to #${f.rank} on Sonus Bubbling Under.`

**N-10. Falls within Bubbling Under (#122 → #168).** Recommendation: **no story**. F-Q4 says "not every negative fluctuation", and a fall that stays inside #101–200 is rarely consequential. If you want one anyway, a draft:
- SD: `${f.subject} falls from #${f.previousRank} to #${f.rank} on the weekly Sonus Bubbling Under.`

**N-11. First Hot 100 entrance that cites last week's Bubbling Under rank as context** (your example wording). Optional: the existing `songHot100Breakthrough` lines already cover the case accurately.
- SD: `${f.subject} makes its Sonus Hot 100 debut at #${f.rank}, after #${f.previousRank} on Sonus Bubbling Under last week.`
- SD: `Previously #${f.previousRank} on Sonus Bubbling Under, ${f.work} by ${f.artist} now debuts at #${f.rank} on the Sonus Hot 100.`
- PP: `Hot 100 debut! ${f.work} arrives at #${f.rank}; it was #${f.previousRank} on Sonus Bubbling Under.`

### 7.4 Publication clocks (unchanged, confirmed by tests)

- Weekly Bubbling Under and Hot 100 stories come only from finalized weeks (`publishFinalizedForWeek`). A second finalization of the same week publishes nothing.
- Provisional This Week changes produce no permanent weekly story.
- Real-time (all-time chart) arrivals follow the activation gate from its instant.

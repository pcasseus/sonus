# SN-50 Existing Headline Approval Summary

**Status: RECOMMENDATIONS ONLY — NOT APPROVED.** This summarizes `SN50_Editorial_Change_Proposal.md` (P-001 to P-050, N-1 to N-7) against the current code at `f062551` and recommends a decision for each item. The **384 original headline variants stay word for word** until you approve an item; nothing here changes them.
**Date:** 2026-10-30. Editorial preparation only: no Dart, test or config change. The refined Moments flag stays off.

**How to answer:** per item, **Approve recommendation**, **Approve original proposal**, **Revise: …** or **Reject**. Decisions H-1 to H-6 (§7) come first, because they decide how any approved item is applied.

---

## 1. Kinds of copy

| Kind | What | Status |
|---|---|---|
| **Existing approved copy** | The 384 SN-45 catalog variants (F01–F32), bodies B1–B9, and the approved chart-jump families (`ae0fd05`) | Approved and live. Unchanged. |
| **Proposed revisions** | P-001 to P-050 (46 headline variants, 2 chart-name helpers, 2 weekly body sentences) | Pending; none applied. |
| **New drafts** | N-1 to N-7 (new families) | N-2 to N-6 are in code as drafts, held by the approved-family guard; see `SN50_Refined_Moments_Family_Approval_Package.md`. N-7's exits are superseded by BUG-04 §E; see `SN50_Final_BUG04_Editorial_Package.md`. |

## 2. The constraint that governs every rewrite

Moment headlines are **not stored**. They are composed from stored events each time the feed is shown (`charts_controller.dart:250` → `MomentEditorialDesk.compose`), and a variant is picked by a hash of the story id modulo the number of fitting lines (`_write`).

So rewording a variant, adding one, or changing a helper such as `chart` would also change the headline of **stories already published**. That is a historical repair, which is separately gated (Progress BLOCKED #11).

**Recommendation (H-1):** apply every approved item **prospectively**, only to stories under the refined rules (`facts.refined`, after the per-install activation). Legacy and pre-activation stories then stay byte-identical, as the existing tests pin. The alternative, applying the items to old stories too, would need your explicit historical-repair approval.

---

## 3. Priority items

### 3.1 "This week's" in finalized stories (P-003, P-004, P-007, P-008, P-009)

- **Today:** `MomentFacts.chart` renders a weekly song as "this week's Sonus Hot 100" and a weekly release as "this week's Sonus Albums & EPs chart". Under the refined rules, a weekly song at #101–200 renders as "this week's Sonus Bubbling Under" (`moment_facts.dart:249-259`). **118** of the original headlines use `${f.chart}`.
- **Already fixed in part:** the SN-50 lines use `${f.scopedChart}`, which is exactly P-003 Option A ("the weekly Sonus Hot 100", "the weekly Sonus Bubbling Under", "the weekly Sonus Albums & EPs chart"). The P-004 branch order (Bubbling Under before Hot 100) is in code for refined stories, but still with "this week's".
- **Literal "this week" in approved lines:** `song-gainer-d6` (P-007), `song-gainer-p6` (P-008) and `artist-sim-p4` (P-009). All three are reachable under both rule sets.
- **Recommendation:** approve **P-003 Option A** and **P-004** together, implemented as "for refined stories, `chart` returns `scopedChart`" (one change, all 118 lines, legacy unchanged). Approve P-007, P-008 and P-009. Option B (week-ending dates) is not recommended: it needs a NEW FACT and makes long headlines.

### 3.2 "Before this stream" (P-005, P-006)

- **Today:** bodies B3/B4 say "…before this stream." They are **suppressed** for weekly refined stories (`moment_editorial_desk.dart:336`), so refined weekly stories lose the sentence instead of getting a correct one. Legacy weekly bodies still print it.
- **Recommendation:** approve P-005 and P-006 for weekly refined stories, which restores the context sentence with correct wording ("…the previous week, its best until then." / "…the previous week."). Career (real-time) bodies stay verbatim, as F-Q8 allows.

### 3.3 Album positions #101–200 and Bubbling Under naming (P-004, N-1)

- Songs at #101–200 are "Sonus Bubbling Under" (P-004). Releases have no Bubbling Under chart; `chart` names every album rank as "the Sonus Albums & EPs chart".
- **Recommendation (H-3):** keep "the Sonus Albums & EPs chart" for album positions #101–200 and never use "Bubbling Under" for releases. Then N-1's release lines need no new chart name. "Top 200" wording on the song chart stays unused (the roundup zone is at most 10).

### 3.4 Performer credits (F-Q19, F-Q20)

- `${f.subject}` names featured artists; `${f.work} by ${f.artist}` does not. **16** approved lines use the latter: `song-debut-1-p4`, `song-debut-10-p6`, `song-debut-p2`, `song-bu-debut-p2`, `song-bu-debut-p5`, `song-break-d5`, `song-peak-p2`, `song-repeak-d5`, `song-climb-d5`, `song-gainer-d5`, `song-reentry-d5`, `song-streams-d4`, `song-streams-p6`, `artist-hot100-d5`, `artist-top10-d5`, `artist-1-d6`. A bare `${f.work}` is fine, because the card's credit line names every performer.
- **Options (H-4):** (a) for refined stories with a featured artist, skip those 16 lines (a selection change; no copy changes); (b) 16 new P-items rewriting them to `${f.subject}`; (c) accept as is.
- **Recommendation:** (a).
- **Artist-first lines that can imply an artist milestone** (approved copy, flagged only):
  - `song-break-p4` "`${f.artist}` cracks the Sonus Hot 100 as …" reads as the artist's first Hot 100 entry. Suggested P-051 if you want one: `${f.work} cracks the Sonus Hot 100, rising to #${f.rank}.`
  - Milder: `song-bu-debut-p3` "… lands on Sonus Bubbling Under …", `song-peak-p6` "… sees … rise …", `release-peak-p6` "… sees … rise …".

---

## 4. Item-by-item recommendations (P-001 to P-050)

Item texts are in `SN50_Editorial_Change_Proposal.md` §2. "Approve" means approving the proposal's text as written. Every approved item is applied under H-1.

| Item | Line(s) | Issue | Recommendation |
|---|---|---|---|
| P-001 | F15-SD-05 `artist-hot100-d5` | "its" for a person (F-Q21) | **Approve** |
| P-002 | F18-SD-06 `artist-1-d6` | "its" for a person | **Approve** (also on the §3.4 credit list) |
| P-003 | `chart` helper, weekly | "this week's" | **Approve Option A** (§3.1) |
| P-004 | `chart` helper, branch order | #101–200 named as Hot 100 | **Approve** (§3.1) |
| P-005 | Body B3, weekly | "before this stream" | **Approve** (§3.2) |
| P-006 | Body B4, weekly | "before this stream" | **Approve** (§3.2) |
| P-007 | F11-SD-06 `song-gainer-d6` | "this week" | **Approve** |
| P-008 | F11-PP-06 `song-gainer-p6` | "this week" | **Approve** |
| P-009 | F22-PP-04 `artist-sim-p4` | "this week" | **Approve** (takes its scope from P-003) |
| P-010 | F15-PP-04 `artist-hot100-p4` | Streams presented as the cause; rank missing | **Approve** |
| P-011 | F20-PP-03 `artist-top-p3` | Name twice | **Approve** |
| P-012 | F22-PP-02 `artist-sim-p2` | Count twice | **Approve** |
| P-013 | F18-SD-01 | "#1" twice | **Approve** (optional) |
| P-014 | F19-SD-01 | "#1" twice | **Approve** (optional) |
| P-015 | F31-SD-01 | "#1" twice | **Approve** (optional) |
| P-016 | F32-SD-01 | "#1" twice; adds the chart scope | **Approve** |
| P-017 | F23-SD-06 | "#1" twice | **Approve** (optional) |
| P-018 | F23-PP-05 | "#1" twice | **Approve** (optional) |
| P-019 | F23-PP-06 | "#1" twice | **Approve** (optional) |
| P-020 | F02-PP-04 | Flat PulsePop copy of an SD line | **Approve** (the streams floor of 10 already applies) |
| P-021 | F06-PP-04 | Flat PulsePop | **Approve** |
| P-022 | F03-PP-06 | Flat PulsePop | **Approve** |
| P-023 | F24-PP-03 | Flat PulsePop | **Approve** |
| P-024 to P-028 | F23/F24/F25 release twins | Exact copies of song lines (F-Q29) | **Approve** |
| P-029 | F25-SD-02 | Twin; "as the #1 `${f.releaseWord}`" can imply the rival was the same format | **Revise:** `${f.subject} succeeds ${f.rivalSubject} at #1 on ${f.chart}, the new #1 ${f.releaseWord}.` |
| P-030 to P-050 | F25–F29 release twins | Exact copies of song lines | **Approve as a group** |

On P-024 to P-050: many differ from their song twins only by the format word. If you want fuller variety, reject the group and a fuller rewrite will be drafted (Proposal §2E note).

Tally: 48 Approve (7 of them optional: P-013 to P-015 and P-017 to P-019), 1 Revise (P-029), and P-003 approved as Option A.

---

## 5. New-family proposals N-1 to N-7: where each stands

| Item | Status at `f062551` | Where to decide |
|---|---|---|
| N-1 Guaranteed debuts and re-entries #1–200 | Songs: in code with existing F03/F04/F12 copy; still prints "this week's" until P-003/P-004. Releases #101–200: 4 draft lines in the proposal, not in code | H-3; then the 4 release lines need 2 more per publisher |
| N-2 First zone entry | In code as drafts (`songFirstThreshold`, `releaseFirstThreshold`), held | Refined Moments package §5–§6 |
| N-3 Several zones at once | In code as drafts (`songThresholds`, `releaseThresholds`), held | Package §7–§8; major-zone question |
| N-4 Self-replacement at #1 | In code as drafts, held | Package §3–§4 |
| N-5 Release roundups | In code as drafts (`artistSimultaneousReleases`), held | Package §11 |
| N-6 Repeat #1s with chart scope | In code as drafts, held | Package §9–§10 |
| N-7 Dethronings and exits | Hot 100 exits into Bubbling Under: superseded by BUG-04 §E (approved rule 3). Dethronings are told through the verified rival in the new #1's story (F-Q5, done). Exits off both charts: no approved selection rule | BUG-04 package §6; exits off the chart need a rule from you (H-6) |

Not reopened: F09 `songPeakMatch` is now published under the refined rules. F14/F30 longevity (Proposal §4): F30 still needs its own release wording before it can publish (Progress / reconciliation #17).

---

## 6. Recommended approval order

1. **H-1** (prospective, refined-only application).
2. **P-003 (Option A) + P-004**, then **P-007, P-008, P-009**: all the misleading "this week" wording in finalized stories.
3. **P-005 + P-006**: "before this stream".
4. **P-010, P-001, P-002, P-011, P-012**: factual, people and redundancy items.
5. **H-4** (performer credits).
6. **P-020 to P-023**, then **P-024 to P-050**: voice and release twins.
7. **P-013 to P-019** (optional).

The BUG-04 package and the refined-family package can be decided in parallel. They depend on this summary only through P-003/P-004 and H-1.

## 7. Choices that need your input

| # | Question | Recommendation |
|---|---|---|
| H-1 | Apply approved rewrites only to refined, post-activation stories (old stories keep their text), or also to stories already published (a historical repair, BLOCKED #11)? | Refined-only. |
| H-2 | P-003 Option A ("the weekly …") or Option B ("for the week ending …")? | Option A. |
| H-3 | Album positions #101–200: keep "the Sonus Albums & EPs chart" (no Bubbling Under name for releases)? | Yes. |
| H-4 | Performer credits in the 16 `work by artist` lines: (a) skip them for songs with a guest, (b) rewrite them, or (c) accept? | (a). |
| H-5 | Release twins P-024 to P-050: approve the format-word versions, or ask for fuller rewrites? | Approve now; fuller variety later if wanted. |
| H-6 | Exits off both charts (N-7 remainder): define a selection rule, or keep them untold? | Keep untold for this release. |

Until these items are approved, the existing copy stays as it is, and the refined flag stays off (Progress BLOCKED #7, #21).

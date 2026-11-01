# Sonus Pulse 2.0: Implementation Scope

Status: proposal. **Not authorized.** Scheduled after SN-50 backup and device QA and a separate scope approval. Design: `SN50_Sonus_Pulse_2_Design_Spec.md`. Data classes: `SN50_Sonus_Pulse_Data_Feasibility.md`.

## 1. Minimum viable redesign (MVP)

Everything here is class A or B: no schema change, migration, cloud, playback or chart change.

- Insights tab renders **Sonus Pulse** (replaces the Monthly/Year segmented page).
- Month and Year views, previous/next, remembered period and measure (SharedPreferences, device-local).
- Pulse hero: daily spokes, Minutes / Streams, average ring, zero / future / no-history states, tap/drag readout, keyboard and screen-reader list.
- Overview tiles (Minutes, Streams, All plays, Active days, Artists, Tracks) with comparison deltas.
- Comparisons: previous period and same period last year, with the history-eligibility rule.
- Top 5 artists, tracks, albums & EPs; metric menu (Streams, Minutes, All plays); Top 10 / 25 in place.
- Inline detail with stats, trend, Play / Open artist / Open album, Close.
- Theme-derived colour system (spec §7): per-theme metric ramps, value bars, comparison colours, halo, settings behaviour.
- Artwork overlay on the opened card, hero halo and the item's share of each spoke, with Reset colours (existing palette and atmosphere code).
- Loading, empty, partial-history and error states; motion per spec with reduced-motion alternatives; 320 dp / 2× text / nine themes / high contrast.
- Year view: Months and Milestones cards (existing Year in Sonus data).

## 2. Later enhancements

| Item | Class | Notes |
|---|---|---|
| Dedicated full-screen ranking views with search and paging | B | MVP links Top 25 in place; the route is next |
| Month/year picker sheet with per-period bars | B | |
| Hour-of-day inner ring (months) | A | Data exists; legibility review first |
| Week and Lifetime periods | B | `AnalyticsPeriod` supports them |
| Current streak, new songs discovered, monthly milestones | B | |
| Shared-element artwork transitions to profiles | — | UI only |
| Featured-artist credit in rankings | B (current credits) / C (at play time) | Needs decision |
| Play-time time-zone accuracy | C | Migration to store a UTC offset per session |
| Genre share | B, weak | Library genres only |
| Listening source or device | C/D | Not recorded |

## 3. Missing dependencies

1. **Year-window day buckets:** the distribution service is month-only. Generalize it to any window (B).
2. **"All plays" counts** per period and per entity: new aggregation over sessions (B).
3. **Minutes per entity for a year:** generalize `MonthlyEntityListeningDurationService` (B).
4. **Segment query lower bound** (`ended_at >= start`) so year and multi-year views don't read all history; optional grouped SQL. DAO change only, no schema change.
5. **Comparison eligibility helper** from the first recorded session.
6. **Period preference store** (new SharedPreferences keys).
7. **Pulse ring painter** with hit-testing and semantics (new `CustomPainter`; no chart package exists or is needed).
8. **Do not use** `AnalyticsSummary.qualifiedListeningDuration` for minutes (it sums 30-second snapshots). Optionally fix or document it in the same batch.
9. ~~Decisions in the feasibility doc §5~~ resolved 2026-10-31.
10. **Pulse colour derivation** from `SonusTheme` tokens (OKLCH ramps, chroma floor, contrast checks); no theme or settings change.
11. **Per-item day series** for the selected item's spoke overlay, in the selected metric (B), computed from the same rows and day boundaries as the totals.

## 4. Proposed batches (each: targeted tests, analyzer, format; one full suite per group)

| Batch | Contents | Tests |
|---|---|---|
| **P1 Data layer** | Window-generic day/hour buckets; all-plays counts; year minutes per entity; segment lower bound; eligibility helper; `PulsePeriodData` model assembled by a `PulseInsightsService` reusing existing services | Disposable SQLite: day boundaries at local midnight, segments spanning midnight split correctly, no-history vs zero, eligibility at the exact first-play day, Singles/blocked per decisions, no double counting across editions, minutes never from qualified snapshots, lower bound returns identical totals to the current query |
| **P2 Controller and persistence** | `PulseInsightsController` (period, measure, comparison, generation counter); `insights.pulse.*` store with clamping | Restore, clamp future/past periods, stale-response discard, comparison eligibility toggling |
| **P3 Pulse hero and colour** | Ring painter, theme-derived ramps, halo, item overlay, legend, readout, keyboard/list semantics, sweep animation and reduced-motion path | Golden-free painter tests (spoke geometry and tip colour from data); item overlay ≤ day total for every day in both metrics, absent on days without the item, lead-artist and `album_id` attribution; Monochrome stays greyscale (zero chroma) except for selection accents; ramps for all nine themes (≥ 3:1 on surface, families distinct), flat steps with low effects / Decoration Off, solid colours in high contrast, hit-test to day, semantics labels, reduced motion = no ticker |
| **P4 Overview and comparisons** | Tiles, deltas ("New", "Not enough history"), info sheet, chips | Delta rules incl. zero base, partial history copy |
| **P5 Rankings and detail** | Three cards, metric menu, Top 5/10/25, labels, inline detail, actions, accent and Reset | Ranking per metric, labels, play/open callbacks, accent scoped to one card, reset paths, low effects/high contrast disable |
| **P6 Page assembly and design matrix** | Replace `ListeningInsightsPage`; Year cards; states; 320 dp × 2× text × nine themes; high contrast; Decoration Off | Existing design-test pattern; old Monthly/Year tests retired or rewritten under the new rules (listed in the batch report) |

Groups for full suites: P1–P2, P3–P4, P5–P6.

**Status (2026-10-31):** MVP approved. **P1 done** (`PulsePeriod`, `PulsePeriodData`, `PulseListeningRecords` with `SqlitePulseListeningRecords`, `PulseInsightsService`; 20 tests). It reads through a new bounded read-only source, so no existing repository interface changed. Lifetime streams per entity and per-item trend lines move to P5 (detail). No in-memory cache yet; P2's controller can add one for finished periods.

## 5. Risks

- Retiring Monthly/Year pages removes some existing tables (completion rate, lifetime streams per row); the spec keeps them in "More about this month" and the detail, but confirm nothing you rely on is dropped.
- Year views over long histories are the main performance risk until dependency 4 lands.
- Device-zone bucketing can shift travel-day plays; documented in the page's info sheet.
- Monochrome is greyscale by decision, with tonal ramps and bar patterns (spec §7.2); colour appears there only through temporary artwork accents.
- The spoke gradients, glow and halo must stay smooth on the target phone; measure on device before release (low effects is the fallback).
- No device verification until a build is installed (separate approval).

## 6. Boundaries during implementation

No schema or migration, no change to qualification, charts, finalized history, sync or playback; refined Moments flag stays off; new strings go to wording review; no install, cloud write, push or merge.

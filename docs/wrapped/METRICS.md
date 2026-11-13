# Sonus Wrapped: metric definitions

Sonus Wrapped (App Update 1.2) summarises a calendar month or year from what Sonus recorded while you listened.

**Where the numbers come from:**
- Wrapped is built from Sonus Pulse's period data (`PulseInsightsService`). Streams, minutes, rankings and comparisons therefore always match the Insights tab for the same period.
- It adds read-only queries for genres, lifetime milestones and stored chart #1s (`SqliteWrappedHistoryReader`).

**What it never does:**
- write;
- store a derived statistic;
- import or estimate history.

## Periods and time

| Rule | Definition |
|---|---|
| Time zone | The device's current zone. No per-play offset is stored, so plays made while travelling are bucketed by the zone the device is in now (the same as Pulse). |
| Month / year | Local midnight on the first day to local midnight on the first day of the next period. Daylight-saving days are kept as whole local days. |
| History start | The start of the first recorded listening session. Days before it are *no history*, never zero listening. |
| States | **future** (starts after today); **beforeHistory** (ends before history began); **inProgress** (contains today: a Wrapped *so far*, never presented as finished); **complete**. A complete period that history began inside is labelled **partial**. |
| Archive | Every month and year from the history start to today. |

## Listening

| Metric | Definition |
|---|---|
| **Streams** | Qualified plays: at least 30 s of listening, or half of a track shorter than that (minimum 5 s) (`ListeningQualificationPolicy`). A stream belongs to the period in which it qualified. |
| **Listening time** | Audible time from listening segments, clipped to the period and split at local hour boundaries. It is never the full track length, and never the ~30 s snapshot stored on a qualified play. |
| All plays | Sessions with any audible time, skips included, by start time (shown in data, not headlined). |
| Sessions crossing a boundary | The listening time is split at the boundary. The stream counts once, in the period where it qualified. |
| Skips | A session that never reached the threshold: a play, not a stream. |
| Repeat One | Each loop is its own session, so each qualifying loop is a stream. |
| Duplicate queue entries | Each playback is its own session; there is no deduplication beyond that. |
| Active days | Local days with at least one stream. |

## Identities

| Metric | Definition |
|---|---|
| Songs | Distinct Song IDs with a stream in the period. |
| Artists | The artist each play counts for: the lead artist after Sonus's attribution, so a contributor's songs on a project count for its owner. Featured artists never receive streams. |
| Albums | Distinct **Albums & EPs** (`album_id`) with a stream. **Singles are left out** of album counts and the top albums list, as in Pulse and the charts. |
| Multiple editions | A play belongs to one release (`album_id`) whatever edition it was played from. It is counted once and never once per edition. |
| Merged Song IDs | A merge repoints history to the surviving Song ID, so the next load counts it under the survivor. Nothing is double-counted. |
| Permanent deletion | Deleting a song removes its history; the next load no longer counts it. |
| Unavailable / blocked / removed | Still counted (they were genuinely listened to). They are labelled with the Insights badges (UNAVAILABLE, BLACKLISTED, HISTORICAL); names of removed items come from the session snapshot. |
| Cloud-restored history | Counted like any recorded history; restored rows are the recorded rows. |

## Rankings

| Rule | Definition |
|---|---|
| Measure | Streams. |
| Size | Top 10. |
| Ties | The more recently heard first, then by ID (stable and deterministic). |
| Most-played song / artist | The first of the top list. |
| Most active month | The month with the most streams; the earlier month wins a tie. |

## Genres

| Rule | Definition |
|---|---|
| Source | The genre of the edition the stream was played from, else the release's primary edition. Never guessed. |
| Normalisation | Exact aliases map to their category (`GenreCatalog`: "hip hop", "hip-hop" → Hip-Hop/Rap). Other genres group by spelling, ignoring case, and keep the alphabetically first spelling. |
| Unknown | Streams from releases without a genre are counted apart ("N streams from releases without a genre") and never assigned one. |
| Share | Of the streams that have a genre. |

## Comparison

- A period is compared with the previous month or year only when history covers all of the previous period.
- Otherwise it shows "No comparison", never a comparison against a partial period.

## Milestones (derived, never stored)

| Milestone | Definition |
|---|---|
| Lifetime streams | The 100th, 250th, 500th, 1,000th … stream ever recorded in Sonus. It is told in the period it happened, with its date, and never again. |
| Longest streak | The most consecutive local days with a stream, within the period, when at least two. |
| Busiest day | The local day with the most streams; the earlier day wins a tie. |

## Chart highlights

- Stored, finalized weekly Sonus Hot 100 #1s.
- A chart week belongs to the period that holds its **last moment** (its end).
- Weeks before charts began are absent; nothing is replayed.

## Caching and invalidation

- Summaries live only in memory while Wrapped is open.
- A recorded play, an import, or any library edit (including merges and deletions) drops them, and the next view rebuilds them from history.
- Nothing is persisted, so a summary can never contradict its history.

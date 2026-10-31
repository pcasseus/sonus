# Sonus Pulse 2.0: Data Feasibility

Read-only audit of `sn-50-final-refinement` at `8c92c7f` (2026-10-31). Paths are under `lib/`. Nothing was changed. Classes:

- **A** Already supported with reliable data (a service computes it today).
- **B** Derivable from existing records without a schema change.
- **C** Needs new recording, persistence or a migration.
- **D** Not reliably available: omit or show as unavailable.

## 1. What is recorded

| Fact | Source |
|---|---|
| One `playback_sessions` row per play attempt of one song, including plays under 30 s. Columns: ids for song, artist, release (`album_id`) and the song's own edition; saved names (`song_title`, `artist_name`, `album_title`, `album_edition_title`); `started_at`, `ended_at`; `listened_duration_ms`, `track_duration_ms`, `final_position_ms`; `end_reason`; `source_context`. | `core/database/schema/analytics_schema.dart:15-56` |
| `playback_listening_segments`: one row per stretch of audible playback, with start, end and duration. | `analytics_schema.dart:64-82` |
| `qualified_plays`: at most one per session (`playback_session_id UNIQUE`) with `qualified_at`. This is the "stream". | `analytics_schema.dart:87-110` |
| Times are UTC ISO strings; **no time-zone offset is stored**. | `analytics/data/mappers/playback_session_row_mapper.dart:48-49` |
| Listened time is wall-clock audible time; pause closes a segment; checkpoints every 5 s; seeking doesn't add time; no cap at track length. | `listening_session_tracker.dart:231-266, 359-382`; `playback_analytics_controller.dart:22, 281-289` |
| End reasons: completed, skipped, stopped, replaced, interrupted, failed. Repeat One starts a new session each loop. | `playback_analytics_controller.dart:164-171, 205-230, 296-300, 347-357, 404-408` |
| `source_context` is never written (always null); no device id. | `playback_analytics_controller.dart:245-262` |
| Qualification: 30 s; shorter tracks need max(5 s, half the track), never more than the track; unknown length = 30 s. Stored as a `qualified_plays` row when reached. | `listening_qualification_policy.dart:6-42`; `listening_session_tracker.dart:441-480` |
| History syncs between devices (sessions, segments, qualified plays), so other devices' plays are included. | `sync/data/services/sqlite_cloud_archive_store.dart:108-139, 215-239` |
| Indexes on session `started_at`, segment `started_at`/`ended_at`, `qualified_at`, and each entity id with its time. | `analytics_schema.dart:113-182` |

**Pitfall:** `qualified_plays.listened_duration_ms` is a snapshot at the moment of qualifying (≈30 s) and is never updated, yet `AnalyticsSummaryService` adds those snapshots up as `qualifiedListeningDuration` (`analytics_summary_service.dart:69, 86`). Pulse must take minutes from listening segments only.

## 2. Metric classification

### Listening totals

| Metric | Class | Basis / caveat |
|---|---|---|
| Minutes listened (all audible playback, any length) | **A** | `AnalyticsListeningDurationService` (segments clipped to the window), `analytics_listening_duration_service.dart:21-48` |
| Qualified streams | **A** | `AnalyticsSummaryService.qualifiedStreamCount` |
| All recorded plays (every session start) | **B** | Count `playback_sessions` in the window. Recommend counting only sessions with audible time > 0, so failed loads are not "plays". No service today. |
| Distinct tracks, artists, releases | **A** | `AnalyticsSummaryService` (:89-91), from qualified plays |
| Active days, average per active day, peak day | **A** | `AnalyticsBehaviorMetricsService` (:27-191) |
| Skips and completion rate | **A** | `AnalyticsBehaviorMetricsService` (:65-123) by end reason |
| Longest streak | **A** (year) / **B** (month) | `year_in_sonus_service.dart:277-317` |
| Current streak | **B** | Same day logic, ending today |
| New artists / new releases discovered (first-ever play) | **A** (year) / **B** (month) | `year_in_sonus_service.dart:239-275` |
| New songs discovered | **B** | Same logic over `song_id` |
| Genre share | **B, weak** | Only from current library genres; removed songs have no genre. Leave out of the MVP. |

### Pulse buckets

| Metric | Class | Basis / caveat |
|---|---|---|
| Per-day minutes and streams, monthly | **A** | `MonthlyListeningDistributionService` (`monthly_insights/monthly_listening_distribution_service.dart:14-190`), segments split at local hour boundaries |
| Per-hour (0–23) minutes and streams, monthly | **A** | same service |
| Per-day buckets for a whole year | **B** | Same algorithm over a year window; no service yet |
| Per-month totals for a year | **A** | `YearInSonusService` 12-month series |
| Day boundaries in the time zone **at play time** | **C** | Needs a stored UTC offset per session (migration). Today every bucket uses the device's *current* zone via `.toLocal()`; plays made while travelling can land on a neighbouring day. Show an info note; accept for MVP. |
| Audio waveform, loudness, BPM or energy | **D** | Never recorded. Pulse must not imitate one. |

### Comparisons

| Metric | Class | Basis / caveat |
|---|---|---|
| Month vs previous month (totals, rank change, stream change) | **A** | `monthly_listening_insights_service.dart:50-70, 114-122`; `monthly_ranking_comparison_service.dart:7-42` |
| Year vs previous year | **B** | Run the year services twice |
| Same month last year | **B** | Run the month services for that month |
| Comparison eligibility | **B** | First recorded session (`firstSessionStartedAt`, behaviour metrics) must be on or before the comparison period's start. Otherwise "partial history" (§4). |
| Percent change when the earlier value is 0 | **D** | Show "new", never a percentage |

### Rankings

| Metric | Class | Basis / caveat |
|---|---|---|
| Top tracks / artists / releases by streams | **A** | `AnalyticsEntityRankingService` (:25-65), ties to most recent |
| Top tracks / artists / releases by minutes | **A** (month) / **B** (year) | `MonthlyEntityListeningDurationService`; `AnalyticsArtistListeningDurationService` |
| Top by all recorded plays | **B** | Group sessions by entity |
| Top 25 tracks; Top 10 artists and releases | **A** (year) | `YearInSonusService`; month gives top 25 / 15 |
| Release ranking without double-counting editions | **A** | Rank by `album_id`; one `song_id` per song across editions (`analytics_entity_ranking_service.dart:62`; `library_schema.dart:153-169`) |
| Release display: Deluxe-first title, cover and edition | **A** | Display only (`charts/presentation/models/chart_album_presentation.dart:17-50`) |
| "Albums & EPs" without Singles | **B** | Charts exclude Singles (`library_release_chart_eligibility.dart:15-17`); Insights rankings currently don't. Needs a decision (§5). |
| Per-item trend line (streams per day or month) | **B** | Filter qualified plays by entity id; indexes exist |
| Rank last period, lifetime streams | **A** (month) / **B** (year) | `monthly_ranking_comparison_service.dart` |

### Attribution and content policy

| Metric | Class | Basis / caveat |
|---|---|---|
| Plays credited to the song's lead artist | **A** | `songs.artist_id` copied at play time (`playback_analytics_controller.dart:249`; `listening_artist_attribution.dart:1-7`) |
| Contributors hidden from the library counted for the release owner | **A** | `library_organization_service.dart:165-171, 603-628` |
| Featured, co-primary or guest artists receiving plays | **B, with a gap** | Credits are in `song_artist_credits` (roles at `library_schema.dart:209-210`), but no analytics reads them. Derivable from **current** credits only: songs removed from the library lose them, and later credit edits rewrite the past. |
| Featured credit as it was at play time | **C** | Would need credits recorded per session |
| Removed songs and releases | **A** | History is never deleted; names come from the last session (`charts/.../play_time_identity.dart:10-105`; monthly enrichment `:174-235`). Monthly tags HISTORICAL / UNAVAILABLE. |
| Blocked songs | **A (labelled, counted)** | Insights count blocked songs and label them (`monthly_listening_insights_page.dart:915-921`). Charts exclude them. Pulse keeps the Insights policy unless you decide otherwise (§5). |
| Trash / soft delete | **D** | Not implemented (destructive workflows are design only) |
| Artist merges | **A** | Rewrite `artist_id` in history (`sqlite_artist_identity_repair_repository.dart:18-33`), so rankings follow the merged artist |
| Backup restore | n/a | Replaces all history (`sqlite_restore_executor.dart:59-66, 108-111`); Pulse simply reads what is there |
| Listening source, device or context | **D** | `source_context` always null; no device id |

### Artwork and appearance

| Capability | Class | Basis |
|---|---|---|
| Track art (song art, then primary, then edition cover) | **A** | `library_query_dao.dart:82-94` |
| Release cover (Deluxe-first display) | **A** | chart album presentation |
| Artist image (`top_artists_artwork_id`, then `header_artwork_id`) | **A** | `library_schema.dart:25-26`; `monthly_artist_insight_row.dart:22-35` |
| Artwork-derived accent with contrast guarantees | **A** | `SonusArtworkPalette` (`core/design/sonus_artwork_palette.dart:41-151`, `ColorScheme.fromImageProvider`, rejects greyscale) and `SonusArtworkAtmosphere.resolve` (:248-324, 4.5:1 text / 3:1 accent, no tint when gradients are off) |
| Reduced motion, high contrast, low effects, decoration level, nine themes | **A** | `SonusTheme.of` forces reduced motion with the system flag (`sonus_theme.dart:34-52`); `appearance_preferences.dart:103-123, 289-300`; `sonus_theme_factory.dart:252-283` |
| Remember last Insights period | **B** | No key today; follow the `appearance.preferences` SharedPreferences pattern (`settings/data/appearance_preferences_store.dart:33-98`). Device-local, no schema. |

## 3. Performance

- All aggregation happens in Dart over rows from `findAll` (`playback_session_dao.dart:65-88`, `qualified_play_dao.dart:80-103`). There is no SQL `GROUP BY`.
- Segment queries load every segment that started before the window end, with **no lower bound** (e.g. `analytics_listening_duration_service.dart:30-32`). A year view over several years of history reads everything each time. It is harmless for months today, but year bucketing and Top 25 by minutes would multiply it.
- Fix without a schema change (B): add a lower bound (`ended_at >= windowStart`; the `ended_at` index exists) and, for year buckets, a grouped SQL query. Cache each finished period's result in memory for the session; only the current period changes.
- No `user_id` index and no user filter in analytics queries. That is intended (signed-out plays are attached later, `analytics_account_attachment_service.dart:24-74`), but means Pulse shows everything on the device.

## 4. Rules Pulse must follow (no fabrication)

1. Minutes come from segments; streams from `qualified_plays`; "all plays" from sessions with audible time. Never mix them in one number.
2. A day before the first recorded session is "no history", not zero.
3. A comparison is shown only when the comparison period starts on or after the first recorded session. Otherwise show "Not enough history". If the current period itself starts before the first session, mark it "History starts 12 Oct 2025". Use that real date.
4. No percentage from a zero base; show "New".
5. Day buckets use the device's current time zone, and the page says so in its info sheet.
6. Featured artists get no plays in rankings unless you approve the current-credits derivation (§5).
7. Nothing animates as if it were data: spokes move only between two real states.

## 5. Decisions (resolved 2026-10-31)

1. **Pulse toggle:** Minutes / Streams. All plays (sessions with audible time) is a separate metric in tiles and ranking menus.
2. **Releases ranking:** Albums & EPs only; Singles excluded, as on the charts.
3. **Blocked songs:** counted in Insights and visibly labelled; chart exclusion unchanged.
4. **Attribution:** lead artist only for the MVP (featured credits stay a later, class B/C option).
5. **Time zone:** device-current-time-zone day buckets with an informational note; no migration now.
6. **Old layouts:** Monthly/Year layouts retire when Pulse replaces them; their useful metrics move into expanded stats and detail panels.

One metric added by the colour revision: the selected item's per-day contribution on the Pulse ring, in the selected Pulse metric. Class **B**:
- **Minutes:** sum of listening segments, clipped to the day, whose session has the item's `song_id`, lead `artist_id` or `album_id`.
- **Streams:** count of qualified plays on that day with the item's id.
- Computed from the same rows and day boundaries as the day's total, so it is a subset by construction and can never exceed it; a test asserts item ≤ total for every day. Lead-artist attribution, `album_id` release identity across editions and the blocked-songs rule are the same as for the totals. Entity-time indexes exist.

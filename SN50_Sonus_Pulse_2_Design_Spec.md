# Sonus Pulse 2.0: Design Specification

Status: design only, not approved for implementation. **Revision 2 (2026-10-31):** your six decisions applied; colour system rewritten to be vivid and derived from the active Sonus theme (§7). **Final (2026-10-31):** colour and theme decisions approved: Monochrome stays greyscale (§7.2), no Pulse light theme (§7.1), per-item highlight follows the selected metric and never exceeds the day (§3.1). Data claims are classified in `SN50_Sonus_Pulse_Data_Feasibility.md` (A–D); scope and batches in `SN50_Sonus_Pulse_Implementation_Scope.md`.

**Interactive prototype (fictional sample data, private to you):** https://claude.ai/artifact/UVZLwfaaqa1f9Qb15M8VBf. It runs the screen below in a 360 dp frame in any of the nine Sonus themes (real token values; the theme buttons stand in for Settings → Appearance and are not a Pulse control): Month/Year, previous/next, Minutes/Streams, comparisons, tap/drag readout, rankings with metric menus and value bars, Top 5/10/25, inline detail with artwork colour on the card, hero halo and ring, Reset colours, and reduce-motion / low-effects / high-contrast / decoration settings. Its numbers, names and covers are invented.

## 0. Principles

- **Identity:** the navigation tab stays **Insights**; the page title is **Sonus Pulse**.
- **Emphasis:** about 70% Pulse visualization, 20% music gallery (real covers and artist images in rankings and details), 10% precise statistics (stat grid, tables, comparisons).
- **Data first:** every mark is a real recorded quantity or an explicit "no history" / "not yet" state. No idle animation, recap sequence or intro.
- **Replaces** the Monthly / Year segmented pages (`listening_insights_page.dart`) when Pulse ships; Year in Sonus chapters fold into the Year view (§6). Useful existing metrics stay, in "More about this month" and the detail panels (decision 6).
- **Colour:** vivid and multicolour, always meaning something (§7). Pulse follows the active Sonus theme and appearance settings; it has no theme setting of its own.
- **Decided (2026-10-31):** Minutes / Streams is the Pulse toggle and All plays a separate metric; releases are Albums & EPs only; blocked songs count and are labelled (chart rules unchanged); lead-artist attribution only; device-time-zone days with an info note; old Monthly/Year layouts retire when Pulse replaces them.

## 1. Screen structure (360 × 800 dp reference)

| Order | Block | Height at 1× text |
|---|---|---|
| 1 | Header: "Sonus Pulse", Month / Year selector | 48 |
| 2 | Period bar: ‹ October 2026 › | 52 |
| 3 | **Pulse hero** (ring + centre total), legend row with Minutes / Streams | 252 + 36 (≈ one third of the first screen) |
| 4 | Readout line (selected day or hint) | 40 |
| 5 | Comparison chips | 40 |
| 6 | Overview stat grid (2 rows × 3) | 128 |
| 7 | Top artists (Top 5) | ≈ 330 |
| 8 | Top tracks (Top 5) | ≈ 330 |
| 9 | Top albums & EPs (Top 5) | ≈ 330 |
| 10 | Footnote: what Minutes, Streams and All plays mean | 48 |

The first screen shows blocks 1–5 and the top of the stat grid. Page gutter 20 dp (`metrics.pageGutter`), sections 16 dp apart.

## 2. Header and reporting period

- **Month / Year** as a `SonusSegmentedSelector` (existing). Week and Lifetime are not offered at launch (the `AnalyticsPeriod` model has them; later).
- **Period bar:** 44 dp previous / next buttons. Next is disabled at the current period; previous is disabled before the month or year of the first recorded session. The title is a live region ("October 2026", "2026").
- Tapping the title opens a month/year picker sheet listing only periods with recorded history, with each period's minutes as a small bar (real data, class B).
- **Remember the period (locked):** SharedPreferences key `insights.pulse.period`, JSON `{"v":1,"view":"month","year":2026,"month":10}`, plus `insights.pulse.measure` (`minutes` / `streams`). Restored on open. A stored period after today clamps to the current period; one before the first recorded play clamps to that first period. No schema change.
- Horizontal swipe on the hero changes period (same as the buttons); never on the rankings, which scroll vertically.

## 3. Pulse hero

### 3.1 Data mapping

| Element | Meaning |
|---|---|
| Spoke | One local calendar day. Month: 28–31 spokes evenly around the ring, day 1 at 12 o'clock, clockwise. Year: 365/366 hairline spokes in 12 month arcs separated by small gaps, January at 12 o'clock. |
| Spoke length | Linear from the inner ring. 0 at the ring; the period's busiest day reaches the outer radius. Spokes have constant width, so only length encodes value (no area distortion). |
| Measure | **Minutes:** audible time from listening segments clipped to the day (A month, B year). **Streams:** qualified plays by `qualified_at` (A/B). Each measure has its own colour family (§7.2); the centre label names the measure in that colour. |
| Spoke colour | Runs along the measure's ramp from its base at the inner ring to a tip colour set by the day's value: the quietest day ends low on the ramp, the busiest at its brightest end. Colour repeats what length shows and adds nothing of its own. |
| Average ring | Faint dotted circle at the period's mean per recorded day. |
| Zero day | Small dot on the inner ring. |
| Future day | Nothing drawn. |
| Before first recorded play | Short hatched stub. Never a zero. |
| Comparison ghost | Dashed spokes for the comparison period in the same colour family as the measure, at its lightest step ("you, before"), aligned by day of month (month) or day of year (year). Shown only when the comparison is eligible (§5). Same scale as the current period: the maximum covers both series, so a ghost can be longer than any current spoke. |
| Selected item | When an artist, track or release detail is open, each spoke shows that item's own part of the day from the inner ring outward in the item's artwork colour, in the **selected Pulse metric**: in Minutes, the audible segment time of that item's plays clipped to the day; in Streams, that item's qualified plays that day. The item's part is drawn to the same scale as the spoke and is always a subset of the day's total (it can equal it, never exceed it); a day with none of the item shows no overlay. Attribution follows the approved rules: an artist's part counts plays credited to the lead artist; a release's part counts plays whose `album_id` is that release, across its editions; blocked songs count, as in the totals. The rest of the spoke dims to 62%. The readout adds the item's value for a tapped day. |
| Halo | A soft radial glow behind the ring in the measure's mid colour, or the selected item's artwork colour. Strength follows decoration intensity (0 / 0.10 / 0.20 / 0.32, the existing atmosphere scale); none with low effects, high contrast or Decoration Off. The halo is atmosphere only and never encodes a value. |
| Centre | Period total in the chosen measure ("1,842 minutes listened" / "512 qualified streams"), 34 sp display weight, tabular numbers. |

Scale annotation: the readout hint reads "The longest spoke is 14 Oct, 3 h 12 m", using the real busiest day. Optional later: an hour-of-day inner ring for months (per-hour data is A), off at launch to keep the hero legible.

### 3.2 Interaction

- **Tap or drag along the ring:** selects the nearest spoke. It turns full white, the others dim to 55%, and the readout shows "Tue 14 Oct 2026 · 192 min listened · 51 streams". Drag scrubs, with a light haptic tick per day that follows the system haptics setting.
- **Year view:** tapping selects the day; a second tap on the same day or the readout's "Open October" switches to that month.
- **Tap the centre or outside the ring:** clears the selection.
- **Keyboard / switch access:** the hero is one focusable element; left and right arrows move a day; Home / End jump to the first and last day; the readout announces each.
- **Screen readers:** the hero's label summarizes the period ("October 2026: 1,842 minutes across 27 recorded days; busiest day 14 October"). A "Show as list" action opens an accessible day-by-day table (date, minutes, streams).

## 4. Listening overview

Grid of six tiles (3 × 2; 2 × 3 below 340 dp or at ≥ 1.3× text):

| Tile | Source | Class |
|---|---|---|
| Minutes | segments | A |
| Streams | qualified plays | A |
| All plays | sessions with audible time | B |
| Active days | behaviour metrics | A |
| Artists | distinct lead artists streamed | A |
| Tracks | distinct songs streamed | A |

Minutes, Streams and All plays tiles carry their metric colour (value and a 3 dp top stripe); the other tiles stay neutral. Each tile shows the comparison delta ("▲ 12%", "▼ 4%", "New" from a zero base, or "Not enough history"), coloured with semantic up/down tokens and always with the arrow or word, never colour alone. An info button opens a sheet explaining the three counts, the 30-second rule, the device-time-zone caveat, and that blocked and removed songs are included and labelled.

Secondary row (collapsed "More about this month"): skip rate, completion rate, peak hour, longest streak, new artists discovered. All A or B.

## 5. Comparisons

- Chips: **vs previous month** / **vs October 2025** (same period last year) / **No comparison**. Year view: **vs 2025** / **No comparison** (previous year and same period last year are the same thing).
- **Eligible** when the comparison period starts on or after the first recorded session. Otherwise the chip is dashed and reads "vs October 2025 · partial history"; selecting it explains "Your history starts 12 Oct 2025, so October 2025 is incomplete."
- If the **current** period starts before the first recorded session, the period title gets a "History starts 12 Oct" caption.
- The selected comparison drives the hero ghost, tile deltas and ranking rank changes. It is remembered with the period.

## 6. Rankings

Three cards: **Top artists**, **Top tracks**, **Top albums & EPs** (Singles excluded, as on the charts).

- **Rows:** rank, artwork (44 dp), title, subtitle, value. Artist art uses mixed shapes in a fixed rhythm (circle, rounded square, square by rank), all real images; no image falls back to an initials tile, never another artist's picture. Track art is genuine song art, then the edition cover; release covers are Deluxe-first. Track subtitle: credit line; release subtitle: owner · Album/EP.
- **Metric menu** per card: Streams (default), Minutes, All plays. Remembered per card for the session.
- **Value bars:** each row has a soft bar behind it, its length the row's value as a share of #1, coloured along the selected metric's ramp (longer bars reach brighter steps); the value text uses the metric colour. Rank changes use the theme's chart up / down colours with ▲ ▼; NEW uses the All plays colour.
- **Size:** Top 5 by default; chips Top 10 / Top 25 expand in place (animated height); "All rankings ›" opens the dedicated view.
- **Labels:** HISTORICAL (no longer in the library), UNAVAILABLE (file missing) and BLOCKED, as Monthly does today. Ties keep the existing most-recent rule.
- **Rank change** column when a comparison is on: ▲3, ▼1, NEW, or "–".

### 6.1 Inline detail (tap a row)

Opens directly under the row (other rows push down). Contents:

- Mini stats: streams, minutes, rank (and previous rank when comparing).
- A small trend: streams per day (month) or per month (year) for this item, real data (B).
- For artists: their top 3 tracks this period. For releases: tracks streamed from it. For tracks: first played date and lifetime streams.
- Actions: **Play** (tracks; uses `PlaybackCoordinator.playInContext` with the ranked list), **Open artist** / **Open album** (existing `ArtistProfilePage` / `AlbumProfilePage` pushes), track overflow (Play next, Add to queue, Add to playlist), **Reset colours**, **Close**.
- One detail open per card; opening another row closes the first.

### 6.2 Dedicated ranking view

Full-screen route per kind: the same metric menu, Top 25 (or all, paged by 25), a search field, the comparison column and sorting by rank change. It shares the period and comparison with the Pulse page, and its period bar changes both.

### 6.3 Year view additions

The Year view keeps the same layout and adds two cards from Year in Sonus: **Months** (12 bars, tapping opens that month) and **Milestones** (most active month, longest streak, new artists, new releases). Year in Sonus's "chapters" presentation is retired.

## 7. Colour system

### 7.1 Theme-derived, not a separate theme

- Pulse reads the active `SonusTheme` (Settings → Appearance) and builds its colours from that theme's tokens: `primary`, `secondary`, `tertiary`, `surface`, `raisedSurface`, `text`, `chartUp`, `chartDown`. There is no Pulse theme picker and nothing is stored.
- All nine themes are dark today (`sonus_theme_catalog.dart`), so each yields a dark, vivid Pulse with a different character:

| Theme | Minutes family (primary → tertiary) | Streams family (secondary → tertiary) | All plays (tertiary → primary) |
|---|---|---|---|
| Concrete Spray | electric blue → sky | hot pink → sky | sky → blue |
| Kickflip | acid lime → olive | orange → olive | olive → lime |
| After Hours | cyan → teal | coral → teal | teal → cyan |
| Y2K Replay | bubblegum → ice | lavender → ice | ice → pink |
| Neon Mixtape | neon cyan → violet | magenta → violet | violet → cyan |
| Haze 2017 | lilac → peach | rose → peach | peach → lilac |
| Monochrome | charcoal → white, solid bars | charcoal → silver, striped bars | grey → white, dotted bars |
| Daylight | ivory → sand, chroma lifted toward gold | sage → sand, lifted | sand → ivory, lifted |
| Evergreen | mint → cream, lifted | sage → cream, lifted | cream → mint, lifted |

- Pulse adds no light theme and no appearance setting. Everything is computed from the active theme's tokens and contrast checks, so a future light theme (detected from the palette's `brightness`) works by inverting the lightness range and re-checking contrast against its `surface`.

### 7.2 Ramp rule

- Interpolate in OKLCH from the start token toward the end token's hue, 64 steps.
- Lightness runs 0.58 → 0.88, so every step keeps at least 3:1 against `surface` (graphics contrast) and text stays on theme text colours.
- Chroma has a floor of 0.12, which lifts muted themes (Daylight, Evergreen, Haze) into vivid colour while keeping their hues.
- **Monochrome (decided):** greyscale by default, with no permanent tint. Its expressiveness comes from tone: the ramp runs from charcoal to white (lightness 0.42 → 0.98), spokes use charcoal-to-white gradients with white tips on the busiest days, the halo and card tint are layered greys, Minutes / Streams / All plays differ by lightness band and by pattern on bars (solid, fine stripe, dotted), and the comparison is a mid-grey dash. Contrast is checked per step against its `surface` (#111111). Temporary artwork accents on selection still apply, under the same appearance and accessibility rules as other themes.
- If the start and end tokens are near-identical in hue, the family varies lightness only, so metrics stay distinct by family.

### 7.3 Meaning

| Colour | Means |
|---|---|
| Minutes family | All audible listening: the hero in Minutes, the Minutes tile, Minutes ranking bars |
| Streams family | Qualified chart streams: the hero in Streams, the Streams tile, Streams ranking bars |
| All plays family | Every play started: its tile and ranking bars (never on the ring) |
| Lightest step of the active family, dashed | The comparison period |
| `chartUp` / `chartDown` with ▲ ▼ | Better / worse than the comparison |
| Artwork colour | The selected item, while selected |

Metrics also differ by label and position everywhere, so colour is never the only cue.

### 7.4 Artwork-reactive overlay

- Opening a detail extracts the item's palette with `SonusArtworkPalette` and resolves it through `SonusArtworkAtmosphere` against the active theme, keeping 4.5:1 text and 3:1 accent contrast. Greyscale art yields no accent; the theme colours stay.
- The colour applies to the item's ranking card (tint and accent for buttons, trend line, mini stats), the hero halo, and the item's part of each spoke (§3.1).
- It is temporary. **Reset colours** returns card, halo and spokes to the theme colours while the detail stays open. Closing the detail, opening another item, changing period or view, or leaving Insights also returns them. Nothing persists, and the global theme never changes.

### 7.5 Appearance settings

| Setting | Pulse behaviour |
|---|---|
| Decoration intensity | Scales the halo and card tint (0 / 0.10 / 0.20 / 0.32). Spoke colours are data and stay at every level. |
| Decoration Off | No halo, glow or tint; ramps become five solid steps; spokes and bars keep their metric colours. |
| Low effects | Same as Decoration Off for Pulse: no gradients, glow, blur or halo; five solid steps. |
| High contrast | One solid colour per metric at high lightness; comparison dashed; selection outlined in `text`; artwork colour shown only as an outline. |
| Reduce motion | Every transition instant (§9). |

## 8. States

| State | Behaviour |
|---|---|
| Loading | Ring outline and tiles at final size with muted placeholders; no fake spokes; rankings show three skeleton rows. A period change keeps the old spokes until new data arrives, then animates (§9). |
| Empty period | Ring of zero dots; centre "0 minutes"; message "No listening recorded in March 2026"; tiles show 0; rankings hidden; period controls work. |
| No history at all | "Listen to something and your Pulse starts here." No ring. |
| Partial history | Hatched stubs before the first play; title caption; comparisons marked partial. |
| Error | "Your listening couldn't be loaded. Nothing was changed." with Try again; previously loaded period stays on screen with a small error banner. |
| Stale response | The controller's generation counter (existing pattern) discards late results. |

## 9. Motion

| Moment | Default | Reduced motion |
|---|---|---|
| Period change | Clockwise sweep: each spoke grows or shrinks from its old to its new length and colour, starting a little after the one before (about 520 ms in all, theme curve); centre number counts over 250 ms; period title cross-fades | Instant swap |
| Measure toggle | Same sweep, with a wash from one colour family to the other; the toggle pill fills with the new family | Instant |
| Item selected | A single bloom: the item's part of each spoke grows outward with a soft glow, and halo and card tint ease to the artwork colour (250 ms) | Instant, no glow |
| Day selected | The spoke brightens to `text` with a brief glow; others dim | Instant |
| Comparison toggle | Ghost fades in or out, 150 ms | Instant |
| Section reveal on first load | Cards fade and rise 8 dp, 40 ms stagger, once per page open | None |
| Top 5 → 10 → 25 | Height expands, new rows fade in, 250 ms | Instant |
| Inline detail | Opens with height and fade, 250 ms; accent eases in | Instant, no accent ease |
| Ranking route | Platform transition; row artwork shared-element motion is a later enhancement | Instant (existing `_InstantPageTransitionsBuilder`) |

Every motion follows a tap or a data change, and nothing loops. Durations come from `SonusMotion` (150 / 250 / 400 ms; zero when reduced), which already follows the system animation flag and the in-app setting.

## 10. Accessibility and responsiveness

- All nine themes, with the colour rules of §7; high contrast, low effects, Decoration Off and reduced motion as in §7.5 and §9. Metric distinctions survive with every effect disabled: separate solid colours, labels and positions.
- 320 dp and 2× text: hero shrinks to the available width (minimum 220 dp ring), centre number scales down before wrapping; stat grid 2 columns; ranking rows put the value under the title below 300 dp (existing `SonusNumericTable` rule).
- Touch targets ≥ 44 dp; all chips and menus reachable by keyboard and switch access with visible focus.
- Semantics: headers on period and section titles; rows announce rank, name, value and change; delta tiles announce direction in words; decorative motifs excluded.
- Landscape and tablets ≥ 720 dp: hero on the left (40%), overview and rankings on the right in a scroll view.
- Tests follow `monthly_insights_design_test.dart`: every theme at 320 dp and 2× text, high contrast, Decoration Off, semantics. Add a ramp test per theme: every step at least 3:1 against `surface`, and the three families distinguishable (minimum OKLCH hue or lightness gap) in every theme.

## 11. Words

"Minutes", "Streams", "All plays"; "Not enough history"; "History starts 12 Oct 2025"; "Reset colours"; "No listening recorded in {period}". All new strings go through your wording review before release.

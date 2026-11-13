# Sonus Wrapped: visual redesign roadmap (outstanding)

The App Update 1.2 Wrapped is a **functional foundation**: plain cards, lists, a bar strip and tables. The visual experience is still to be designed. It can be built without changing any statistic, because the screens only render a `WrappedSummary`, and all calculation lives in `WrappedService`, `PulseInsightsService` and `SqliteWrappedHistoryReader`.

## Contract the redesign must keep

- Read `WrappedSummary` and its parts only. No widget computes a metric, and screenshots are never a data source.
- Keep the honest states: in progress ("so far"), partial (history start), before history, future, no comparison, and streams without a genre.
- Keep the definitions in `METRICS.md`. Any new metric is added to `WrappedService` with tests, never in a widget.
- Accessibility: large text, TalkBack summaries, reduced motion, High Contrast, Low Effects and Decoration Off.

## Proposed stages (each needs design approval)

1. **Design freeze.** Mockups at 360 dp and on the S26 Ultra, at 2× text, across the nine themes and the accessibility modes. Wording review.
2. **Story player.** A chapter-by-chapter guided recap that can be paused and navigated (WCAG 2.2.2), with the list view kept as the accessible alternative.
3. **Visual system.** A palette derived from artwork (an OKLCH ramp from `SonusArtworkPalette`), and data-bearing bars and waves whose heights are real values. Decorative motion is clearly separated and static under Reduce Motion.
4. **Chapters.** Totals, top artists (possibly the Film Reel adapted with a period header), top songs, top Albums & EPs, the timeline, genres, milestones and chart highlights, comparison, and an outro.
5. **Protection.** New protected screen baselines for the approved chapters, with device performance profiling before acceptance.
6. **Optional, separately approved.** Frozen recap snapshots (a migration), sharing and export (a privacy review), and a Home entry card (a protected surface).

## Open product decisions carried from discovery

- **Entry points:** Settings › Listening & Charts is implemented. Pulse, Home or a new tab would be protected changes.
- **Year in Sonus:** keep it, fold it into Wrapped, or redirect it.
- **Blacklisted songs:** counted and labelled (the current Insights rule) or excluded.
- **Playback during Wrapped:** none today. Any audio would create real listening history and needs a decision.

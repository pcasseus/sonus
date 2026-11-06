# Film Reel: design archive (for the future Sonus Wrapped)

The artist **Film Reel** was the Library's alternative artist view. In **App
Update 1.1** it was retired from the Library: the **Artist Roster** is now
the Library's only artist browser, and the Library-view setting and the
Roster / Film Reel switch were removed. The Film Reel is meant to return
as part of **Sonus Wrapped**.

## What is kept

- **The component:** `lib/features/library/presentation/widgets/film_reel/artist_film_reel.dart`
  (`ArtistFilmReel`), unchanged apart from the removed view switch. It
  still takes artists, a statistics snapshot, a count label, an optional
  search action and a refresh action. Nothing in the app shows it at the
  moment.
- **Its statistics plumbing:** `ArtistReelStatisticsController` and
  `ArtistLibraryStatisticsService`, which the Roster uses too.
- **Shared design pieces:** `SonusPerspectivePanel`, `SonusGlassPanel`,
  `SonusArtworkBackdrop`, the cinematic colours and atmosphere builder.
- **Its tests**, which pump the component on its own:
  - `test/features/library/presentation/widgets/film_reel/artist_film_reel_test.dart`
  - `test/features/library/presentation/widgets/film_reel/film_reel_harness.dart`
  - `test/features/library/presentation/pages/library_design_test.dart`
  - the Film Reel group of `library_selection_consistency_test.dart`
- **The approved look:** `approved_goldens/`. These are the protected
  baselines that `ebe6710` recorded (Stage 1, 2026-11-05) inside the real
  shell:
  - Galaxy S26 Ultra, with and without a song
  - Monochrome
  - High contrast
  - 1.3× text
  - 360 × 780 and 412 × 915
  - `geometry.json` with the pinned positions

  All artwork in them is generated, never real. They are a reference only:
  no test compares against them any more. The test that recorded them
  (`test/visual_baselines/film_reel_baseline_test.dart`) is in the Git
  history at `ebe6710`.

## Approved behaviour to keep in mind

- The reel has no mini-player allowance: it takes the mini-player's height
  when nothing is queued. At 360 × 780 the extra height changes the layout:
  - with the mini-player: stacked, with the statistics below;
  - without it: three panels.
- On narrow screens, with large text, or when short, the panels sit flat
  under the reel instead of tilted beside the portrait.
- High contrast, Low effects and Decoration Off keep the panels flat.
- Portraits are decoded at the card size. Only the centred card and its
  neighbours are built.
- Every statistic shown belongs to the centred artist. This is the
  3Quency / Madison Beer device bug, and it is tested.

## When Sonus Wrapped brings it back

Give it a new protected screen: a `ScreenDefinition`, a baseline test and a
recording, approved on the device (see `test/visual_baselines/README.md`).
These goldens are the starting point for comparison.

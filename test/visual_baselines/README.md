# Protected visual baselines

These tests protect interfaces that were approved on the phone:

- **Artist Roster**, accepted at `a678b95`: featured portrait geometry and the two-row selection grid.
- **Film Reel**: retired from the Library in App Update 1.1. Its approved goldens are archived in `docs/design/film_reel/` for the future Sonus Wrapped; they are no longer checked.
- **Home**.
- **Navigation and mini-player**.
- **Full-screen player (Now Playing)**.

They were recorded from the accepted implementation at `a678b95`. Production code was not changed to add them.

## What protects what

| Layer | File(s) | Catches |
|---|---|---|
| **Source manifest** | `protected_manifest.json`, `protected_manifest_test.dart` | Any change to a file a protected screen **owns**. Also any change to a **shared** file that shapes it: theme pipeline, design widgets it imports, the Library page, the shell, the playback host and mini-player, the app root. The failure lists the affected screens and the exact tests to run. |
| **Golden images** | `goldens/<screen>/*.png`, `*_baseline_test.dart` | Visible changes: colour, effects, icons, text, layout. Compared with a tolerant comparator (below). |
| **Pinned geometry** | `goldens/<screen>/geometry.json` | Moves and resizes of key parts, in logical pixels at the phone's real density, ±0.5dp. A part that appears or disappears is a change too. |
| **Invariants** | in the baseline tests | Approved rules: the Roster picture, portraits and 5 × 2 grid don't change with the mini-player; the mini-player never covers the page; Now Playing hides it. |

The older behaviour tests stay as they were. Each screen's list in the manifest names them, for example `artist_roster_test.dart`.

## Scenario matrix

**Goldens:**
- the Galaxy S26 Ultra (384 × 832dp, 40dp status bar, 48dp three-button navigation), with and without a queued song (mini-player shown and hidden);
- Monochrome as the second theme;
- High contrast;
- 1.3× text;
- 360 × 780 and 412 × 915.

Navigation and Now Playing add 2× text, and Monochrome with High contrast. Home adds a scrolled view.

**Geometry:** all three sizes, with and without a song, at 1.0× and 1.3× text, at each phone's real density.

## Deterministic inputs

**Artwork is generated** (`support/generated_artwork.dart`): cool, warm and neutral covers and portraits, drawn from formulas and encoded by a small PNG writer. **Real artwork must never be added here**, because the repository is public.

**Fonts** (`support/baseline_fonts.dart`):
- Real Roboto, through the existing `test/support/device_layout.dart`, which is not edited.
- The real Material Icons font from the Flutter SDK. Without it, every icon renders as a square.

**Data and time:**
- Fixed fixture data;
- a fixed clock for Home;
- a paused song at 1:12 of 3:30, so nothing animates forever.

**Artwork colours** are extracted for real, before the first frame. That uses the same shared palette the app uses.

**Golden density:** goldens render at **1.5×**, not the phone's 2.8125×. Layout is in logical pixels, so the geometry is identical, and each image is about a quarter of the size. Geometry is checked at the real density.

## Tolerance

`support/tolerant_golden_comparator.dart` is applied to this folder only, by `flutter_test_config.dart`.
- A pixel counts as changed when a channel differs by more than **8/255**.
- A golden fails when more than **0.2%** of its pixels changed, or when the size differs.
- On failure, Flutter writes `failures/` images (`*_masterImage`, `*_testImage`, `*_isolatedDiff`, `*_maskedDiff`) beside the test. Don't commit them.

**Platform:** the goldens were recorded on Windows with the Flutter version in use on 2026-11-05. Another OS or Flutter version can differ by more than the tolerance in text anti-aliasing. If so, re-record on the reference machine; don't widen the tolerance.

## Running

The checks for one screen:

```
flutter test test/visual_baselines/roster_baseline_test.dart
```

Everything, including the manifest:

```
flutter test test/visual_baselines
```

Which protected screens are affected by the current changes:

```
dart run test/visual_baselines/tool/protected_manifest_tool.dart check
```

## When the manifest test fails

It lists:
1. **Protected files changed**, per screen: the screen's own code changed. This needs a named approval for that screen, for example `ROSTER-2`. Without one, revert the change.
2. **Shared dependencies changed**: a theme, design, shell or host file that shapes a protected screen. Run the tests it prints.
   - If they pass, the protected screens still look and measure the same. Record the new state (step 4 below) with the ticket that changed the shared file.
   - If a golden or geometry check fails, the shared change altered a protected screen. Either fix the change, or treat it as a visual change that needs approval (next section).
3. **Dependency lists changed**: a new file under an owned folder, or a protected screen now imports new design code. Review it, then record.

## Updating baselines after an approved visual change

Only after the user has approved the new look, on the device where the change is visible:

1. Implement the approved change.
2. Re-record **only the affected screen's file**, never the whole test tree:
   ```
   flutter test --update-goldens test/visual_baselines/<screen>_baseline_test.dart
   ```
   This rewrites that screen's PNGs and `geometry.json`. The legacy Moments JSON goldens use their own mechanism and are not touched by `--update-goldens`. Even so, never run `--update-goldens` on the whole suite.
3. Review every changed PNG and every changed number in `geometry.json`. Each must be explained by the approved change. Run the screen's file again without `--update-goldens`; it must pass.
4. Record the manifest with the approval named:
   ```
   dart run test/visual_baselines/tool/protected_manifest_tool.dart update --approval "ROSTER-2: <what was approved, by whom, when>"
   ```
   This stores the new hashes and appends the approval, with the files that changed, to the manifest's history.
5. Commit the code, PNGs, `geometry.json` and manifest **together**. Put the approval in the commit message, for example `Protected-change: Roster ROSTER-2`.

Adding a screen means adding a `ScreenDefinition` in `support/protected_manifest.dart`, a baseline test file, a recording, and a manifest update, all with an approval.

## Limitations

- The renders are headless Flutter renders, not the phone: no OLED, no device gamma, no Samsung font rendering, no system bars drawn. They catch regressions; final visual acceptance stays on the device.
- **Artwork decoding** of very large real covers, **performance**, **scrolling smoothness** and **animations** are not covered. Every capture is a settled frame.
- The **manifest only follows imports through design and shell code** (`lib/core/design/`, `lib/features/shell/`), plus the listed hosts and app-wide theme files. A feature-layer change that alters a protected screen's data or state without touching those files isn't flagged by the manifest; it is caught by the goldens and geometry only if it changes the fixtures' rendering.
- **Theme coverage:** two themes (Concrete & Spray, Monochrome) of nine. The theme catalog is a shared dependency, so any change to any theme is flagged for these tests, but a broken third theme only shows in its own tests.

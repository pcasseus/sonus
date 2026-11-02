# SN-50 A-0 Build History and Historical Rendering Verification

**Date:** 2026-10-30. **Checkpoint:** `f062551` on `sn-50-final-refinement` (worktree `C:\dev\sonus\sonus_next_sn50`). This pass was read-only: it ran no tests or builds, changed no code or configuration, touched no device, cloud, backup or app data, and cleared or changed no marker. This report is the only file created.

**Addendum (same date):** `SN50_A0_Addendum_Time_Trigger_and_Device_Identification.md` records the follow-up inspection, the device-identification guide, R-V as a release blocker, and a **correction**: the affected build window is wider than the commit times below. It runs from 2026-10-29 02:09 EDT (worktree creation; the gate code was in the working tree before `ba2d575` was committed) to 16:25 EDT (`8d2cbfe`). Affected builds also **record** extra career events from 2026-11-01 UTC, not only display them. A-0 is still INCONCLUSIVE.

**Overall result: A-0 remains INCONCLUSIVE.** The records available inside the approved scope cannot prove that no build ever had refined Moments active. They do narrow the question a lot, and they reveal a second, date-based activation path that the contract did not account for (§3.2).

---

## 1. Evidence inspected

| # | Evidence | Path / reference | What it shows |
|---|---|---|---|
| 1 | Activation code | `lib/features/charts/application/services/moment_rules_activation.dart:17-92` | `buildApproved = bool.fromEnvironment('SONUS_MOMENTS_REFINED_APPROVED')`. If false, `rules()` returns `ChartMomentRules.legacy` without reading the marker. If true, the first run writes the instant once and reads it back; later runs reuse it. |
| 2 | Marker store | `lib/features/charts/data/services/shared_preferences_moment_rules_activation_store.dart:12-31` | Key `charts.moments.rules_activated_utc` in SharedPreferences. Not in Sonus library backups. Lost on reinstall or cleared data unless the platform restores app data. |
| 3 | Rules | `lib/features/charts/domain/moments/chart_moment_rules.dart` | Without an instant, every story is legacy. Career and real-time stories are refined from the instant; weekly stories from chart weeks that start at or after it. |
| 4 | Where the rules act | `charts_controller.dart:1044-1067`, `all_time_moment_service.dart:130-226`, `moment_editorial_desk.dart:108-113` | The rules decide how stories are **told** (planner, catalog), and also which career events are **recorded** (`thresholdEntriesFromUtc: rules.activatedAtUtc`, `rules.appliesTo`). |
| 5 | Flag history | `git log --all -S SONUS_MOMENTS_REFINED_APPROVED` | Introduced in `8d2cbfe` (2026-10-29 16:25 −0400). Later hits are docs only (`3080338`, `426b7c2`, `ff0b8c9`, `f062551`). |
| 6 | Earlier gate | `git log --all -S refinedFromUtc`; `git show ba2d575:lib/features/charts/domain/moments/chart_moment_rules.dart:8-11` | `ba2d575` (2026-10-29 09:21) introduced `refinedFromUtc = DateTime.utc(2026, 11, 1)` with **no flag**; replaced by the flag and marker in `8d2cbfe`. |
| 7 | Marker history | `git log --all -S rules_activated_utc` | Introduced in `8d2cbfe`; otherwise docs only. |
| 8 | Branch reach | `git branch -a --contains ba2d575` / `8d2cbfe`; `git for-each-ref --contains ba2d575` | Only `refs/heads/sn-50-final-refinement`. No remote-tracking ref contains them. |
| 9 | Push history | `.git/logs/refs/remotes/origin/` (in `C:\dev\sonus\sonus_next\.git`); `git config branch.sn-50-final-refinement.remote` | No remote-tracking log for any sn-50 ref; the branch has no upstream. |
| 10 | Other checkouts | Reflogs `C:\dev\sonus\sonus_next\.git\logs\HEAD` (307 entries) and `…\worktrees\sonus_next_sn49\logs\HEAD` (18), compared with the full SHAs of all 40 commits from `ba2d575` to `HEAD` | **0** entries in either reflog point at a commit containing refined code. Only the sn50 worktree ever had them checked out. |
| 11 | Tracked build tooling, all revisions | `tool/build-release.ps1`, `tool/run-dev.ps1`, `.vscode/launch.json`, `config/sonus.dev.example.json`, `tool/sn42/*.ps1`; `git ls-files`; `git log --all -- tool/... .vscode/...` | No tracked file in any revision sets the flag. Release and dev builds use `--dart-define-from-file=config/sonus.dev.json` plus any extra `@FlutterArgs`. The example file has only the three account keys. There is no CI workflow, `.github`, Codemagic or Fastlane configuration. |
| 12 | Untracked config | `.gitignore:53-55` | `config/sonus.dev.json` and `config/sonus.prod.json` are git-ignored. **Neither exists in the sn50 worktree.** Their contents elsewhere are not recorded by Git and were not opened (they hold account settings). |
| 13 | sn50 build outputs | `build/` (only `native_assets`, `test_cache`, `unit_test_assets`); no `build/app/outputs`; no `android/app/build` or `android/build`; `.dart_tool/flutter_build/` holds only `dart_plugin_registrant.dart` (2026-10-29 02:10) | No Android or APK build record exists in this worktree. The flag name appears in `build/test_cache/…cache.dill.track.dill` only because the source references it; this says nothing about its value. |
| 14 | Repository process records | `SN50_QA_Report.md:158` ("No phone or ADB access, no emulator use…"), `SN50_Restart_Instructions.md:120`, `SN50_Progress.md:847` | The SN-50 sessions recorded no device access or installs. That covers only their own conduct. |

**Not inspected (outside the approved scope; listed so you can decide whether to approve each):**
- `config/sonus.dev.json` / `sonus.prod.json` in `C:\dev\sonus\sonus_next` or `sonus_next_sn49` (sensitive: account settings). Only the presence or absence of a `SONUS_MOMENTS_REFINED_APPROVED` key would matter; the values need not be printed.
- `build\app\outputs\` and `android\app\build\` in the other two worktrees (APK metadata, `output-metadata.json`, timestamps).
- PowerShell command history (PSReadLine `ConsoleHost_history.txt`) and earlier Claude Code session transcripts, which could show a `flutter build` / `flutter install` / `flutter run` invocation with `--dart-define`.
- Any other clone or copy of the repository outside `C:\dev\sonus\`.
- The phone itself: whether `charts.moments.rules_activated_utc` exists in Sonus's SharedPreferences, and which build is installed. Not accessed, by instruction.

---

## 2. What can be positively established

| Claim | Status | Basis |
|---|---|---|
| No tracked file in any revision sets `SONUS_MOMENTS_REFINED_APPROVED=true` (configs, scripts, launch configurations, CI) | **VERIFIED OFF** | §1 rows 5, 11 (complete Git history of tracked files; no CI exists) |
| Refined code exists only on `sn-50-final-refinement`, was never pushed, and has no upstream | **Established** (as far as local remote-tracking logs go) | Rows 8, 9 |
| No other worktree of this repository ever checked out a refined commit | **Established** (surviving reflogs; the commits are under two days old, well within reflog expiry) | Row 10 |
| No Android or APK build was produced in the sn50 worktree **with its outputs still present** | **Established** | Row 13 |
| A build compiled from `8d2cbfe` onward is refined only if compiled with the flag; with the flag off it ignores any stored marker | **Established** (code) | Row 1 |
| A build compiled from `ba2d575` to `430700d` (8 commits, 2026-10-29 09:21–15:32 −0400) needs **no flag**: it turns refined rules on by itself at **2026-11-01 00:00 UTC** (2026-10-31 20:00 EDT) | **Established** (code) | Row 6 |

## 3. What remains unknown

### 3.1 The flag path (builds from `8d2cbfe` on)

| Claim | Status | Why |
|---|---|---|
| Any build was **compiled** with the flag enabled | **INCONCLUSIVE** | It could have been set through an untracked `config/sonus.dev.json`, a command-line `--dart-define`, or a build whose outputs were later removed (`flutter clean`), none of which Git records. Inside scope there is no positive record either way. |
| Such a build was **installed, distributed or used** | **INCONCLUSIVE** | No install or distribution record is kept in the repository. Only the device (marker, installed version) could show it. |
| A refined story was **displayed** | **INCONCLUSIVE** | Stories are composed at display time, and nothing records a display. The marker, if present, would show only that a flagged build **ran**, not that the Moments feed was opened. |
| Any recorded build invocation explicitly enabled the flag | **INCONCLUSIVE** (none found in scope; untracked and out-of-scope records not read) | Rows 11–13; §1 "not inspected" |

The evidence makes a flagged build unlikely without proving its absence. It would have to be built from the sn50 worktree (the only checkout of these commits) and then cleaned, or from an untracked copy.

### 3.2 The date path (builds from `ba2d575` to `430700d`): new risk

- These 8 commits gate the refined rules on the **date alone**: `isRefined(occurredAt) = occurredAt ≥ 2026-11-01 UTC`. No flag and no marker are involved.
- A build compiled from any of them would show **no** refined story before 2026-11-01 UTC, unless the device clock is ahead. From then on it would plan and tell new stories under the round-1 refined rules and the round-1 draft copy (before the approved-family guard, `ae0fd05`).
- **Compiled / installed / displayed: INCONCLUSIVE**, for the same reasons as §3.1, except that "displayed" is bounded: impossible before 2026-11-01 00:00 UTC on a correct clock.
- **Action for you (not taken):** if any phone runs a Sonus build made on 2026-10-29 between about 09:21 and 16:25 EDT, replace it with a build from `8d2cbfe` or later **before 2026-10-31 20:00 EDT**. This needs no flag, marker or data change.

### 3.3 Distinctions the records cannot make

| Distinction | Can the available records tell? |
|---|---|
| Flag compiled into a build vs not | Only from the build itself (an untracked config or a command line), not from Git. |
| Build installed or used vs only built | No. Only the device can show it. |
| Refined story displayed vs not | No. There is no display log, and headlines aren't stored. The marker shows only "a flagged build ran, first at T". |
| Which build or catalog version displayed a refined story | No. The marker records an instant, not a build, commit or catalog version. Stored Moment events carry no catalog version. |

---

## 4. Historical rendering assessment (if A-0 stays unverified)

### 4.1 Legacy and pre-activation stories: protected regardless of A-0

`facts.refined` is false for (a) every story on any unflagged build from `8d2cbfe` on, even if a marker exists, because `rules()` returns `legacy` without reading it, and (b) every story before the marker instant on a flagged build.

The contract's frozen legacy view therefore keeps exactly what legacy rendering shows today. This holds whether or not A-0 is ever verified, and the Batch 0 golden fixtures pin it.

### 4.2 An installation that was activated (flag path)

- **What the marker can establish:** the instant a flagged build first ran on that install. It is write-once; a reinstall or cleared storage gives a later instant on the next flagged run, and a restore can bring the old one back. It cannot establish which build ran, whether the feed was opened, or when the flag was later removed.
- **On today's unflagged builds**, every story on that install, including stories after the marker, renders as legacy. Any refined story it once displayed **already** renders differently today: legacy planning tells one story per group, with the hash-chosen publisher and the legacy catalog. That is existing behaviour, not something the contract introduces. The legacy freeze keeps it stable.
- **Stored data:** a flagged build also recorded extra career events from the instant on (row 4). Unflagged builds compose those events with the legacy planner. This is also existing behaviour and is untouched by any catalog change.
- **On a future flagged build**, stories after the marker would render with that build's refined catalog. That catalog has already changed in almost every round (R3, BUG-04, chart jumps, the guard that now holds nine families). So a refined display from an earlier build has **no single stored rendering that could be reproduced**, and the records cannot tell which build displayed it.

### 4.3 An installation on a date-gated build

Before 2026-11-01 UTC, nothing refined was displayed (on a correct clock), so nothing needs preserving. After that date it would display round-1 draft copy until replaced. Replacing the build (§3.2) prevents this.

### 4.4 Would adding headlines re-render historical refined stories?

- **Legacy and pre-activation stories:** no, with the contract's two-catalog design.
- **Refined stories on a future flagged build:** yes, in principle. The variant index is `hash % fitting lines`, so a later catalog change would re-pick headlines for refined stories already shown by an earlier **flagged** build.

Because no released build has ever been intended to carry the flag, this risk only becomes real once the flag ships. It must be closed **before** the flag is enabled, not before Batch 0.

---

## 5. Smallest safe implementation adjustment

These are additions to the contract, not implemented:

1. **Keep §5 of the contract unchanged** (frozen legacy view and refined view). It protects legacy and pre-activation stories without depending on A-0.
2. **Add golden fixtures for the "marker present, flag off" case:** a stored marker with stories before and after it must render exactly like the plain legacy fixtures. This pins §4.1(a).
3. **Add a refined catalog version, required before the flag can ever be enabled:**
   - each released refined catalog gets a version number;
   - each install records, write-once, the instant it first ran each version (a new SharedPreferences key per version, beside the existing marker; nothing is overwritten or cleared);
   - a refined story renders with the newest version whose first-run instant is at or before the story's time (weekly: its week start);
   - this is the same mechanism as the activation marker, applied per catalog version, so stories already displayed by an earlier flagged build keep that build's lines.
   - **Not needed for Batch 0 or editorial Batches 1–9**, because the flag stays off. Add it as a new release blocker for #21.
4. **Accepted limitation (your decision, V-2):** refined stories displayed by any pre-release build (if one ever ran) cannot be reproduced, because no record says which build or catalog showed them. The safe treatment is to leave them as they render today (legacy on unflagged builds) and never attempt a repair.
5. **No change to the markers.** Never clear, overwrite or reset `charts.moments.rules_activated_utc`.

## 6. Recommendation for Batch 0

**Proceed with Batch 0 when authorized**, with two additions and one new blocker:
- Batch 0 as in the contract: the legacy and refined views, inert refined tables, and golden fixtures captured at `f062551` before any catalog change.
- **Add** the "marker present, flag off" goldens (§5.2) and a test that `MomentRulesActivation.rules()` returns legacy without reading the store when the flag is off.
- **Add release blocker R-V:** refined catalog versioning (§5.3) must exist before `SONUS_MOMENTS_REFINED_APPROVED` is ever enabled.
- **Keep A-0 recorded as INCONCLUSIVE.** Batch 0 does not depend on it; the refined flag does.

## 7. Decisions and evidence gaps for you

| # | Item | Needed for |
|---|---|---|
| V-1 | **Urgent, by 2026-10-31 20:00 EDT:** confirm that no phone runs a build from `ba2d575`–`430700d` (built 2026-10-29 09:21–16:25 EDT), or replace it | Avoiding round-1 refined copy from 2026-11-01 UTC |
| V-2 | Accept the limitation in §5.4 | Closing A-0 without proof |
| V-3 | Approve or decline each out-of-scope check in §1 ("Not inspected"): key-presence check in the other worktrees' `config/sonus.dev.json`; APK metadata in the other worktrees; PowerShell history; earlier session transcripts; the device marker (by you, on the phone) | Turning INCONCLUSIVE into VERIFIED OFF or VERIFIED ENABLED |
| V-4 | Approve adding release blocker R-V (§5.3) | Flag #21 |
| V-5 | Approve the Batch 0 additions (§6) | Batch 0 |

# SN-50 A-0 Addendum: Time-Triggered Activation and Device Identification

**Date:** 2026-10-30. **Checkpoint:** `f062551`. Addendum to `SN50_A0_Build_History_and_Historical_Rendering_Verification.md`. Read-only: no app code, build, install, phone, cloud, backup or app-data access, and no marker was touched. **A-0 remains INCONCLUSIVE.** The editorial contract remains unapproved.

**Phone check (2026-10-31, read-only `dumpsys` run by you):** `com.sonus.sonus_next` versionName 1.0.0, versionCode 1, firstInstallTime 2026-10-25 23:05:14, lastUpdateTime 2026-10-26 19:06:35. That predates the affected window (from 2026-10-29 02:09 EDT), so this phone's date-trigger risk is **RESOLVED** (assuming Android's package timestamps are accurate). The update time also matches the `sonus_next_sn49` release APK built 2026-10-26 19:06 (SHA-1 `8acac31e…`), which supports but does not prove that this is the installed build. No replacement, uninstall, app-data or database action is needed. **Global A-0 stays INCONCLUSIVE**; R-V stays a release blocker.

## 1. Decisions recorded (from your follow-up)

| Decision | Recorded as |
|---|---|
| R-V: versioned refined headline catalogs are required before any future activation | Release blocker (A-0 report §5.3; `SN50_Progress.md` BLOCKED #28) |
| Batch 0 additions approved: "marker present, flag off" golden fixtures, and a test that rules are legacy whenever the flag is off | To be included when Batch 0 is separately started. Batch 0 itself is **not** started. |
| Preserve all historical data: no re-rendering repair, marker reset or backfill | Policy (unchanged) |
| Narrow read-only inspection approved (build metadata, flag-key presence, shell build commands) | Done, §3 |
| Phone inspection, APK replacement, installation, backup and app-data access | **Not authorized**; not done |

## 2. The time trigger, stated precisely (corrects the A-0 report)

**What triggers.** Builds containing the date gate use `ChartMomentRules.refinedFromUtc = 2026-11-01T00:00Z` (`git show 430700d:lib/features/charts/domain/moments/chart_moment_rules.dart:8-11`). No flag and no marker are involved. From that instant, on the device's own clock, an affected build:
- **tells** Moments whose `occurredAt` is on or after it with the round-1 refined planner and draft copy (`moment_editorial_desk.dart:102`, `charts_controller.dart:614` in `430700d`). This is display only and composed at display time.
- **records** extra career Moment events: first threshold entries from that instant (`all_time_moment_service.dart:199`, `thresholdEntriesFromUtc: ChartMomentRules.refinedFromUtc`). **This writes stored data** to the device database.
- does both whenever Sonus's charts load. `ChartsScope` sits at the app root (`sonus_app.dart:115`) and calls `controller.load()` (`charts_scope.dart:213`), so any app start can run it, not only opening the Charts tab.

**Deadline:** 2026-11-01 00:00 UTC = **Saturday 2026-10-31, 8:00 PM EDT** (US daylight time ends later, on Nov 1).

**Which builds (corrected window).** The A-0 report gave 09:21–16:25 EDT, from the commit times. The gate code existed in the working tree **before** it was committed, so the window is wider:
- **Affected:** a build compiled from the `sonus_next_sn50` worktree between its creation, **2026-10-29 02:09 EDT** (reflog `1793254197` = 06:09:57Z), and the commit that removed the gate, `8d2cbfe`, at **2026-10-29 16:25 EDT**.
- After 16:25 the worktree never returned to an older commit. Its reflog has only the creation entry and commits, no checkout or reset to an earlier commit.
- No other worktree ever checked out any of the 40 commits from `ba2d575` on (A-0 report §1, row 10).

## 3. Results of the approved read-only inspection

| Check | Finding | Status |
|---|---|---|
| Flag key in `config/sonus.dev.json`, `C:\dev\sonus\sonus_next` | Present file; `SONUS_MOMENTS_REFINED_APPROVED` occurs **0** times (values not read or printed) | **VERIFIED OFF** for the file as it is now (earlier contents unknown) |
| Same, `C:\dev\sonus\sonus_next_sn49` | 0 occurrences | **VERIFIED OFF** (current file) |
| `config/sonus.prod.json` (both) | Absent | — |
| `sonus.local.json` (named in shell history), `C:\dev\sonus\sonus_next` | Keys only `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, `GOOGLE_WEB_CLIENT_ID`; flag key 0 | **VERIFIED OFF** (current file) |
| APKs on disk | `sonus_next`: `app-debug.apk` 2026-10-23 20:50 (SHA-1 `13117f71090b9e191ebf4f344b8c31261540208c`), `app-release.apk` 2026-10-24 13:28 (SHA-1 `758c77d35b004654a04170534b3e22137e6019c4`). `sonus_next_sn49`: `app-release.apk` 2026-10-26 19:06 (SHA-1 `8acac31eaeed0bfa46eb707b150d5675c5de492c`). `sonus_next_sn50`: none. | These three files were built **before** the window, so they **cannot contain** the gate (the code did not exist yet) |
| APK version metadata | All `com.sonus.sonus_next`, versionName **1.0.0**, versionCode **1** (`output-metadata.json`), the same as `pubspec.yaml` `version: 1.0.0+1` at HEAD | Version **cannot** distinguish builds |
| Newest app-build caches | `sn49` `.dart_tool/flutter_build/4c5a…` 2026-10-26 19:00; `sonus_next` 2026-10-23 21:19; `sn50` none | No recorded app build after 2026-10-26 |
| PowerShell history (`%APPDATA%\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt`, 305,794 lines) | 81 build/run commands; **0** mention `SONUS_MOMENTS`; **0** `--dart-define=` arguments; define files used: `config/sonus.dev.json` (1) and `sonus.local.json` (11); **0** release-build or install commands | No recorded command enabled the flag. **But** the history has no timestamps or working directory, and it does not record commands run by Claude Code sessions: the release APKs of Oct 24 and Oct 26 exist with no matching history line. |
| Bash history | Absent | — |

**Net:** every build artifact and command record found predates the window or shows the flag absent. Builds made from the sn50 worktree inside the window would leave no record in these places if their outputs were deleted, or if a Claude Code session ran them. Session transcripts were not inspected (not approved). **Whether an affected build exists, was installed, or is on a phone: INCONCLUSIVE.**

## 4. Device-identification guide (for you; nothing here changes data)

### 4.1 See the installed version (Settings, no data change)

1. **Settings → Apps → See all apps → Sonus.** On App info, scroll to the bottom: it shows **Version 1.0.0**.
2. Every Sonus build reports 1.0.0 (1), so **the version cannot tell an affected build from a safe one**. On its own, the result is INCONCLUSIVE.
3. On App info, **do not** tap Storage & cache → Clear, Uninstall, or Clear data.

### 4.2 Find when the installed APK was installed (read-only; optional; you run it)

On a computer with USB debugging already enabled (this reads package-manager metadata only and never opens Sonus's data):

```
adb shell "dumpsys package com.sonus.sonus_next | grep -E 'versionName|versionCode|firstInstallTime|lastUpdateTime'"
```

`lastUpdateTime` is when the **currently installed APK** was installed, in the phone's local time.

| `lastUpdateTime` | Meaning |
|---|---|
| Before 2026-10-29 02:09 EDT | **Not affected.** The gate code did not exist when this APK was installed. |
| 2026-10-29, 02:09 to about 16:30 EDT | **Possibly affected. Treat it as affected** (§4.4). |
| After 2026-10-29 16:30 EDT | **INCONCLUSIVE, less likely.** Affected only if an APK built inside the window was installed later. Check the APK file (§4.3). |

If you do not want to connect the phone yet, skip this and go to §4.4 on the precautionary path.

### 4.3 Match an APK file on the computer to a commit (read-only; installs nothing)

For an APK file you still have (for example the one you installed from):

1. **Hash match:** in PowerShell, `Get-FileHash <file.apk> -Algorithm SHA1`. If it equals one of the three SHA-1 values in §3, that APK was built on Oct 23, 24 or 26: **not affected**.
2. **Code test** (Git Bash; looks for two string literals in the compiled app):
   ```
   unzip -p <file.apk> lib/arm64-v8a/libapp.so | grep -a -c "keeping the top spot with "
   unzip -p <file.apk> lib/arm64-v8a/libapp.so | grep -a -c "charts.moments.rules_activated_utc"
   ```
   The first literal appears from `ba2d575` on; the second from `8d2cbfe` on. For a **debug** APK, read `assets/flutter_assets/kernel_blob.bin` instead of `lib/arm64-v8a/libapp.so`.

   | First | Second | Result |
   |---|---|---|
   | 0 | 0 | Built before the refined code: **not affected** |
   | ≥ 1 | 0 | **Affected window** (date gate present) |
   | ≥ 1 | ≥ 1 | Built from `8d2cbfe` on: not date-gated (flag value unknown) |
   | 0 | ≥ 1, or the file can't be read | **INCONCLUSIVE** |

3. Knowing **which** APK is on the phone needs the installed file itself (`adb shell pm path` + `adb pull`). That is phone access and is **not authorized**; ask before doing it.

### 4.4 Safest response if the installed build may be in the window

**Before Saturday 2026-10-31 8:00 PM EDT — stop it (temporary, reversible, no data change):**
1. Settings → Apps → Sonus → **Force stop**. This keeps all data. Android keeps a force-stopped app stopped until you open it yourself.
2. Then **do not open Sonus**, and do not start it indirectly (its notification, a home-screen widget, or headset or Bluetooth play buttons meant for Sonus) until a replacement is approved.
3. Optional and reversible: App info → Battery → **Restricted**, so it does not run in the background.
4. **Do not change the phone's date or clock.** That would corrupt play timestamps and charts.

**What stopping does and does not do:**
- It prevents the refined display and the extra event recording **only while the app stays stopped**.
- It is **not a fix**. Opening the affected build on or after the deadline starts both.
- If it runs after the deadline anyway, leave everything as it is: no repair, marker reset or backfill. Tell me, and the additive events will be documented.

**Replacing the APK is a separate step and is not authorized now.** Before any replacement, all of the following are needed:
- an approved `.sonusbackup` (BLOCKED #1);
- confirmation that the replacement is signed with the **same key** as the installed app. Android refuses an update with a different signature, and that must never be solved by uninstalling;
- a database compatibility check. Affected builds already contain the v41 migration (`2a10990` predates `ba2d575`), and HEAD is still v41; confirm this before installing;
- your explicit approval.

**Never, without an approved backup and compatibility check:** uninstall, clear data or cache, overwrite the installation, or reset `charts.moments.rules_activated_utc`.

## 5. Evidence gaps still open

| Gap | Would resolve |
|---|---|
| Builds run by Claude Code sessions are not in PowerShell history | Approval to read build commands in earlier session transcripts (masked as here) |
| Which APK is installed on each phone, and when | §4.2 / §4.3 by you; pulling the APK needs approval |
| Earlier contents of the define files | Not recoverable from Git (untracked) |
| Whether a refined story was ever displayed | Not recordable; stays INCONCLUSIVE |

## 6. Your next manual steps, in order

1. **Now:** decide whether any phone could have had a Sonus build installed on **2026-10-29** (from about 02:00 to 16:30 EDT). If you are sure none was, record that, and the urgent risk is closed for that device.
2. **If unsure, before Saturday 8:00 PM EDT:** **Force stop** Sonus on that phone (§4.4) and keep it closed. This changes no data.
3. **Optional, when convenient:** run the read-only `dumpsys` line (§4.2) and/or the APK-file checks (§4.3). Send me the dates and counts only.
4. **Then** decide on replacement (backup, signing and DB checks first) and on the session-transcript check (§5). Until then, keep Sonus stopped on any phone that may be affected.

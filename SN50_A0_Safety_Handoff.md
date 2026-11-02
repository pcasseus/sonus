# SN-50 A-0 Safety Handoff

**Date:** 2026-10-30. **Checkpoint:** `f062551` on `sn-50-final-refinement` (worktree `C:\dev\sonus\sonus_next_sn50`). **A-0: INCONCLUSIVE.** Refined Moments are not activated, and editorial integration has not begun.
**Details:** `SN50_A0_Build_History_and_Historical_Rendering_Verification.md` and `SN50_A0_Addendum_Time_Trigger_and_Device_Identification.md` (both preserved).

**Phone check (2026-10-31, read-only `dumpsys` run by you):** `com.sonus.sonus_next` versionName 1.0.0, versionCode 1, firstInstallTime 2026-10-25 23:05:14, lastUpdateTime 2026-10-26 19:06:35. That predates the affected window (from 2026-10-29 02:09 EDT), so this phone's date-trigger risk is **RESOLVED** (assuming Android's package timestamps are accurate). The update time also matches the `sonus_next_sn49` release APK built 2026-10-26 19:06 (SHA-1 `8acac31e…`), which supports but does not prove that this is the installed build. No replacement, uninstall, app-data or database action is needed. **Global A-0 stays INCONCLUSIVE**; R-V stays a release blocker.

## 1. Corrected affected-build window

- **Affected:** any Sonus build compiled from the `sonus_next_sn50` worktree on **2026-10-29 between 02:09 and 16:25 EDT**. This includes the uncommitted date-gate code that existed before `ba2d575` was committed at 09:21, and runs through `430700d` until `8d2cbfe` removed the gate.
- **What triggers:** the date alone, at **2026-11-01 00:00 UTC = Saturday 2026-10-31, 8:00 PM EDT**, by the phone's clock. No flag or marker is involved.
- **Effect when Sonus runs after that instant:**
  - it shows Moments using the round-1 refined rules and draft copy;
  - it **writes additional career Moment events** to the device database;
  - this runs on any app start (the charts load at the app root).
- **Not affected:** builds from `8d2cbfe` onward with the flag off (they ignore any marker), and every build made before 2026-10-29 02:09 EDT.

## 2. Safe Android identification steps (you; no data change)

1. **Settings → Apps → Sonus → App info** shows **Version 1.0.0**. Every Sonus build reports 1.0.0 (versionCode 1), so the version alone is **inconclusive**.
2. **Optional and read-only** (USB debugging; package metadata only, no app data):
   `adb shell "dumpsys package com.sonus.sonus_next | grep -E 'versionName|versionCode|firstInstallTime|lastUpdateTime'"`

   | `lastUpdateTime` | Result |
   |---|---|
   | before 2026-10-29 02:09 EDT | not affected |
   | 2026-10-29, 02:09 to about 16:30 EDT | treat as affected |
   | later | inconclusive; check the APK file (step 3) |

3. **APK file on the computer** (installs nothing):
   - compare `Get-FileHash <apk> -Algorithm SHA1` with the hashes in §3;
   - or run the two-literal test in the addendum §4.3: `keeping the top spot with ` present and `charts.moments.rules_activated_utc` absent means the affected window.
4. **If affected or unsure, before Saturday 8:00 PM EDT:**
   - **Force stop** Sonus (App info → Force stop) and keep it closed. Don't start it from its notification, a widget, or headset or Bluetooth buttons. Optional: Battery → Restricted.
   - This is reversible and changes no data. It protects only while the app stays closed.
   - **Don't** change the clock, clear data or cache, uninstall, overwrite the installation or reset `charts.moments.rules_activated_utc`.

## 3. APK evidence found and its limits

| APK | Built | SHA-1 | Status |
|---|---|---|---|
| `C:\dev\sonus\sonus_next\build\app\outputs\flutter-apk\app-debug.apk` | 2026-10-23 20:50 | `13117f71090b9e191ebf4f344b8c31261540208c` | Predates the window: not affected |
| `C:\dev\sonus\sonus_next\build\app\outputs\flutter-apk\app-release.apk` | 2026-10-24 13:28 | `758c77d35b004654a04170534b3e22137e6019c4` | Predates the window: not affected |
| `C:\dev\sonus\sonus_next_sn49\build\app\outputs\flutter-apk\app-release.apk` | 2026-10-26 19:06 | `8acac31eaeed0bfa46eb707b150d5675c5de492c` | Predates the window: not affected |
| `sonus_next_sn50` | — | — | No APK or app-build record |

**Limits:**
- These are only the APKs still on disk. A build made in the window and later cleaned, or run by a Claude Code session, would leave no record. PowerShell history doesn't capture session commands, and the session transcripts were not searched, by instruction.
- The flag key is absent from every current define file, but their earlier contents are unknown.
- The installed phone build is unknown, and so is whether any refined story was ever displayed.

## 4. Pending decision: the installed phone build (yours)

Decide whether any phone may have had a Sonus build installed on **2026-10-29, about 02:00–16:30 EDT**.
- **Sure it didn't:** record "not affected" for that phone.
- **Unsure or yes:** Force stop it before the deadline (§2.4), optionally run the read-only checks (§2.2–2.3), and send me only the dates and counts.

**Replacing the APK is not authorized.** It would need an approved `.sonusbackup`, confirmation that the replacement uses the same signing key (never resolved by uninstalling), a database check (affected builds and HEAD are both v41) and your explicit approval.

## 5. R-V requirement (mandatory release blocker, Progress BLOCKED #28)

**Versioned refined headline catalogs before `SONUS_MOMENTS_REFINED_APPROVED` is ever enabled.**
- Each released refined catalog gets a version.
- Each install records, write-once, when it first ran each version. This adds new keys beside the existing marker and never overwrites it.
- A refined story renders with the newest version whose first-run instant is at or before the story's time (weekly: its week start).
- Not needed while the flag stays off.

## 6. Next engineering step, once the phone risk is resolved

**Batch 0 of `SN50_Final_Editorial_Approval_and_Implementation_Contract.md`.** It still needs your authorization (contract checklist A-1 to A-3 and E-b; it is not started). It has no copy change and publishes nothing:
- the frozen legacy and refined catalog views, with inert (unapproved) override, exclusion and addition tables;
- golden fixtures captured at `f062551` **before** any catalog change: weekly and career stories, with and without featured performers, legacy and pre-activation;
- **the approved additions:** "marker present, flag off" fixtures, and a test that a disabled flag always returns legacy rules without reading the marker;
- targeted tests, then one full suite (`--concurrency=1`) and a local commit.

Editorial Batches 1–9 wait for the contract approvals. The flag stays disabled (BLOCKED #21, #28).

## 7. Working-tree state to preserve

- **Untracked:** `SN50_Decision_and_Release_Checklist.md`, `SN50_Round9_Editorial_and_Release_Safety_Review.md`, `SN50_Final_BUG04_Editorial_Package.md`, `SN50_Refined_Moments_Family_Approval_Package.md`, `SN50_Existing_Headline_Approval_Summary.md`, `SN50_Final_Editorial_Approval_and_Implementation_Contract.md`, both A-0 reports and this note.
- **Modified, uncommitted:** `SN50_Progress.md` (BLOCKED #28 R-V) and the seven generated registrant files (never committed).

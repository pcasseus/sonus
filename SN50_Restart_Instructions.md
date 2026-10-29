# SN-50 Restart Instructions

## Where things stand

- **Worktree:** `C:\dev\sonus\sonus_next_sn50`.
- **Branch:** `sn-50-final-refinement` (local only, never pushed).
- **Base:** `36d4d5d`, the SN-49 HEAD, which includes the unpushed SN-49 commits `3476e87..36d4d5d`.
- **HEAD:** the docs commit on top of `14b592f`. Check with `git log --oneline 36d4d5d..HEAD`.
- **Last full results:** `flutter test` reports **4,798 passed, 0 failed**; `flutter analyze` reports no issues (at `14b592f`).
- **Untouched:** `C:\dev\sonus\sonus_next_sn49` @ `36d4d5d` holds only its seven line-ending-only registrant files. `origin/main` = `5c7a838`, `origin/sn-49-release-hardening` = `97045b5`.

### Commits (oldest first)

| Commit | Content |
|---|---|
| `8956e3a` | Phase 1: finalized weeks and Moments frozen |
| `1a017eb` | 2a: edition counts, numbering, dates, defaults |
| `e4027e7` | 2b: display title, artwork context, disc rule, genre note, sync queue |
| `2a10990` | 2c: release Leaked (DB v41), edition-delete safeguards |
| `1bce919` | 3: credits, credit line, version suffix |
| `70fdf64` | 4: Artist Profile |
| `3dbaaa0` | 5a: chart presentation |
| `78750b3` | 5b: This Week, prospective engine fixes |
| `ba2d575` | 6a: Moments events |
| `9aee76d` | 6b: Moments feed |
| `081d4ab` | 7: bulk actions |
| `9547ef0` | 8: media session (Dart side) |
| `14b592f` | Release Studio layout, Import Review credits, menus |
| docs commit | the SN-50 reports |

## Resume

```powershell
cd C:\dev\sonus\sonus_next_sn50
git status --short          # expect only the 7 registrant files
git log --oneline -15
flutter pub get             # regenerates the 7 registrant files (LF churn); never commit them
flutter analyze
flutter test --reporter=compact > $env:TEMP\sn50_full.txt 2>&1; Get-Content $env:TEMP\sn50_full.txt -Tail 3
```

Gotchas:
- Format only the files you changed (`dart format <files>`). Never run `dart format lib test`.
- Never pipe `flutter test` into `grep -m1` or `head`.
- Use absolute paths for every file write, because subagent relative paths twice landed in `sonus_next_sn49`.
- Commit through a reviewed allowlist script: branch guard, staged set equals the allowlist, `git diff --cached --check`, secret scan, no attribution trailers, the user's git identity.

## Reports in this worktree

- `SN50_Progress.md`: phase-by-phase detail, the `BLOCKED_NEEDS_APPROVAL` list and open questions.
- `SN50_Decision_Traceability.md`: all 177 A–F IDs with status, commit and test evidence.
- `SN50_QA_Report.md`: analyzer and test counts, migration tests, accessibility and performance, incidents.
- `SN50_Editorial_Change_Proposal.md`: P-001 to P-050 rewrites and N-1 to N-7 new-family drafts, all awaiting approval.
- `SN50_Destructive_Workflows_Design.md`: Trash, Delete from Phone, ringtones and media session, with the approval checklist in §6.

## Next safe local work (no approval needed)

Each item is small; check the Traceability "Partial" rows first.
1. **A-Q13:** test the neutral placeholder when the primary edition has no artwork (song-row fallback).
2. **A-Q26:** apply the last-membership preservation check to Choose songs removals, not just edition delete.
3. **B-Q30 / F-Q7:** add explicit tests (contributor project playback; major versus supporting stream milestones).
4. **D-Q18:** the subtle album atmosphere on the Queue screen.
5. **A-Q7D:** a previewed, per-release numbering repair. User-initiated only, one release at a time, never in bulk.

## Blocked until the user approves

See `SN50_Progress.md` → `BLOCKED_NEEDS_APPROVAL` for the full list. In short:
- **Never unattended:** push, merge, PR, phone or ADB install, Supabase or cloud, sign-in, real-database migration, Trash purge, physical file deletion, ringtone setting.
- **DB v41 on a real phone:** take a `.sonusbackup` before installing any build that contains `2a10990`.
- **Product choices:**
  - the Moments gate date (2026-11-01);
  - major-zone story noise;
  - repair of old Moments;
  - E-Q19 handling of songs missing from the library;
  - A-Q12 artwork precedence;
  - credit auto-linking;
  - the chart wording labels;
  - See All visibility;
  - Play after the end of the queue (M-1);
  - confirming the Dart-side media changes M-2/M-3, which were implemented under D-Q3/D-Q6 although the design doc listed them for approval.
- **Editorial:** approve or reject P-001 to P-050, the 27 new lines, and expansion to 6+6 lines per family.
- **Destructive and device:** items A-T0 to A-T6, P-1 to P-5, R-1 to R-3 and M-1 to M-6 in the design doc §6; plugin patches 2 and 3; device QA on the S26, Android ≤12 and the Android Auto test head unit.
- **Separate tracks, not started:** G Insights, H Visual Polish, I Account & Cloud.

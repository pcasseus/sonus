# SN-43 — Settings Completion Audit

- **Branch:** `sn-43-settings-completion`
- **Baseline:** `31c47e9` (main after PR #45, SN-48 appearance foundation)
- **Baseline test run:** 3,118 passed, 0 failed (one `flutter test` runner).
- **Sources:**
  - the live working tree (authoritative);
  - `SONUS_SN43_PROJECT_AUDIT.txt` (an inventory snapshot of the same tree);
  - `SONUS_SOURCE_AUDIT.zip` (a source snapshot, not extracted).

## Classification key

| # | Meaning |
|---|---------|
| 1 | Already implemented and accessible from Settings |
| 2 | Implemented, but not accessible from Settings |
| 3 | Partially implemented |
| 4 | Missing and appropriate for SN-43 |
| 5 | Deferred to another ticket |

## 1. Starting point

`SettingsPage` (`lib/features/settings/presentation/pages/settings_page.dart`) is one long `ListView` of cards in a fixed order: Account, Appearance, Sync, Listening, Metadata Intelligence, Library (blacklisted songs only), and Backup & Restore. It has grown with each ticket.

- **Account and sync details** are rendered in full on the landing page.
- **Many implemented features cannot be reached from Settings at all.** These include imports, the import review queue, monthly insights, Year in Sonus, charts, and the accessibility controls (which are buried at the bottom of Appearance).
- **No About page and no licenses page** exist.

The whole provider tree sits above `MaterialApp` (`lib/app/sonus_app.dart`): Appearance → Restart → LibraryQuery → Playlists → Playback → Account → Sync → bridges and analytics → Monthly insights → Year in Sonus → Home → Charts → Import → Recovery. Any page pushed from Settings can therefore read every existing controller; no new scope wiring is needed for navigation.

## 2. Candidate features

### Account & Cloud

| Feature | Class | Existing implementation | SN-43 action |
|---|---|---|---|
| Google sign-in/out, identity, errors | 1 | `AccountController` (`signInWithGoogle`, `signOut`, `user`, `isLoading`, `hasError`); `_AccountCard` | Move unchanged into an **Account & Cloud** detail page. All keys are kept. |
| Sync status, last sync, pending changes, Sync now | 1 | `SyncController` (`status`, `lastSuccessfulSync`, `pendingChanges`, `isSyncing`), `AutomaticSyncCoordinator.trigger` | Move unchanged. |
| Account-conflict warning, recovery sync hold | 1 | `hasAccountConflict`, `isRecoveryHeld`; text in `_SyncCard` | Move unchanged. The landing summary also surfaces both states. |
| Mobile-data consent (allow / Wi-Fi only) | 1 | `AutomaticSyncCoordinator.mobileConsentRequired`, `allowMobileDataAndSync`, `denyMobileData` | Move unchanged. While access is `mobileDenied`, also show "Allow mobile data" (the existing `allowMobileDataAndSync`). |
| Revoke a previous mobile-data permission | 3 → **5** | `SyncNetworkPolicyService.resetMobileDataChoice` exists, but SyncScope does not expose it and the coordinator cannot report the stored choice | Deferred. Showing it would need sync wiring changes, which the standing safety rules reserve for approval (sync owner, SN-47 follow-up). |
| What Sonus syncs | 3 | Five static chips, which are incomplete. Nothing says what is not synced. | Derive the explanation from `SyncDataContract`. State what stays on the device and what is never synced (playlists, listening history, charts, lyrics, appearance). |
| Sign-out keeps local data; account binding | 2 | `SupabaseAccountRepository.signOut` keeps everything local. The binding row persists, so a different account produces `accountConflict`. | Explain this on the Account & Cloud page. No behaviour change. |

**Persistence:** none new. **Backup and sync implications:** none; this is presentation only.
**Risk:** moving widgets could break the existing keys. Every key is preserved, and the tests now navigate to the detail page.

### Appearance & Accessibility (SN-48)

| Feature | Class | SN-43 action |
|---|---|---|
| Nine themes, typography, decoration, schedule, previews | 1 | Reuse `AppearanceSettingsPage` unchanged. The landing tile keeps `settings-appearance` and its summary. |
| High contrast, reduced motion, low effects | 2 (hidden at the bottom of Appearance) | Add an **Accessibility** destination. The existing private `_AccessibilitySection` becomes a shared `AppearanceAccessibilityControls` widget, used by both pages, over the same `AppearanceController`. There is no second preference system. |
| System text scaling, reduced motion, high contrast | 1 | Already honoured by `AppearanceScope` and `SonusTheme`. Explain on the Accessibility page. |

**Persistence:** existing `AppearancePreferencesStore`. **Backup and sync:** appearance preferences are device-local and not in backups (a known item; see §4).

### Playback & Audio

Facts from `lib/features/player`:

- The engine is `JustAudioPlaybackEngine`.
- Shuffle, repeat and the queue are held in memory only, and nothing is restored after a restart.
- `just_audio`'s default `handleInterruptions: true` provides two behaviours, neither configurable: playback pauses when headphones are unplugged, and pauses or resumes around phone calls.
- There is no media session, notification, background service or Android Auto code.

| Feature | Class | Decision |
|---|---|---|
| Remember shuffle and repeat between launches | 4 | **Implement.** A typed `PlaybackPreferences` model, a `PlaybackPreferencesStore` (SharedPreferencesAsync, key `playback.preferences`, versioned JSON), and a `PlaybackPreferencesController` owned by `PlaybackScope`. Off by default, so current behaviour is kept. Saved modes are applied only while the queue is empty, so a reshuffle can never reorder music already playing. Changes are recorded from `PlaybackCoordinator.states`. |
| Library shuffle buttons out of sync with the player | 3 (existing defect) | The library, album and artist controllers each start their own `_isShuffleEnabled` copy at `false`. Initialise each from `PlaybackCoordinator.currentState.shuffleEnabled` so they show the real mode. This is required for the preference above. |
| Built-in behaviour (headphones, calls, unavailable songs) | 2 | Show as accurate, read-only information. These are not toggles. |
| Resume the last queue at launch | 5 | Needs queue snapshots, playability re-checks, a non-zero start position, and analytics review. Belongs to engine/session work (**SN-44**). |
| Configurable interruption and headphone handling | 5 | Needs `handleInterruptions: false` plus custom audio-session handling. Overlaps media-session work (**SN-44**). |
| Equalizer, crossfade, ReplayGain, normalization, gapless toggle, speed | 5 | Not supported by the engine. Deliberately absent; no fake controls. |
| Media session, notification, Android Auto | 5 | **SN-44** and **SN-45**. Not touched. |

**Backup and sync:** the playback preference is device-local, in neither backups nor sync (consistent with appearance).
**Risks:**
- An asynchronous load could race the first tap. Mitigated by the empty-queue rule.
- `setShuffleEnabled` reshuffles every time it is called. Avoided by applying the mode only to an empty queue.
- `PlaybackScope` is rebuilt after a restore, and its preference controller reloads with it.

### Library & Imports

| Feature | Class | Existing implementation | SN-43 action |
|---|---|---|---|
| Import music and manage sources | 2 | `ImportsPage` (only the header "+" button); sources persist in SQLite; per-source "Scan for changes" | Link from a **Library & Imports** page. Settings adds no new rescan trigger: rescanning changes availability without review, so it stays on the Imports page with its existing context. |
| Import review queue | 2 | `ImportReviewPage`, `ImportReviewService.countUnresolved()` | Link with a live pending count. The push copies `ImportsPage._openReviewPage`. |
| Library summary (songs, albums, artists, sources, unavailable, blacklisted, pending review) | 4 | No count APIs. Counts come from existing repository lists. | **Implement** a read-only `LibraryOverviewService` over `LibraryQueryRepository`, `ImportWorkflowService` and `ImportReviewService`. Nothing is written. |
| Unavailable songs | 3 | `LibraryTrack.isAvailable` exists, but there is no list or relink UI | **Implement** a read-only `UnavailableSongsPage` listing them, explaining how availability is restored (rescan the source in Import music, or relink from Backup & Restore). No relink logic. |
| Blacklisted songs | 1 | `BlacklistedSongsPage` | Move into Library & Imports. The key `settings-blacklisted-songs` is kept. |
| Artist blacklist (SN-19) | — | Retired: migration 15 cleared it and nothing reads it | Not exposed. |
| Remove an import source | 5 | No repository API | Deferred. Removing bindings is reconciliation work (**SN-46**). |
| Advanced relink and reconciliation UI | 5 | Automatic only (imports and restore relink) | **SN-46**. |
| Per-entity metadata studios | 1 (in context) | Artist, Album and Track studios need an entity | Stay on their profile pages; they make no sense without context. |

**Backup and sync:** read-only. **Risk:** list-based counts load every track once per visit. That is acceptable for a settings page, and it runs only when the page opens.

### Metadata Intelligence

| Feature | Class | SN-43 action |
|---|---|---|
| MusicBrainz lookup and Cover Art Archive switches; authority and safety explanations | 1 | Reuse `MetadataIntelligenceSettingsPage` unchanged. The landing tile shows the live On/Off state. The key `settings-metadata-intelligence` is kept. |
| Automatic metadata application | — | Not added. Manual and confirmed authority and the review policies are unchanged. |

### Listening & Charts

| Feature | Class | SN-43 action |
|---|---|---|
| Listening history | 1 | Move into a **Listening & Charts** page. The key `settings-listening-history` is kept. |
| Monthly Listening Insights, Year in Sonus | 2 (shell tab only) | Link directly (`MonthlyListeningInsightsPage`, `YearInSonusPage`). Both controllers sit above `MaterialApp`. |
| Hot 100 / Hot 200 and chart moments | 2 (shell tab only) | Link to `ChartsPage` in its own route. |
| Qualified-stream rule | 2 (constant) | Explain the fixed rule from `ListeningQualificationPolicy` (30 s, or half of a short track with a 5 s minimum). It is not editable, so the SN-28 authority model is preserved. |
| Stream editing, history backfill, recalculation | — | Not offered (forbidden). |

**Backup and sync:** history and charts are in backups and not synced. Stated on the page.

### Backup, Recovery & Data

| Feature | Class | SN-43 action |
|---|---|---|
| Backup, restore, private backups, audio relink, sync-hold review | 1 | `BackupRestorePage` unchanged. The landing tile keeps `settings-backup-restore`, its subtitle key and the hold flag. |
| What a backup contains, what stays on the device, what reaches the cloud | 3 (scattered across cards) | **Implement** a **Your data & privacy** page derived from `BackupCoverageContract` and `SyncDataContract`, with tests that fail if a new table is added unclassified. It covers device-specific audio paths, managed artwork, uninstall loss of private backups, and the recovery limitations. |
| Storage usage | 5 | No reliable per-category size API (`availableBytes` reports free space only). Not shown. |
| Cache clearing, delete-all, one-click destructive actions | — | Not added. No cache is clearly separable from user-owned data. |

### About Sonus & Diagnostics

| Feature | Class | SN-43 action |
|---|---|---|
| Sonus name and Waveform S mark | 4 | **Implement** an About page using `SonusBrandMark(concept: selected)`. |
| App version and build | 4 | No version API (no `package_info_plus`). **Implement** a dependency-free `com.sonus.sonus_next/app_info` channel (`AppInfoChannel.kt`, registered in `MainActivity`) that returns `versionName` and `versionCode`. Where the channel is unavailable (tests, other platforms), "Unavailable" is shown. |
| Open-source licenses | 4 | Flutter's built-in `showLicensePage` (no dependency). |
| Database schema version | 4 | `AppDatabase.databaseVersion` (33). |
| Privacy and storage explanation | 4 | Links to Your data & privacy. |
| Troubleshooting | 4 | Short, accurate guidance (sync paused, unavailable songs, review queue) that links to the real destinations. |
| Diagnostic export | 5 | Not needed for SN-43. It needs a sanitisation design (no user IDs or paths). |

## 3. Final information architecture

The landing page (`SettingsPage`) becomes a scannable list of compact navigation tiles, each with a live one-line summary, grouped into sections:

1. **Account** — *Account & Cloud* (identity, sync state, conflict or hold)
2. **Experience** — *Appearance* (theme · typography), *Accessibility*, *Playback*
3. **Library** — *Library & Imports* (pending review), *Metadata Intelligence* (on/off)
4. **Listening** — *Listening & Charts*
5. **Data** — *Backup & Restore* (hold-aware), *Your data & privacy*
6. **About** — *About Sonus* (version)

The detail pages are separate files in `lib/features/settings/presentation/pages/`, with shared tiles and sections in `presentation/widgets/settings/`. Everything uses Sonus theme tokens, so it works under all nine themes, high contrast and large text.

## 4. Known release items (unchanged by SN-43, kept visible)

- Cloud-linked restore reconciliation: no design yet (release blocker; recovery/sync owner).
- The backup exporter embeds absolute artwork source paths (privacy; recovery owner).
- Appearance and playback preferences are not in backups or cloud sync (needs a backup-format decision; SN-48 / recovery).
- The intermittent `supabase_cloud_artwork_download_test` (it passed in the SN-43 baseline run; sync owner; not modified).
- The native launcher icon and the "Sonus" app display name (**SN-48L**).
- Hosted Supabase deployment and permissions, and receipt-route activation (sync/infrastructure owner).

## 5. Deferred work and owners

| Item | Owner |
|---|---|
| Resume the last queue; configurable interruption/headphone handling; media session/notification | SN-44 |
| Android Auto | SN-45 |
| Remove import source; relink and reconciliation UI | SN-46 |
| Revoking mobile-data permission from Settings | Sync owner (SN-47 follow-up). Needs approval for SyncScope wiring. |
| Appearance and playback preferences in backups and sync | SN-48 / recovery (format decision) |
| Diagnostic export | Future support ticket (SN-49 or later) |
| Storage usage breakdown | Future (needs a reliable sizing API) |

## 6. Tests required

- **Landing page:** sections, summaries, navigation to every destination, unavailable dependencies, all nine themes, 320 dp at 2× text.
- **Account & Cloud:** the existing account and sync suites, moved to the detail page with unchanged assertions; the hold, conflict, error and mobile-data states; a "what syncs" explanation that matches `SyncDataContract`.
- **Playback preferences:**
  - Model: JSON round-trip, defaults, corrupt-data fallback.
  - Store: persistence.
  - Controller: restore to an empty queue only, record changes, turning off stops recording, load and save failures.
  - Library controllers: start from the player's shuffle state.
- **Library & Imports:** counts from the overview service, review navigation and count, the unavailable-songs list, the empty and unavailable states.
- **Data & privacy:** every backup table and cloud entity is classified.
- **About:** version from the channel, fallback when unavailable, licenses page, schema version.
- **Accessibility:** controls bound to the shared `AppearanceController`.

## 7. Implementation outcome

All items marked **Implement** in §2 are done; deferred items are unchanged (§5).

- **New persisted preference:** `playback.preferences` (SharedPreferencesAsync, versioned JSON, device-local): `rememberShuffleAndRepeat` (default off), plus the last `shuffleEnabled` and `repeatMode` when it is on.
- **New platform channel:** `com.sonus.sonus_next/app_info` (`AppInfoChannel.kt`) returns only `versionName` and `buildNumber`. The application ID is unchanged.
- **Sync:** no sync code changed. Settings uses only the existing controller and coordinator APIs. The one new control, "Allow mobile data" after Wi-Fi only, calls the existing `allowMobileDataAndSync`.
- **Fix found during the work:** the library, album and artist shuffle buttons now start from the player's real shuffle mode instead of always showing "off".
- **Verification:**
  - `flutter analyze`: no issues.
  - Full suite: 3,179 passed, 0 failed, against a baseline of 3,118.
  - Android emulator QA:
    - every destination checked at 411 dp, and at 320 dp with 2× text;
    - the About page showed `1.0.0 (build 1)` through the real channel;
    - one defect fixed: the Playback switch title broke mid-word at 2× text.
- **Formatting:** 28 untouched files on `main` are not `dart format`-clean (mostly recovery and sync tests). They were left unchanged rather than reformatted on this branch.

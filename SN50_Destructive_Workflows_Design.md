# SN-50: Destructive and Device-Dependent Workflows, Safety Design

**Status:** design for approval. It approves nothing by itself and authorizes no code, migration, device, cloud or real-file operation.
**Date:** 2026-10-29
**Scope:** Sonus Trash (logical), Delete from Phone (physical), Ringtones, Android media session (Session D).
**Authority:** `C:\dev\sonus\SN50_Master_Implementation_Spec.md` (spec) §0, §3 C3/C4, §4, §8 Phases 7–8, §9 scenarios 10–11. Evidence: `C:\dev\sonus\SN50_Current_Source_Audit.md` (audit) Part I §§4–6, Appendix C §§6–10, Appendix D.
**Source baseline:** worktree `C:\dev\sonus\sonus_next_sn50`, branch `sn-50-final-refinement` at `9aee76d`, read-only. Database is already at **v41** (Leaked, `lib/core/database/app_database.dart:29`, `database_migrations.dart:493-497`). Line numbers below are from that checkout. Another agent is still committing there, so re-check them before implementing.

Labels used: **[REPO]** read in source. **[PLATFORM]** Android knowledge, not yet verified on a device. **[DEVICE-QA]** can only be settled on hardware. **APPROVAL** means the user must sign off on that item.

---

## 0. Ground rules for every workflow in this document

1. Nothing here runs against the real phone library, real MP3s, production or cloud data, or remote Git without a separate explicit approval for that specific operation (spec §0 item 7).
2. Every destructive path ships **behind a feature flag that defaults to off**. Code can be merged locally and tested on disposable databases and emulator media while the flag stays off. Activation is its own approval (§6.2).
3. **No automatic purge ever runs while unattended.** The purge job does not exist in a runnable form until the tests in §5.1 pass and the user approves activation (spec §8 Phase 7).
4. Never report success before the platform confirms it. "Android says the file is in its trash" means Sonus re-queried MediaStore and saw `IS_TRASHED = 1`. A `RESULT_OK` from the dialog alone is not enough.
5. Listening history (`playback_sessions`, `playback_listening_segments`, `qualified_plays`), finalized charts (`chart_snapshots`, `chart_entries`) and published Moments (`chart_moment_events`) are **never written** by any workflow here (spec §0 item 1).
6. Each workflow fails closed. If a precondition cannot be verified (sync state, SDK level, MediaStore identity, clock), the action is disabled and the UI says why.

---

## 1. Sonus Trash (logical): C-Q13A/B, C-Q14/B, C-Q15/R, C-Q21, C-Q24

### 1.1 What exists today [REPO]

- **No song delete path exists.** Blacklist is `songs.is_blocked` (`library_schema.dart:115-116`), set by `SongBlockService.setBlocked` (`lib/features/library/application/services/song_block_service.dart:10-46`). It saves the song and queues a cloud upsert (`:39-43`). About 30 files filter on `is_blocked`/`isBlocked` (search, album/artist profiles, tracks, home, charts builder, insights, playback engine, restoration). Trash needs the same coverage. See §1.10.
- Song id is a random UUID (`core/identity/entity_id.dart:12`, audit C §6). No MediaStore id and no fingerprint are stored.
- The queue is persisted device-locally in SharedPreferences (`lib/features/player/data/services/playback_session_store.dart:12-28`). Restoration already drops songs that are "missing, unavailable or blacklisted" (`playback_restoration_controller.dart:19`, `:92-104`).
- Restore **replaces** portable tables and deletes songs that aren't in the backup (`lib/features/recovery/application/services/sqlite_restore_executor.dart:108-158`). Optional tables the backup lacks keep their local rows untouched (`:74-80`, `:103-106`).

### 1.2 Every reference to `songs.id`, and what purge does to each

From `lib/core/database/schema/*.dart` (grep of `song_id`, `entity_id`, `REFERENCES songs`):

| Table (schema file:line) | Link to song | FK action today | At **Trash** | At **Purge (day 30)** |
|---|---|---|---|---|
| `album_edition_tracks` (`library_schema.dart:153-179`) | `song_id` FK | ON DELETE **CASCADE** | kept (song hidden by Trash filter) | cascade-deleted. Listing captured first in the history identity (`edition_listings_json`). Edition renumbering is **not** triggered (A-Q7 rules apply only to explicit edits). |
| `song_artist_credits` (`library_schema.dart:201-226`) | `song_id` FK | **CASCADE** | kept | captured in `credits_json`, then cascade-deleted |
| `track_lyrics` (`lyrics_schema.dart:8-18`) | `song_id` PK/FK | **CASCADE** | kept | cascade-deleted. User lyrics are lost; the purge preview says so. **APPROVAL A-T7** |
| `song_import_reviews` (`import_schema.dart:33-46`, device-local) | `song_id` PK/FK | **CASCADE** | kept | cascade-deleted |
| `playlist_items` (`playlist_schema.dart:25-38`) | `song_id` FK | **CASCADE** | **removed** after a snapshot (C-Q14). §1.5 | none left. Snapshot rows are deleted ("recovery information expires") |
| `media_file_bindings` (`library_schema.dart:306-333`, device-local) | `song_id` FK | ON DELETE **RESTRICT** | kept (file untouched) | binding **row** deleted explicitly before the song. The audio file is **not** touched. |
| `songs.artwork_id` → `artwork_assets` (`library_schema.dart:143-146`) | song → asset | SET NULL (reverse direction) | kept | the asset row and file are left alone. Orphan cleanup is out of scope. |
| `metadata_field_states` (`library_schema.dart:252-291`), `entity_type='song'` | `entity_id`, **no FK** | none | kept | deleted explicitly in the purge transaction (otherwise orphaned) |
| `playback_sessions` (`analytics_schema.dart:15-60`) | `song_id`, **no FK**. Snapshots `song_title`, `artist_name`, `album_title`, `album_edition_title` | none | **untouched** | **untouched** (immutable history) |
| `playback_listening_segments` (`analytics_schema.dart:64-80`) | via session id | n/a | untouched | untouched |
| `qualified_plays` (`analytics_schema.dart:87-110`) | `song_id`, **no FK**, **no title snapshot** | none | untouched | untouched. Display resolves via its `playback_session_id` snapshot or the history identity. |
| `chart_entries` (`chart_schema.dart:41-94`) | `entity_id` (song chart), title/artist snapshot | none | untouched | untouched |
| `chart_moment_events` (`chart_schema.dart:105-200`) | `entity_id`, `related_entity_id` + title snapshots | none | untouched | untouched |
| `sync_outbox`, `cloud_revision_baselines`, `outbound_conflicts`, inbound deferred (`sync_schema.dart:28-280`) | `entity_id` | none | see §1.9 | **no delete is recorded** (cloud tombstones are deferred, SN-47). Purge is blocked while sync is enabled (§1.9). |
| `PlaybackSessionStore` JSON (SharedPreferences) | queued song ids | n/a | song removed from the live queue (`playback_coordinator.dart:152-160`, `removeSongFromQueue`) | restoration already drops missing ids |
| Android Auto "recent" root (`media_browse_catalog.dart:55-60`) | built from history | n/a | trashed ids filtered out | purged ids filtered out |

Not affected: `albums`, `album_editions`, `artists`, classification and project tables (`organization_schema.dart`) reference albums/artists, not songs. A release or artist left with zero active songs **stays**. Purge never cascades upward. Whether empty releases are hidden in the UI is **APPROVAL A-T8**.

### 1.3 Data model proposal

Five new tables, **no new column on any existing portable table**. That keeps `songs` column-for-column identical, so backups v31–41 stay restorable without touching `songs.columnsAddedLater` (`backup_table_coverage.dart:19`, `:51-53`).

```sql
-- Portable, optional (requiredInEveryBackup: false). One row per song that is or was in Trash.
CREATE TABLE song_trash_entries (
  song_id        TEXT PRIMARY KEY NOT NULL
                 REFERENCES songs(id) ON UPDATE CASCADE ON DELETE CASCADE,
  state          TEXT NOT NULL CHECK (state IN ('trashed','review')),
  trashed_at     TEXT NOT NULL,           -- UTC ISO-8601
  purge_after    TEXT NOT NULL,           -- trashed_at + 30 days
  origin         TEXT NOT NULL CHECK (origin IN
                   ('user','legacy_backup_review','external_file_restore_review')),
  review_reason  TEXT,                    -- set when state = 'review'
  created_at     TEXT NOT NULL,
  updated_at     TEXT NOT NULL
);
CREATE INDEX idx_song_trash_entries_purge ON song_trash_entries(state, purge_after);

-- Portable, optional. Playlist memberships removed at Trash time (C-Q14).
CREATE TABLE song_trash_playlist_snapshots (
  song_id         TEXT NOT NULL REFERENCES song_trash_entries(song_id) ON DELETE CASCADE,
  playlist_id     TEXT NOT NULL,          -- no FK: the playlist may be deleted later
  playlist_name   TEXT NOT NULL,          -- shown in the restore prompt if the playlist is gone
  playlist_item_id TEXT NOT NULL,
  position        INTEGER NOT NULL CHECK (position >= 0),
  item_created_at TEXT NOT NULL,
  PRIMARY KEY (song_id, playlist_id)
);

-- Portable, optional. Minimal historical identity kept after purge (C-Q15R). No FK.
CREATE TABLE song_history_identities (
  song_id               TEXT PRIMARY KEY NOT NULL,   -- original id, never reused
  title                 TEXT NOT NULL,
  canonical_title       TEXT NOT NULL,
  artist_id             TEXT NOT NULL,
  artist_name           TEXT NOT NULL,
  album_id              TEXT NOT NULL,
  album_title           TEXT NOT NULL,
  album_edition_id      TEXT NOT NULL,
  album_edition_title   TEXT NOT NULL,
  duration_seconds      INTEGER NOT NULL,
  version_label         TEXT,
  version_characteristics TEXT NOT NULL DEFAULT '[]',
  credits_json          TEXT NOT NULL DEFAULT '[]',  -- role-aware credit snapshot
  edition_listings_json TEXT NOT NULL DEFAULT '[]',  -- (edition_id, disc, track) pairs
  trashed_at            TEXT NOT NULL,
  purged_at             TEXT NOT NULL
);

-- Device-local (never restored, never synced). Resurrection guard (§1.7).
CREATE TABLE song_purge_ledger (
  song_id    TEXT PRIMARY KEY NOT NULL,
  event      TEXT NOT NULL CHECK (event IN ('trashed','purged')),
  at         TEXT NOT NULL
);

-- Internal state (never restored). Durable pending-operation journal (C-Q24, §1.8).
CREATE TABLE destructive_operation_journal (
  id             TEXT PRIMARY KEY NOT NULL,
  operation      TEXT NOT NULL CHECK (operation IN
                   ('trash','restore','purge','phone_trash','phone_untrash',
                    'ringtone_write','ringtone_set')),
  state          TEXT NOT NULL CHECK (state IN
                   ('prepared','awaiting_platform','committed','failed',
                    'abandoned','needs_review')),
  song_ids_json  TEXT NOT NULL,
  payload_json   TEXT NOT NULL DEFAULT '{}',  -- uris, snapshot ids, expected values; no personal data beyond ids
  platform_result TEXT,
  attempts       INTEGER NOT NULL DEFAULT 0,
  created_at     TEXT NOT NULL,
  updated_at     TEXT NOT NULL
);
```

Why tables and not a `songs.trashed_at` column:
- A `songs` column would make every v31–41 song row "trash = null" and need a `songs` compatibility proof. Cloud `songs` records would also carry an unknown column that older clients refuse (audit Part I §5).
- With a table, "restored" is simply "no `song_trash_entries` row". The row is deleted on restore, and a ledger line records it.

Registration (all required by existing contracts):
- `BackupCoverageContract.tables` (`backup_table_coverage.dart:30-192`): the three portable tables use `requiredInEveryBackup: false`. Ledger is `deviceLocal`. Journal is `internalState`.
- `SqliteRestoreExecutor.optionalTables` (`sqlite_restore_executor.dart:76-80`): add the three portable tables, entries before snapshots. `_assertCoverage` (`:181`) then passes.
- `columnsAddedLater`: **no change** (no existing table gains a column).
- `BackupCompatibility.restorableDatabaseVersions` (`backup_compatibility.dart:23-35`): add `42` only after the migration test in §5.1 passes. The comment block gets a "42 only added optional tables" line.

### 1.4 Migration v42 sketch

Use v42 only if no other SN-50 migration has claimed it by then. Otherwise take the next free number.

```dart
case 42:
  // SN-50: Sonus Trash. Only new tables; every existing row is untouched.
  await TrashSchema.createSongTrashEntries(db);
  await TrashSchema.createSongTrashPlaylistSnapshots(db);
  await TrashSchema.createSongHistoryIdentities(db);
  await TrashSchema.createSongPurgeLedger(db);
  await TrashSchema.createDestructiveOperationJournal(db);
  return;
```

- Additive only. Every `CREATE` uses `IF NOT EXISTS` so a retried upgrade is idempotent.
- **Reversibility:** the codebase has no down-migration pattern (`SN50_Progress.md` 2c). Rollback is (a) restore the backup taken before upgrade, or (b) for test DBs, a documented `DROP TABLE` of the five tables. The test proves that (b) returns the exact v41 `sqlite_master` shape.
- Fresh installs create the tables in the base `onCreate` path, and a test pins that fresh-v42 equals upgraded-v42.

### 1.5 State machine

```
            Remove from Sonus                     30 days elapsed AND purge enabled AND gates (§1.6)
  ACTIVE ───────────────────────▶ TRASHED ───────────────────────────────────────────────▶ PURGED
    ▲                               │  ▲                                                   (song row gone;
    │      Restore (+ ask about     │  │ user: "Keep in Trash"                              history identity
    └────── playlists, §1.5.2) ◀────┘  │                                                    + ledger remain)
    ▲                                  │
    │  user: "Restore"           REVIEW (unknown) ◀── legacy backup restore (§1.7)
    └──────────────────────────────────┘          ◀── file restored outside Sonus (§2.6)
```

- **ACTIVE**: no trash row.
- **TRASHED**: excluded from every live surface (§1.10). Still shown in history, finalized charts and Moments via snapshots. Visible in Settings → Sonus Trash with "Deletes on <date>".
- **REVIEW**: unknown state. Excluded from live surfaces like TRASHED but **never purged**. Listed under Trash → "Needs review" with Restore / Keep in Trash. "Keep in Trash" starts a fresh 30-day window from that decision (**APPROVAL A-T5**: fresh window vs original `trashed_at`).
- **PURGED**: terminal. The id is never reused. `EntityId` is random so collisions are already negligible, and the ledger lets import reject the id outright.
- Blacklist is independent. `is_blocked` is not changed by Trash or restore (C-Q13A).
- Remove from Sonus never touches the file (C-Q23). The binding stays, so a rescan sees `knownFile` and does **not** re-import it as a new song (`atomic_library_importer.dart:159`).

#### 1.5.1 Trash transaction (single SQLite transaction, through `SyncMutationRunner` like `SongBlockService`)

1. Preconditions: song exists, not already trashed, Trash flag on, sync gate (§1.9) passes.
2. Read its `playlist_items`, insert into `song_trash_playlist_snapshots`, delete those `playlist_items`, compact positions using the existing playlist-service routine.
3. Insert `song_trash_entries(state='trashed', purge_after = trashed_at + 30d)`. Insert ledger `trashed`.
4. Commit. Then, outside the transaction, `coordinator.removeSongsFromQueue(ids)` (`playback_coordinator.dart:160`).
5. Bulk: one transaction per batch. Report trashed / already in Trash / failed counts (C-Q11 pattern).

The journal is written for logical operations too (`prepared` → `committed` in the same transaction), so there is an audit trail. A crash before commit leaves nothing, because SQLite atomicity covers it.

#### 1.5.2 Restore and the playlist prompt (C-Q14B)

1. Delete the trash row (snapshots stay until step 3). Ledger records `restored` implicitly: the ledger row is deleted.
2. If snapshots exist, **ask**: "Add *Song* back to 3 playlists?" with *Add back*, *Choose…*, *Not now*.
3. Re-add per playlist, in one transaction:
   - playlist deleted → skipped, reported by its snapshot name;
   - already contains the song (`UNIQUE(playlist_id, song_id)`) → "already present";
   - position = `min(snapshot.position, current length)`.
   - Report added / already present / skipped / failed. Then delete the snapshot rows.
4. "Not now" deletes the snapshots too: one ask, no nagging (**APPROVAL A-T4**: keep snapshots for a later ask instead?).

#### 1.5.3 Purge transaction (per song; only when §1.6 gates pass)

1. Re-read inside the transaction: `state='trashed'`, `purge_after <= now`, no journal row for this song in `prepared`/`awaiting_platform`/`needs_review`.
2. Insert `song_history_identities` from the song row, its credits and its edition listings.
3. Delete `metadata_field_states` (entity_type 'song'), `media_file_bindings` rows (RESTRICT), then the `songs` row. Cascades remove listings, credits, lyrics, import review, trash row and snapshots.
4. Ledger `purged`. Journal `committed`. No `recordDelete` in the sync outbox.
5. After commit, assert the history tables have the same row counts and checksums as before (a cheap `count(*)` + `max(rowid)`). A mismatch is a release-blocking bug: it is logged with context and purge is disabled for the session.

### 1.6 Purge activation gates (purge must never run automatically until all hold)

1. All tests in §5.1 pass, including §9 scenario 10.
2. User approves activation (**APPROVAL A-T1**) after reviewing a dry-run report on a disposable copy.
3. The **first** activation runs in *preview mode*: it lists what would purge, and the user confirms. Automatic purge is a further approval (**A-T2**).
4. Clock guard: Sonus stores the highest UTC time it has observed. If the device clock is earlier than that (moved back), or `now - trashed_at > 400 days` (clock jumped forward), purge pauses and asks.
5. Sync gate (§1.9) passes. A pre-purge `.sonusbackup` was written in the last 24 h, or is written now (atomic backup needs API 30+, audit Part I §6. Below that, purge stays manual).
6. Never purge from a background isolate or the media service. Purge runs only in the foreground app, after startup reconciliation (§1.8).

### 1.7 Backups, legacy restores and resurrection protection (C-Q21)

- **v42+ backup** carries the three portable tables, which are restored verbatim.
- **v31–41 backup** has no Trash tables. Trash didn't exist when it was written, so a song in it could only have been trashed *later*. Rule:
  - Before clearing tables, the restore transaction reads the local `song_trash_entries` and the device-local `song_purge_ledger` (the ledger is never touched by restore).
  - After anchors are upserted, every restored song whose id is in either set gets `song_trash_entries(state='review', origin='legacy_backup_review')`. It is hidden from live surfaces and listed for review.
  - Songs with no local Trash history restore as active.
  - **APPROVAL A-T3**: this interpretation of "absent = unknown", versus marking *every* restored song as review, which is impractical for thousands of songs.
- **Resurrection**: a v42 backup taken before a purge contains the song row. On restore, the ledger flags it as `review`. It is never silently live and never re-purged without a fresh decision.
- Different device or fresh install: the ledger is empty, so an old backup restores the song as active. Full cross-device protection needs logical cloud state (§1.9, gated). State this limit in the restore confirmation text.
- Existing restore deletes songs that aren't in the backup (`sqlite_restore_executor.dart:136-158`). Their Trash rows go by cascade, but the ledger keeps them, which is what we want.

### 1.8 Durable journal and crash reconciliation (C-Q24)

At startup, before any destructive UI is enabled and before purge:

| Journal state found | Meaning | Action |
|---|---|---|
| `prepared`, logical op | transaction never committed | mark `abandoned` (SQLite rolled back) |
| `committed` | done | prune after 90 days |
| `awaiting_platform` (phone trash/untrash, ringtone write) | Sonus may have died between consent and result | query MediaStore for each URI (§2.4 `queryTrashState`). Apply what Android actually shows. Mark `committed`, `failed`, or `needs_review` if unresolvable. |
| `needs_review` | ambiguous | show in Trash → Needs review. Never auto-resolve. |

Reconciliation is idempotent, logs with context (operation id, counts, never paths in full or personal data), and shows one plain message when something needs the user.

### 1.9 Cloud (C-Q13B): designed, **not activated**

- Today songs sync by id with no tombstones. Inbound sync would **re-create a purged song**, and outbound playlist-item removals would propagate to clients that don't know Trash.
- **Fail-closed rule, now:** Remove from Sonus and purge are **disabled while cloud sync is enabled** for the account. The UI says "Trash is not available while sync is on". **APPROVAL A-T6**. The alternative, Trash local-only with sync on, is rejected because it diverges.
- Future (separate cloud approval): a logical `song_trash_state` cloud record with a client capability version. Clients below it receive nothing and the feature stays off while any registered device is incompatible. **Never** propagate physical deletion. No Supabase migration is authored or deployed under this design.

### 1.10 Live-surface exclusion

Add one shared predicate (a `LibraryQueryDao` join `LEFT JOIN song_trash_entries t ON t.song_id = songs.id WHERE t.song_id IS NULL`) and use it wherever `is_blocked` filters today (≈30 files; list in §1.1). Include live/current chart builders (`chart_snapshot_builder_service.dart:175,191`, `all_time_chart_service.dart:145`), the playback engine guard, restoration, Auto browse and search. Finalized weeks are frozen by Phase 1 (`8956e3a`) and are unaffected. A widget test per surface proves trashed songs are hidden. One test greps that every `is_blocked` filter site also applies the Trash predicate, so the two can't drift.

---

## 2. Delete from Phone (physical): C-Q16, C-Q17, C-Q18, C-Q19, C-Q23

### 2.1 Product rules (approved) restated as invariants

- Separate action from Remove from Sonus. It **does not** put the song in Sonus Trash (C-Q23). The song stays in the library as *Unavailable — in your phone's trash until <date>*.
- Uses only `MediaStore.createTrashRequest` (recoverable, about 30 days). **Never** `createDeleteRequest` or `File.delete()`.
- **API 30+ only.** On API 24–29 the action is shown disabled with "Your Android version can't move files to a recoverable trash" (C-Q16). minSdk is 24 (audit C §7).
- Per-batch system consent (C-Q17). **No `MANAGE_MEDIA`** is requested, which avoids Play's special-access review.
- Success is claimed only for files Android confirms as `IS_TRASHED=1` after re-query.

### 2.2 Why it needs new identity storage [REPO]

- `AudioLibraryChannel.kt` is read-only: `status`, `request`, `openSettings`, `audioFolders` (`android/app/src/main/kotlin/com/sonus/sonus_next/AudioLibraryChannel.kt:31-36`, `:103-139`). It reads only `DATA`.
- Import reads files by path. Sonus stores **no MediaStore `_ID`** (audit C §6–7). A path→`_ID` lookup at action time fails for unindexed or SAF-only files and is ambiguous after renames.
- Proposal (migration **v43**, separate from v42 so Trash can ship without it): add nullable device-local columns to `media_file_bindings`. Because it is `deviceLocal` (`backup_table_coverage.dart:110-113`) and never restored, backup compatibility is unaffected.
  - `media_store_id INTEGER`, `media_store_volume TEXT`, `media_store_relative_path TEXT`, `media_store_display_name TEXT`, `media_store_date_modified INTEGER`
  - `phone_trash_state TEXT CHECK (phone_trash_state IS NULL OR phone_trash_state IN ('trashed','expired','restored_externally'))`, `phone_trashed_at TEXT`, `phone_trash_expires_at TEXT`
  - Filled lazily: on import, on reconciliation scan, and just before Delete from Phone.

### 2.3 Flow

```
select songs ─▶ resolveIds(paths) ─▶ preview sheet
   "4 files will move to your phone's trash. Android will ask you to confirm.
    1 file can't be moved (not in Android's media index)."
 ─▶ journal(phone_trash, awaiting_platform, uris)  [committed to SQLite BEFORE the dialog]
 ─▶ requestTrash(uris)  ── system consent dialog ──▶ resultCode
 ─▶ queryTrashState(uris)   (always, even on CANCELED: the user may have partially acted, or OK may be lost)
 ─▶ per uri: IS_TRASHED=1 → binding is_available=0, phone_trash_state='trashed', expires from DATE_EXPIRES
             IS_TRASHED=0 → unchanged, reported as "not moved"
 ─▶ journal committed; message "3 moved to your phone's trash. 1 not moved."
```

- Batch cap: 100 URIs per request, to stay under PendingIntent/Binder limits (verify in feasibility tests).
- Only bindings with `is_available=1` and a resolved, unambiguous `media_store_id`.
- If the song is currently playing, it is skipped to the next track before the request. If it is queued, it is removed from the queue after confirmation.

### 2.4 Native sketch: new channel `com.sonus.sonus_next/media_store`

Kept separate from `audio_library` so that channel stays read-only.

```kotlin
// MediaStoreChannel.kt (sketch, not code to commit as is)
"capabilities"    -> mapOf("sdkInt" to SDK_INT, "trashSupported" to (SDK_INT >= 30))
"resolveIds"      -> // args: paths: List<String>
    // query EXTERNAL_CONTENT_URI, projection _ID, VOLUME_NAME, RELATIVE_PATH, DISPLAY_NAME,
    // SIZE, DATE_MODIFIED, DURATION, IS_TRASHED; Bundle QUERY_ARG_MATCH_TRASHED = MATCH_INCLUDE;
    // per path: {path, status: found|notIndexed|ambiguous, id, uri, size, dateModified, ...}
"requestTrash"    -> // args: uris, requestId; SDK_INT >= 30 else error("unsupported")
    // val pi = MediaStore.createTrashRequest(resolver, uris, true)
    // activity.startIntentSenderForResult(pi.intentSender, REQ_TRASH, null, 0, 0, 0)
    // pending = (requestId, result); answered from onActivityResult with {requestId, resultCode}
"requestUntrash"  -> // createTrashRequest(resolver, uris, false), same plumbing
"queryTrashState" -> // per uri: {uri, exists, isTrashed, dateExpires, relativePath, displayName, size}
```

- Activity-result plumbing: `MainActivity.onActivityResult` (`MainActivity.kt:41-46`) already routes to `BackupDocumentChannel`, so add the same hook for this channel. If the activity is recreated during the dialog, the pending `Result` is lost. The journal plus `queryTrashState` at the next start settles the truth (§1.8).
- Errors are returned as codes (`unsupported`, `notIndexed`, `securityException`, `cancelled`), logged with the operation id, and shown as plain sentences. No stack traces reach the UI.
- Permissions: none new. `READ_MEDIA_AUDIO` (already declared, `AndroidManifest.xml:15`) covers queries. Trash requests need no manifest permission on API 30+, because consent is per request.
- Play policy: no `MANAGE_MEDIA`, no `MANAGE_EXTERNAL_STORAGE`, no `WRITE_EXTERNAL_STORAGE`. The data-safety form is unchanged (nothing leaves the device). The store listing should mention that Sonus can move songs to the phone's trash with your confirmation.

### 2.5 Expiry and Sonus restore

- After `phone_trash_expires_at`, `queryTrashState` shows `exists=false`, so the state becomes `expired` and the song stays in the library as Unavailable. History is untouched.
- "Restore to phone" (optional UI) calls `requestUntrash` with the same verify-after pattern. **APPROVAL P-4**: include it in this release, or rely on the Files/Gallery trash?

### 2.6 External restore detection (C-Q18)

- **Today** a rescan that finds a known path on an unavailable binding **relinks automatically** (`atomic_library_importer.dart:147-178`, `:804-814`). A song in Sonus Trash would become playable while still listed as trashed (audit C §8 partial state 4).
- Change: relink the binding as now (file availability is a fact). If the song has `state='trashed'`, set `state='review'`, `origin='external_file_restore_review'` and ask: "*Song*'s file is back on your phone. Restore it from Sonus Trash?" Never auto-restore.
- Trusted identity for "same file is back" requires **both** of these. Otherwise go to §2.7.
  - the same `media_store_id` on the same volume, **or** the same `relative_path` + `display_name`;
  - the same `SIZE`.

### 2.7 Re-import and move matching (C-Q19)

Signals, strongest first:
1. MediaStore `_ID` + volume (survives rename within MediaStore, not copy).
2. File size + `DATE_MODIFIED`.
3. Duration within ±max(3 s, 2 %) and the same featured set (`RecordingEvidence`, audit C §6).
4. Tag identity: artist, canonical title, version (`_sameVersionIdentity`).
5. Optional content hash of the first 1 MB + file length. **Only if approved (APPROVAL P-5).** It costs one read per candidate and is the only signal that survives copies and tag edits.

Decision rule: auto-relink only when (1 and 2) match, or (2, 3 and 5) match, **and** there is exactly one candidate. Everything else goes to a review list: "Is this the same recording as …?" with *Same song (keep history)* / *Different song*. **Never merge two existing Song ids**, never move plays, never invent plays. This also closes the audit's PLAUSIBLE DEFECT where a Track Studio edit makes a moved file import as a new song, *if* signals 1, 2 or 5 match.

### 2.8 Partial states (audit C §8, items 1–10): handling

| # | State | Handling |
|---|---|---|
| 1 | Android expiry passes | binding `expired`. Song Unavailable. History kept. |
| 2 | Consent denied or cancelled | nothing committed. Message "Nothing was moved". |
| 3 | Process dies around consent | journal `awaiting_platform` → re-query at start |
| 4 | Restored in Files/Gallery | §2.6 ask |
| 5 | Sonus Trash restore while file is still in phone trash | song active but Unavailable. Offer "Restore file too" (P-4). |
| 6 | Comes back at a new path or `_ID` | §2.7 matching. Review if ambiguous. |
| 7 | Another device has the song | physical delete is never synced (C-Q13B) |
| 8 | OEM cleaner purges early | same as 1, detected by query |
| 9 | API < 30 | action disabled |
| 10 | Old backup restore | bindings are device-local and keep `phone_trash_state`. Song rows follow §1.7. |

---

## 3. Ringtones: C-Q20A, C-Q20B, C-Q20C

Nothing exists in the repo today (audit C §9).

### 3.1 Behavior

- **Unedited whole song (C-Q20A):** set the original MediaStore URI with `RingtoneManager.setActualDefaultRingtoneUri(ctx, TYPE_RINGTONE, uri)`. Some OEMs ignore URIs whose row lacks `IS_RINGTONE=1`. Setting that flag on a file Sonus doesn't own needs `createWriteRequest` consent (API 30+), and that **writes to the user's MediaStore row**, though not to the audio bytes.
  - **APPROVAL R-1:** (a) original URI only, with no flag write; if the OEM ignores it, fall back to (c). (b) Original URI + consented `IS_RINGTONE` flag write. (c) Treat as a separate output copy, like an edit.
  - Recommendation: (a) with (c) as the fallback, because it never modifies a user-owned row.
- **Edited (trim, fade, effects; C-Q20B/C):** always a **new file** owned by Sonus:
  - `MediaStore.Audio.Media` insert into `RELATIVE_PATH = "Ringtones/Sonus/"`, `IS_RINGTONE=1`, `IS_MUSIC=0`, `IS_PENDING=1` while writing, then `IS_PENDING=0`.
  - Unique display name: "<title> (Sonus ringtone).m4a".
  - The source is opened **read-only** (`"r"`) and nothing ever opens it for writing.
- Import must **exclude** Sonus ringtone outputs (`IS_MUSIC=0`, or the `Ringtones/Sonus/` path), so they never become duplicate songs. The folder tree already shows a "Ringtones" folder (`test/features/import/application/folders/device_music_folder_tree_test.dart:14`).

### 3.2 Editing engine (needs a decision)

- Trim without re-encode: `MediaExtractor` + `MediaMuxer` (AAC/M4A, cut at sync samples). MP3 can be frame-cut by bytes.
- Fades or effects need decode → PCM → `MediaCodec` AAC encode. That is native work of moderate size.
- **No new dependency without saying why.** `ffmpeg_kit_flutter` was retired upstream, so it is not acceptable. **APPROVAL R-3:** platform `MediaCodec` (recommended, no dependency), or a named maintained package.

### 3.3 Permissions and flow

1. `<uses-permission android:name="android.permission.WRITE_SETTINGS"/>`. Check `Settings.System.canWrite(ctx)`. If false, explain, then open `Settings.ACTION_MANAGE_WRITE_SETTINGS` with `package:` URI. Re-check in `onResume` and continue only if granted.
2. Write the output (journal `ringtone_write`, `awaiting_platform` until `IS_PENDING=0`). On crash, reconciliation deletes the Sonus-owned pending row (allowed because Sonus owns it) or finishes it.
3. Set (journal `ringtone_set`). **Read back** `getActualDefaultRingtoneUri` and claim success only if it matches.
4. API 24–28: writing into `Ringtones/` needs `WRITE_EXTERNAL_STORAGE` (maxSdkVersion 28). **APPROVAL R-2:** add that permission, or disable ringtone output below API 29. Recommendation: disable, to keep the permission surface small.

Native channel methods, on the same `media_store` channel: `ringtoneCapabilities`, `openWriteSettings`, `writeRingtoneOutput(sourceUri, startMs, endMs, fadeInMs, fadeOutMs) → outputUri`, `setDefaultRingtone(uri, type)`, `readDefaultRingtone(type)`.

### 3.4 Feasibility tests (disposable media only)

On emulators API 29, 30, 33 and 36, use a generated 40-second sine-tone MP3 and M4A pushed by the test harness (never a user file):
- output appears in `Ringtones/Sonus/`;
- the source's bytes and `DATE_MODIFIED` are unchanged (hash before and after);
- read-back equals the set URI;
- the pending-row crash path is cleaned;
- import excludes the output;
- WRITE_SETTINGS denial leaves everything unchanged.

The S26 (One UI) check of the "original URI without flag" case is **[DEVICE-QA]** and uses a disposable copied file, not library music.

---

## 4. Media session (Session D): D-Q1 … D-Q19

Files: Dart mapper `lib/features/player/application/services/media_session/media_session_state_mapper.dart`, handler `.../sonus_audio_handler.dart`, config `.../media_session_bootstrap.dart:27-42`, vendored plugin `third_party/audio_service/` (0.18.18 + Patch 1, `third_party/audio_service/PATCHES.md`), app-side shim `android/app/src/main/java/com/ryanheise/audioservice/SonusForegroundRelease.java`, keep list `android/app/src/main/res/raw/keep.xml`.

### 4.1 Decision → change → kind of change

| Decision | Change | Kind |
|---|---|---|
| **D-Q1/D-Q2** Shuffle · Prev · Play/Pause · Next · Repeat, accepting system placement | `controlsFor` (`media_session_state_mapper.dart:37-42`) becomes `[prev, play/pause, next, custom(shuffle), custom(repeat)]`, using `MediaControl.custom(androidIcon:'drawable/sonus_shuffle_on'|'…_off', name:'sonus.shuffle')` and `sonus_repeat_off/all/one`. Icon and label follow state, so `controlsFor` takes `shuffle` and `repeat`. On API 33+ the plugin turns any `customAction` control into a PlaybackState custom action (`AudioService.java:453-456`, `:514-520`). New padded drawables go in `android/app/src/main/res/drawable-*`, and `keep.xml` gains `@drawable/sonus_*`. Without that, release builds throw on every `setState` (audit D §4). Compact indices `[0,1,2]` stay. | **Dart + app resources only** (safe, no vendor patch) |
| | `SonusAudioHandler` overrides `customAction` (base no-op at `third_party/audio_service/lib/audio_service.dart:3181-3182`). It routes `sonus.shuffle` and `sonus.repeat` to the coordinator. | Dart |
| **D-Q3/D-Q15** Remove visible Stop; add End Session | Drop `MediaControl.stop` from `controlsFor`. `ACTION_STOP` stays in `AUTO_ENABLED_ACTIONS` (`AudioService.java:76`), so Bluetooth/AVRCP STOP keeps working. Add **End Session** to the Now Playing overflow and the mini-player long-press menu. It calls `coordinator.stop()` (`playback_coordinator.dart:172`), which ends the session and keeps queue and position, matching D-Q6. The mini-player stays visible while a current track exists (`shell_playback_slot.dart:38-48`). **APPROVAL M-2:** End Session keeps the queue (recommended, same as dismissal), or clears it. | Dart/UI |
| **D-Q4** Prioritize paused resumption | Keep `androidStopForegroundOnPause: false` (SN-44 D2(a), `media_session_bootstrap.dart:33-36`). No change. | none |
| **D-Q5/D-Q6** Dismiss while playing where Android allows; dismissal ends session, keeps queue | Path exists: deleteIntent → `onNotificationDeleted` → base `stop()` (`audio_service.dart:3188-3190`) → engine `stop()` keeps queue and position (`just_audio_playback_engine.dart:410-430`). Make it **explicit**: override `onNotificationDeleted` in `SonusAudioHandler` to call the same `stop()`, with a test, so an upstream default change can't flip semantics. Whether One UI lets the user dismiss, and whether that *cancels* (fires deleteIntent) or only hides the card, is **[DEVICE-QA]**. | Dart |
| **D-Q7** Paused mini-player swipe clears queue | Already current: `dismissPausedSession` (`playback_coordinator.dart:178-187`), refused while playing or loading. Add a regression test that the notification path never calls it. | test only |
| **D-Q8** Bluetooth Play restores saved queue and position | Process alive: already true (Patch 1 PLAY → `onPlay` → `coordinator.play()`). Process killed: the media-button receiver starts the service, and `play()` must wait for `PlaybackRestorationController` (`playback_restoration_controller.dart:58-104`) before acting. Add a "restore-then-play" path in the handler: if the queue is empty and restoration hasn't run, await it, then play. | Dart |
| **D-Q9** System Resume card restores the saved queue, not Recent | Today the `recent` root returns the last-played song, and resume builds a **Recent** queue (`media_browse_catalog.dart:55-60`, audit D F12). Change: the recent root returns the saved session's current item with a reserved id `sonus.resume:<songId>`. `playFromMediaId` recognizes it → restore the saved queue and position → play. Fallback to the old behavior only when there is no saved session. | Dart |
| **D-Q10** Swiping Sonus out of Recents keeps playing/paused state | Already current: `onTaskRemoved` base no-op (`audio_service.dart:3185`), no `stopWithTask` in the manifest. Add an explicit no-op override with a comment, plus a test. | Dart (pin) |
| **D-Q11** No paused timeout; no needless wake lock | Wake lock is acquired on play (`AudioService.java:710`) and released only in `exitForegroundState` (`:720-724`, reached only when stop-on-pause is true) or `onDestroy` (`:381`). The field is `private` (`:269`), so the app-side shim **can't** reach it. Fix: **vendor Patch 2.** `exitPlayingState()` always calls `releaseWakeLock()`, while foreground stays per config. `stop()` also releases it. Logged in `PATCHES.md`. | **Vendor patch (APPROVAL M-4)** |
| **D-Q12** Repeat Off → All → One → Off everywhere | Move `_nextRepeatMode` (`now_playing_page.dart:143-148`) to a domain function `PlaybackRepeatMode.next`, used by Now Playing and `customAction`. | Dart |
| **D-Q13** External shuffle/repeat changes follow "Remember" | Already true via coordinator state (`playback_preferences_controller.dart:25`, `:139-150`). Add a test for the custom-action path. | test only |
| **D-Q14** Android ≤12 must show Shuffle/Repeat | In this plugin, a `customAction` control never becomes a notification action (`AudioService.java:514-520`). **Vendor Patch 3:** below API 33, build custom controls as `NotificationCompat.Action`s with a broadcast `PendingIntent` that the service maps to `onCustomAction`. Per spec: separately approved, never unattended. | **Vendor patch (APPROVAL M-5)** |
| **D-Q16** End of queue with Repeat Off stays paused on the final track | Today `completed` maps to idle and removes the notification (`media_session_state_mapper.dart:70-83`). Change in the engine (`just_audio_playback_engine.dart:520-540`): on `ProcessingState.completed` with repeat off, `pause()` and keep the last index, emitting `paused` at the final track. The mapper then keeps controls (D2(a) keeps the notification). The analytics session for the finished track closes as `completed` exactly once, and the paused-at-end transition must not open a new one. | Dart |
| **D-Q16 minor (open)** Play after end of queue | **APPROVAL M-1**: (a) replay the final track from 0:00, or (b) restart the queue from track 1 (shuffle respected). Displayed position at rest: end (duration) or 0:00. Either way a new play counts only if it qualifies again. No recommendation is implemented until chosen. | Dart (after choice) |
| **D-Q17** One authoritative queue with Android Auto | Already one queue published to the session (`media_session_state_mapper.dart:104-112`). Auto stays read-only + `skipToQueueItem`. Car-side editing only if a host is verified to send `addQueueItem`/`removeQueueItem`, which is **[DEVICE-QA]**. | none/test |
| **D-Q18/D-Q19** Queue visuals; mini-player interactive behind non-blocking overlays | UI only, not destructive. Outside this safety design apart from the 320 px / a11y checks. | UI |

### 4.2 Device QA per decision

Only when authorized. Use a debug or release build installed per the existing SN-49 rule (`tool/build-release.ps1` only), and disposable test music.

| Decision | S26 Ultra / One UI (API 36) | Android ≤ 12 (emulator API 31/32 + any real device if available) | Android Auto DHU |
|---|---|---|---|
| D-Q1/2 | Screenshot QS player, lock screen, Now Bar. Record where custom1/custom2 sit. Tap each and confirm state and icon change. | No buttons before Patch 3; after it, 5 actions, compact 3 | shuffle/repeat appear (maybe overflow), taps work |
| D-Q3/15 | No Stop button anywhere. End Session from both menus. `dumpsys media_session` shows inactive; notification gone. | same | Stop absent; session ends when phone ends it |
| D-Q5/6 | Try to swipe the player **while playing** and **while paused**. `adb logcat` for `onNotificationDeleted`. `dumpsys notification` (cancelled vs hidden). Queue and position kept in app. | not swipeable (expected, FGS) | n/a |
| D-Q7 | Mini-player swipe while paused clears the queue. While playing it is refused. | same | n/a |
| D-Q8 | Bluetooth headset PLAY after End Session: (a) process alive, (b) after `adb shell am kill`. Same queue and position resume. | same, API 31 FGS-start rules | n/a |
| D-Q9 | Dismiss, then tap the QS resume card: saved queue and position, not Recent | API 30+ only | n/a |
| D-Q10 | Swipe from Recents while playing (keeps playing) and paused (stays paused, notification stays) | same | n/a |
| D-Q11 | `adb shell dumpsys power \| grep -i AudioService` after play, pause, End Session: the lock is held only while playing (after Patch 2) | same | n/a |
| D-Q12/13 | Cycle repeat from notification and Now Playing: same order, saved per Remember | after Patch 3 | cycle from car |
| D-Q16 | Let the last track finish: paused on final track, notification stays. Then Play per M-1. Qualified plays +1 only for a qualifying replay. | same | car shows paused last track |
| D-Q17 | n/a | n/a | Queue in car matches phone. Skip-to-item works. Edits from phone appear in car. |

Blocked today: the Android Auto host check (emulator has only the stub, audit Part I §6). The DHU needs installation on this PC, which is its own approval.

### 4.3 Tests that must change (so they're not surprises)

- `media_session_state_mapper_test.dart:26` asserts the exact 4-control list including Stop. It is rewritten for 5 controls, state-dependent icons, and `:111` (completed → idle) for D-Q16.
- `media_session_wiring_test.dart:14-44` (keep.xml coverage) is extended to custom icons. `:46` (Patch 1 present) gains Patch 2/3 checks when they are approved. `:75-84` (`androidStopForegroundOnPause` false) stays.
- `sonus_audio_handler_test.dart`: add `customAction`, `onNotificationDeleted`, `onTaskRemoved`, restore-then-play.
- `stop_resume_regression_test.dart:81-121` stays green (End Session = stop keeps queue).

---

## 5. Test plan

All tests run on **disposable** databases (`sqflite_common_ffi` in-memory or temp files), fake libraries and generated audio. None touch the phone, real MP3s or cloud.

### 5.1 Sonus Trash

**Migration (disposable DBs):**
- v41 → v42 upgrade on a literal v41 fixture leaves every existing table byte-identical (row checksums), and the new tables are empty.
- Fresh v42 schema equals upgraded v42.
- Retrying the upgrade is idempotent.
- The documented DROP returns the v41 shape.
- Backups from **each of v31…v41** restore into v42: Trash tables absent, every song active unless it is in the local ledger/trash, and then `review`.
- A v42 backup round-trips trash, snapshot and identity rows.
- `BackupCompatibility` includes 42 only after these tests exist (the existing "schema bump fails compatibility tests" guard enforces review).

**Unit / service:**
- Trash moves playlist memberships into snapshots atomically. A failure mid-batch rolls back everything.
- Restore prompt cases: playlist deleted, already present, position clamp, counts.
- Purge refuses: not expired; `review` state; pending journal; sync enabled; clock moved back; clock jumped forward; flag off; no recent backup.
- Purge happy path: history tables (`playback_sessions`, `playback_listening_segments`, `qualified_plays`, `chart_snapshots`, `chart_entries`, `chart_moment_events`) are **row-identical** before and after. The history identity holds the original id, credits and listings. Bindings are removed, files untouched (fake filesystem asserts no delete call). `metadata_field_states` is cleaned. No outbox delete.
- Insights, history and chart detail resolve a purged id via the session snapshot or `song_history_identities`.
- Resurrection: a pre-purge v42 backup restored on the same device lands in `review`, not active.
- Journal reconciliation for every state in §1.8.
- **§9 scenario 10** as one end-to-end test with a fake clock at day 29, 30 and 31.
- Live-surface exclusion: one widget test per surface in §1.10, plus the "every `is_blocked` site has the Trash predicate" guard test.

**Widget:** Trash page (empty, trashed, review sections); restore prompt; disabled-with-reason states (sync on, flag off). 320 px width, 200 % text, nine themes, TalkBack labels, keyboard/D-pad focus order, 44×44 targets.

### 5.2 Delete from Phone

- **Unit:** decision table for §2.7 matching (every signal combination → relink/review); journal handling of every resultCode × query outcome; a CANCELED dialog with items actually trashed (must still be recorded truthfully); API gate.
- **Channel contract:** fake `MethodChannel` round trips for each method and error code.
- **Instrumentation (emulator API 30, 33, 36, disposable media inserted by the test into MediaStore):** resolve → trash → `IS_TRASHED=1` and binding unavailable; deny → unchanged; kill the process during the dialog → reconciliation is correct at next start; untrash outside Sonus → C-Q18 prompt; move/rename → matching outcome. API 29 emulator: action disabled.
- **Not allowed:** any run on the S26 library. A device trial uses a disposable copied file under an approved session (**P-6**).

### 5.3 Ringtone

Feasibility matrix in §3.4, plus:
- unit tests of the output naming and exclusion rule;
- a widget test of the editor's trim handles (keyboard-adjustable, labeled);
- the WRITE_SETTINGS explanation flow.

### 5.4 Media session

The Dart tests in §4.3; an engine test for D-Q16 (completed → paused at last index, exactly one `completed` session end, no new session until Play); restore-then-play; resume id; repeat cycle shared; **§9 scenario 11** as a coordinator + handler integration test with a fake engine. Device QA per §4.2.

### 5.5 Always

`dart format` on changed files, `flutter analyze`, targeted tests, then the full `flutter test` (baseline 4,462+; current count per `SN50_Progress.md`). The result is reported. §9 scenario 12 (no live cloud, no ADB, no physical MP3 op) is checked by inspection of the run.

---

## 6. Approval

### 6.1 Approve before **implementation** (local code, flag off, disposable data only)

| ID | Item |
|---|---|
| A-T0 | Data model in §1.3 (tables, not `songs` columns) and migration v42 (or next free) with backup registration as described |
| A-T3 | Legacy-backup rule: absent Trash info → `review` only for songs this device knows were trashed/purged; others restore active |
| A-T4 | Restore prompt: "Not now" discards the playlist snapshot (vs keep for later) |
| A-T5 | Review → "Keep in Trash" starts a fresh 30-day window |
| A-T6 | Trash and purge disabled while cloud sync is enabled, until a cloud design is approved |
| A-T7 | Purge deletes user lyrics and the edition listing (listing is preserved only inside the history identity) |
| A-T8 | Releases or artists with zero active songs: keep visible, or hide from live lists (data is never deleted either way) |
| P-1 | Delete from Phone: `createTrashRequest` only, API 30+, per-batch consent, no `MANAGE_MEDIA`, new `media_store` channel |
| P-2 | Migration v43: device-local MediaStore identity columns on `media_file_bindings` |
| P-3 | External restore → `review` + ask. Change the importer's automatic relink so it doesn't silently un-trash. |
| P-4 | Include "Restore to phone" (`requestUntrash`) in this release? |
| P-5 | Partial content hash (first 1 MB + length) as an identity signal |
| R-1 | Unedited ringtone: original URI only (recommended) / with consented `IS_RINGTONE` write / always copy |
| R-2 | Ringtone below API 29: disable (recommended) or add `WRITE_EXTERNAL_STORAGE` maxSdk 28 |
| R-3 | Editing engine: platform `MediaCodec`/`MediaMuxer` (recommended) or a named package |
| M-1 | Play after a completed queue: replay final track, or restart queue; resting position shown. **Resolved:** replay the final track (R4, `db79c4e`). |
| M-2 | End Session keeps queue and position (recommended), or clears it. **Implemented as recommended** in `9547ef0` (D-Q3/D-Q6); explicit sign-off pending. |
| M-3 | Dart-side media changes in §4.1 (custom shuffle/repeat, Stop removed, explicit overrides, resume id, restore-then-play, end-of-queue pause). **Implemented** in `9547ef0` under D-Q1/D-Q3/D-Q6/D-Q10/D-Q12/D-Q16; reconciled in SN-50 round 5 (F7); explicit sign-off pending. |
| M-4 | Vendor Patch 2: wake lock released on pause and stop |
| M-5 | Vendor Patch 3: Android ≤ 12 custom notification actions |

### 6.2 Approve before **activation** (flag on, or touching anything real)

| ID | Item |
|---|---|
| A-T1 | Enable Remove from Sonus and manual purge in a build that goes on the phone, after reviewing the §5.1 results |
| A-T2 | Enable **automatic** day-30 purge (only after A-T1 has run in preview mode on real data) |
| C-1 | Any cloud logical-Trash record, Supabase migration or deployment (separate track) |
| P-6 | First Delete from Phone on the S26, using a disposable copied file |
| P-7 | Delete from Phone on real library files |
| R-4 | First ringtone set on the S26 (disposable file), then real use |
| M-6 | Install on the S26 for §4.2 device QA. DHU installation for Android Auto checks. |
| M-7 | Publish/push any of this work (standing rule: no push without fresh approval) |

---

## 7. Safe now vs gated

| Work | Status | Why |
|---|---|---|
| Shared repeat-cycle function, explicit `onNotificationDeleted`/`onTaskRemoved` overrides, tests pinning D-Q7/D-Q10/D-Q13 | **Safe now** (local, behavior-preserving) | No behavior change; adds tests |
| Trash tables, migration v42, restore/backup registration, Trash service, UI behind flag off | **Gated: A-T0, A-T3…A-T8** | New schema and restore semantics |
| Purge code path (flag off, preview only) | **Gated: A-T0 + §5.1 green** | Irreversible deletion of song rows |
| Automatic purge | **Gated: A-T1, A-T2** | Never unattended |
| Cloud logical Trash | **Gated: C-1** (separate track) | Cross-device deletion |
| `media_store` channel, v43 identity columns, matching rules | **Gated: P-1…P-3, P-5** | New native surface and importer behavior |
| Any MediaStore trash request | **Gated: P-6, P-7** | Physical file operation |
| Ringtone native code and editor | **Gated: R-1…R-3** | Native writes and possible new permission |
| Setting a ringtone on the device | **Gated: R-4** | Changes system settings and writes a file |
| Custom Shuffle/Repeat controls, Stop removal, End Session, resume id, restore-then-play, end-of-queue pause | **Gated: M-1 (for Play-after-end), M-2, M-3** | User-visible session behavior; emulator-testable |
| Vendor Patch 2 (wake lock), Patch 3 (≤12 actions) | **Gated: M-4, M-5** | Vendored plugin divergence |
| Any device or DHU check | **Gated: M-6** | Physical device |

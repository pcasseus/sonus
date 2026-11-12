# Proposed cloud migration 20261113000001: edition date precision and disc names

**Status: proposed, not deployed.**
- This folder sits outside `supabase/migrations`, so `supabase db push` and the deploy scripts never see it.
- Deploying needs, in order: approval, a staging rehearsal (runbook below), and a production decision.

## What it adds (`migration.sql`)

| Column on `public.album_editions` | Holds | Local source |
|---|---|---|
| `release_date_partial text null` | The date as written: `2019`, `2019-03` or `2019-03-15` | `album_editions.release_date` + `release_date_precision` (SQLite) |
| `disc_labels jsonb null` | Disc names, e.g. `{"2": "Bonus Tracks"}`; `{}` = no names; NULL = not provided | `album_edition_disc_labels` (SQLite v45) |

Checks enforced by the database:
- The date has the right format.
- Disc names are an object keyed by disc numbers 1–999.
- Each value is non-blank text of at most 200 characters.

What it doesn't need:
- No trigger, no new table and no RLS change. The existing row policies cover the new columns.
- No change to the existing `server_revision` trigger, which already advances on every update.

### Why a partial date instead of a precision column

Sonus writes with PostgREST upserts that only update the columns they send. So an app that doesn't know a column never changes it.

- **The problem with a precision column:** an older app could move `release_date` and leave a stale "year" beside an exact day. A trigger can't tell an older app's write from a newer app that kept the same precision.
- **How the partial date avoids it:** it describes itself. The app trusts it only while `ReleaseDate.tryParse(partial).instant == release_date`. After an older app changes the date the two disagree, and the partial is ignored.
- **Effect:** writes never fail and no wrong precision is ever applied.

## App changes this needs (not made)

These follow the SN-45 song-extension pattern (`SupabaseCloudSyncGateway` probes once and sends extension columns only when the server has them).

1. **Contract and gate:** add `release_date_partial` and `disc_labels` to `SupabaseSyncContract` as edition extension columns, gated by the same probe.
2. **Records:** `CloudAlbumEditionRecord` gains `releaseDatePartial` and `discLabels`, which are null when not provided.
   - Outbound: the local `ReleaseDate.iso`, and the edition's disc names as a map.
   - Disc name edits (`setDiscLabel`, and the label cleanup in `arrangeEdition`) must also bump the edition's `updated_at` and queue an `albumEdition` upsert.
3. **Inbound precision** (`InboundCloudRecordApplier._applyAlbumEdition`):
   - If the partial matches the instant, its precision wins.
   - Otherwise, today's rule applies: keep this device's precision for the same instant, else none (tested in `inbound_cloud_record_applier_test.dart`).
4. **Inbound disc names:**
   - NULL leaves local names untouched.
   - An object replaces the edition's names (`keepOnly`, then `save` each), in the same transaction as the edition.
5. **Equivalence:** `cloud_record_equivalence` compares both fields, so a real change is never skipped as "already equal".

## Mixed old/new clients

| Writer → reader | Result |
|---|---|
| Old app writes, new server | Columns untouched; nothing fails (`test.sql`) |
| Old app reads a row with new columns | Ignored; edition maps exactly as before (`supabase_cloud_record_inbound_mapper_test.dart`, run today) |
| New app writes partial + names, old app later changes the date | Names kept; partial no longer matches, so it is ignored, and the old app's exact date stands (`test.sql`) |
| Old app changes the title only | Partial still matches and stays valid; names kept |
| New app, server without the columns | Probe finds none; nothing extra is sent (same as SN-45 today) |
| Two new apps edit names | Last writer wins on the edition record (`updated_at` / `server_revision`), the same as every edition field |

## Backup, restore and conflicts

- **Local backups** already carry both values: `release_date_precision` in `album_editions` and the optional `album_edition_disc_labels` table (restore accepts database versions 31–45). Nothing changes there.
- **Restoring from the cloud** onto a fresh device brings back exact precision and disc names once the app changes above ship. Until then, dates come back as exact days and discs as "Disc N".
- **Conflicts:** editions resolve as whole records; the new fields ride along.
  - A user's manual date keeps its authority through `metadata_field_states`, which already syncs with the edition.
  - A disc-name change made offline on two devices keeps the later write.
  - A conflict never mixes two devices' names.

## Rollback (`rollback.sql`) and its limits

- **What it removes:** both columns, both checks and the function. Nothing else.
- **What's lost:** values held only in the cloud.
  - Devices with a local copy re-upload once the columns return.
  - A device restored from the cloud alone loses its precision and disc names.
- **Timing:** roll back before shipping the app changes if possible. Older apps are unaffected either way.

## Local test (approved; not yet run)

The test runs on its own local stack, `sonus_p12_local`: database only, on ports 556xx, with the 18 migrations from `supabase/migrations`. It never uses another local stack, staging or production.

```
cd /c/dev/sonus/staging/p12-local
../tools/node_modules/.bin/supabase db start      # pinned CLI 2.121.0
./run_p12_local_tests.sh                          # logs: test_runs/au12/p12_local/<time>
../tools/node_modules/.bin/supabase stop --no-backup
```

The runner, in order:
1. Seeds an edition the way today's apps write it.
2. Applies `migration.sql` twice; it must be idempotent.
3. Runs `verify.sql`.
4. Checks the seeded row is unchanged and still NULL in both new columns.
5. Runs `test.sql`, which rolls itself back.
6. Rehearses `rollback.sql` inside a transaction.
7. Rolls back for real, checks the seeded row again, and applies the migration once more.

**Status (2026-11-12): blocked on memory, not on SQL.** Starting Docker Desktop also restarts an older local stack (`supabase_*_sonus_next`, restart policy `unless-stopped`). That left about 0.6–0.9 GB free on this PC, too little for a second stack. Docker Desktop was shut down again and nothing was applied. To run the test, either stop that older stack first (`docker stop`, which keeps its data), or free memory.

## Staging rehearsal (after the local test passes)

Sonus has no hosted staging project. Earlier rehearsals (permanent deletion, 11-08) used an isolated local stack with the Flutter staging harness (`test/integration/staging`), and this one follows the same pattern.

1. Take a fresh local stack, loaded from a schema-only dump of production (or from `supabase/migrations`) plus seeded data. Record `verify.sql` counts.
2. Apply `migration.sql`, then run `verify.sql`: the columns, checks and function are present, no row has a value yet, and counts are unchanged.
3. Mixed clients. With the app changes above built behind the probe, run the staging harness twice:
   - an app without the columns (today's), which must leave both columns untouched;
   - an app with them, which writes a year-only date and disc names, then has today's app change the date.

   Expected results are in the mixed-client table.
4. Backup and restore: export a local backup from the new app, restore it onto a fresh device database, and sign in. Precision and names come back from the local backup; cloud restore brings them back only on new apps.
5. Rehearse `rollback.sql` inside a transaction, then for real. Confirm the other columns and the counts are unchanged, and that today's app still syncs.
6. Only then decide on production. Use the pinned CLI, take a pre-deploy backup and repeat the verify steps. It needs its own approval; nothing here touches production or any account.

Steps 1, 2, 5 and 6 need nothing new. Step 3 needs the app changes listed above, which are not made.

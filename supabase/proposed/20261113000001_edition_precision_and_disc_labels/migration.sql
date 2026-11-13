-- App Update 1.2 (REF-12b, REF-13c): PROPOSED, NOT DEPLOYED.
-- Lives outside supabase/migrations so no CLI push can apply it. Moving it
-- there needs an approved staging rehearsal and a production decision.
--
-- 1. album_editions.release_date_partial: the edition's release date as
--    written, 'YYYY', 'YYYY-MM' or 'YYYY-MM-DD', so the year-only and
--    month-year dates Sonus keeps locally survive the cloud. It is only
--    trusted while it describes release_date exactly: the app reads it
--    when parsing it gives the stored release_date instant (UTC midnight
--    of its first day), and ignores it otherwise. An app that does not know
--    the column can change release_date without touching it; the two then
--    disagree and the partial is ignored, so a stale "year" never sticks to
--    a new exact date. No trigger is needed and old writes never fail.
-- 2. album_editions.disc_labels: the edition's disc names (local SQLite
--    v45 table album_edition_disc_labels) as one JSON object,
--    {"2": "Bonus Tracks"}. NULL means "not provided", never "no names";
--    {} means the edition has no names.
--
-- Additive only. Existing rows keep NULL in both. Sonus writes with upserts
-- that update only the columns they send, so apps without these columns
-- never erase them. Safe to run again: every step is skipped when already
-- applied.

alter table public.album_editions
  add column if not exists release_date_partial text null;

alter table public.album_editions
  add column if not exists disc_labels jsonb null;

-- Disc names: keys are disc numbers (1-999), values non-blank text of at
-- most 200 characters. A function, because CHECK cannot iterate JSON.
create or replace function public.album_edition_disc_labels_valid(labels jsonb)
returns boolean
language sql
immutable
set search_path = ''
as $function$
  select labels is null
    or (
      jsonb_typeof(labels) = 'object'
      and not exists (
        select 1
        from jsonb_each(labels) as entry(disc, label)
        where entry.disc !~ '^[1-9][0-9]{0,2}$'
          or jsonb_typeof(entry.label) <> 'string'
          or length(trim(entry.label #>> '{}')) = 0
          or length(entry.label #>> '{}') > 200
      )
    );
$function$;

do $migration$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.album_editions'::regclass
      and conname = 'album_editions_release_date_partial_format'
  ) then
    alter table public.album_editions
      add constraint album_editions_release_date_partial_format
      check (
        release_date_partial is null
        or release_date_partial ~ '^[0-9]{4}(-[0-9]{2}(-[0-9]{2})?)?$'
      );
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.album_editions'::regclass
      and conname = 'album_editions_disc_labels_valid'
  ) then
    alter table public.album_editions
      add constraint album_editions_disc_labels_valid
      check (public.album_edition_disc_labels_valid(disc_labels));
  end if;
end
$migration$;

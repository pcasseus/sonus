-- Read-only checks after applying 20261108000001.
select public.sonus_capabilities() as capabilities;
select tgrelid::regclass as table_name, tgname
  from pg_trigger
  where tgname like '%_keep_tombstone_final'
  order by 1;
select pg_get_constraintdef(oid) as kind_check
  from pg_constraint
  where conname = 'sonus_archive_records_kind_check';

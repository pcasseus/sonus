-- App Update 1.2 (migration 20261108000001), as the app roles through RLS
-- and grants. Throwaway database only; the test user is fake.
\set ON_ERROR_STOP on
-- Run as the app roles, through RLS and grants.
insert into auth.users (id) values ('11111111-1111-1111-1111-111111111111');
begin;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
do $t$
declare v text[];
begin
  select public.sonus_capabilities() into v;
  if not ('permanent_deletion_v1' = any (v)) then raise exception 'FAIL caps'; end if;
  raise notice 'PASS authenticated can probe';
  insert into public.sonus_archive_records (user_id, kind, record_key, payload, client_updated_at)
    values ('11111111-1111-1111-1111-111111111111', 'listening_session', 's1', '{"t":"x"}', now());
  update public.sonus_archive_records set is_deleted = true, payload = '{}'
    where record_key = 's1';
  begin
    update public.sonus_archive_records set is_deleted = false, payload = '{"t":"x"}'
      where record_key = 's1';
    raise exception 'FAIL revived through RLS';
  exception when insufficient_privilege then
    raise notice 'PASS authenticated cannot revive deleted history';
  end;
  insert into public.sonus_archive_records (user_id, kind, record_key, payload, client_updated_at)
    values ('11111111-1111-1111-1111-111111111111', 'library_deletion', 'op1', '{"entries":[]}', now());
  begin
    update public.sonus_archive_records set payload = '{"entries":[["song","x"]]}'
      where record_key = 'op1';
    raise exception 'FAIL deletion record rewritten';
  exception when insufficient_privilege then
    raise notice 'PASS deletion record is permanent through RLS';
  end;
end $t$;
rollback;
begin;
set local role anon;
do $t$
begin
  perform public.sonus_capabilities();
  raise exception 'FAIL anon can probe';
exception when insufficient_privilege then
  raise notice 'PASS anon cannot call the probe';
end $t$;
rollback;

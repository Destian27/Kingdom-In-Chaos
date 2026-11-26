-- =====================================================================
-- v15 server-side maintenance gate hardening
-- Appended to the v14 super-complete SQL. Idempotent by policy/trigger name.
-- Admin service_role operations remain available while maintenance is active.
-- =====================================================================
begin;

create or replace function public.game_maintenance_is_active()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce((
    select coalesce(m.is_active, true)
       and (m.start_at is null or now() >= m.start_at)
       and (m.end_at is null or now() < m.end_at)
    from public.app_maintenance m
    where m.id = 1
  ), true);
$$;
revoke all on function public.game_maintenance_is_active() from public;
grant execute on function public.game_maintenance_is_active() to anon, authenticated, service_role;

create or replace function public.guard_player_data_during_maintenance()
returns trigger
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare v_role text := coalesce(auth.role(), '');
begin
  -- Authenticated game clients cannot change player data while maintenance is active.
  -- service_role remains available to the admin Edge Function for emergency repairs.
  if v_role in ('anon', 'authenticated') and public.game_maintenance_is_active() then
    raise exception 'GAME_IN_MAINTENANCE: player data operations are disabled';
  end if;
  if tg_op = 'DELETE' then return old; else return new; end if;
end;
$$;
revoke all on function public.guard_player_data_during_maintenance() from public, anon, authenticated;
grant execute on function public.guard_player_data_during_maintenance() to service_role;

do $$
declare v_table text;
        v_tables text[] := array[
          'game_profiles', 'game_player_saves', 'game_presence',
          'game_friendships', 'game_pvp_queue', 'game_pvp_matches',
          'game_world_boss_score_claims'
        ];
begin
  foreach v_table in array v_tables loop
    if to_regclass('public.' || v_table) is not null then
      execute format('drop trigger if exists guard_player_maintenance on public.%I', v_table);
      execute format(
        'create trigger guard_player_maintenance before insert or update or delete on public.%I for each row execute function public.guard_player_data_during_maintenance()',
        v_table
      );
    end if;
  end loop;
end $$;

-- Defense in depth: RLS-based direct reads are hidden while maintenance is active.
-- The admin Edge Function uses service_role and is unaffected by these policies.
drop policy if exists game_profiles_read_authenticated on public.game_profiles;
create policy game_profiles_read_authenticated on public.game_profiles
  for select to authenticated using (not public.game_maintenance_is_active());

drop policy if exists game_player_saves_select_self on public.game_player_saves;
create policy game_player_saves_select_self on public.game_player_saves
  for select to authenticated using (user_id = auth.uid() and not public.game_maintenance_is_active());

drop policy if exists game_presence_read_authenticated on public.game_presence;
create policy game_presence_read_authenticated on public.game_presence
  for select to authenticated using (not public.game_maintenance_is_active());

drop policy if exists game_friendships_read_participant on public.game_friendships;
create policy game_friendships_read_participant on public.game_friendships
  for select to authenticated using (
    not public.game_maintenance_is_active()
    and (requester_id = auth.uid() or addressee_id = auth.uid())
  );

drop policy if exists game_rankings_read_all on public.game_rankings;
create policy game_rankings_read_all on public.game_rankings
  for select to anon, authenticated using (not public.game_maintenance_is_active());

drop policy if exists game_world_boss_scores_read_all on public.game_world_boss_scores;
create policy game_world_boss_scores_read_all on public.game_world_boss_scores
  for select to anon, authenticated using (not public.game_maintenance_is_active());

drop policy if exists game_pvp_matches_read_participant on public.game_pvp_matches;
create policy game_pvp_matches_read_participant on public.game_pvp_matches
  for select to authenticated using (
    not public.game_maintenance_is_active()
    and (player_one = auth.uid() or player_two = auth.uid())
  );

drop policy if exists game_world_boss_cycles_read on public.game_world_boss_cycles;
create policy game_world_boss_cycles_read on public.game_world_boss_cycles
  for select to authenticated using (not public.game_maintenance_is_active());

drop policy if exists game_world_boss_claims_read_own on public.game_world_boss_score_claims;
create policy game_world_boss_claims_read_own on public.game_world_boss_score_claims
  for select to authenticated using (user_id = auth.uid() and not public.game_maintenance_is_active());

drop policy if exists game_pvp_queue_read_self on public.game_pvp_queue;
create policy game_pvp_queue_read_self on public.game_pvp_queue
  for select to authenticated using (user_id = auth.uid() and not public.game_maintenance_is_active());

drop policy if exists game_admin_economy_read_self on public.game_admin_player_economy;
create policy game_admin_economy_read_self on public.game_admin_player_economy
  for select to authenticated using (user_id = auth.uid() and not public.game_maintenance_is_active());

commit;

-- Validation query:
-- select public.game_maintenance_is_active();
-- Expected: true when active/in scheduled window or when the config row is missing;
-- false only when the server confirms the maintenance gate is OFF.

-- Atomic write path for the existing Admin HTML maintenance toggle/clock.
begin;
create or replace function public.admin_update_app_maintenance(
  p_is_active boolean,
  p_title text,
  p_message text,
  p_end_at timestamptz default null
)
returns public.app_maintenance
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_row public.app_maintenance;
begin
  if p_is_active is null then raise exception 'is_active is required'; end if;
  if p_title is null or char_length(btrim(p_title)) not between 1 and 100 then
    raise exception 'Title must contain 1-100 characters';
  end if;
  if p_message is null or char_length(btrim(p_message)) > 2000 then
    raise exception 'Message must contain no more than 2000 characters';
  end if;
  if p_is_active and p_end_at is not null and p_end_at <= now() then
    raise exception 'Active maintenance end time must be in the future';
  end if;
  update public.app_maintenance
     set is_active = p_is_active,
         title = btrim(p_title),
         message = btrim(p_message),
         start_at = null,
         end_at = case when p_is_active then p_end_at else null end,
         updated_at = now()
   where id = 1
   returning * into v_row;
  if not found then raise exception 'Maintenance config is missing'; end if;
  insert into public.app_maintenance_log(is_active, title, message, end_at)
  values(v_row.is_active, v_row.title, v_row.message, v_row.end_at);
  return v_row;
end;
$$;
revoke all on function public.admin_update_app_maintenance(boolean, text, text, timestamptz) from public, anon, authenticated;
grant execute on function public.admin_update_app_maintenance(boolean, text, text, timestamptz) to service_role;
commit;

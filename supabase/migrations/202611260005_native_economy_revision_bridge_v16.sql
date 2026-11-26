-- v16 native currency bridge revision support (run after v15 admin/player schema).
-- Does not overwrite balances until an admin explicitly edits the corresponding currency.
begin;

alter table public.game_admin_player_economy
    add column if not exists coins_admin_revision timestamptz,
    add column if not exists crystals_admin_revision timestamptz,
    add column if not exists goblin_coins_admin_revision timestamptz;

create or replace function public.admin_update_player_economy(
  p_target_user_id uuid,
  p_fields jsonb,
  p_reason text,
  p_admin_user_id uuid
)
returns public.game_admin_player_economy
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_before public.game_admin_player_economy;
  v_after public.game_admin_player_economy;
  v_key text;
  v_allowed text[] := array[
    'coins','crystals','goblin_coins','hero_xp','hero_level','player_xp','player_level',
    'energy','stamina','honor_points','arena_tokens','skill_points','extra_stats'
  ];
begin
  if p_target_user_id is null then raise exception 'Target user ID required'; end if;
  if p_admin_user_id is null or not exists (
    select 1 from public.game_admin_users a
     where a.user_id = p_admin_user_id and a.active = true
  ) then raise exception 'Active admin required'; end if;
  if p_reason is null or char_length(btrim(p_reason)) not between 4 and 500 then
    raise exception 'Reason must contain 4-500 characters';
  end if;
  if p_fields is null or jsonb_typeof(p_fields) <> 'object' or p_fields = '{}'::jsonb then
    raise exception 'Fields must be a non-empty JSON object';
  end if;
  for v_key in select jsonb_object_keys(p_fields) loop
    if not (v_key = any(v_allowed)) then
      raise exception 'Field is not allowed: %', v_key;
    end if;
  end loop;
  if p_fields ? 'extra_stats' and jsonb_typeof(p_fields->'extra_stats') <> 'object' then
    raise exception 'extra_stats must be a JSON object';
  end if;
  if p_fields ? 'coins' and (p_fields->>'coins')::numeric > 2147483647 then
    raise exception 'Coins exceed the native game 32-bit wallet limit';
  end if;
  if p_fields ? 'crystals' and (p_fields->>'crystals')::numeric > 2147483647 then
    raise exception 'Crystals exceed the native game 32-bit wallet limit';
  end if;
  if p_fields ? 'goblin_coins' and (p_fields->>'goblin_coins')::numeric > 2147483647 then
    raise exception 'Goblin Coins exceed the native game 32-bit wallet limit';
  end if;
  if not exists (select 1 from auth.users u where u.id = p_target_user_id) then
    raise exception 'Target user not found';
  end if;

  insert into public.game_admin_player_economy(user_id)
    values (p_target_user_id) on conflict (user_id) do nothing;
  select * into v_before from public.game_admin_player_economy
    where user_id = p_target_user_id for update;

  update public.game_admin_player_economy set
    coins = case when p_fields ? 'coins' then (p_fields->>'coins')::bigint else coins end,
    crystals = case when p_fields ? 'crystals' then (p_fields->>'crystals')::bigint else crystals end,
    goblin_coins = case when p_fields ? 'goblin_coins' then (p_fields->>'goblin_coins')::bigint else goblin_coins end,
    coins_admin_revision = case when p_fields ? 'coins' then now() else coins_admin_revision end,
    crystals_admin_revision = case when p_fields ? 'crystals' then now() else crystals_admin_revision end,
    goblin_coins_admin_revision = case when p_fields ? 'goblin_coins' then now() else goblin_coins_admin_revision end,
    hero_xp = case when p_fields ? 'hero_xp' then (p_fields->>'hero_xp')::bigint else hero_xp end,
    hero_level = case when p_fields ? 'hero_level' then (p_fields->>'hero_level')::integer else hero_level end,
    player_xp = case when p_fields ? 'player_xp' then (p_fields->>'player_xp')::bigint else player_xp end,
    player_level = case when p_fields ? 'player_level' then (p_fields->>'player_level')::integer else player_level end,
    energy = case when p_fields ? 'energy' then (p_fields->>'energy')::bigint else energy end,
    stamina = case when p_fields ? 'stamina' then (p_fields->>'stamina')::bigint else stamina end,
    honor_points = case when p_fields ? 'honor_points' then (p_fields->>'honor_points')::bigint else honor_points end,
    arena_tokens = case when p_fields ? 'arena_tokens' then (p_fields->>'arena_tokens')::bigint else arena_tokens end,
    skill_points = case when p_fields ? 'skill_points' then (p_fields->>'skill_points')::bigint else skill_points end,
    extra_stats = case when p_fields ? 'extra_stats' then p_fields->'extra_stats' else extra_stats end,
    updated_at = now(), updated_by = p_admin_user_id
  where user_id = p_target_user_id returning * into v_after;

  insert into public.game_admin_audit(
    admin_user_id, target_user_id, action, reason, before_data, after_data, created_at
  ) values (
    p_admin_user_id, p_target_user_id, 'economy_update', btrim(p_reason),
    to_jsonb(v_before), to_jsonb(v_after), now()
  );
  return v_after;
end;
$$;
revoke all on function public.admin_update_player_economy(uuid, jsonb, text, uuid) from public, anon, authenticated;
grant execute on function public.admin_update_player_economy(uuid, jsonb, text, uuid) to service_role;

create or replace function public.get_my_game_runtime_state()
returns jsonb
language plpgsql
security invoker
set search_path = public, auth
as $$
declare v_id uuid := auth.uid();
begin
  if v_id is null then raise exception 'Authentication required'; end if;
  return jsonb_build_object(
    'profile', coalesce((select to_jsonb(p) from public.game_profiles p where p.user_id = v_id), '{}'::jsonb),
    'economy', coalesce((
      select jsonb_build_object(
        'coins', e.coins, 'crystals', e.crystals, 'goblin_coins', e.goblin_coins,
        'coins_admin_revision', e.coins_admin_revision,
        'crystals_admin_revision', e.crystals_admin_revision,
        'goblin_coins_admin_revision', e.goblin_coins_admin_revision,
        'hero_xp', e.hero_xp, 'hero_level', e.hero_level, 'player_xp', e.player_xp,
        'player_level', e.player_level, 'energy', e.energy, 'stamina', e.stamina,
        'honor_points', e.honor_points, 'arena_tokens', e.arena_tokens,
        'skill_points', e.skill_points, 'extra_stats', e.extra_stats,
        'updated_at', e.updated_at
      ) from public.game_admin_player_economy e where e.user_id = v_id
    ), '{}'::jsonb),
    'ranking', coalesce((select to_jsonb(r) from public.game_rankings r where r.user_id = v_id), '{}'::jsonb),
    'save', coalesce((select to_jsonb(s) from public.game_player_saves s where s.user_id = v_id), '{}'::jsonb),
    'server_time', clock_timestamp()
  );
end;
$$;
revoke all on function public.get_my_game_runtime_state() from public, anon;
grant execute on function public.get_my_game_runtime_state() to authenticated;

commit;

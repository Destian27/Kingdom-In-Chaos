-- =====================================================================
-- Kingdom in Chaos DTP v17 — Event Shop + Event Eyes + schedule controls
-- Requires the merged v16 SQL. All schedule timestamps are evaluated in WIB.
-- Android Event Shop catalogue/config are published for Supabase Realtime.
-- Purchasing/gear delivery remains disabled until a verified native inventory
-- adapter is added for the matching libgame.so build.
-- =====================================================================
begin;

alter table public.game_admin_player_economy
  add column if not exists event_eyes bigint not null default 0,
  add column if not exists event_eyes_admin_revision timestamptz;

do $$
begin
  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.game_admin_player_economy'::regclass
       and conname = 'game_admin_event_eyes_nonnegative'
  ) then
    alter table public.game_admin_player_economy
      add constraint game_admin_event_eyes_nonnegative check (event_eyes >= 0);
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.game_admin_player_economy'::regclass
       and conname = 'game_admin_event_eyes_native_int32'
  ) then
    alter table public.game_admin_player_economy
      add constraint game_admin_event_eyes_native_int32 check (event_eyes between 0 and 2147483647);
  end if;
end $$;

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
    'coins','crystals','goblin_coins','event_eyes','hero_xp','hero_level','player_xp','player_level',
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
  if p_fields ? 'event_eyes' and (p_fields->>'event_eyes')::numeric > 2147483647 then
    raise exception 'Event Eyes exceed the native game 32-bit wallet limit';
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
    event_eyes = case when p_fields ? 'event_eyes' then (p_fields->>'event_eyes')::bigint else event_eyes end,
    event_eyes_admin_revision = case when p_fields ? 'event_eyes' then now() else event_eyes_admin_revision end,
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

-- Update the existing v16 runtime snapshot contract so the Android JNI bridge
-- receives event_eyes and event_eyes_admin_revision after an admin edit.
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
        'event_eyes', e.event_eyes, 'event_eyes_admin_revision', e.event_eyes_admin_revision,
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

create table if not exists public.game_event_store_config (
  id boolean primary key default true check (id is true),
  enabled boolean not null default false,
  title text not null default 'Halloween Store',
  banner_text text not null default 'Toko Event',
  starts_at timestamptz,
  ends_at timestamptz,
  recurrence text not null default 'once'
    check (recurrence in ('once','daily','weekly')),
  repeat_until timestamptz,
  refresh_minutes smallint not null default 120
    check (refresh_minutes between 1 and 1440),
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now(),
  constraint game_event_store_window_valid
    check (not enabled or (starts_at is not null and ends_at is not null and ends_at > starts_at)),
  constraint game_event_store_repeat_valid
    check (repeat_until is null or starts_at is null or repeat_until >= starts_at)
);

insert into public.game_event_store_config(id, enabled)
values (true, false)
on conflict (id) do nothing;

create table if not exists public.game_event_store_items (
  item_key text primary key check (item_key ~ '^[A-Za-z0-9_-]{1,64}$'),
  item_name text not null check (char_length(btrim(item_name)) between 1 and 80),
  description text not null default '' check (char_length(description) <= 180),
  image_url text not null default '' check (char_length(image_url) <= 2048),
  price_eyes bigint not null default 0 check (price_eyes between 0 and 2147483647),
  item_type text not null default 'gear' check (char_length(item_type) between 1 and 32),
  native_item_id integer,
  item_payload jsonb not null default '{}'::jsonb
    check (jsonb_typeof(item_payload) = 'object'),
  enabled boolean not null default true,
  sort_order integer not null default 0 check (sort_order between 0 and 100000),
  updated_at timestamptz not null default now()
);

create table if not exists public.game_event_store_admin_log (
  log_id bigint generated always as identity primary key,
  admin_user_id uuid references auth.users(id) on delete set null,
  action text not null check (action in ('store_saved','store_enabled','store_disabled')),
  reason text not null check (char_length(btrim(reason)) between 4 and 500),
  details jsonb not null default '{}'::jsonb check (jsonb_typeof(details) = 'object'),
  created_at timestamptz not null default now()
);
create index if not exists game_event_store_admin_log_created_idx
  on public.game_event_store_admin_log(created_at desc);

alter table public.game_event_store_config enable row level security;
alter table public.game_event_store_items enable row level security;
alter table public.game_event_store_admin_log enable row level security;

-- Public event configuration/catalogue is readable by authenticated players so
-- Realtime postgres_changes can authorize subscribers. Writes/logs stay server-only.
revoke all on public.game_event_store_config from public, anon, authenticated;
revoke all on public.game_event_store_items from public, anon, authenticated;
revoke all on public.game_event_store_admin_log from public, anon, authenticated;
grant select on public.game_event_store_config to authenticated;
grant select on public.game_event_store_items to authenticated;
grant select, insert, update, delete on public.game_event_store_config to service_role;
grant select, insert, update, delete on public.game_event_store_items to service_role;
grant select, insert, update, delete on public.game_event_store_admin_log to service_role;
grant usage, select on sequence public.game_event_store_admin_log_log_id_seq to service_role;

drop policy if exists game_event_store_config_read_authenticated on public.game_event_store_config;
create policy game_event_store_config_read_authenticated
  on public.game_event_store_config for select to authenticated using (true);
drop policy if exists game_event_store_items_read_authenticated on public.game_event_store_items;
create policy game_event_store_items_read_authenticated
  on public.game_event_store_items for select to authenticated using (true);

do $$
declare
  v_table text;
  v_tables text[] := array['game_event_store_config', 'game_event_store_items'];
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    foreach v_table in array v_tables loop
      if not exists (
        select 1 from pg_publication_tables
         where pubname = 'supabase_realtime'
           and schemaname = 'public'
           and tablename = v_table
      ) then
        execute format('alter publication supabase_realtime add table public.%I', v_table);
      end if;
      execute format('alter table public.%I replica identity full', v_table);
    end loop;
  else
    raise notice 'supabase_realtime publication is absent; enable Supabase Realtime before using live Event Shop updates.';
  end if;
end $$;

-- Called only by the server-side admin Edge Function (service_role).
create or replace function public.admin_save_event_store(
  p_config jsonb,
  p_items jsonb,
  p_admin_user_id uuid,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_enabled boolean;
  v_title text;
  v_banner text;
  v_starts timestamptz;
  v_ends timestamptz;
  v_recurrence text;
  v_repeat_until timestamptz;
  v_refresh integer;
  v_count integer;
  v_distinct integer;
  v_saved_count integer;
begin
  if p_admin_user_id is null or not exists (
    select 1 from public.game_admin_users a where a.user_id = p_admin_user_id and a.active = true
  ) then raise exception 'Active admin required'; end if;
  if p_reason is null or char_length(btrim(p_reason)) not between 4 and 500 then
    raise exception 'Reason must contain 4-500 characters';
  end if;
  if p_config is null or jsonb_typeof(p_config) <> 'object' then raise exception 'Config must be a JSON object'; end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) > 100 then
    raise exception 'Items must be an array with at most 100 entries';
  end if;

  v_enabled := coalesce((p_config->>'enabled')::boolean, false);
  v_title := btrim(coalesce(p_config->>'title',''));
  v_banner := btrim(coalesce(p_config->>'banner_text',''));
  v_recurrence := coalesce(p_config->>'recurrence','once');
  v_refresh := coalesce((p_config->>'refresh_minutes')::integer,120);
  v_starts := nullif(p_config->>'starts_at','')::timestamptz;
  v_ends := nullif(p_config->>'ends_at','')::timestamptz;
  v_repeat_until := nullif(p_config->>'repeat_until','')::timestamptz;

  if char_length(v_title) not between 1 and 80 then raise exception 'Title must contain 1-80 characters'; end if;
  if char_length(v_banner) not between 1 and 160 then raise exception 'Banner text must contain 1-160 characters'; end if;
  if v_recurrence not in ('once','daily','weekly') then raise exception 'Invalid recurrence'; end if;
  if v_refresh not between 1 and 1440 then raise exception 'Refresh interval must be 1-1440 minutes'; end if;
  if v_enabled and (v_starts is null or v_ends is null or v_ends <= v_starts) then
    raise exception 'Enabled event needs a valid start and end date';
  end if;
  if v_enabled and (v_ends - v_starts) > interval '30 days' then
    raise exception 'A single event duration cannot exceed 30 days';
  end if;
  if v_repeat_until is not null and v_starts is not null and v_repeat_until < v_starts then
    raise exception 'Repeat-until must not be earlier than the first start';
  end if;

  select count(*), count(distinct x.item_key)
    into v_count, v_distinct
  from jsonb_to_recordset(p_items) as x(
    item_key text, item_name text, description text, image_url text,
    price_eyes numeric, item_type text, native_item_id integer,
    item_payload jsonb, enabled boolean, sort_order integer
  );
  if v_count <> v_distinct then raise exception 'Duplicate item_key values are not allowed'; end if;
  if exists (
    select 1 from jsonb_to_recordset(p_items) as x(
      item_key text, item_name text, description text, image_url text,
      price_eyes numeric, item_type text, native_item_id integer,
      item_payload jsonb, enabled boolean, sort_order integer
    )
    where coalesce(x.item_key,'') !~ '^[A-Za-z0-9_-]{1,64}$'
       or char_length(btrim(coalesce(x.item_name,''))) not between 1 and 80
       or char_length(coalesce(x.description,'')) > 180
       or char_length(coalesce(x.image_url,'')) > 2048
       or (coalesce(x.image_url,'') <> '' and x.image_url not like 'https://%')
       or x.price_eyes is null or x.price_eyes < 0 or x.price_eyes > 2147483647
       or x.price_eyes <> trunc(x.price_eyes)
       or char_length(coalesce(x.item_type,'')) not between 1 and 32
       or coalesce(jsonb_typeof(x.item_payload),'') <> 'object'
       or x.enabled is null
       or x.sort_order is null or x.sort_order not between 0 and 100000
  ) then raise exception 'One or more event shop items contain invalid values'; end if;

  insert into public.game_event_store_config(
    id, enabled, title, banner_text, starts_at, ends_at, recurrence,
    repeat_until, refresh_minutes, updated_by, updated_at
  ) values (
    true, v_enabled, v_title, v_banner, v_starts, v_ends, v_recurrence,
    v_repeat_until, v_refresh, p_admin_user_id, now()
  ) on conflict (id) do update set
    enabled = excluded.enabled, title = excluded.title, banner_text = excluded.banner_text,
    starts_at = excluded.starts_at, ends_at = excluded.ends_at,
    recurrence = excluded.recurrence, repeat_until = excluded.repeat_until,
    refresh_minutes = excluded.refresh_minutes, updated_by = excluded.updated_by,
    updated_at = now();

  delete from public.game_event_store_items;
  insert into public.game_event_store_items(
    item_key, item_name, description, image_url, price_eyes, item_type,
    native_item_id, item_payload, enabled, sort_order, updated_at
  )
  select x.item_key, btrim(x.item_name), coalesce(x.description,''), coalesce(x.image_url,''),
    x.price_eyes::bigint, x.item_type, x.native_item_id,
    coalesce(x.item_payload,'{}'::jsonb), x.enabled, x.sort_order, now()
  from jsonb_to_recordset(p_items) as x(
    item_key text, item_name text, description text, image_url text,
    price_eyes numeric, item_type text, native_item_id integer,
    item_payload jsonb, enabled boolean, sort_order integer
  );

  select count(*) into v_saved_count from public.game_event_store_items;
  insert into public.game_event_store_admin_log(admin_user_id, action, reason, details)
  values (p_admin_user_id,
    case when v_enabled then 'store_enabled' else 'store_disabled' end,
    btrim(p_reason),
    jsonb_build_object('enabled',v_enabled,'title',v_title,'recurrence',v_recurrence,'items',v_saved_count,
                       'starts_at',v_starts,'ends_at',v_ends,'repeat_until',v_repeat_until));
  return jsonb_build_object('config', (select to_jsonb(c) from public.game_event_store_config c where c.id = true),
                            'items', (select coalesce(jsonb_agg(to_jsonb(i) order by i.sort_order,i.item_key),'[]'::jsonb) from public.game_event_store_items i),
                            'saved_items',v_saved_count);
end;
$$;

revoke all on function public.admin_save_event_store(jsonb,jsonb,uuid,text) from public, anon, authenticated;
grant execute on function public.admin_save_event_store(jsonb,jsonb,uuid,text) to service_role;

-- Authenticated client RPC. Recurrence is evaluated against Asia/Jakarta wall time.
create or replace function public.get_active_event_store()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_user uuid := auth.uid();
  v_cfg public.game_event_store_config;
  v_now_local timestamp without time zone := now() at time zone 'Asia/Jakarta';
  v_start_local timestamp without time zone;
  v_candidate_local timestamp without time zone;
  v_duration interval;
  v_cycle_start timestamptz;
  v_cycle_end timestamptz;
  v_refresh_at timestamptz;
  v_active boolean := false;
  v_eyes bigint := 0;
  v_items jsonb := '[]'::jsonb;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  select coalesce(e.event_eyes,0) into v_eyes
    from public.game_admin_player_economy e where e.user_id = v_user;
  v_eyes := coalesce(v_eyes,0);

  if to_regprocedure('public.game_maintenance_is_active()') is not null then
    if public.game_maintenance_is_active() then
      return jsonb_build_object('active',false,'reason','maintenance','event_eyes',v_eyes,'items','[]'::jsonb);
    end if;
  end if;

  select * into v_cfg from public.game_event_store_config where id = true;
  if not found or not v_cfg.enabled then
    return jsonb_build_object('active',false,'reason','disabled','event_eyes',v_eyes,'items','[]'::jsonb);
  end if;

  v_duration := v_cfg.ends_at - v_cfg.starts_at;
  v_start_local := v_cfg.starts_at at time zone 'Asia/Jakarta';
  if v_cfg.recurrence = 'once' then
    v_cycle_start := v_cfg.starts_at;
    v_cycle_end := v_cfg.ends_at;
  elsif v_cfg.recurrence = 'daily' then
    v_candidate_local := date_trunc('day',v_now_local) + (v_start_local::time - time '00:00');
    if v_candidate_local > v_now_local then v_candidate_local := v_candidate_local - interval '1 day'; end if;
    -- Do not allow a daily recurrence to appear before its configured first start.
    if v_candidate_local < v_start_local then v_candidate_local := v_start_local; end if;
    v_cycle_start := v_candidate_local at time zone 'Asia/Jakarta';
    v_cycle_end := v_cycle_start + v_duration;
  else
    v_candidate_local := date_trunc('week',v_now_local)
      + make_interval(days => extract(isodow from v_start_local)::integer - 1)
      + (v_start_local::time - time '00:00');
    if v_candidate_local > v_now_local then v_candidate_local := v_candidate_local - interval '7 days'; end if;
    -- Likewise, the first weekly cycle cannot precede the initial configured date.
    if v_candidate_local < v_start_local then v_candidate_local := v_start_local; end if;
    v_cycle_start := v_candidate_local at time zone 'Asia/Jakarta';
    v_cycle_end := v_cycle_start + v_duration;
  end if;

  v_active := now() >= v_cycle_start and now() < v_cycle_end
    and (v_cfg.repeat_until is null or v_cycle_start <= v_cfg.repeat_until);
  if v_active then
    v_refresh_at := v_cycle_start + make_interval(mins =>
      (floor(extract(epoch from (now() - v_cycle_start)) / (v_cfg.refresh_minutes * 60))::integer + 1)
        * v_cfg.refresh_minutes);
    select coalesce(jsonb_agg(jsonb_build_object(
      'item_key',i.item_key,'item_name',i.item_name,'description',i.description,
      'image_url',i.image_url,'price_eyes',i.price_eyes,'item_type',i.item_type,
      'native_item_id',i.native_item_id,'item_payload',i.item_payload,'sort_order',i.sort_order
    ) order by i.sort_order,i.item_key),'[]'::jsonb)
    into v_items from public.game_event_store_items i where i.enabled = true;
  end if;

  return jsonb_build_object(
    'active',v_active,
    'reason',case when v_active then 'scheduled' else 'outside_schedule' end,
    'title',v_cfg.title,'banner_text',v_cfg.banner_text,
    'recurrence',v_cfg.recurrence,'refresh_minutes',v_cfg.refresh_minutes,
    'starts_at',v_cycle_start,'ends_at',v_cycle_end,
    'server_now',now(),'refresh_at',v_refresh_at,'event_eyes',v_eyes,'items',v_items
  );
end;
$$;
revoke all on function public.get_active_event_store() from public, anon;
grant execute on function public.get_active_event_store() to authenticated, service_role;

commit;

-- Quick validation after migration:
-- select public.get_active_event_store(); -- run from an authenticated player session
-- select * from public.game_event_store_config;
-- select * from public.game_event_store_items order by sort_order;

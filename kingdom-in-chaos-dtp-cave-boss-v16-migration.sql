-- =====================================================================
-- Kingdom in Chaos DTP — v16 Cave Boss Scheduler
-- Jalankan SETELAH SQL All-in-One v15 / schema admin game sudah ada.
-- Semua jam jadwal memakai Asia/Jakarta (WIB, UTC+7).
-- =====================================================================
begin;

create table if not exists public.game_cave_boss_hourly_schedule (
  hour_local smallint primary key check (hour_local between 0 and 23),
  enabled boolean not null default false,
  boss_id text not null default '',
  boss_name text not null default '',
  difficulty text not null default 'normal'
    check (difficulty in ('normal','hard','elite','nightmare','custom')),
  hp_multiplier numeric(12,3) not null default 1.000
    check (hp_multiplier >= 0.100 and hp_multiplier <= 10000.000),
  spawn_minutes smallint not null default 60 check (spawn_minutes between 1 and 60),
  reward_config jsonb not null default '{}'::jsonb
    check (jsonb_typeof(reward_config) = 'object'),
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now(),
  constraint game_cave_boss_slot_boss_required
    check (not enabled or (char_length(btrim(boss_id)) between 1 and 80 and char_length(btrim(boss_name)) between 1 and 120))
);

insert into public.game_cave_boss_hourly_schedule (hour_local)
select generate_series(0,23)::smallint
on conflict (hour_local) do nothing;

create table if not exists public.game_cave_boss_override (
  id boolean primary key default true check (id is true),
  enabled boolean not null default false,
  boss_id text not null default '',
  boss_name text not null default '',
  difficulty text not null default 'normal'
    check (difficulty in ('normal','hard','elite','nightmare','custom')),
  hp_multiplier numeric(12,3) not null default 1.000
    check (hp_multiplier >= 0.100 and hp_multiplier <= 10000.000),
  spawn_minutes smallint not null default 30 check (spawn_minutes between 1 and 180),
  reward_config jsonb not null default '{}'::jsonb
    check (jsonb_typeof(reward_config) = 'object'),
  starts_at timestamptz,
  expires_at timestamptz,
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now(),
  constraint game_cave_boss_override_boss_required
    check (not enabled or (char_length(btrim(boss_id)) between 1 and 80 and char_length(btrim(boss_name)) between 1 and 120 and starts_at is not null and expires_at > starts_at))
);

insert into public.game_cave_boss_override (id, enabled)
values (true, false)
on conflict (id) do nothing;

create table if not exists public.game_cave_boss_admin_log (
  log_id uuid primary key default gen_random_uuid(),
  admin_user_id uuid references auth.users(id) on delete set null,
  action text not null check (action in ('schedule_saved','override_started','override_cleared')),
  reason text not null check (char_length(btrim(reason)) between 4 and 500),
  details jsonb not null default '{}'::jsonb check (jsonb_typeof(details) = 'object'),
  created_at timestamptz not null default now()
);
create index if not exists game_cave_boss_admin_log_created_idx
  on public.game_cave_boss_admin_log (created_at desc);

alter table public.game_cave_boss_hourly_schedule enable row level security;
alter table public.game_cave_boss_override enable row level security;
alter table public.game_cave_boss_admin_log enable row level security;

-- Pemain hanya dapat membaca jadwal/config, bukan mengubahnya langsung.
drop policy if exists game_cave_boss_schedule_read on public.game_cave_boss_hourly_schedule;
create policy game_cave_boss_schedule_read on public.game_cave_boss_hourly_schedule
  for select to authenticated using (true);
drop policy if exists game_cave_boss_override_read on public.game_cave_boss_override;
create policy game_cave_boss_override_read on public.game_cave_boss_override
  for select to authenticated using (true);

revoke all on public.game_cave_boss_hourly_schedule from anon, authenticated;
revoke all on public.game_cave_boss_override from anon, authenticated;
revoke all on public.game_cave_boss_admin_log from anon, authenticated;
grant select on public.game_cave_boss_hourly_schedule to authenticated;
grant select on public.game_cave_boss_override to authenticated;
grant select, insert, update, delete on public.game_cave_boss_hourly_schedule to service_role;
grant select, insert, update, delete on public.game_cave_boss_override to service_role;
grant select, insert, update, delete on public.game_cave_boss_admin_log to service_role;

-- Hanya server tepercaya yang menulis 24 jam jadwal dalam satu transaksi.
create or replace function public.admin_save_cave_boss_hourly_schedule(
  p_hours jsonb,
  p_admin_user_id uuid,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_saved jsonb;
  v_enabled_count integer;
  v_slot_count integer;
  v_distinct_count integer;
begin
  if p_admin_user_id is null then raise exception 'Admin user ID is required'; end if;
  if p_reason is null or char_length(btrim(p_reason)) not between 4 and 500 then
    raise exception 'Reason must contain 4-500 characters';
  end if;
  if p_hours is null or jsonb_typeof(p_hours) <> 'array' or jsonb_array_length(p_hours) <> 24 then
    raise exception 'Exactly 24 hourly slots are required';
  end if;
  select count(*), count(distinct x.hour_local)
    into v_slot_count, v_distinct_count
  from jsonb_to_recordset(p_hours) as x(
    hour_local integer, enabled boolean, boss_id text, boss_name text,
    difficulty text, hp_multiplier numeric, spawn_minutes integer, reward_config jsonb
  );
  if v_slot_count <> 24 or v_distinct_count <> 24 then
    raise exception 'Hours 0-23 must each appear exactly once';
  end if;
  if exists (
    select 1 from jsonb_to_recordset(p_hours) as x(
      hour_local integer, enabled boolean, boss_id text, boss_name text,
      difficulty text, hp_multiplier numeric, spawn_minutes integer, reward_config jsonb
    )
    where x.hour_local < 0 or x.hour_local > 23
       or x.enabled is null
       or coalesce(x.difficulty,'') not in ('normal','hard','elite','nightmare','custom')
       or x.hp_multiplier is null or x.hp_multiplier < 0.100 or x.hp_multiplier > 10000.000
       or x.spawn_minutes is null or x.spawn_minutes < 1 or x.spawn_minutes > 60
       or coalesce(jsonb_typeof(x.reward_config), '') <> 'object'
       or (x.enabled and (char_length(btrim(coalesce(x.boss_id,''))) not between 1 and 80
                        or char_length(btrim(coalesce(x.boss_name,''))) not between 1 and 120))
  ) then raise exception 'One or more cave boss slots have invalid values'; end if;

  insert into public.game_cave_boss_hourly_schedule (
    hour_local, enabled, boss_id, boss_name, difficulty, hp_multiplier,
    spawn_minutes, reward_config, updated_by, updated_at
  )
  select x.hour_local::smallint, x.enabled, btrim(coalesce(x.boss_id,'')), btrim(coalesce(x.boss_name,'')),
         x.difficulty, x.hp_multiplier, x.spawn_minutes,
         coalesce(x.reward_config, '{}'::jsonb), p_admin_user_id, now()
  from jsonb_to_recordset(p_hours) as x(
    hour_local integer, enabled boolean, boss_id text, boss_name text,
    difficulty text, hp_multiplier numeric, spawn_minutes integer, reward_config jsonb
  )
  on conflict (hour_local) do update set
    enabled = excluded.enabled,
    boss_id = excluded.boss_id,
    boss_name = excluded.boss_name,
    difficulty = excluded.difficulty,
    hp_multiplier = excluded.hp_multiplier,
    spawn_minutes = excluded.spawn_minutes,
    reward_config = excluded.reward_config,
    updated_by = excluded.updated_by,
    updated_at = now();

  select count(*) filter (where enabled)
    into v_enabled_count from public.game_cave_boss_hourly_schedule;
  select coalesce(jsonb_agg(to_jsonb(s) order by s.hour_local), '[]'::jsonb)
    into v_saved from public.game_cave_boss_hourly_schedule s;
  insert into public.game_cave_boss_admin_log(admin_user_id, action, reason, details)
  values (p_admin_user_id, 'schedule_saved', btrim(p_reason),
          jsonb_build_object('enabled_slots', v_enabled_count, 'updated_slots', 24));
  return v_saved;
end;
$$;

create or replace function public.admin_set_cave_boss_override(
  p_boss_id text,
  p_boss_name text,
  p_difficulty text,
  p_hp_multiplier numeric,
  p_duration_minutes integer,
  p_reward_config jsonb,
  p_admin_user_id uuid,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare v_row public.game_cave_boss_override;
begin
  if p_admin_user_id is null then raise exception 'Admin user ID is required'; end if;
  if char_length(btrim(coalesce(p_boss_id,''))) not between 1 and 80 then raise exception 'Boss ID must contain 1-80 characters'; end if;
  if char_length(btrim(coalesce(p_boss_name,''))) not between 1 and 120 then raise exception 'Boss name must contain 1-120 characters'; end if;
  if p_difficulty not in ('normal','hard','elite','nightmare','custom') then raise exception 'Invalid difficulty'; end if;
  if p_hp_multiplier is null or p_hp_multiplier < 0.100 or p_hp_multiplier > 10000.000 then raise exception 'Invalid HP multiplier'; end if;
  if p_duration_minutes is null or p_duration_minutes not between 1 and 180 then raise exception 'Duration must be 1-180 minutes'; end if;
  if p_reward_config is null or jsonb_typeof(p_reward_config) <> 'object' then raise exception 'Reward config must be a JSON object'; end if;
  if p_reason is null or char_length(btrim(p_reason)) not between 4 and 500 then raise exception 'Reason must contain 4-500 characters'; end if;

  insert into public.game_cave_boss_override (
    id, enabled, boss_id, boss_name, difficulty, hp_multiplier, spawn_minutes,
    reward_config, starts_at, expires_at, updated_by, updated_at
  ) values (
    true, true, btrim(p_boss_id), btrim(p_boss_name), p_difficulty, p_hp_multiplier,
    p_duration_minutes::smallint, p_reward_config, now(), now() + make_interval(mins => p_duration_minutes),
    p_admin_user_id, now()
  ) on conflict (id) do update set
    enabled = true, boss_id = excluded.boss_id, boss_name = excluded.boss_name,
    difficulty = excluded.difficulty, hp_multiplier = excluded.hp_multiplier,
    spawn_minutes = excluded.spawn_minutes, reward_config = excluded.reward_config,
    starts_at = excluded.starts_at, expires_at = excluded.expires_at,
    updated_by = excluded.updated_by, updated_at = now()
  returning * into v_row;

  insert into public.game_cave_boss_admin_log(admin_user_id, action, reason, details)
  values (p_admin_user_id, 'override_started', btrim(p_reason),
    jsonb_build_object('boss_id', v_row.boss_id, 'boss_name', v_row.boss_name,
      'difficulty', v_row.difficulty, 'hp_multiplier', v_row.hp_multiplier,
      'duration_minutes', p_duration_minutes, 'expires_at', v_row.expires_at));
  return to_jsonb(v_row);
end;
$$;

create or replace function public.admin_clear_cave_boss_override(
  p_admin_user_id uuid,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare v_row public.game_cave_boss_override;
begin
  if p_admin_user_id is null then raise exception 'Admin user ID is required'; end if;
  if p_reason is null or char_length(btrim(p_reason)) not between 4 and 500 then raise exception 'Reason must contain 4-500 characters'; end if;
  insert into public.game_cave_boss_override(id, enabled, boss_id, boss_name, difficulty, hp_multiplier, spawn_minutes, reward_config)
  values(true, false, '', '', 'normal', 1.000, 30, '{}'::jsonb)
  on conflict (id) do nothing;
  update public.game_cave_boss_override
    set enabled = false, starts_at = null, expires_at = null,
        updated_by = p_admin_user_id, updated_at = now()
    where id = true returning * into v_row;
  insert into public.game_cave_boss_admin_log(admin_user_id, action, reason, details)
  values (p_admin_user_id, 'override_cleared', btrim(p_reason),
    jsonb_build_object('boss_id', v_row.boss_id, 'boss_name', v_row.boss_name));
  return to_jsonb(v_row);
end;
$$;

-- RPC runtime untuk klien game: manual override menang; bila kosong, pilih slot WIB sekarang.
-- Klien game wajib memanggil RPC ini dan menghubungkan hasilnya ke logika mode gua.
create or replace function public.get_active_cave_boss()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_now_wib timestamp without time zone := now() at time zone 'Asia/Jakarta';
  v_hour integer;
  v_slot public.game_cave_boss_hourly_schedule;
  v_override public.game_cave_boss_override;
  v_maintenance boolean := false;
  v_hour_start timestamp without time zone;
begin
  -- Compatibility with v14/v15: maintenance gate is checked when installed.
  if to_regprocedure('public.game_maintenance_is_active()') is not null then
    execute 'select public.game_maintenance_is_active()' into v_maintenance;
    if coalesce(v_maintenance, true) then
      return jsonb_build_object('active', false, 'reason', 'maintenance');
    end if;
  end if;

  select * into v_override from public.game_cave_boss_override where id = true;
  if found and v_override.enabled and v_override.starts_at <= now() and v_override.expires_at > now() then
    return jsonb_build_object(
      'active', true, 'source', 'manual_override',
      'boss_id', v_override.boss_id, 'boss_name', v_override.boss_name,
      'difficulty', v_override.difficulty, 'hp_multiplier', v_override.hp_multiplier,
      'spawn_minutes', v_override.spawn_minutes, 'reward_config', v_override.reward_config,
      'starts_at', v_override.starts_at, 'ends_at', v_override.expires_at,
      'cycle_id', 'cave-manual-' || to_char(v_override.starts_at at time zone 'Asia/Jakarta', 'YYYYMMDDHH24MISS')
    );
  end if;

  v_hour := extract(hour from v_now_wib)::integer;
  select * into v_slot from public.game_cave_boss_hourly_schedule where hour_local = v_hour;
  if not found or not v_slot.enabled then
    return jsonb_build_object('active', false, 'source', 'hourly_schedule', 'hour_local', v_hour, 'reason', 'no_boss_scheduled');
  end if;
  if extract(minute from v_now_wib)::integer >= v_slot.spawn_minutes then
    return jsonb_build_object('active', false, 'source', 'hourly_schedule', 'hour_local', v_hour, 'reason', 'duration_elapsed');
  end if;
  v_hour_start := date_trunc('hour', v_now_wib);
  return jsonb_build_object(
    'active', true, 'source', 'hourly_schedule', 'hour_local', v_hour,
    'boss_id', v_slot.boss_id, 'boss_name', v_slot.boss_name,
    'difficulty', v_slot.difficulty, 'hp_multiplier', v_slot.hp_multiplier,
    'spawn_minutes', v_slot.spawn_minutes, 'reward_config', v_slot.reward_config,
    'starts_at', timezone('Asia/Jakarta', v_hour_start),
    'ends_at', timezone('Asia/Jakarta', v_hour_start + make_interval(mins => v_slot.spawn_minutes)),
    'cycle_id', 'cave-' || to_char(v_now_wib, 'YYYYMMDDHH24')
  );
end;
$$;

revoke all on function public.admin_save_cave_boss_hourly_schedule(jsonb, uuid, text) from public, anon, authenticated;
revoke all on function public.admin_set_cave_boss_override(text, text, text, numeric, integer, jsonb, uuid, text) from public, anon, authenticated;
revoke all on function public.admin_clear_cave_boss_override(uuid, text) from public, anon, authenticated;
revoke all on function public.get_active_cave_boss() from public, anon;
grant execute on function public.admin_save_cave_boss_hourly_schedule(jsonb, uuid, text) to service_role;
grant execute on function public.admin_set_cave_boss_override(text, text, text, numeric, integer, jsonb, uuid, text) to service_role;
grant execute on function public.admin_clear_cave_boss_override(uuid, text) to service_role;
grant execute on function public.get_active_cave_boss() to authenticated, service_role;

-- Allow client apps to receive realtime notifications for the non-sensitive schedule tables.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'game_cave_boss_hourly_schedule') then
      execute 'alter publication supabase_realtime add table public.game_cave_boss_hourly_schedule';
    end if;
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'game_cave_boss_override') then
      execute 'alter publication supabase_realtime add table public.game_cave_boss_override';
    end if;
  end if;
end $$;

commit;

-- Check current state (must be logged in as an authenticated user):
-- select public.get_active_cave_boss();
-- Schedule writes use the admin Edge Function only; do not expose service_role in APK/browser.

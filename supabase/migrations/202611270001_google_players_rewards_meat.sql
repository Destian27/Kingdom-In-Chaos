-- Kingdom In Chaos DTP v17.13
-- Direct Google player identity (no Supabase Auth for players), reward codes,
-- server-owned DM/coin wallet, and 5-minute meat regeneration.
-- Supabase Auth remains only for the separate Admin dashboard session.
begin;

create table if not exists public.game_google_players (
  player_uuid uuid primary key default gen_random_uuid(),
  player_id bigint generated always as identity unique,
  google_sub text not null unique,
  email text not null,
  email_verified boolean not null default false,
  google_name text not null default '',
  avatar_url text not null default '',
  nickname text,
  profile_completed boolean not null default false,
  game_avatar_id integer not null default 1 check (game_avatar_id >= 0),
  region text not null default 'ID',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint game_google_player_email_nonempty check (char_length(btrim(email)) > 2),
  constraint game_google_player_nickname_length check (nickname is null or char_length(btrim(nickname)) between 3 and 32)
);
create unique index if not exists game_google_players_nickname_ci_uq
  on public.game_google_players(lower(nickname)) where nickname is not null;
create index if not exists game_google_players_created_idx
  on public.game_google_players(created_at desc);

create table if not exists public.game_google_player_economy (
  player_uuid uuid primary key references public.game_google_players(player_uuid) on delete cascade,
  coins bigint not null default 0 check (coins >= 0),
  crystals bigint not null default 0 check (crystals >= 0),
  goblin_coins bigint not null default 0 check (goblin_coins >= 0),
  meat integer not null default 24 check (meat >= 0 and meat <= 24),
  meat_last_regen_at timestamptz not null default now(),
  energy bigint not null default 0 check (energy >= 0),
  stamina bigint not null default 0 check (stamina >= 0),
  player_level integer not null default 1 check (player_level >= 1),
  player_xp bigint not null default 0 check (player_xp >= 0),
  updated_at timestamptz not null default now()
);

create table if not exists public.game_meat_config (
  id boolean primary key default true check (id),
  capacity integer not null default 24 check (capacity between 1 and 100),
  regen_seconds integer not null default 300 check (regen_seconds between 30 and 86400),
  dm_per_meat integer not null default 1 check (dm_per_meat between 1 and 100000),
  updated_at timestamptz not null default now()
);
insert into public.game_meat_config(id) values(true) on conflict(id) do nothing;

create table if not exists public.game_reward_codes (
  code_id uuid primary key default gen_random_uuid(),
  code text not null unique,
  reward_config jsonb not null default '{}'::jsonb check (jsonb_typeof(reward_config) = 'object'),
  enabled boolean not null default true,
  max_uses integer not null default 1 check (max_uses between 1 and 10000000),
  uses_count integer not null default 0 check (uses_count >= 0),
  starts_at timestamptz,
  expires_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint game_reward_code_format check (code = upper(code) and code ~ '^[A-Z0-9-]{4,40}$'),
  constraint game_reward_code_time check (expires_at is null or starts_at is null or expires_at > starts_at)
);
create index if not exists game_reward_codes_active_idx
  on public.game_reward_codes(enabled, starts_at, expires_at);

create table if not exists public.game_reward_code_claims (
  claim_id uuid primary key default gen_random_uuid(),
  code_id uuid not null references public.game_reward_codes(code_id) on delete cascade,
  player_uuid uuid not null references public.game_google_players(player_uuid) on delete cascade,
  reward_applied jsonb not null default '{}'::jsonb,
  claimed_at timestamptz not null default now(),
  unique(code_id, player_uuid)
);
create index if not exists game_reward_claims_player_idx
  on public.game_reward_code_claims(player_uuid, claimed_at desc);

create table if not exists public.game_reward_code_admin_log (
  log_id bigint generated always as identity primary key,
  code_id uuid references public.game_reward_codes(code_id) on delete set null,
  admin_user_id uuid references auth.users(id) on delete set null,
  action text not null,
  reason text not null check (char_length(btrim(reason)) between 4 and 500),
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

-- Player tables are only accessed by trusted Edge Functions using service_role.
alter table public.game_google_players enable row level security;
alter table public.game_google_player_economy enable row level security;
alter table public.game_meat_config enable row level security;
alter table public.game_reward_codes enable row level security;
alter table public.game_reward_code_claims enable row level security;
alter table public.game_reward_code_admin_log enable row level security;
revoke all on public.game_google_players from public, anon, authenticated;
revoke all on public.game_google_player_economy from public, anon, authenticated;
revoke all on public.game_meat_config from public, anon, authenticated;
revoke all on public.game_reward_codes from public, anon, authenticated;
revoke all on public.game_reward_code_claims from public, anon, authenticated;
revoke all on public.game_reward_code_admin_log from public, anon, authenticated;
grant select, insert, update, delete on public.game_google_players to service_role;
grant select, insert, update, delete on public.game_google_player_economy to service_role;
grant select, insert, update, delete on public.game_meat_config to service_role;
grant select, insert, update, delete on public.game_reward_codes to service_role;
grant select, insert, update, delete on public.game_reward_code_claims to service_role;
grant select, insert, update, delete on public.game_reward_code_admin_log to service_role;
grant usage, select on sequence public.game_reward_code_admin_log_log_id_seq to service_role;

create or replace function public.game_google_regenerate_meat(p_player_uuid uuid)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_cfg public.game_meat_config;
  v_row public.game_google_player_economy;
  v_periods bigint;
  v_next integer;
begin
  select * into v_cfg from public.game_meat_config where id = true;
  if not found then
    v_cfg.capacity := 24; v_cfg.regen_seconds := 300; v_cfg.dm_per_meat := 1;
  end if;
  select * into v_row from public.game_google_player_economy where player_uuid = p_player_uuid for update;
  if not found then raise exception 'Player wallet not found'; end if;
  if v_row.meat >= v_cfg.capacity then
    update public.game_google_player_economy set meat = v_cfg.capacity, meat_last_regen_at = now(), updated_at = now()
      where player_uuid = p_player_uuid;
    return;
  end if;
  v_periods := floor(greatest(0, extract(epoch from (now() - v_row.meat_last_regen_at))) / v_cfg.regen_seconds)::bigint;
  if v_periods > 0 then
    v_next := least(v_cfg.capacity, v_row.meat + v_periods)::integer;
    update public.game_google_player_economy set
      meat = v_next,
      meat_last_regen_at = case when v_next >= v_cfg.capacity then now()
        else meat_last_regen_at + make_interval(secs => (v_periods * v_cfg.regen_seconds)::integer) end,
      updated_at = now()
    where player_uuid = p_player_uuid;
  end if;
end;
$$;
revoke all on function public.game_google_regenerate_meat(uuid) from public, anon, authenticated;
grant execute on function public.game_google_regenerate_meat(uuid) to service_role;

create or replace function public.game_google_player_state(p_google_sub text)
returns jsonb
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_player public.game_google_players;
  v_wallet public.game_google_player_economy;
  v_cfg public.game_meat_config;
  v_seconds integer := 0;
begin
  select * into v_player from public.game_google_players where google_sub = p_google_sub;
  if not found then raise exception 'Google player not found'; end if;
  insert into public.game_google_player_economy(player_uuid) values(v_player.player_uuid) on conflict do nothing;
  perform public.game_google_regenerate_meat(v_player.player_uuid);
  select * into v_wallet from public.game_google_player_economy where player_uuid = v_player.player_uuid;
  select * into v_cfg from public.game_meat_config where id = true;
  if v_wallet.meat < coalesce(v_cfg.capacity, 24) then
    v_seconds := greatest(0, coalesce(v_cfg.regen_seconds, 300) - floor(extract(epoch from (now() - v_wallet.meat_last_regen_at)))::integer);
  end if;
  return jsonb_build_object(
    'profile', to_jsonb(v_player),
    'economy', to_jsonb(v_wallet),
    'meat_capacity', coalesce(v_cfg.capacity,24),
    'meat_regen_seconds', coalesce(v_cfg.regen_seconds,300),
    'meat_seconds_to_next', v_seconds,
    'dm_per_meat', coalesce(v_cfg.dm_per_meat,1)
  );
end;
$$;
revoke all on function public.game_google_player_state(text) from public, anon, authenticated;
grant execute on function public.game_google_player_state(text) to service_role;

create or replace function public.game_google_buy_meat(p_google_sub text, p_amount integer)
returns jsonb
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_player public.game_google_players;
  v_wallet public.game_google_player_economy;
  v_cfg public.game_meat_config;
  v_cost bigint;
begin
  if p_amount is null or p_amount < 1 or p_amount > 24 then raise exception 'Jumlah daging harus 1-24'; end if;
  select * into v_player from public.game_google_players where google_sub = p_google_sub;
  if not found then raise exception 'Google player not found'; end if;
  perform public.game_google_regenerate_meat(v_player.player_uuid);
  select * into v_cfg from public.game_meat_config where id = true;
  select * into v_wallet from public.game_google_player_economy where player_uuid = v_player.player_uuid for update;
  if v_wallet.meat + p_amount > coalesce(v_cfg.capacity,24) then raise exception 'Daging sudah hampir penuh. Isi sesuai kapasitas yang tersedia.'; end if;
  v_cost := p_amount::bigint * coalesce(v_cfg.dm_per_meat,1)::bigint;
  if v_wallet.crystals < v_cost then raise exception 'DM tidak cukup untuk membeli daging.'; end if;
  update public.game_google_player_economy set crystals = crystals - v_cost, meat = meat + p_amount, updated_at = now()
    where player_uuid = v_player.player_uuid;
  return public.game_google_player_state(p_google_sub);
end;
$$;
revoke all on function public.game_google_buy_meat(text, integer) from public, anon, authenticated;
grant execute on function public.game_google_buy_meat(text, integer) to service_role;

create or replace function public.game_google_consume_meat(p_google_sub text)
returns jsonb
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_player public.game_google_players;
  v_wallet public.game_google_player_economy;
  v_cfg public.game_meat_config;
begin
  select * into v_player from public.game_google_players where google_sub = p_google_sub;
  if not found then raise exception 'Google player not found'; end if;
  perform public.game_google_regenerate_meat(v_player.player_uuid);
  select * into v_cfg from public.game_meat_config where id = true;
  select * into v_wallet from public.game_google_player_economy where player_uuid = v_player.player_uuid for update;
  if v_wallet.meat <= 0 then raise exception 'Daging habis. Beli daging memakai DM untuk melanjutkan.'; end if;
  update public.game_google_player_economy set
    meat = meat - 1,
    meat_last_regen_at = case when meat >= coalesce(v_cfg.capacity,24) then now() else meat_last_regen_at end,
    updated_at = now()
  where player_uuid = v_player.player_uuid;
  return public.game_google_player_state(p_google_sub);
end;
$$;
revoke all on function public.game_google_consume_meat(text) from public, anon, authenticated;
grant execute on function public.game_google_consume_meat(text) to service_role;

create or replace function public.game_google_redeem_reward_code(p_google_sub text, p_code text)
returns jsonb
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_player public.game_google_players;
  v_code public.game_reward_codes;
  v_reward jsonb;
  v_coins bigint;
  v_crystals bigint;
  v_goblin bigint;
  v_meat integer;
  v_capacity integer;
begin
  select * into v_player from public.game_google_players where google_sub = p_google_sub;
  if not found then raise exception 'Google player not found'; end if;
  select * into v_code from public.game_reward_codes where code = upper(btrim(p_code)) for update;
  if not found then raise exception 'Kode hadiah tidak ditemukan.'; end if;
  if not v_code.enabled then raise exception 'Kode hadiah sudah dinonaktifkan.'; end if;
  if v_code.starts_at is not null and now() < v_code.starts_at then raise exception 'Kode hadiah belum berlaku.'; end if;
  if v_code.expires_at is not null and now() > v_code.expires_at then raise exception 'Kode hadiah sudah kedaluwarsa.'; end if;
  if v_code.uses_count >= v_code.max_uses then raise exception 'Kuota kode hadiah sudah habis.'; end if;
  if exists(select 1 from public.game_reward_code_claims where code_id = v_code.code_id and player_uuid = v_player.player_uuid) then
    raise exception 'Akun ini sudah pernah memakai kode tersebut.';
  end if;
  v_reward := v_code.reward_config;
  v_coins := coalesce((v_reward->>'coins')::bigint,0);
  v_crystals := coalesce((v_reward->>'crystals')::bigint,0);
  v_goblin := coalesce((v_reward->>'goblin_coins')::bigint,0);
  v_meat := coalesce((v_reward->>'meat')::integer,0);
  if v_coins < 0 or v_crystals < 0 or v_goblin < 0 or v_meat < 0 then raise exception 'Reward tidak boleh negatif'; end if;
  if v_coins > 2147483647 or v_crystals > 2147483647 or v_goblin > 2147483647 or v_meat > 24 then raise exception 'Reward melebihi batas game'; end if;
  select capacity into v_capacity from public.game_meat_config where id = true;
  insert into public.game_google_player_economy(player_uuid) values(v_player.player_uuid) on conflict do nothing;
  update public.game_google_player_economy set
    coins = coins + v_coins,
    crystals = crystals + v_crystals,
    goblin_coins = goblin_coins + v_goblin,
    meat = least(coalesce(v_capacity,24), meat + v_meat),
    updated_at = now()
  where player_uuid = v_player.player_uuid;
  insert into public.game_reward_code_claims(code_id, player_uuid, reward_applied)
  values(v_code.code_id, v_player.player_uuid, v_reward);
  update public.game_reward_codes set uses_count = uses_count + 1 where code_id = v_code.code_id;
  return public.game_google_player_state(p_google_sub);
end;
$$;
revoke all on function public.game_google_redeem_reward_code(text, text) from public, anon, authenticated;
grant execute on function public.game_google_redeem_reward_code(text, text) to service_role;

commit;

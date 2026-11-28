-- #####################################################################
-- Kingdom in Chaos DTP — SQL GABUNGAN v17.14.17 (SATU FILE, JALANKAN SEKALI)
-- Urutan di dalam file ini (sudah benar, tidak perlu menjalankan file lain):
--   BAGIAN 1  SQL GABUNGAN v17.14.8   (fondasi v15-v17.4, Google Auth, kode hadiah, daging, Surat, aktivitas)
--   BAGIAN 2  v17.14.16               (tabel kredensial Daftar: Nama Pengguna + Kata Sandi)
--   BAGIAN 3  v17.14.17 ADMIN SAMBUNG (Event Shop untuk pemain Google + kolom event_eyes)
-- Aman diulang: semua perintah memakai IF NOT EXISTS / CREATE OR REPLACE.
-- #####################################################################



-- =====================================================================
-- BAGIAN 1: SQL GABUNGAN v17.14.8
-- =====================================================================
-- v17.14.8: tidak ada perubahan skema dibanding v17.14.2. Akses hadiah admin kini lewat tombol Bakat -> Hub Online (Surat, Kode Hadiah, Daging).
-- =====================================================================
-- Kingdom in Chaos DTP — SQL GABUNGAN v17.13 (v17.4 + Google Auth langsung, kode hadiah, dan daging)
-- Urutan eksekusi (jalankan seluruh file ini sekali di Supabase SQL Editor):
--   1) All-in-One v15 REALTIME STRICT  (sudah termasuk admin migration v11
--      dan strict maintenance gate v15)
--   2) v16 Cave Boss Scheduler
--   3) v17 Event Shop + Event Eyes
--   4) v17.3 Realtime publication + replica identity (migration 007)
-- File ini menggabungkan fondasi v15, strict maintenance, Cave Boss v16, ekonomi native, Event Shop v17, dan Realtime player/event v17.3 (migration 007).
-- Jam jadwal memakai Asia/Jakarta (WIB).
-- =====================================================================
-- PREFLIGHT: this bundle targets Supabase and requires its Realtime publication.
-- Fail before applying schema changes if the target project is not ready.
DO $v174_preflight$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    RAISE EXCEPTION 'Supabase publication supabase_realtime is missing. Enable Realtime for this project, then rerun this SQL bundle.';
  END IF;
END
$v174_preflight$;

-- =====================================================================
-- Kingdom in Chaos DTP — SUPER COMPLETE ALL-IN-ONE SUPABASE SQL
-- Includes online backend, account/profile/avatar, cloud-save history, presence,
-- friends, PvP queue/history/review, rankings, World Boss claims/review, admin
-- users/economy/audit, and the maintenance gate/log.
--
-- IMPORTANT SOURCE FINDING:
-- The current DTP APK/source uses Supabase only for public.app_maintenance.
-- The game's native library still contains legacy HTTP API paths such as
-- /ph/boss/login_v16.php, /ph/boss/signup_v16.php, /ph/boss/modify.php,
-- PvP, rankings, and World Boss endpoints. This SQL does NOT implement those
-- HTTP endpoints and cannot, by itself, restore the original online game.
-- The app must be integrated with Supabase Auth/REST/RPC or a compatible API.
--
-- Run in Supabase Dashboard -> SQL Editor as project owner.
-- Safe to run again (idempotent for the objects created below).
-- Maintenance objects are included in the merged modules appended at the end.
-- =====================================================================

begin;

-- 1) Player profile. avatar_id is an integer to match the legacy game's
--    numeric image/avatar field; actual allowed IDs should match game assets.
create table if not exists public.game_profiles (
    user_id uuid primary key references auth.users(id) on delete cascade,
    legacy_uid bigint generated always as identity unique,
    username text not null unique,
    nickname text not null,
    avatar_id integer not null default 1 check (avatar_id >= 0),
    region text not null default 'global' check (char_length(region) between 1 and 16),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint game_profiles_username_format
        check (username = lower(username) and char_length(username) between 3 and 32),
    constraint game_profiles_nickname_length
        check (char_length(btrim(nickname)) between 1 and 32)
);

create unique index if not exists game_profiles_nickname_ci_uq
    on public.game_profiles (lower(nickname));

-- 2) Player save/sync data. Do not treat values sent by a client as secure
--    currency, premium-currency, ranking, or anti-cheat authority.
create table if not exists public.game_player_saves (
    user_id uuid primary key references auth.users(id) on delete cascade,
    save_version integer not null default 1 check (save_version > 0),
    save_data jsonb not null default '{}'::jsonb
        check (jsonb_typeof(save_data) = 'object'),
    updated_at timestamptz not null default now()
);

-- 3) Online presence / room status. Clients should call heartbeat_game_presence
--    periodically (e.g. every 30–60 seconds) after authentication.
create table if not exists public.game_presence (
    user_id uuid primary key references auth.users(id) on delete cascade,
    is_online boolean not null default true,
    room_code text,
    last_seen timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

-- 4) Friend requests / friends list.
create table if not exists public.game_friendships (
    id uuid primary key default gen_random_uuid(),
    requester_id uuid not null references auth.users(id) on delete cascade,
    addressee_id uuid not null references auth.users(id) on delete cascade,
    status text not null default 'pending'
        check (status in ('pending', 'accepted', 'rejected', 'blocked')),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint game_friendships_not_self check (requester_id <> addressee_id),
    constraint game_friendships_pair_unique unique (requester_id, addressee_id)
);

create index if not exists game_friendships_addressee_status_idx
    on public.game_friendships (addressee_id, status);
create index if not exists game_friendships_requester_status_idx
    on public.game_friendships (requester_id, status);

-- 5) Global leaderboard. Only a trusted server/Edge Function should write
--    ranking values; public clients get read-only access to prevent score spoofing.
create table if not exists public.game_rankings (
    user_id uuid primary key references auth.users(id) on delete cascade,
    nickname text not null,
    avatar_id integer not null default 1 check (avatar_id >= 0),
    level integer not null default 1 check (level >= 1),
    total_score bigint not null default 0 check (total_score >= 0),
    pvp_wins integer not null default 0 check (pvp_wins >= 0),
    honor_points bigint not null default 0 check (honor_points >= 0),
    updated_at timestamptz not null default now()
);

create index if not exists game_rankings_score_idx
    on public.game_rankings (total_score desc, level desc);

-- 6) World Boss scores. Writes must come from a trusted server/Edge Function,
--    not a client-provided score.
create table if not exists public.game_world_boss_scores (
    boss_cycle text not null,
    user_id uuid not null references auth.users(id) on delete cascade,
    nickname text not null,
    avatar_id integer not null default 1 check (avatar_id >= 0),
    score bigint not null default 0 check (score >= 0),
    rank integer check (rank is null or rank > 0),
    updated_at timestamptz not null default now(),
    primary key (boss_cycle, user_id)
);

create index if not exists game_world_boss_score_idx
    on public.game_world_boss_scores (boss_cycle, score desc);

-- 7) PvP battle records. Only trusted backend code should insert match results.
create table if not exists public.game_pvp_matches (
    match_id uuid primary key default gen_random_uuid(),
    player_one uuid not null references auth.users(id) on delete cascade,
    player_two uuid not null references auth.users(id) on delete cascade,
    winner_user_id uuid references auth.users(id) on delete set null,
    battle_summary jsonb not null default '{}'::jsonb
        check (jsonb_typeof(battle_summary) = 'object'),
    played_at timestamptz not null default now(),
    constraint game_pvp_players_differ check (player_one <> player_two),
    constraint game_pvp_winner_is_participant
        check (winner_user_id is null or winner_user_id in (player_one, player_two))
);

create index if not exists game_pvp_player_one_idx
    on public.game_pvp_matches (player_one, played_at desc);
create index if not exists game_pvp_player_two_idx
    on public.game_pvp_matches (player_two, played_at desc);

-- 8) Common updated_at trigger function.
create or replace function public.game_touch_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

drop trigger if exists game_profiles_touch on public.game_profiles;
create trigger game_profiles_touch before update on public.game_profiles
    for each row execute function public.game_touch_updated_at();
drop trigger if exists game_player_saves_touch on public.game_player_saves;
create trigger game_player_saves_touch before update on public.game_player_saves
    for each row execute function public.game_touch_updated_at();
drop trigger if exists game_presence_touch on public.game_presence;
create trigger game_presence_touch before update on public.game_presence
    for each row execute function public.game_touch_updated_at();
drop trigger if exists game_friendships_touch on public.game_friendships;
create trigger game_friendships_touch before update on public.game_friendships
    for each row execute function public.game_touch_updated_at();
drop trigger if exists game_rankings_touch on public.game_rankings;
create trigger game_rankings_touch before update on public.game_rankings
    for each row execute function public.game_touch_updated_at();
drop trigger if exists game_world_boss_scores_touch on public.game_world_boss_scores;
create trigger game_world_boss_scores_touch before update on public.game_world_boss_scores
    for each row execute function public.game_touch_updated_at();

-- 9) Create a game profile automatically for new Supabase Auth users.
--    The app must use Supabase Auth for this trigger to be useful.
create or replace function public.game_handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_suffix text;
    v_username text;
    v_nickname text;
begin
    v_suffix := substr(replace(new.id::text, '-', ''), 1, 12);
    v_username := lower(regexp_replace(coalesce(new.raw_user_meta_data ->> 'username', ''), '[^a-zA-Z0-9_]', '', 'g'));
    v_nickname := btrim(coalesce(new.raw_user_meta_data ->> 'nickname', ''));

    if char_length(v_username) < 3 or char_length(v_username) > 32
       or exists (select 1 from public.game_profiles p where p.username = v_username) then
        v_username := 'player_' || v_suffix;
    end if;

    if char_length(v_nickname) < 1 or char_length(v_nickname) > 32
       or exists (select 1 from public.game_profiles p where lower(p.nickname) = lower(v_nickname)) then
        v_nickname := 'Player-' || substr(new.id::text, 1, 8);
    end if;

    insert into public.game_profiles (user_id, username, nickname)
    values (new.id, v_username, v_nickname)
    on conflict (user_id) do nothing;

    return new;
end;
$$;

drop trigger if exists on_auth_user_created_game_profile on auth.users;
create trigger on_auth_user_created_game_profile
after insert on auth.users
for each row execute function public.game_handle_new_auth_user();

-- 10) RPC: update the logged-in user's public game profile/avatar.
create or replace function public.update_my_game_profile(
    p_nickname text,
    p_avatar_id integer,
    p_region text default 'global'
)
returns public.game_profiles
language plpgsql
security invoker
set search_path = public, auth
as $$
declare
    v_profile public.game_profiles;
begin
    if auth.uid() is null then
        raise exception 'Authentication required';
    end if;
    if p_nickname is null or char_length(btrim(p_nickname)) not between 1 and 32 then
        raise exception 'Nickname must be 1-32 characters';
    end if;
    if p_avatar_id is null or p_avatar_id < 0 then
        raise exception 'Invalid avatar ID';
    end if;
    if p_region is null or char_length(btrim(p_region)) not between 1 and 16 then
        raise exception 'Region must be 1-16 characters';
    end if;

    update public.game_profiles
       set nickname = btrim(p_nickname), avatar_id = p_avatar_id,
           region = btrim(p_region)
     where user_id = auth.uid()
     returning * into v_profile;

    if not found then
        raise exception 'Game profile not found for this account';
    end if;
    return v_profile;
end;
$$;

-- 11) RPC: mark current player online / heartbeat.
create or replace function public.heartbeat_game_presence(p_room_code text default null)
returns void
language plpgsql
security invoker
set search_path = public, auth
as $$
begin
    if auth.uid() is null then
        raise exception 'Authentication required';
    end if;

    insert into public.game_presence (user_id, is_online, room_code, last_seen)
    values (auth.uid(), true, nullif(btrim(p_room_code), ''), now())
    on conflict (user_id) do update
       set is_online = true,
           room_code = excluded.room_code,
           last_seen = now();
end;
$$;

create or replace function public.set_my_game_presence_offline()
returns void
language plpgsql
security invoker
set search_path = public, auth
as $$
begin
    if auth.uid() is null then
        raise exception 'Authentication required';
    end if;
    update public.game_presence
       set is_online = false, last_seen = now()
     where user_id = auth.uid();
end;
$$;

-- 12) Online-player listing. A player is considered online only if a heartbeat
--     was seen during the last two minutes. Uses invoker permissions/RLS.
create or replace view public.game_online_players
with (security_invoker = true)
as
select p.user_id, p.nickname, p.avatar_id, p.region,
       s.room_code, s.last_seen
  from public.game_profiles p
  join public.game_presence s on s.user_id = p.user_id
 where s.is_online = true
   and s.last_seen >= now() - interval '2 minutes';

-- 13) Row-level security.
alter table public.game_profiles enable row level security;
alter table public.game_player_saves enable row level security;
alter table public.game_presence enable row level security;
alter table public.game_friendships enable row level security;
alter table public.game_rankings enable row level security;
alter table public.game_world_boss_scores enable row level security;
alter table public.game_pvp_matches enable row level security;

drop policy if exists game_profiles_read_authenticated on public.game_profiles;
create policy game_profiles_read_authenticated on public.game_profiles
    for select to authenticated using (true);
drop policy if exists game_profiles_update_self on public.game_profiles;
create policy game_profiles_update_self on public.game_profiles
    for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists game_player_saves_select_self on public.game_player_saves;
create policy game_player_saves_select_self on public.game_player_saves
    for select to authenticated using (user_id = auth.uid());
drop policy if exists game_player_saves_insert_self on public.game_player_saves;
create policy game_player_saves_insert_self on public.game_player_saves
    for insert to authenticated with check (user_id = auth.uid());
drop policy if exists game_player_saves_update_self on public.game_player_saves;
create policy game_player_saves_update_self on public.game_player_saves
    for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists game_player_saves_delete_self on public.game_player_saves;
create policy game_player_saves_delete_self on public.game_player_saves
    for delete to authenticated using (user_id = auth.uid());

drop policy if exists game_presence_read_authenticated on public.game_presence;
create policy game_presence_read_authenticated on public.game_presence
    for select to authenticated using (true);
drop policy if exists game_presence_insert_self on public.game_presence;
create policy game_presence_insert_self on public.game_presence
    for insert to authenticated with check (user_id = auth.uid());
drop policy if exists game_presence_update_self on public.game_presence;
create policy game_presence_update_self on public.game_presence
    for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists game_presence_delete_self on public.game_presence;
create policy game_presence_delete_self on public.game_presence
    for delete to authenticated using (user_id = auth.uid());

drop policy if exists game_friendships_read_participant on public.game_friendships;
create policy game_friendships_read_participant on public.game_friendships
    for select to authenticated
    using (requester_id = auth.uid() or addressee_id = auth.uid());
drop policy if exists game_friendships_send_self on public.game_friendships;
create policy game_friendships_send_self on public.game_friendships
    for insert to authenticated
    with check (requester_id = auth.uid() and addressee_id <> auth.uid() and status = 'pending');
drop policy if exists game_friendships_respond_as_addressee on public.game_friendships;
create policy game_friendships_respond_as_addressee on public.game_friendships
    for update to authenticated
    using (addressee_id = auth.uid() and status = 'pending')
    with check (addressee_id = auth.uid() and status in ('accepted', 'rejected', 'blocked'));
drop policy if exists game_friendships_delete_requester_pending on public.game_friendships;
create policy game_friendships_delete_requester_pending on public.game_friendships
    for delete to authenticated
    using (requester_id = auth.uid() and status = 'pending');

-- Read-only for clients; trusted server functions should update competitive data.
drop policy if exists game_rankings_read_all on public.game_rankings;
create policy game_rankings_read_all on public.game_rankings
    for select to anon, authenticated using (true);
drop policy if exists game_world_boss_scores_read_all on public.game_world_boss_scores;
create policy game_world_boss_scores_read_all on public.game_world_boss_scores
    for select to anon, authenticated using (true);
drop policy if exists game_pvp_matches_read_participant on public.game_pvp_matches;
create policy game_pvp_matches_read_participant on public.game_pvp_matches
    for select to authenticated
    using (player_one = auth.uid() or player_two = auth.uid());

-- 14) API privileges. RLS still filters each row.
grant select on public.game_profiles to authenticated;
grant update (nickname, avatar_id, region) on public.game_profiles to authenticated;
grant select, insert, update, delete on public.game_player_saves to authenticated;
grant select, insert, update, delete on public.game_presence to authenticated;
grant select, insert, delete on public.game_friendships to authenticated;
grant update (status) on public.game_friendships to authenticated;
grant select on public.game_rankings to anon, authenticated;
grant select on public.game_world_boss_scores to anon, authenticated;
grant select on public.game_pvp_matches to authenticated;
grant select on public.game_online_players to authenticated;
grant execute on function public.update_my_game_profile(text, integer, text) to authenticated;
grant execute on function public.heartbeat_game_presence(text) to authenticated;
grant execute on function public.set_my_game_presence_offline() to authenticated;

-- Competitive results are writable by service_role / trusted Edge Functions only.
revoke insert, update, delete on public.game_rankings from anon, authenticated;
revoke insert, update, delete on public.game_world_boss_scores from anon, authenticated;
revoke insert, update, delete on public.game_pvp_matches from anon, authenticated;

-- 15) Enable Supabase Realtime for tables the client might subscribe to.
--     Realtime still needs app code to subscribe to these tables.
do $$
declare
    v_table text;
    v_tables text[] := array[
        'game_profiles', 'game_presence', 'game_friendships',
        'game_rankings', 'game_world_boss_scores', 'game_pvp_matches'
    ];
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
        end loop;
    end if;
end $$;

commit;

-- =====================================================================
-- OPTIONAL ONLY: to turn OFF the existing DTP maintenance gate so the game
-- can be entered. Do this only if you intentionally want maintenance disabled.
-- This does not restore the old login/avatar/PvP/World Boss API by itself.
--
-- update public.app_maintenance
--    set is_active = false, start_at = null, end_at = null
--  where id = 1;
-- =====================================================================

-- Quick verification after running:
-- select table_name from information_schema.tables
--  where table_schema = 'public'
--    and table_name in (
--      'game_profiles', 'game_player_saves', 'game_presence', 'game_friendships',
--      'game_rankings', 'game_world_boss_scores', 'game_pvp_matches'
--    )
--  order by table_name;
-- Kingdom in Chaos DTP - Supabase online foundation v2
-- Apply AFTER the existing online-backend-foundation.sql.
-- No service_role key is used by the APK. Competitive result writes remain server-only.
begin;

-- A World Boss cycle is created by an administrator/service process. Client cannot create cycles.
create table if not exists public.game_world_boss_cycles (
    cycle_id text primary key check (char_length(btrim(cycle_id)) between 1 and 80),
    boss_name text not null check (char_length(btrim(boss_name)) between 1 and 80),
    starts_at timestamptz not null,
    ends_at timestamptz not null,
    is_active boolean not null default true,
    created_at timestamptz not null default now(),
    constraint game_world_boss_cycle_time check (ends_at > starts_at)
);

-- Track whether PvP is queued, active, or completed. Historical rows default to completed,
-- but never become trusted ranking input merely because they are present.
alter table public.game_pvp_matches
    add column if not exists status text not null default 'completed';
alter table public.game_pvp_matches
    add column if not exists result_verified boolean not null default false;
alter table public.game_pvp_matches
    add column if not exists started_at timestamptz not null default now();
alter table public.game_pvp_matches
    add column if not exists ended_at timestamptz;

do $$ begin
    if not exists (select 1 from pg_constraint where conname = 'game_pvp_matches_status_check') then
        alter table public.game_pvp_matches add constraint game_pvp_matches_status_check
            check (status in ('in_progress', 'completed', 'cancelled'));
    end if;
end $$;

create table if not exists public.game_pvp_queue (
    user_id uuid primary key references auth.users(id) on delete cascade,
    queue_status text not null default 'waiting' check (queue_status in ('waiting', 'matched')),
    match_id uuid references public.game_pvp_matches(match_id) on delete set null,
    queued_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint game_pvp_queue_match_state check (
       (queue_status = 'waiting' and match_id is null) or
       (queue_status = 'matched' and match_id is not null)
    )
);
create index if not exists game_pvp_queue_waiting_idx
    on public.game_pvp_queue (queued_at) where queue_status = 'waiting';

-- Score submissions are claims only. They do not alter rankings or verified World Boss scores.
-- A server-side verifier must validate battle/replay data before promoting them to official scores.
create table if not exists public.game_world_boss_score_claims (
    claim_id uuid primary key default gen_random_uuid(),
    cycle_id text not null references public.game_world_boss_cycles(cycle_id) on delete cascade,
    user_id uuid not null references auth.users(id) on delete cascade,
    claimed_score bigint not null check (claimed_score >= 0),
    replay_payload jsonb not null default '{}'::jsonb check (jsonb_typeof(replay_payload) = 'object'),
    claim_status text not null default 'pending' check (claim_status in ('pending', 'accepted', 'rejected')),
    submitted_at timestamptz not null default now(),
    reviewed_at timestamptz,
    review_note text
);
create index if not exists game_world_boss_claim_user_cycle_idx
    on public.game_world_boss_score_claims (cycle_id, user_id, submitted_at desc);

-- Do not allow clients to bypass safe profile/save/friend functions by writing rows directly.
revoke insert, update, delete on public.game_profiles from anon, authenticated;
revoke insert, update, delete on public.game_player_saves from anon, authenticated;
revoke insert, update, delete on public.game_friendships from anon, authenticated;
revoke insert, update, delete on public.game_pvp_queue from anon, authenticated;
revoke insert, update, delete on public.game_world_boss_cycles from anon, authenticated;
revoke insert, update, delete on public.game_world_boss_score_claims from anon, authenticated;

alter table public.game_world_boss_cycles enable row level security;
alter table public.game_pvp_queue enable row level security;
alter table public.game_world_boss_score_claims enable row level security;

drop policy if exists game_world_boss_cycles_read on public.game_world_boss_cycles;
create policy game_world_boss_cycles_read on public.game_world_boss_cycles
  for select to authenticated using (true);
drop policy if exists game_world_boss_claims_read_own on public.game_world_boss_score_claims;
create policy game_world_boss_claims_read_own on public.game_world_boss_score_claims
  for select to authenticated using (user_id = auth.uid());

grant select on public.game_world_boss_cycles to authenticated;
grant select on public.game_world_boss_score_claims to authenticated;

-- Update profile/avatar id through an authenticated RPC. Avatar IDs refer to bundled game assets.
create or replace function public.update_my_game_profile(
    p_nickname text,
    p_avatar_id integer,
    p_region text default 'global'
) returns public.game_profiles
language plpgsql security definer set search_path = public, auth
as $$
declare v_profile public.game_profiles;
begin
    if auth.uid() is null then raise exception 'Authentication required'; end if;
    if p_nickname is null or char_length(btrim(p_nickname)) not between 1 and 32 then
        raise exception 'Nickname must be 1-32 characters';
    end if;
    if p_avatar_id is null or p_avatar_id < 0 then raise exception 'Invalid avatar ID'; end if;
    if p_region is null or char_length(btrim(p_region)) not between 1 and 16 then
        raise exception 'Region must be 1-16 characters';
    end if;
    update public.game_profiles
       set nickname = btrim(p_nickname), avatar_id = p_avatar_id, region = btrim(p_region)
     where user_id = auth.uid() returning * into v_profile;
    if not found then raise exception 'Game profile not found'; end if;
    return v_profile;
end;
$$;

grant execute on function public.update_my_game_profile(text, integer, text) to authenticated;

create or replace function public.find_game_players(p_query text, p_limit integer default 20)
returns table(user_id uuid, username text, nickname text, avatar_id integer, region text, is_online boolean)
language plpgsql security invoker set search_path = public, auth
as $$
declare v_query text := btrim(coalesce(p_query, ''));
begin
    if auth.uid() is null then raise exception 'Authentication required'; end if;
    if char_length(v_query) < 2 then raise exception 'Search must contain at least 2 characters'; end if;
    return query
      select p.user_id, p.username, p.nickname, p.avatar_id, p.region,
             coalesce(pr.is_online and pr.last_seen > now() - interval '2 minutes', false)
        from public.game_profiles p
        left join public.game_presence pr on pr.user_id = p.user_id
       where p.user_id <> auth.uid()
         and (p.username ilike '%' || v_query || '%' or p.nickname ilike '%' || v_query || '%')
       order by (lower(p.username) = lower(v_query)) desc, p.nickname asc
       limit greatest(1, least(coalesce(p_limit, 20), 50));
end;
$$;
grant execute on function public.find_game_players(text, integer) to authenticated;

create or replace function public.send_game_friend_request(p_target_user_id uuid)
returns public.game_friendships
language plpgsql security definer set search_path = public, auth
as $$
declare v_me uuid := auth.uid(); v_row public.game_friendships; v_reverse public.game_friendships;
begin
    if v_me is null then raise exception 'Authentication required'; end if;
    if p_target_user_id is null or p_target_user_id = v_me then raise exception 'Invalid friend target'; end if;
    if not exists (select 1 from public.game_profiles where user_id = p_target_user_id) then
        raise exception 'Player not found';
    end if;
    select * into v_row from public.game_friendships
      where requester_id = v_me and addressee_id = p_target_user_id for update;
    if found then
       if v_row.status = 'accepted' then return v_row; end if;
       if v_row.status = 'pending' then raise exception 'Friend request already sent'; end if;
       if v_row.status = 'blocked' then raise exception 'This player is blocked'; end if;
       delete from public.game_friendships where id = v_row.id;
    end if;
    select * into v_reverse from public.game_friendships
      where requester_id = p_target_user_id and addressee_id = v_me for update;
    if found then
       if v_reverse.status = 'accepted' then return v_reverse; end if;
       if v_reverse.status = 'pending' then
          update public.game_friendships set status = 'accepted', updated_at = now()
           where id = v_reverse.id returning * into v_reverse;
          return v_reverse;
       end if;
       if v_reverse.status = 'blocked' then raise exception 'You cannot send a request to this player'; end if;
       delete from public.game_friendships where id = v_reverse.id;
    end if;
    insert into public.game_friendships(requester_id, addressee_id, status)
      values (v_me, p_target_user_id, 'pending') returning * into v_row;
    return v_row;
end;
$$;
grant execute on function public.send_game_friend_request(uuid) to authenticated;

create or replace function public.respond_game_friend_request(p_request_id uuid, p_accept boolean)
returns public.game_friendships
language plpgsql security definer set search_path = public, auth
as $$
declare v_row public.game_friendships;
begin
    if auth.uid() is null then raise exception 'Authentication required'; end if;
    update public.game_friendships
       set status = case when coalesce(p_accept, false) then 'accepted' else 'rejected' end,
           updated_at = now()
     where id = p_request_id and addressee_id = auth.uid() and status = 'pending'
     returning * into v_row;
    if not found then raise exception 'Pending friend request not found'; end if;
    return v_row;
end;
$$;
grant execute on function public.respond_game_friend_request(uuid, boolean) to authenticated;

create or replace function public.remove_game_friend(p_other_user_id uuid)
returns boolean
language plpgsql security definer set search_path = public, auth
as $$
declare v_me uuid := auth.uid();
begin
    if v_me is null then raise exception 'Authentication required'; end if;
    if p_other_user_id is null or p_other_user_id = v_me then raise exception 'Invalid player'; end if;
    delete from public.game_friendships
     where status in ('accepted', 'pending')
       and ((requester_id = v_me and addressee_id = p_other_user_id)
         or (requester_id = p_other_user_id and addressee_id = v_me));
    return true;
end;
$$;
grant execute on function public.remove_game_friend(uuid) to authenticated;

create or replace function public.get_my_game_friends()
returns table(friendship_id uuid, user_id uuid, username text, nickname text, avatar_id integer,
              region text, is_online boolean, last_seen timestamptz)
language plpgsql security invoker set search_path = public, auth
as $$
begin
    if auth.uid() is null then raise exception 'Authentication required'; end if;
    return query
      select f.id, p.user_id, p.username, p.nickname, p.avatar_id, p.region,
             coalesce(pr.is_online and pr.last_seen > now() - interval '2 minutes', false), pr.last_seen
        from public.game_friendships f
        join public.game_profiles p on p.user_id = case when f.requester_id = auth.uid()
                                                        then f.addressee_id else f.requester_id end
        left join public.game_presence pr on pr.user_id = p.user_id
       where f.status = 'accepted' and (f.requester_id = auth.uid() or f.addressee_id = auth.uid())
       order by p.nickname asc;
end;
$$;
grant execute on function public.get_my_game_friends() to authenticated;


create or replace function public.get_my_game_friend_requests()
returns table(request_id uuid, other_user_id uuid, username text, nickname text, avatar_id integer,
              request_status text, direction text, created_at timestamptz)
language plpgsql security invoker set search_path = public, auth
as $$
begin
    if auth.uid() is null then raise exception 'Authentication required'; end if;
    return query
      select f.id, p.user_id, p.username, p.nickname, p.avatar_id, f.status,
             case when f.addressee_id = auth.uid() then 'incoming' else 'outgoing' end, f.created_at
        from public.game_friendships f
        join public.game_profiles p on p.user_id = case when f.requester_id = auth.uid()
                                                        then f.addressee_id else f.requester_id end
       where f.status = 'pending' and (f.requester_id = auth.uid() or f.addressee_id = auth.uid())
       order by f.created_at desc;
end;
$$;
grant execute on function public.get_my_game_friend_requests() to authenticated;

create or replace function public.get_active_game_world_boss_cycles()
returns table(cycle_id text, boss_name text, starts_at timestamptz, ends_at timestamptz)
language sql security invoker set search_path = public, auth
as $$
    select c.cycle_id, c.boss_name, c.starts_at, c.ends_at
      from public.game_world_boss_cycles c
     where c.is_active and now() between c.starts_at and c.ends_at
     order by c.starts_at desc;
$$;
grant execute on function public.get_active_game_world_boss_cycles() to authenticated;

create or replace function public.save_my_game_data(p_save_version integer, p_save_data jsonb)
returns public.game_player_saves
language plpgsql security definer set search_path = public, auth
as $$
declare v_id uuid := auth.uid(); v_row public.game_player_saves;
begin
    if v_id is null then raise exception 'Authentication required'; end if;
    if p_save_version is null or p_save_version < 1 then raise exception 'Invalid save version'; end if;
    if p_save_data is null or jsonb_typeof(p_save_data) <> 'object' then raise exception 'Save data must be a JSON object'; end if;
    select * into v_row from public.game_player_saves where user_id = v_id for update;
    if found and p_save_version < v_row.save_version then raise exception 'Older save version rejected'; end if;
    insert into public.game_player_saves(user_id, save_version, save_data)
      values(v_id, p_save_version, p_save_data)
    on conflict(user_id) do update set save_version = excluded.save_version,
      save_data = excluded.save_data, updated_at = now()
    returning * into v_row;
    return v_row;
end;
$$;
grant execute on function public.save_my_game_data(integer, jsonb) to authenticated;

create or replace function public.join_game_pvp_queue()
returns table(queue_status text, match_id uuid, opponent_user_id uuid)
language plpgsql security definer set search_path = public, auth
as $$
declare
    v_me uuid := auth.uid(); v_match uuid; v_opponent uuid; v_existing public.game_pvp_queue;
    v_state text;
begin
    if v_me is null then raise exception 'Authentication required'; end if;
    -- Serialize queue matching to prevent two callers claiming the same opponent.
    perform pg_advisory_xact_lock(91473051);
    select * into v_existing from public.game_pvp_queue where user_id = v_me for update;
    if found and v_existing.queue_status = 'matched' and v_existing.match_id is not null
       and exists (select 1 from public.game_pvp_matches m where m.match_id = v_existing.match_id and m.status = 'in_progress') then
       select case when m.player_one = v_me then m.player_two else m.player_one end
         into v_opponent from public.game_pvp_matches m where m.match_id = v_existing.match_id;
       return query select 'matched'::text, v_existing.match_id, v_opponent; return;
    end if;

    select q.user_id into v_opponent
      from public.game_pvp_queue q
     where q.user_id <> v_me and q.queue_status = 'waiting'
       and q.queued_at > now() - interval '10 minutes'
     order by q.queued_at asc
     limit 1 for update skip locked;

    if v_opponent is not null then
       v_match := gen_random_uuid();
       insert into public.game_pvp_matches(match_id, player_one, player_two, winner_user_id,
           battle_summary, played_at, status, result_verified, started_at)
       values(v_match, v_opponent, v_me, null, '{}'::jsonb, now(), 'in_progress', false, now());
       update public.game_pvp_queue set queue_status = 'matched', match_id = v_match, updated_at = now()
         where user_id = v_opponent;
       insert into public.game_pvp_queue(user_id, queue_status, match_id, queued_at)
         values(v_me, 'matched', v_match, now())
       on conflict(user_id) do update set queue_status = 'matched', match_id = excluded.match_id, updated_at = now();
       return query select 'matched'::text, v_match, v_opponent; return;
    end if;

    insert into public.game_pvp_queue(user_id, queue_status, match_id, queued_at)
      values(v_me, 'waiting', null, now())
    on conflict(user_id) do update set queue_status = 'waiting', match_id = null,
      queued_at = case when public.game_pvp_queue.queue_status = 'waiting' then public.game_pvp_queue.queued_at else now() end,
      updated_at = now();
    return query select 'waiting'::text, null::uuid, null::uuid;
end;
$$;
grant execute on function public.join_game_pvp_queue() to authenticated;

create or replace function public.cancel_game_pvp_queue()
returns boolean language plpgsql security definer set search_path = public, auth
as $$
begin
    if auth.uid() is null then raise exception 'Authentication required'; end if;
    delete from public.game_pvp_queue where user_id = auth.uid() and queue_status = 'waiting';
    return true;
end;
$$;
grant execute on function public.cancel_game_pvp_queue() to authenticated;

create or replace function public.get_game_world_boss_rankings(p_cycle_id text, p_limit integer default 100)
returns table(rank_position bigint, user_id uuid, nickname text, avatar_id integer, score bigint, updated_at timestamptz)
language plpgsql security invoker set search_path = public, auth
as $$
begin
    if auth.uid() is null then raise exception 'Authentication required'; end if;
    if not exists (select 1 from public.game_world_boss_cycles c where c.cycle_id = p_cycle_id) then
       raise exception 'World Boss cycle not found';
    end if;
    return query
      select dense_rank() over (order by s.score desc, s.updated_at asc), s.user_id,
             s.nickname, s.avatar_id, s.score, s.updated_at
        from public.game_world_boss_scores s where s.boss_cycle = p_cycle_id
       order by s.score desc, s.updated_at asc
       limit greatest(1, least(coalesce(p_limit, 100), 500));
end;
$$;
grant execute on function public.get_game_world_boss_rankings(text, integer) to authenticated;

create or replace function public.submit_world_boss_score_claim(
    p_cycle_id text, p_claimed_score bigint, p_replay_payload jsonb default '{}'::jsonb
) returns uuid
language plpgsql security definer set search_path = public, auth
as $$
declare v_claim uuid;
begin
    if auth.uid() is null then raise exception 'Authentication required'; end if;
    if p_claimed_score is null or p_claimed_score < 0 then raise exception 'Invalid score'; end if;
    if p_replay_payload is null or jsonb_typeof(p_replay_payload) <> 'object' then raise exception 'Replay payload must be an object'; end if;
    if octet_length(p_replay_payload::text) > 250000 then raise exception 'Replay payload is too large'; end if;
    if not exists (select 1 from public.game_world_boss_cycles c where c.cycle_id = p_cycle_id
          and c.is_active and now() between c.starts_at and c.ends_at) then
       raise exception 'World Boss cycle is not active';
    end if;
    insert into public.game_world_boss_score_claims(cycle_id, user_id, claimed_score, replay_payload)
      values(p_cycle_id, auth.uid(), p_claimed_score, p_replay_payload)
      returning claim_id into v_claim;
    return v_claim;
end;
$$;
grant execute on function public.submit_world_boss_score_claim(text, bigint, jsonb) to authenticated;

create or replace function public.get_my_pvp_history(p_limit integer default 50)
returns table(match_id uuid, opponent_user_id uuid, winner_user_id uuid, my_result text,
              played_at timestamptz, result_verified boolean)
language plpgsql security invoker set search_path = public, auth
as $$
begin
    if auth.uid() is null then raise exception 'Authentication required'; end if;
    return query
      select m.match_id,
             case when m.player_one = auth.uid() then m.player_two else m.player_one end,
             m.winner_user_id,
             case when m.status <> 'completed' then 'in_progress'
                  when m.winner_user_id is null then 'draw'
                  when m.winner_user_id = auth.uid() then 'win' else 'loss' end,
             m.played_at, m.result_verified
        from public.game_pvp_matches m
       where m.player_one = auth.uid() or m.player_two = auth.uid()
       order by m.played_at desc
       limit greatest(1, least(coalesce(p_limit, 50), 200));
end;
$$;
grant execute on function public.get_my_pvp_history(integer) to authenticated;


-- Admin/server-only result verification. These functions are deliberately unavailable
-- to ordinary authenticated clients; a reviewer or real replay verifier must call them.
create or replace function public.admin_approve_pvp_result(
    p_match_id uuid, p_winner_user_id uuid, p_battle_summary jsonb default '{}'::jsonb
) returns public.game_pvp_matches
language plpgsql security definer set search_path = public, auth
as $$
declare v_match public.game_pvp_matches; v_player public.game_profiles;
begin
    if p_match_id is null then raise exception 'Match ID required'; end if;
    if p_battle_summary is null or jsonb_typeof(p_battle_summary) <> 'object' then
        raise exception 'Battle summary must be a JSON object';
    end if;
    select * into v_match from public.game_pvp_matches where match_id = p_match_id for update;
    if not found then raise exception 'PvP match not found'; end if;
    if v_match.status <> 'in_progress' then raise exception 'PvP match is not in progress'; end if;
    if p_winner_user_id is not null and p_winner_user_id not in (v_match.player_one, v_match.player_two) then
        raise exception 'Winner must be a participant in the match';
    end if;
    update public.game_pvp_matches
       set winner_user_id = p_winner_user_id, battle_summary = p_battle_summary,
           status = 'completed', result_verified = true, ended_at = now(), played_at = now()
     where match_id = p_match_id returning * into v_match;

    for v_player in
        select p.* from public.game_profiles p where p.user_id in (v_match.player_one, v_match.player_two)
    loop
        insert into public.game_rankings(user_id, nickname, avatar_id, level, total_score, pvp_wins, honor_points)
        values(v_player.user_id, v_player.nickname, v_player.avatar_id, 1, 0,
               case when v_player.user_id = p_winner_user_id then 1 else 0 end, 0)
        on conflict(user_id) do update
          set nickname = excluded.nickname, avatar_id = excluded.avatar_id,
              pvp_wins = public.game_rankings.pvp_wins + excluded.pvp_wins,
              updated_at = now();
    end loop;
    return v_match;
end;
$$;
revoke all on function public.admin_approve_pvp_result(uuid, uuid, jsonb) from public, anon, authenticated;
grant execute on function public.admin_approve_pvp_result(uuid, uuid, jsonb) to service_role;

create or replace function public.admin_approve_world_boss_claim(p_claim_id uuid)
returns public.game_world_boss_scores
language plpgsql security definer set search_path = public, auth
as $$
declare v_claim public.game_world_boss_score_claims; v_profile public.game_profiles; v_result public.game_world_boss_scores;
begin
    select * into v_claim from public.game_world_boss_score_claims where claim_id = p_claim_id for update;
    if not found then raise exception 'World Boss claim not found'; end if;
    if v_claim.claim_status <> 'pending' then raise exception 'Claim is not pending'; end if;
    select * into v_profile from public.game_profiles where user_id = v_claim.user_id;
    if not found then raise exception 'Player profile not found'; end if;
    update public.game_world_boss_score_claims
       set claim_status = 'accepted', reviewed_at = now(), review_note = 'Approved by trusted reviewer'
     where claim_id = p_claim_id;
    insert into public.game_world_boss_scores(boss_cycle, user_id, nickname, avatar_id, score, updated_at)
      values(v_claim.cycle_id, v_claim.user_id, v_profile.nickname, v_profile.avatar_id, v_claim.claimed_score, now())
    on conflict(boss_cycle, user_id) do update
      set nickname = excluded.nickname, avatar_id = excluded.avatar_id,
          score = greatest(public.game_world_boss_scores.score, excluded.score), updated_at = now()
    returning * into v_result;
    return v_result;
end;
$$;
revoke all on function public.admin_approve_world_boss_claim(uuid) from public, anon, authenticated;
grant execute on function public.admin_approve_world_boss_claim(uuid) to service_role;

create or replace function public.admin_reject_world_boss_claim(p_claim_id uuid, p_review_note text default null)
returns boolean language plpgsql security definer set search_path = public, auth
as $$
declare v_count integer;
begin
    update public.game_world_boss_score_claims
       set claim_status = 'rejected', reviewed_at = now(), review_note = left(coalesce(p_review_note, 'Rejected by trusted reviewer'), 500)
     where claim_id = p_claim_id and claim_status = 'pending';
    get diagnostics v_count = row_count;
    if v_count = 0 then raise exception 'Pending World Boss claim not found'; end if;
    return true;
end;
$$;
revoke all on function public.admin_reject_world_boss_claim(uuid, text) from public, anon, authenticated;
grant execute on function public.admin_reject_world_boss_claim(uuid, text) to service_role;


-- Functions are callable only by authenticated players unless intentionally server-only.
revoke all on function public.update_my_game_profile(text, integer, text) from public, anon, authenticated;
grant execute on function public.update_my_game_profile(text, integer, text) to authenticated;
revoke all on function public.find_game_players(text, integer) from public, anon, authenticated;
grant execute on function public.find_game_players(text, integer) to authenticated;
revoke all on function public.send_game_friend_request(uuid) from public, anon, authenticated;
grant execute on function public.send_game_friend_request(uuid) to authenticated;
revoke all on function public.respond_game_friend_request(uuid, boolean) from public, anon, authenticated;
grant execute on function public.respond_game_friend_request(uuid, boolean) to authenticated;
revoke all on function public.remove_game_friend(uuid) from public, anon, authenticated;
grant execute on function public.remove_game_friend(uuid) to authenticated;
revoke all on function public.get_my_game_friends() from public, anon, authenticated;
grant execute on function public.get_my_game_friends() to authenticated;
revoke all on function public.get_my_game_friend_requests() from public, anon, authenticated;
grant execute on function public.get_my_game_friend_requests() to authenticated;
revoke all on function public.get_active_game_world_boss_cycles() from public, anon, authenticated;
grant execute on function public.get_active_game_world_boss_cycles() to authenticated;
revoke all on function public.save_my_game_data(integer, jsonb) from public, anon, authenticated;
grant execute on function public.save_my_game_data(integer, jsonb) to authenticated;
revoke all on function public.join_game_pvp_queue() from public, anon, authenticated;
grant execute on function public.join_game_pvp_queue() to authenticated;
revoke all on function public.cancel_game_pvp_queue() from public, anon, authenticated;
grant execute on function public.cancel_game_pvp_queue() to authenticated;
revoke all on function public.get_game_world_boss_rankings(text, integer) from public, anon, authenticated;
grant execute on function public.get_game_world_boss_rankings(text, integer) to authenticated;
revoke all on function public.submit_world_boss_score_claim(text, bigint, jsonb) from public, anon, authenticated;
grant execute on function public.submit_world_boss_score_claim(text, bigint, jsonb) to authenticated;
revoke all on function public.get_my_pvp_history(integer) from public, anon, authenticated;
grant execute on function public.get_my_pvp_history(integer) to authenticated;
revoke all on function public.heartbeat_game_presence(text) from public, anon, authenticated;
grant execute on function public.heartbeat_game_presence(text) to authenticated;
revoke all on function public.set_my_game_presence_offline() from public, anon, authenticated;
grant execute on function public.set_my_game_presence_offline() to authenticated;

-- These tables are written by trusted backend/admin only; players cannot self-award rank or boss score.
revoke insert, update, delete on public.game_rankings from anon, authenticated;
revoke insert, update, delete on public.game_world_boss_scores from anon, authenticated;
revoke insert, update, delete on public.game_pvp_matches from anon, authenticated;
revoke insert, update, delete on public.game_world_boss_score_claims from anon, authenticated;

-- Turn off direct profile/save/friend writes even if the previous foundation granted them.
grant select on public.game_profiles to authenticated;
grant select on public.game_player_saves to authenticated;
grant select on public.game_friendships to authenticated;
grant select on public.game_pvp_matches to authenticated;
grant select on public.game_world_boss_scores to authenticated;

-- Keep realtime publication optional if enabled in this Supabase project.
do $$
declare v_table text; v_tables text[] := array['game_profiles','game_presence','game_friendships','game_rankings','game_world_boss_scores','game_pvp_matches','game_pvp_queue','game_world_boss_cycles'];
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    foreach v_table in array v_tables loop
      if to_regclass('public.' || v_table) is not null and not exists (
        select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename=v_table
      ) then execute format('alter publication supabase_realtime add table public.%I', v_table); end if;
    end loop;
  end if;
end $$;

commit;

-- IMPORTANT:
-- PvP matchmaking only finds an opponent and creates an in-progress match record.
-- A trusted game-server verifier must validate fight/replay data and mark the result
-- completed/result_verified=true before it can affect competitive rankings.
-- World Boss client scores are stored as pending claims and do not enter the official
-- leaderboard until a trusted verifier approves them. This prevents easy score spoofing.

-- =====================================================================
-- Kingdom in Chaos DTP — Online recovery migration v3
-- Apply AFTER online-backend-complete.sql in Supabase SQL Editor.
--
-- Adds save-history recovery, a client-readable PvP state endpoint, safer
-- queue reconciliation, and auditable privileged review RPCs.
-- Does NOT claim to emulate the original native battle engine.
-- =====================================================================

begin;

-- 1) Keep cloud-save snapshots when save data changes, so an accidental
-- overwrite can be investigated/restored. Players may read only their own history.
create table if not exists public.game_player_save_history (
    history_id bigint generated always as identity primary key,
    user_id uuid not null references auth.users(id) on delete cascade,
    save_version integer not null check (save_version > 0),
    save_data jsonb not null check (jsonb_typeof(save_data) = 'object'),
    archived_at timestamptz not null default now()
);
create index if not exists game_player_save_history_user_time_idx
    on public.game_player_save_history (user_id, archived_at desc);

alter table public.game_player_save_history enable row level security;
drop policy if exists game_player_save_history_read_self on public.game_player_save_history;
create policy game_player_save_history_read_self
    on public.game_player_save_history for select to authenticated
    using (user_id = auth.uid());
grant select on public.game_player_save_history to authenticated;
revoke insert, update, delete on public.game_player_save_history from anon, authenticated;

create or replace function public.game_archive_player_save_before_update()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
    if old.save_version is distinct from new.save_version
       or old.save_data is distinct from new.save_data then
        insert into public.game_player_save_history(user_id, save_version, save_data, archived_at)
        values (old.user_id, old.save_version, old.save_data, now());
    end if;
    return new;
end;
$$;

drop trigger if exists game_player_save_archive on public.game_player_saves;
create trigger game_player_save_archive
before update on public.game_player_saves
for each row execute function public.game_archive_player_save_before_update();

-- 2) Query a specific PvP state. Membership is checked in SQL; the client
-- cannot alter match status or result with this function.
create or replace function public.get_my_pvp_match_state(p_match_id uuid)
returns table(
    match_id uuid,
    status text,
    opponent_user_id uuid,
    winner_user_id uuid,
    battle_summary jsonb,
    result_verified boolean,
    started_at timestamptz,
    ended_at timestamptz
)
language plpgsql
security invoker
set search_path = public, auth
as $$
begin
    if auth.uid() is null then raise exception 'Authentication required'; end if;
    return query
      select m.match_id, m.status,
             case when m.player_one = auth.uid() then m.player_two else m.player_one end,
             m.winner_user_id, m.battle_summary, m.result_verified, m.started_at, m.ended_at
        from public.game_pvp_matches m
       where m.match_id = p_match_id
         and (m.player_one = auth.uid() or m.player_two = auth.uid());
end;
$$;
revoke all on function public.get_my_pvp_match_state(uuid) from public, anon, authenticated;
grant execute on function public.get_my_pvp_match_state(uuid) to authenticated;

-- 3) Reconcile stale waiting rows and return an already active match before
-- creating a new one. This improves queue reliability but is NOT combat simulation.
create or replace function public.join_game_pvp_queue()
returns table(queue_status text, match_id uuid, opponent_user_id uuid)
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
    v_me uuid := auth.uid();
    v_match uuid;
    v_opponent uuid;
begin
    if v_me is null then raise exception 'Authentication required'; end if;
    perform pg_advisory_xact_lock(91473051);

    -- Stale queue entries are not valid opponents.
    delete from public.game_pvp_queue
     where queue_status = 'waiting'
       and queued_at < now() - interval '10 minutes';

    -- If this player already has an active battle, return it instead of queueing twice.
    select m.match_id,
           case when m.player_one = v_me then m.player_two else m.player_one end
      into v_match, v_opponent
      from public.game_pvp_matches m
     where m.status = 'in_progress'
       and (m.player_one = v_me or m.player_two = v_me)
     order by m.started_at desc
     limit 1;

    if v_match is not null then
        insert into public.game_pvp_queue(user_id, queue_status, match_id, queued_at, updated_at)
        values (v_me, 'matched', v_match, now(), now())
        on conflict (user_id) do update
           set queue_status = 'matched', match_id = excluded.match_id, updated_at = now();
        return query select 'matched'::text, v_match, v_opponent;
        return;
    end if;

    select q.user_id into v_opponent
      from public.game_pvp_queue q
     where q.user_id <> v_me
       and q.queue_status = 'waiting'
       and q.queued_at > now() - interval '10 minutes'
     order by q.queued_at asc
     limit 1
     for update skip locked;

    if v_opponent is not null then
        v_match := gen_random_uuid();

        insert into public.game_pvp_matches(
            match_id, player_one, player_two, winner_user_id, battle_summary,
            played_at, status, result_verified, started_at
        ) values (
            v_match, v_opponent, v_me, null, '{}'::jsonb,
            now(), 'in_progress', false, now()
        );

        update public.game_pvp_queue
           set queue_status = 'matched', match_id = v_match, updated_at = now()
         where user_id = v_opponent;

        insert into public.game_pvp_queue(user_id, queue_status, match_id, queued_at, updated_at)
        values (v_me, 'matched', v_match, now(), now())
        on conflict (user_id) do update
           set queue_status = 'matched', match_id = excluded.match_id, updated_at = now();

        return query select 'matched'::text, v_match, v_opponent;
        return;
    end if;

    insert into public.game_pvp_queue(user_id, queue_status, match_id, queued_at, updated_at)
    values (v_me, 'waiting', null, now(), now())
    on conflict (user_id) do update
       set queue_status = 'waiting', match_id = null,
           queued_at = case
               when public.game_pvp_queue.queue_status = 'waiting'
                 and public.game_pvp_queue.queued_at > now() - interval '10 minutes'
               then public.game_pvp_queue.queued_at
               else now()
           end,
           updated_at = now();

    return query select 'waiting'::text, null::uuid, null::uuid;
end;
$$;
revoke all on function public.join_game_pvp_queue() from public, anon, authenticated;
grant execute on function public.join_game_pvp_queue() to authenticated;

-- 4) Review audit log. Never store the review key, service_role key, password,
-- access token, or refresh token in this table.
create table if not exists public.game_online_review_audit (
    audit_id bigint generated always as identity primary key,
    action text not null check (action in ('pvp_approved', 'world_boss_approved', 'world_boss_rejected')),
    entity_id text not null,
    review_note text not null check (char_length(btrim(review_note)) between 8 and 500),
    metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata) = 'object'),
    created_at timestamptz not null default now()
);
create index if not exists game_online_review_audit_entity_time_idx
    on public.game_online_review_audit (entity_id, created_at desc);
alter table public.game_online_review_audit enable row level security;
revoke all on public.game_online_review_audit from public, anon, authenticated;
grant select, insert on public.game_online_review_audit to service_role;

-- 5) Audited World Boss claim review. The claim is still a player-submitted
-- assertion. Approval must follow manual replay inspection or a real verifier.
create or replace function public.admin_review_world_boss_claim(
    p_claim_id uuid,
    p_approve boolean,
    p_review_note text
)
returns public.game_world_boss_score_claims
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_claim public.game_world_boss_score_claims;
    v_profile public.game_profiles;
    v_action text;
begin
    if p_claim_id is null then raise exception 'Claim ID required'; end if;
    if p_approve is null then raise exception 'Approval decision required'; end if;
    if p_review_note is null or char_length(btrim(p_review_note)) not between 8 and 500 then
        raise exception 'Review note must contain 8-500 characters';
    end if;

    select * into v_claim
      from public.game_world_boss_score_claims
     where claim_id = p_claim_id
     for update;
    if not found then raise exception 'World Boss claim not found'; end if;
    if v_claim.claim_status <> 'pending' then raise exception 'Claim is no longer pending'; end if;

    if p_approve then
        select * into v_profile from public.game_profiles where user_id = v_claim.user_id;
        if not found then raise exception 'Player profile not found'; end if;

        update public.game_world_boss_score_claims
           set claim_status = 'accepted', reviewed_at = now(), review_note = btrim(p_review_note)
         where claim_id = p_claim_id
         returning * into v_claim;

        insert into public.game_world_boss_scores(
            boss_cycle, user_id, nickname, avatar_id, score, updated_at
        ) values (
            v_claim.cycle_id, v_claim.user_id, v_profile.nickname, v_profile.avatar_id,
            v_claim.claimed_score, now()
        )
        on conflict (boss_cycle, user_id) do update
           set nickname = excluded.nickname,
               avatar_id = excluded.avatar_id,
               score = greatest(public.game_world_boss_scores.score, excluded.score),
               updated_at = now();
        v_action := 'world_boss_approved';
    else
        update public.game_world_boss_score_claims
           set claim_status = 'rejected', reviewed_at = now(), review_note = btrim(p_review_note)
         where claim_id = p_claim_id
         returning * into v_claim;
        v_action := 'world_boss_rejected';
    end if;

    insert into public.game_online_review_audit(action, entity_id, review_note, metadata)
    values (
        v_action, p_claim_id::text, btrim(p_review_note),
        jsonb_build_object('cycle_id', v_claim.cycle_id, 'user_id', v_claim.user_id,
                           'claimed_score', v_claim.claimed_score)
    );

    return v_claim;
end;
$$;
revoke all on function public.admin_review_world_boss_claim(uuid, boolean, text) from public, anon, authenticated;
grant execute on function public.admin_review_world_boss_claim(uuid, boolean, text) to service_role;

-- 6) Audited PvP result review. This records a result only after a trusted reviewer
-- has checked the native fight/replay; it does not calculate the battle itself.
create or replace function public.admin_review_pvp_result(
    p_match_id uuid,
    p_winner_user_id uuid,
    p_battle_summary jsonb,
    p_review_note text
)
returns public.game_pvp_matches
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_match public.game_pvp_matches;
    v_profile public.game_profiles;
begin
    if p_match_id is null then raise exception 'Match ID required'; end if;
    if p_battle_summary is null or jsonb_typeof(p_battle_summary) <> 'object' then
        raise exception 'Battle summary must be a JSON object';
    end if;
    if octet_length(p_battle_summary::text) > 200000 then
        raise exception 'Battle summary is too large';
    end if;
    if p_review_note is null or char_length(btrim(p_review_note)) not between 8 and 500 then
        raise exception 'Review note must contain 8-500 characters';
    end if;

    select * into v_match
      from public.game_pvp_matches
     where match_id = p_match_id
     for update;
    if not found then raise exception 'PvP match not found'; end if;
    if v_match.status <> 'in_progress' or v_match.result_verified then
        raise exception 'PvP match is not awaiting review';
    end if;
    if p_winner_user_id is not null
       and p_winner_user_id not in (v_match.player_one, v_match.player_two) then
        raise exception 'Winner must be a participant in the match';
    end if;

    update public.game_pvp_matches
       set winner_user_id = p_winner_user_id,
           battle_summary = p_battle_summary,
           status = 'completed',
           result_verified = true,
           ended_at = now(),
           played_at = now()
     where match_id = p_match_id
     returning * into v_match;

    for v_profile in
        select p.* from public.game_profiles p
         where p.user_id in (v_match.player_one, v_match.player_two)
    loop
        insert into public.game_rankings(
            user_id, nickname, avatar_id, level, total_score, pvp_wins, honor_points, updated_at
        ) values (
            v_profile.user_id, v_profile.nickname, v_profile.avatar_id, 1, 0,
            case when v_profile.user_id = p_winner_user_id then 1 else 0 end, 0, now()
        )
        on conflict (user_id) do update
           set nickname = excluded.nickname,
               avatar_id = excluded.avatar_id,
               pvp_wins = public.game_rankings.pvp_wins + excluded.pvp_wins,
               updated_at = now();
    end loop;

    insert into public.game_online_review_audit(action, entity_id, review_note, metadata)
    values (
        'pvp_approved', p_match_id::text, btrim(p_review_note),
        jsonb_build_object('winner_user_id', p_winner_user_id,
                           'player_one', v_match.player_one, 'player_two', v_match.player_two)
    );

    return v_match;
end;
$$;
revoke all on function public.admin_review_pvp_result(uuid, uuid, jsonb, text) from public, anon, authenticated;
grant execute on function public.admin_review_pvp_result(uuid, uuid, jsonb, text) to service_role;

-- Ensure legacy approval RPCs stay server-only as well.
revoke all on function public.admin_approve_pvp_result(uuid, uuid, jsonb) from public, anon, authenticated;
grant execute on function public.admin_approve_pvp_result(uuid, uuid, jsonb) to service_role;
revoke all on function public.admin_approve_world_boss_claim(uuid) from public, anon, authenticated;
grant execute on function public.admin_approve_world_boss_claim(uuid) to service_role;
revoke all on function public.admin_reject_world_boss_claim(uuid, text) from public, anon, authenticated;
grant execute on function public.admin_reject_world_boss_claim(uuid, text) to service_role;

commit;

-- Verification queries:
-- select table_name from information_schema.tables
--  where table_schema='public' and table_name in ('game_player_save_history','game_online_review_audit');
-- select routine_name from information_schema.routines
--  where routine_schema='public' and routine_name in
--  ('get_my_pvp_match_state','admin_review_world_boss_claim','admin_review_pvp_result');
--
-- IMPORTANT remaining native integration:
-- - The original native C++ game logic / HTTP protocol is not available here.
-- - PVP matching creates a match record only; it cannot run the original battle.
-- - Score review approves submitted claims only after a trusted verifier/manual review.
-- - Cloud save SQL stores JSON sent by the app; the game must serialize/restore its actual native save.
-- - Official currency/reward delivery requires mapping to the original in-game save format and a trusted reward writer.
-- Kingdom in Chaos DTP: secure player administration (v11)
-- Apply AFTER the v10 online backend migrations.
-- This migration creates server-only admin/economy/audit tables. The browser/APK
-- must call the game-admin Edge Function; never expose SUPABASE_SERVICE_ROLE_KEY.
begin;

create table if not exists public.game_admin_users (
    user_id uuid primary key references auth.users(id) on delete cascade,
    role text not null default 'admin' check (role in ('admin', 'super_admin')),
    active boolean not null default true,
    created_at timestamptz not null default now(),
    created_by uuid references auth.users(id) on delete set null
);

create table if not exists public.game_admin_player_economy (
    user_id uuid primary key references auth.users(id) on delete cascade,
    coins bigint not null default 0 check (coins >= 0),
    crystals bigint not null default 0 check (crystals >= 0),
    goblin_coins bigint not null default 0 check (goblin_coins >= 0),
    hero_xp bigint not null default 0 check (hero_xp >= 0),
    hero_level integer not null default 1 check (hero_level between 1 and 1000000),
    player_xp bigint not null default 0 check (player_xp >= 0),
    player_level integer not null default 1 check (player_level between 1 and 1000000),
    energy bigint not null default 0 check (energy >= 0),
    stamina bigint not null default 0 check (stamina >= 0),
    honor_points bigint not null default 0 check (honor_points >= 0),
    arena_tokens bigint not null default 0 check (arena_tokens >= 0),
    skill_points bigint not null default 0 check (skill_points >= 0),
    extra_stats jsonb not null default '{}'::jsonb check (jsonb_typeof(extra_stats) = 'object'),
    updated_at timestamptz not null default now(),
    updated_by uuid references auth.users(id) on delete set null
);

create table if not exists public.game_admin_audit (
    audit_id bigint generated always as identity primary key,
    admin_user_id uuid references auth.users(id) on delete set null,
    target_user_id uuid references auth.users(id) on delete set null,
    action text not null check (action in ('economy_update', 'profile_update', 'save_update')),
    reason text not null check (char_length(btrim(reason)) between 4 and 500),
    before_data jsonb not null default '{}'::jsonb check (jsonb_typeof(before_data) = 'object'),
    after_data jsonb not null default '{}'::jsonb check (jsonb_typeof(after_data) = 'object'),
    created_at timestamptz not null default now()
);

create index if not exists game_admin_audit_target_time_idx
    on public.game_admin_audit (target_user_id, created_at desc);
create index if not exists game_admin_audit_admin_time_idx
    on public.game_admin_audit (admin_user_id, created_at desc);

-- Keep an economy control row for existing accounts and any future Auth user.
insert into public.game_admin_player_economy (user_id)
select id from auth.users
on conflict (user_id) do nothing;

create or replace function public.game_admin_init_player_economy()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
    insert into public.game_admin_player_economy (user_id)
    values (new.id)
    on conflict (user_id) do nothing;
    return new;
end;
$$;

drop trigger if exists game_admin_init_player_economy on auth.users;
create trigger game_admin_init_player_economy
after insert on auth.users
for each row execute function public.game_admin_init_player_economy();

-- Server-only data: RLS is enabled and direct grants are explicitly removed.
alter table public.game_admin_users enable row level security;
alter table public.game_admin_player_economy enable row level security;
alter table public.game_admin_audit enable row level security;
revoke all on public.game_admin_users from public, anon, authenticated;
revoke all on public.game_admin_player_economy from public, anon, authenticated;
revoke all on public.game_admin_audit from public, anon, authenticated;
grant select, insert, update, delete on public.game_admin_users to service_role;
grant select, insert, update, delete on public.game_admin_player_economy to service_role;
grant select, insert, update, delete on public.game_admin_audit to service_role;
grant usage, select on sequence public.game_admin_audit_audit_id_seq to service_role;

commit;

-- Admin bootstrap is consolidated below after all tables are created.
-- =====================================================================
-- MODULE 16: MAINTENANCE GATE + ADMIN CHANGE LOG (merged all-in-one)
-- Existing state is preserved if app_maintenance already exists.
-- This section does NOT automatically turn maintenance on or off.
-- =====================================================================

begin;

create table if not exists public.app_maintenance (
    id integer primary key default 1,
    is_active boolean not null default false,
    title text not null default 'SEDANG MAINTENANCE',
    message text not null default 'Game sedang dalam perbaikan. Silakan kembali beberapa saat lagi.',
    start_at timestamptz,
    end_at timestamptz,
    updated_at timestamptz not null default now(),
    constraint app_maintenance_single_row check (id = 1)
);

-- Compatible with projects where the table was created by an earlier partial script.
alter table public.app_maintenance add column if not exists is_active boolean not null default false;
alter table public.app_maintenance add column if not exists title text not null default 'SEDANG MAINTENANCE';
alter table public.app_maintenance add column if not exists message text not null default 'Game sedang dalam perbaikan. Silakan kembali beberapa saat lagi.';
alter table public.app_maintenance add column if not exists start_at timestamptz;
alter table public.app_maintenance add column if not exists end_at timestamptz;
alter table public.app_maintenance add column if not exists updated_at timestamptz not null default now();

do $$
begin
    if not exists (
        select 1 from pg_constraint
        where conname = 'app_maintenance_single_row'
          and conrelid = 'public.app_maintenance'::regclass
    ) then
        alter table public.app_maintenance
            add constraint app_maintenance_single_row check (id = 1);
    end if;
end $$;

insert into public.app_maintenance (id) values (1)
on conflict (id) do nothing;

alter table public.app_maintenance enable row level security;
drop policy if exists app_maintenance_read on public.app_maintenance;
create policy app_maintenance_read on public.app_maintenance
    for select to anon, authenticated using (true);
revoke insert, update, delete, truncate, references, trigger on public.app_maintenance from anon, authenticated;
grant select on public.app_maintenance to anon, authenticated;
grant select, insert, update, delete on public.app_maintenance to service_role;

create or replace function public.touch_app_maintenance()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

drop trigger if exists app_maintenance_touch on public.app_maintenance;
create trigger app_maintenance_touch
    before update on public.app_maintenance
    for each row execute function public.touch_app_maintenance();

create table if not exists public.app_maintenance_log (
    id bigint generated always as identity primary key,
    created_at timestamptz not null default now(),
    is_active boolean,
    title text,
    message text,
    end_at timestamptz
);

alter table public.app_maintenance_log enable row level security;
revoke all on public.app_maintenance_log from public, anon, authenticated;
grant select, insert on public.app_maintenance_log to service_role;
grant usage, select on sequence public.app_maintenance_log_id_seq to service_role;

-- Enable Realtime only if the Supabase publication exists; safe to re-run.
do $$
begin
    if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
        if not exists (
            select 1 from pg_publication_tables
             where pubname = 'supabase_realtime'
               and schemaname = 'public'
               and tablename = 'app_maintenance'
        ) then
            alter publication supabase_realtime add table public.app_maintenance;
        end if;
    end if;
end $$;

alter table public.app_maintenance replica identity full;

commit;

-- =====================================================================
-- MODULE 17: OPTIONAL FIRST SUPER-ADMIN BOOTSTRAP
-- IMPORTANT: Edit the email below to an account that ALREADY exists in
-- Supabase Authentication -> Users. If the placeholder is untouched, this
-- step safely skips. It never creates an Auth user or grants all users admin.
-- =====================================================================

do $admin_bootstrap$
declare
    v_admin_email text := lower(btrim('GANTI_EMAIL_ADMIN_ANDA'));
    v_admin_id uuid;
begin
    if v_admin_email is null or v_admin_email = ''
       or v_admin_email = 'ganti_email_admin_anda'
       or position('@' in v_admin_email) = 0 then
        raise notice 'Admin bootstrap dilewati. Edit GANTI_EMAIL_ADMIN_ANDA jika ingin memberikan akses super_admin.';
        return;
    end if;

    select id into v_admin_id
      from auth.users
     where lower(email) = v_admin_email
     limit 1;

    if v_admin_id is null then
        raise notice 'Admin bootstrap dilewati: email belum ada di auth.users. Buat akun melalui Supabase Auth terlebih dahulu.';
        return;
    end if;

    insert into public.game_admin_users (user_id, role, active, created_by)
    values (v_admin_id, 'super_admin', true, v_admin_id)
    on conflict (user_id) do update
       set role = 'super_admin', active = true;

    raise notice 'Super admin berhasil disiapkan untuk %.', v_admin_email;
end
$admin_bootstrap$;

-- =====================================================================
-- MODULE 18: FINAL VERIFICATION QUERIES (read-only)
-- These SELECTs should return expected objects after SQL Editor completes.
-- =====================================================================
select table_name
from information_schema.tables
where table_schema = 'public'
  and table_name in (
    'app_maintenance', 'app_maintenance_log',
    'game_profiles', 'game_player_saves', 'game_player_save_history',
    'game_presence', 'game_online_players', 'game_friendships',
    'game_rankings', 'game_world_boss_cycles', 'game_world_boss_scores',
    'game_world_boss_score_claims', 'game_pvp_matches', 'game_pvp_queue',
    'game_online_review_audit', 'game_admin_users',
    'game_admin_player_economy', 'game_admin_audit'
  )
order by table_name;

select routine_name
from information_schema.routines
where routine_schema = 'public'
  and routine_name in (
    'update_my_game_profile', 'find_game_players', 'send_game_friend_request',
    'respond_game_friend_request', 'get_my_game_friends', 'get_my_game_friend_requests',
    'save_my_game_data', 'heartbeat_game_presence', 'set_my_game_presence_offline',
    'join_game_pvp_queue', 'cancel_game_pvp_queue', 'get_my_pvp_match_state',
    'get_my_pvp_history', 'get_active_game_world_boss_cycles',
    'get_game_world_boss_rankings', 'submit_world_boss_score_claim',
    'admin_review_world_boss_claim', 'admin_review_pvp_result',
    'game_admin_init_player_economy', 'touch_app_maintenance'
  )
order by routine_name;

select a.user_id, u.email, a.role, a.active, a.created_at
from public.game_admin_users a
join auth.users u on u.id = a.user_id
order by a.created_at desc;

-- OPTIONAL MANUAL MAINTENANCE CONTROL (uncomment only when intentional):
-- Turn maintenance ON:
-- update public.app_maintenance
-- set is_active = true, title = 'SEDANG MAINTENANCE',
--     message = 'Server sedang diperbaiki. Silakan coba lagi nanti.',
--     start_at = now(), end_at = null
-- where id = 1;
-- Turn maintenance OFF:
-- update public.app_maintenance
-- set is_active = false, start_at = null, end_at = null
-- where id = 1;

-- IMPORTANT LIMITS:
-- 1) SQL provisions Supabase tables/RPCs and admin-managed economy data only.
-- 2) The app must call Supabase Auth/REST/RPC and the game-admin Edge Function.
-- 3) Never put service_role credentials in an APK/browser HTML.
-- 4) PvP queue is matchmaking state, not the native battle engine.
-- 5) World Boss claims need trusted validation before rewards/ranking are granted.
-- 6) Cloud save requires game code to serialize/restore its actual native save data.
-- 7) Coins/crystals/XP in game_admin_player_economy will not affect native gameplay
--    until the native game's save/reward path is explicitly integrated.
-- 8) The legacy HTTP API endpoints in libgame.so are not recreated by SQL alone.

-- =====================================================================
-- MODULE 18: REALTIME STATE + ATOMIC ADMIN ECONOMY CHANGES (v14)
-- NOTE: publication sends database changes, but each client must subscribe.
-- Native gameplay values only change after the game reads/applies this state.
-- =====================================================================
begin;

-- Allow each authenticated player to READ only their own admin-managed economy
-- so Supabase Realtime can deliver server-side changes to the correct player.
-- No client INSERT/UPDATE/DELETE privileges are granted here.
alter table public.game_admin_player_economy enable row level security;
drop policy if exists game_admin_economy_read_self on public.game_admin_player_economy;
create policy game_admin_economy_read_self
  on public.game_admin_player_economy
  for select to authenticated
  using (user_id = auth.uid());
revoke insert, update, delete on public.game_admin_player_economy from anon, authenticated;
grant select on public.game_admin_player_economy to authenticated;

-- Make the user's queue status readable for authenticated Realtime subscribers.
alter table public.game_pvp_queue enable row level security;
drop policy if exists game_pvp_queue_read_self on public.game_pvp_queue;
create policy game_pvp_queue_read_self
  on public.game_pvp_queue for select to authenticated
  using (user_id = auth.uid());
revoke insert, update, delete on public.game_pvp_queue from anon, authenticated;
grant select on public.game_pvp_queue to authenticated;

-- Atomic admin economy update: the row change + immutable audit insert commit together.
-- Only service_role (Edge Function server) may execute this function.
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

-- Single authenticated RPC used by clients when they re-enter/resume the game.
-- Keeps a consistent contract for the server-backed state that an app can apply.
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

-- Publish all player-facing state tables. RLS still filters the events by user.
-- SQL publication is the server-side prerequisite; Android/web clients must subscribe.
do $$
declare
  v_table text;
  v_tables text[] := array[
    'app_maintenance','game_profiles','game_player_saves','game_player_save_history',
    'game_presence','game_friendships','game_rankings','game_world_boss_cycles',
    'game_world_boss_scores','game_world_boss_score_claims','game_pvp_matches',
    'game_pvp_queue','game_admin_player_economy'
  ];
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    foreach v_table in array v_tables loop
      if to_regclass('public.' || v_table) is not null then
        if not exists (
          select 1 from pg_publication_tables
          where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = v_table
        ) then
          execute format('alter publication supabase_realtime add table public.%I', v_table);
        end if;
        execute format('alter table public.%I replica identity full', v_table);
      end if;
    end loop;
  else
    raise notice 'Publication supabase_realtime does not exist; enable/configure Supabase Realtime before subscribing.';
  end if;
end $$;

commit;

-- Verification: these queries should show the publication tables and routine.
select tablename from pg_publication_tables
 where pubname = 'supabase_realtime' and schemaname = 'public'
 order by tablename;
select routine_name from information_schema.routines
 where routine_schema = 'public'
   and routine_name in ('admin_update_player_economy','get_my_game_runtime_state')
 order by routine_name;

-- CRITICAL: these SQL changes make database changes available to Realtime clients.
-- They do NOT make the native game use them automatically. The game client must
-- subscribe to game_admin_player_economy filtered by its own user_id, then apply
-- the received values to the native save/state. Native save format integration is
-- required before admin-edited coins/crystals/XP physically change gameplay.

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


-- =====================================================================
-- BAGIAN 2: v16 Cave Boss Scheduler
-- =====================================================================
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


-- =====================================================================
-- BAGIAN 3: v17 Event Shop + Event Eyes
-- =====================================================================
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

-- Public-facing event configuration/catalogue contain no player secrets. Give
-- authenticated clients read-only access so Supabase Realtime can authorize the
-- postgres_changes subscription. Admin writes and logs remain service_role-only.
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

-- Postgres Changes needs publication membership as well as SELECT privilege/RLS.
-- REPLICA IDENTITY FULL ensures UPDATE/DELETE events contain the changed row.
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


-- =====================================================================
-- =====================================================================
-- BAGIAN 4: PLAYER STATE + EVENT STORE REALTIME (MIGRATION 007, MERGED)
-- Add the authenticated player's own state tables to Postgres Changes.
-- Admin Edge Function also emits minimal Broadcast invalidation events.
-- The Android client reloads the authenticated RPC snapshot after either path.
-- =====================================================================
begin;
do $v174_realtime$
declare
  v_table text;
  v_tables text[] := array[
    'game_profiles',
    'game_player_saves',
    'game_admin_player_economy',
    'game_event_store_config',
    'game_event_store_items',
    'game_cave_boss_hourly_schedule',
    'game_cave_boss_override'
  ];
begin
  IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    RAISE EXCEPTION 'Publication supabase_realtime is missing. Enable Supabase Realtime before installing the player/event Realtime module.';
  END IF;

  FOREACH v_table IN ARRAY v_tables LOOP
    IF to_regclass('public.' || v_table) IS NULL THEN
      RAISE EXCEPTION 'Required Realtime table public.% is missing. Run the complete SQL bundle in order.', v_table;
    END IF;

    IF NOT EXISTS (
      SELECT 1 FROM pg_publication_tables
       WHERE pubname = 'supabase_realtime'
         AND schemaname = 'public'
         AND tablename = v_table
    ) THEN
      EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', v_table);
    END IF;

    EXECUTE format('ALTER TABLE public.%I REPLICA IDENTITY FULL', v_table);
  END LOOP;
END
$v174_realtime$;
commit;

-- CATATAN ADMIN BOOTSTRAP (dari migration v11, jalankan terpisah)
-- =====================================================================
-- ADMIN BOOTSTRAP (run separately after the admin has an account in Supabase Auth):
-- Replace the email below with the exact email of your own admin account, then run:
-- insert into public.game_admin_users (user_id, role, active)
-- select id, 'super_admin', true from auth.users
-- where lower(email) = lower('YOUR_ADMIN_EMAIL')
-- on conflict (user_id) do update set role = 'super_admin', active = true;
-- Verify the account was added:
-- select a.user_id, u.email, a.role, a.active
-- from public.game_admin_users a join auth.users u on u.id = a.user_id;
--
-- SECURITY NOTES:
-- * Do not grant public/authenticated access to these tables.
-- * Do not include a service_role key in admin.html or any APK.
-- * Currency/XP values in this table are DTP admin-managed backend fields. They do
--   not automatically modify the original native game's local save unless the native
--   game is integrated with this table's values; see ADMIN-PLAYER-MANAGEMENT.md.


-- =====================================================================
-- MODULE 19: v17.13 DIRECT GOOGLE PLAYERS + REWARD CODES + MEAT
-- Players are authenticated by Google at the Edge Function, not Supabase Auth.
-- Supabase remains the database / Edge Functions host and Admin Auth provider.
-- =====================================================================
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

-- Kingdom In Chaos DTP v17.14: in-game player mail with transactional one-time claims.
-- Rewards are NOT written to a player wallet when the admin sends the message.
-- The wallet changes only when the recipient claims the mail through google-player.
begin;

alter table public.game_google_players
  add column if not exists last_seen_at timestamptz not null default now();

create index if not exists game_google_players_last_seen_idx
  on public.game_google_players(last_seen_at desc);

create table if not exists public.game_google_player_mail (
  mail_id uuid primary key default gen_random_uuid(),
  player_uuid uuid not null references public.game_google_players(player_uuid) on delete cascade,
  recipient_email text not null,
  subject text not null check (char_length(btrim(subject)) between 1 and 100),
  message text not null check (char_length(btrim(message)) between 1 and 2000),
  reward_config jsonb not null default '{}'::jsonb
    check (jsonb_typeof(reward_config) = 'object'),
  created_by uuid references auth.users(id) on delete set null,
  admin_name text not null default 'Admin',
  reason text not null check (char_length(btrim(reason)) between 4 and 500),
  expires_at timestamptz,
  claimed_at timestamptz,
  claim_result jsonb,
  created_at timestamptz not null default now()
);
create index if not exists game_google_player_mail_inbox_idx
  on public.game_google_player_mail(player_uuid, created_at desc);
create index if not exists game_google_player_mail_unclaimed_idx
  on public.game_google_player_mail(player_uuid, expires_at)
  where claimed_at is null;


-- Last observed native Android wallet. Clients cannot write directly; only the
-- Google-player Edge Function (service_role) stores read-only snapshots.
create table if not exists public.game_google_player_native_wallets (
  player_uuid uuid primary key references public.game_google_players(player_uuid) on delete cascade,
  coins bigint not null default 0 check (coins >= 0),
  crystals bigint not null default 0 check (crystals >= 0),
  goblin_coins bigint not null default 0 check (goblin_coins >= 0),
  meat integer not null default 0 check (meat between 0 and 24),
  client_observed_at timestamptz not null default now(),
  server_received_at timestamptz not null default now()
);
alter table public.game_google_player_native_wallets enable row level security;
revoke all on public.game_google_player_native_wallets from public, anon, authenticated;
grant select, insert, update on public.game_google_player_native_wallets to service_role;

create table if not exists public.game_google_mail_admin_log (
  log_id bigint generated always as identity primary key,
  mail_id uuid references public.game_google_player_mail(mail_id) on delete set null,
  admin_user_id uuid references auth.users(id) on delete set null,
  action text not null,
  reason text not null check (char_length(btrim(reason)) between 4 and 500),
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

alter table public.game_google_player_mail enable row level security;
alter table public.game_google_mail_admin_log enable row level security;
revoke all on public.game_google_player_mail from public, anon, authenticated;
revoke all on public.game_google_mail_admin_log from public, anon, authenticated;
grant select, insert, update, delete on public.game_google_player_mail to service_role;
grant select, insert, update, delete on public.game_google_mail_admin_log to service_role;
grant usage, select on sequence public.game_google_mail_admin_log_log_id_seq to service_role;

create or replace function public.game_google_claim_player_mail(
  p_google_sub text,
  p_mail_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_player public.game_google_players;
  v_mail public.game_google_player_mail;
  v_wallet public.game_google_player_economy;
  v_cfg public.game_meat_config;
  v_reward jsonb;
  v_coins bigint;
  v_crystals bigint;
  v_goblin bigint;
  v_meat integer;
begin
  if p_google_sub is null or btrim(p_google_sub) = '' or p_mail_id is null then
    raise exception 'Data surat tidak valid.';
  end if;
  select * into v_player
    from public.game_google_players
   where google_sub = p_google_sub;
  if not found then raise exception 'Pemain Google tidak ditemukan.'; end if;

  select * into v_mail
    from public.game_google_player_mail
   where mail_id = p_mail_id and player_uuid = v_player.player_uuid
   for update;
  if not found then raise exception 'Surat tidak ditemukan untuk akun ini.'; end if;
  if v_mail.claimed_at is not null then raise exception 'Hadiah surat ini sudah pernah diklaim.'; end if;
  if v_mail.expires_at is not null and now() > v_mail.expires_at then
    raise exception 'Surat sudah kedaluwarsa.';
  end if;

  v_reward := coalesce(v_mail.reward_config, '{}'::jsonb);
  v_coins := coalesce((v_reward->>'coins')::bigint, 0);
  v_crystals := coalesce((v_reward->>'crystals')::bigint, 0);
  v_goblin := coalesce((v_reward->>'goblin_coins')::bigint, 0);
  v_meat := coalesce((v_reward->>'meat')::integer, 0);
  if v_coins < 0 or v_crystals < 0 or v_goblin < 0 or v_meat < 0 then
    raise exception 'Isi hadiah surat tidak valid.';
  end if;
  if v_coins > 2147483647 or v_crystals > 2147483647 or v_goblin > 2147483647 or v_meat > 24 then
    raise exception 'Hadiah surat melebihi batas yang diizinkan.';
  end if;

  insert into public.game_google_player_economy(player_uuid)
    values (v_player.player_uuid) on conflict (player_uuid) do nothing;
  perform public.game_google_regenerate_meat(v_player.player_uuid);
  select * into v_cfg from public.game_meat_config where id = true;
  select * into v_wallet
    from public.game_google_player_economy
   where player_uuid = v_player.player_uuid
   for update;

  if v_wallet.coins + v_coins > 2147483647
     or v_wallet.crystals + v_crystals > 2147483647
     or v_wallet.goblin_coins + v_goblin > 2147483647 then
    raise exception 'Saldo setelah klaim akan melewati batas wallet game.';
  end if;

  update public.game_google_player_economy
     set coins = coins + v_coins,
         crystals = crystals + v_crystals,
         goblin_coins = goblin_coins + v_goblin,
         meat = least(coalesce(v_cfg.capacity, 24), meat + v_meat),
         updated_at = now()
   where player_uuid = v_player.player_uuid;

  update public.game_google_player_mail
     set claimed_at = now(), claim_result = v_reward
   where mail_id = v_mail.mail_id and claimed_at is null
   returning * into v_mail;
  if not found then raise exception 'Surat sudah diklaim pada perangkat lain.'; end if;

  update public.game_google_players set last_seen_at = now(), updated_at = now()
   where player_uuid = v_player.player_uuid;

  return jsonb_build_object(
    'mail', to_jsonb(v_mail),
    'state', public.game_google_player_state(p_google_sub)
  );
end;
$$;
revoke all on function public.game_google_claim_player_mail(text, uuid) from public, anon, authenticated;
grant execute on function public.game_google_claim_player_mail(text, uuid) to service_role;

commit;

-- v17.14.1: unified activity trail for Google players and dashboard admins.
begin;

create table if not exists public.game_google_activity (
  activity_id bigint generated always as identity primary key,
  actor_type text not null check (actor_type in ('player','admin')),
  player_uuid uuid references public.game_google_players(player_uuid) on delete set null,
  admin_user_id uuid references auth.users(id) on delete set null,
  actor_email text not null default '',
  action text not null check (char_length(btrim(action)) between 1 and 80),
  details jsonb not null default '{}'::jsonb check (jsonb_typeof(details) = 'object'),
  created_at timestamptz not null default now(),
  constraint game_google_activity_actor_check check (
    (actor_type = 'player' and player_uuid is not null) or
    (actor_type = 'admin' and admin_user_id is not null)
  )
);
create index if not exists game_google_activity_created_idx
  on public.game_google_activity(created_at desc);
create index if not exists game_google_activity_player_idx
  on public.game_google_activity(player_uuid, created_at desc);

alter table public.game_google_activity enable row level security;
revoke all on public.game_google_activity from public, anon, authenticated;
grant select, insert on public.game_google_activity to service_role;
grant usage, select on sequence public.game_google_activity_activity_id_seq to service_role;

commit;


-- =====================================================================
-- BAGIAN 2: v17.14.16 kredensial Daftar
-- =====================================================================
-- Kingdom In Chaos DTP v17.14.16 — kredensial Daftar (Nama Pengguna + Kata Sandi)
-- Jalankan SEKALI di Supabase SQL Editor, SEBELUM deploy google-player v17.14.16.
-- Kata sandi TIDAK disimpan polos: hanya hash PBKDF2-SHA256 + salt. Tabel hanya bisa diakses service_role.
begin;

create table if not exists public.game_google_player_credentials (
  player_uuid uuid primary key references public.game_google_players(player_uuid) on delete cascade,
  password_hash text not null,
  password_salt text not null,
  password_iterations integer not null default 100000 check (password_iterations >= 10000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.game_google_player_credentials enable row level security;
revoke all on public.game_google_player_credentials from public, anon, authenticated;
grant select, insert, update, delete on public.game_google_player_credentials to service_role;

commit;


-- =====================================================================
-- BAGIAN 3: v17.14.17 ADMIN SAMBUNG
-- =====================================================================
-- ============================================================================
-- Kingdom In Chaos DTP v17.14.17 - ADMIN SAMBUNG
-- Jalankan SEKALI di Supabase SQL Editor (aman diulang). Jalankan SEBELUM deploy function.
--
-- MASALAH YANG DIPERBAIKI:
--   Sejak login Google langsung (v17.13), pemain tidak punya sesi Supabase Auth.
--   get_active_event_store() memakai auth.uid() lalu menolak "Authentication required",
--   dan RPC itu memang dicabut dari anon. Akibatnya perintah admin untuk Event Shop
--   tidak pernah sampai ke game. Fungsi ini versi yang dipanggil Edge Function google-player
--   (service_role) dengan p_player_uuid yang sudah diverifikasi lewat token Google.
--   Isi logika jadwal/katalog disalin PERSIS dari get_active_event_store() v17.4.
-- ============================================================================
begin;

-- Saldo Event Eyes pemain Google (sebelumnya hanya ada di tabel ekonomi akun Supabase Auth lama).
alter table public.game_google_player_economy
  add column if not exists event_eyes bigint not null default 0 check (event_eyes >= 0);

create or replace function public.game_google_active_event_store(p_player_uuid uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_user uuid := p_player_uuid; -- v17.14.17: pemain Google tidak punya auth.uid()
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
  if v_user is null then raise exception 'Player required'; end if;
  select coalesce(e.event_eyes,0) into v_eyes
    from public.game_google_player_economy e where e.player_uuid = v_user;
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

revoke all on function public.game_google_active_event_store(uuid) from public, anon, authenticated;
grant execute on function public.game_google_active_event_store(uuid) to service_role;

commit;

-- Cek cepat (jalankan manual): ganti UUID dengan player_uuid dari tabel game_google_players
-- select public.game_google_active_event_store((select player_uuid from public.game_google_players limit 1));

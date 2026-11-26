-- =====================================================================
-- Kingdom in Chaos DTP — Online Backend Foundation for Supabase
-- Version: 1.0
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
-- This script intentionally does NOT modify app_maintenance.
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

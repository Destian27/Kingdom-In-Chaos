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

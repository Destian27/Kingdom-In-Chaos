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

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

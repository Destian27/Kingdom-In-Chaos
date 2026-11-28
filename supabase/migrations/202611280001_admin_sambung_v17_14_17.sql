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
